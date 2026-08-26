import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { execFile as execFileCallback, spawn } from "node:child_process";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";
import test from "node:test";

import { applyPlan, buildPlan, rollbackBatch, validateManifest, verifyState } from "./reconcile-hooks.mjs";
import { validateRepoPolicyManifest } from "./repo-policy-loader.mjs";

const execFile = promisify(execFileCallback);

const CLAUDE_TARGETS = [
  ["PostToolUse", "Edit|Write", 30, "if [[ \"$CLAUDE_FILE_PATH\" =~ \\.(ts|tsx|js|jsx)$ ]] && command -v prettier &> /dev/null; then prettier --write \"$CLAUDE_FILE_PATH\" 2>/dev/null; fi"],
  ["PostToolUse", "Edit|Write", 30, "~/.claude/hooks/posttool-typecheck.sh"],
  ["PostToolUse", "Edit|Write", 3, "~/.claude/hooks/validation-mark.sh"],
  ["PostToolUse", "Bash", 3, "~/.claude/hooks/validation-clear.sh"],
  ["PostToolUse", "Bash", 3, "~/.claude/hooks/retry-detect.sh"],
  ["PreToolUse", "Bash", 5, "~/.claude/hooks/assert-deploy-target.sh"],
  ["PreToolUse", "Edit|Write", 3, "~/.claude/hooks/fingerprint-gate.sh"],
  ["PreToolUse", "Bash", 300, "~/.claude/hooks/pre-pr-bash-gate.sh"],
  ["Stop", "", 5, "~/.claude/hooks/pre-finalize.sh"],
  ["PreToolUse", "Bash", 5, "~/.claude/hooks/host-pressure-gate.sh"],
  ["PreToolUse", "Bash", 5, "~/.claude/hooks/secret-hygiene.sh"],
  ["PreToolUse", "Bash", null, "~/.claude/hooks/ps-self-match-guard.sh"],
  ["PreToolUse", "Bash", 30, "bash -c 'INPUT=$(cat); CMD=$(echo \"$INPUT\" | jq -r \".tool_input.command // empty\"); if echo \"$CMD\" | grep -qE \"rm\\s+-rf\\s+(/|~|\\$HOME|\\.\\.)\"; then echo \"BLOCK: Comando rm -rf perigoso detectado\"; exit 2; fi; exit 0'"],
  ["PreToolUse", "Bash", 3, "~/.claude/hooks/protect-env-read.sh"],
  ["UserPromptSubmit", "", 5, "~/.claude/hooks/secret-hygiene.sh"],
  ["PreToolUse", "Bash", null, "~/.claude/hooks/log-commands.sh"],
  ["Stop", "", null, "~/.claude/hooks/delivery-proof-gate.sh"],
];
const CODEX_TARGETS = [
  ["PreToolUse", "^Bash$", 30, "~/.claude/hooks/lib/codex-adapt.sh ~/.claude/hooks/assert-deploy-target.sh", "Asserting deploy target"],
  ["PreToolUse", "^Bash$", 180, "~/.claude/hooks/lib/codex-adapt.sh ~/.claude/hooks/pre-pr-bash-gate.sh", "Checking PR gate receipt"],
  ["PreToolUse", "^Bash$", 10, "~/.claude/hooks/ps-self-match-guard.sh", "Checking process-probe self-match"],
  ["PreToolUse", "^Bash$", 20, "~/.claude/hooks/lib/codex-adapt.sh ~/.claude/hooks/protect-env-read.sh", "Protecting .env from reads"],
  ["PreToolUse", "^Bash$", 20, "~/.claude/hooks/lib/codex-adapt.sh ~/.claude/hooks/secret-hygiene.sh", "Checking secret hygiene"],
  ["PreToolUse", "^Bash$", 15, "~/.claude/hooks/lib/codex-adapt.sh ~/.claude/hooks/host-pressure-gate.sh", "Checking host memory pressure"],
];
const CU23_TARGETS = [
  ["PreToolUse", "Bash", null, "~/.claude/hooks/dobra-compose-writer-guard.sh"],
];
const EXTERNAL = "/opt/external/preserve-me";

function configFor(targets) {
  const hooks = { PreToolUse: [{ matcher: "External", hooks: [{ type: "command", command: EXTERNAL, timeout: 9 }] }] };
  for (const [event, matcher, timeout, command, statusMessage] of targets) {
    const groups = hooks[event] ??= [];
    let group = groups.find((candidate) => candidate.matcher === matcher);
    if (!group) {
      group = { matcher, hooks: [] };
      groups.push(group);
    }
    const hook = { type: "command", command };
    if (timeout !== null) hook.timeout = timeout;
    if (statusMessage !== undefined) hook.statusMessage = statusMessage;
    group.hooks.push(hook);
  }
  return { theme: "preserved", hooks };
}

function countCommand(config, command) {
  return Object.values(config.hooks ?? {}).flatMap((groups) => groups)
    .flatMap((group) => group.hooks)
    .filter((hook) => hook.command === command).length;
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

async function git(cwd, ...args) {
  await execFile("git", ["-C", cwd, ...args], { encoding: "utf8" });
}

async function runStop(payload) {
  const child = spawn(process.execPath, [new URL("validation-finalize-hook.mjs", import.meta.url).pathname], {
    stdio: ["pipe", "pipe", "pipe"],
  });
  let stdout = "";
  let stderr = "";
  child.stdout.on("data", (chunk) => { stdout += chunk; });
  child.stderr.on("data", (chunk) => { stderr += chunk; });
  child.stdin.end(JSON.stringify(payload));
  const code = await new Promise((resolve) => child.on("close", resolve));
  return { code, stdout, stderr };
}

async function runPolicyHook(payload) {
  const child = spawn(process.execPath, [new URL("repo-policy-hook.mjs", import.meta.url).pathname], {
    stdio: ["pipe", "pipe", "pipe"],
  });
  let stdout = "";
  let stderr = "";
  child.stdout.on("data", (chunk) => { stdout += chunk; });
  child.stderr.on("data", (chunk) => { stderr += chunk; });
  child.stdin.end(JSON.stringify(payload));
  const code = await new Promise((resolve) => child.on("close", resolve));
  return { code, stdout, stderr };
}

async function scenario(manifestName, config) {
  const root = await mkdtemp(join(tmpdir(), "canuto-t7-retirement-"));
  const sourceDir = join(root, "source");
  const configPath = join(root, "hooks.json");
  const hooksDir = join(root, "hooks");
  const stateDir = join(root, "state");
  await mkdir(sourceDir, { recursive: true });
  await mkdir(hooksDir, { recursive: true });
  await writeFile(configPath, `${JSON.stringify(config, null, 2)}\n`, { mode: 0o600 });
  const manifest = JSON.parse(await readFile(new URL(manifestName, import.meta.url), "utf8"));
  delete manifest.preconditions;
  await writeFile(join(sourceDir, manifestName), `${JSON.stringify(manifest, null, 2)}\n`);
  await writeFile(join(sourceDir, "managed-hooks.schema.json"), await readFile(new URL("managed-hooks.schema.json", import.meta.url)));
  await writeFile(join(sourceDir, "repo-policy-hook.mjs"), await readFile(new URL("repo-policy-hook.mjs", import.meta.url)));
  return {
    root,
    configPath,
    hooksDir,
    stateDir,
    manifestPath: join(sourceDir, manifestName),
    homeDir: "/Users/tester",
  };
}

async function readyPreconditionScenario(manifestName, config, mutateReceipt = () => {}) {
  const root = await mkdtemp(join(tmpdir(), "canuto-t7-ready-precondition-"));
  const sourceDir = join(root, "source");
  const configPath = join(root, "hooks.json");
  const hooksDir = join(root, "hooks");
  const stateDir = join(root, "state");
  await mkdir(join(sourceDir, "audit"), { recursive: true });
  await mkdir(hooksDir, { recursive: true });
  await writeFile(configPath, `${JSON.stringify(config, null, 2)}\n`, { mode: 0o600 });

  const manifest = JSON.parse(await readFile(new URL(manifestName, import.meta.url), "utf8"));
  const receipt = JSON.parse(await readFile(new URL(manifest.preconditions[0].receipt, import.meta.url), "utf8"));
  receipt.status = "ready";
  receipt.pullRequest.state = "MERGED";
  receipt.pullRequest.candidateHeadSha = "c".repeat(40);
  receipt.pullRequest.candidateTreeSha = "d".repeat(40);
  receipt.pullRequest.mergeCommitSha = "a".repeat(40);
  receipt.pullRequest.mergeTreeSha = receipt.pullRequest.candidateTreeSha;
  receipt.mainContainment.observedMainSha = "b".repeat(40);
  receipt.mainContainment.candidateContained = true;
  receipt.mainContainment.contentContained = true;
  receipt.mainContainment.compareStatus = "ahead";
  receipt.blockers = [];
  receipt.ownerArtifact.hashProof = {
    repository: receipt.repository,
    verifiedAtCommitSha: receipt.pullRequest.mergeCommitSha,
    verifiedTreeSha: receipt.pullRequest.mergeTreeSha,
    manifest: {
      path: receipt.ownerArtifact.path,
      sha256: receipt.ownerArtifact.manifestSha256,
    },
    source: {
      path: receipt.ownerArtifact.sourcePath,
      sha256: receipt.ownerArtifact.sourceSha256,
    },
  };
  mutateReceipt(receipt);
  const receiptBytes = Buffer.from(`${JSON.stringify(receipt, null, 2)}\n`);
  manifest.preconditions[0].expectedHash = sha256(receiptBytes);
  await writeFile(join(sourceDir, manifestName), `${JSON.stringify(manifest, null, 2)}\n`);
  await writeFile(join(sourceDir, manifest.preconditions[0].receipt), receiptBytes);
  await writeFile(join(sourceDir, "managed-hooks.schema.json"), await readFile(new URL("managed-hooks.schema.json", import.meta.url)));
  return {
    root,
    configPath,
    hooksDir,
    stateDir,
    manifestPath: join(sourceDir, manifestName),
    homeDir: "/Users/tester",
  };
}

async function consumerPreconditionScenario({
  mutateReceipt = () => {},
  mutateInventory = () => {},
  mutateManifest = () => {},
  omitInventory = false,
  preserveInventoryHash = false,
} = {}) {
  const root = await mkdtemp(join(tmpdir(), "canuto-t7-consumer-precondition-"));
  const sourceDir = join(root, "source");
  const configPath = join(root, "hooks.json");
  const hooksDir = join(root, "hooks");
  const stateDir = join(root, "state");
  await mkdir(join(sourceDir, "audit"), { recursive: true });
  await mkdir(hooksDir, { recursive: true });
  await writeFile(configPath, `${JSON.stringify(configFor(CLAUDE_TARGETS), null, 2)}\n`, { mode: 0o600 });

  const manifestName = "managed-hooks-retirements-t7.claude.json";
  const manifest = JSON.parse(await readFile(new URL(manifestName, import.meta.url), "utf8"));
  const receipt = JSON.parse(await readFile(new URL(manifest.preconditions[0].receipt, import.meta.url), "utf8"));
  const inventory = JSON.parse(await readFile(new URL(receipt.inventory.path, import.meta.url), "utf8"));
  mutateInventory(inventory);
  const inventoryBytes = Buffer.from(`${JSON.stringify(inventory, null, 2)}\n`);
  if (!preserveInventoryHash) receipt.inventory.expectedHash = sha256(inventoryBytes);
  mutateReceipt(receipt);
  const receiptBytes = Buffer.from(`${JSON.stringify(receipt, null, 2)}\n`);
  manifest.preconditions[0].expectedHash = sha256(receiptBytes);
  mutateManifest(manifest);
  await writeFile(join(sourceDir, manifestName), `${JSON.stringify(manifest, null, 2)}\n`);
  await writeFile(join(sourceDir, manifest.preconditions[0].receipt), receiptBytes);
  if (!omitInventory) await writeFile(join(sourceDir, "audit", "t7-repo-policy-consumer-inventory.json"), inventoryBytes);
  await writeFile(join(sourceDir, "managed-hooks.schema.json"), await readFile(new URL("managed-hooks.schema.json", import.meta.url)));
  await writeFile(join(sourceDir, "manifest.json"), await readFile(new URL("manifest.json", import.meta.url)));
  await writeFile(join(sourceDir, "repo-policy-hook.mjs"), await readFile(new URL("repo-policy-hook.mjs", import.meta.url)));
  return {
    root,
    configPath,
    hooksDir,
    stateDir,
    manifestPath: join(sourceDir, manifestName),
    homeDir: "/Users/tester",
  };
}

test("T7 retirement manifests are valid and keep unsupported owner migrations out", async () => {
  const claude = JSON.parse(await readFile(new URL("managed-hooks-retirements-t7.claude.json", import.meta.url), "utf8"));
  const codex = JSON.parse(await readFile(new URL("managed-hooks-retirements-t7.codex.json", import.meta.url), "utf8"));
  const cu23 = JSON.parse(await readFile(new URL("managed-hooks-retirement-t7-cu23.claude.json", import.meta.url), "utf8"));
  assert.deepEqual(validateManifest(claude), []);
  assert.deepEqual(validateManifest(codex), []);
  assert.deepEqual(validateManifest(cu23), []);
  for (const manifest of [claude, codex]) {
    assert.deepEqual(manifest.preconditions.map((item) => item.id), ["repo-policy-consumers"]);
    assert.deepEqual(manifest.preconditions.map((item) => item.receipt), ["audit/t7-consumer-migration-receipt.json"]);
  }
  const ids = new Set([...claude.entries, ...codex.entries].map((entry) => entry.id));
  assert.equal(ids.has("CU-23"), false, "Dobra is not coupled to the general consumer receipt");
  assert.deepEqual([...ids].sort(), [
    "CU-01", "CU-02", "CU-03", "CU-05", "CU-06", "CU-13", "CU-16", "CU-17", "CU-19", "CU-20",
    "CU-24", "CU-25", "CU-28", "CU-33", "CU-37", "CU-41", "CU-57",
    "CX-05", "CX-06", "CX-07", "CX-08", "CX-11", "CX-13", "CX-18",
  ].sort());
  assert.deepEqual(cu23.preconditions, [{
    id: "papiro-dobra-owner",
    receipt: "audit/t7-papiro-dobra-owner-receipt.json",
    expectedHash: "81438658b5423be2f2e86fc211982ab39dc8b1d55da965eb96217d075481a84b",
    requiredStatus: "ready",
    receiptContract: "merged-owner-artifact-v1",
    expectedArtifactId: "CU-23",
    expectedRepository: "csorodrigo/papiro",
    expectedOwner: "repository:Papiro/Dobra",
    expectedPackage: "dobra",
  }]);
  assert.deepEqual(cu23.entries.map((entry) => entry.id), ["CU-23"]);
  for (const requiredField of ["expectedArtifactId", "expectedRepository", "expectedOwner", "expectedPackage"]) {
    const invalid = structuredClone(cu23);
    delete invalid.preconditions[0][requiredField];
    assert.ok(validateManifest(invalid).some((error) => error.includes(requiredField)));
  }
  const installer = await readFile(new URL("../../install.sh", import.meta.url), "utf8");
  assert.match(installer, /^  "\.agents\/hooks\/managed-hooks-retirement-t7-cu23\.claude\.json"$/m);
  assert.match(installer, /^  "\.agents\/hooks\/audit\/t7-papiro-dobra-owner-receipt\.json"$/m);
  const ownership = JSON.parse(await readFile(new URL("audit/t7-owner-dispositions.json", import.meta.url), "utf8"));
  const generalIds = new Set(["CU-01", "CU-02", "CU-03", "CU-05", "CU-06", "CU-25", "CU-28", "CU-33", "CU-37", "CX-11", "CX-13"]);
  assert.deepEqual(
    ownership.entries.filter((entry) => generalIds.has(entry.id)).map((entry) => entry.status),
    Array(generalIds.size).fill("consumer-ready-retirement-eligible"),
  );
  const dobra = ownership.entries.find((entry) => entry.id === "CU-23");
  assert.deepEqual(dobra, {
    id: "CU-23",
    owner: "repository:Papiro/Dobra",
    replacement: ".agents/hooks/dobra-compose-writer-guard.manifest.json",
    status: "owner-ready-retirement-eligible",
    receipt: "audit/t7-papiro-dobra-owner-receipt.json",
    retirementManifest: "managed-hooks-retirement-t7-cu23.claude.json",
  });
});

test("final consolidation replaces raw command logging and legacy machine evaluators", async () => {
  const active = JSON.parse(await readFile(new URL("managed-hooks.json", import.meta.url), "utf8"));
  assert.equal(active.entries.some((entry) => entry.id === "CU-20" || entry.command.includes("log-commands.sh")), false);
  const prompt = active.entries.find((entry) => entry.id === "CU-60");
  const bash = active.entries.find((entry) => entry.id === "CU-58");
  assert.equal(prompt.event, "UserPromptSubmit");
  assert.notEqual(prompt.command, bash.command);
  assert.equal(prompt.origin, "repo-policy-prompt-hook.mjs");
  assert.notEqual(prompt.expectedHash, bash.expectedHash);

  const result = await runPolicyHook({
    hook_event_name: "UserPromptSubmit",
    session_id: "test-session",
    cwd: process.cwd(),
    prompt: "api_key=unit-test-sensitive-value",
  });
  assert.equal(result.code, 0, result.stderr);
  const response = JSON.parse(result.stdout);
  assert.equal(response.hookSpecificOutput.hookEventName, "UserPromptSubmit");
  assert.match(response.hookSpecificOutput.additionalContext, /redact/i);

  const installer = await readFile(new URL("../../install.sh", import.meta.url), "utf8");
  assert.doesNotMatch(installer, /^  "\.agents\/hooks\/log-commands\.sh"$/m);
});

test("PostToolUse telemetry and event log retain only one-way digests", async () => {
  const root = await mkdtemp(join(tmpdir(), "canuto-telemetry-redaction-"));
  const project = join(root, "project");
  await mkdir(join(root, "tmp"), { recursive: true });
  await mkdir(join(project, ".agents", "vault", "audit"), { recursive: true });
  const hookDir = join(root, "hooks");
  const toolDir = join(root, "tools");
  await mkdir(hookDir, { recursive: true });
  await mkdir(toolDir, { recursive: true });
  const hookPath = join(hookDir, "posttooluse-universal.sh");
  await writeFile(hookPath, await readFile(new URL("posttooluse-universal.sh", import.meta.url)));
  const recordPath = join(root, "otel-record.jsonl");
  await writeFile(join(toolDir, "otel-emit.sh"), `#!/usr/bin/env bash
otel_enabled() { return 0; }
otel_emit_span() { printf '%s\\n' "\${1}|\${2}|\${3}|\${4}|\${5}" >> "$CANUTO_OTEL_RECORD"; }
otel_emit_counter() { :; }
`);
  const sentinelCommand = "unit-secret-command --token=do-not-export";
  const sentinelPath = "/private/unit-secret/path.txt";
  const child = spawn("bash", [hookPath], {
    cwd: project,
    env: {
      ...process.env,
      HOME: root,
      TMPDIR: join(root, "tmp"),
      CLAUDE_PROJECT_DIR: project,
      CANUTO_TOOLS_OTLP_ENABLED: "1",
      CANUTO_OTEL_SKIP_PROBE: "1",
      CANUTO_OTEL_PRINT_PAYLOAD: "1",
      CANUTO_EVENT_LOG_TOOLS: "core",
      CANUTO_OTEL_RECORD: recordPath,
    },
    stdio: ["pipe", "pipe", "pipe"],
  });
  let stderr = "";
  child.stderr.on("data", (chunk) => { stderr += chunk; });
  child.stdin.end(JSON.stringify({
    tool_name: "Bash",
    tool_input: { command: sentinelCommand, file_path: sentinelPath },
    tool_response: { duration_ms: 4, success: true },
  }));
  const code = await new Promise((resolve) => child.on("close", resolve));
  assert.equal(code, 0);
  assert.doesNotMatch(stderr, new RegExp(sentinelCommand.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  assert.doesNotMatch(stderr, new RegExp(sentinelPath.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  const record = await readFile(recordPath, "utf8");
  assert.doesNotMatch(record, new RegExp(sentinelCommand.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  assert.doesNotMatch(record, new RegExp(sentinelPath.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
  assert.match(record, /sha256:[a-f0-9]{64}/);
  await rm(root, { recursive: true, force: true });
});

test("T7 consumer inventory and separate CU-23 owner receipt are independently ready", async () => {
  const manifestBytes = await readFile(new URL("manifest.json", import.meta.url));
  const manifest = JSON.parse(manifestBytes);
  assert.deepEqual(validateRepoPolicyManifest(manifest), []);
  assert.deepEqual(manifest.policies.map((policy) => policy.id), [
    "validation-receipt",
    "commit",
    "pull-request",
  ]);
  const validation = manifest.policies.find((policy) => policy.id === "validation-receipt");
  assert.deepEqual(validation.options.allowedArgv, [["bash", "test-framework.sh"]]);
  assert.deepEqual(validation.options.requiredFiles, ["test-framework.sh"]);

  const ownerBytes = await readFile(new URL("audit/t7-papiro-dobra-owner-receipt.json", import.meta.url));
  const owner = JSON.parse(ownerBytes);
  assert.equal(sha256(ownerBytes), "81438658b5423be2f2e86fc211982ab39dc8b1d55da965eb96217d075481a84b");
  assert.equal(owner.status, "ready");
  assert.equal(owner.pullRequest.number, 849);
  assert.equal(owner.pullRequest.state, "MERGED");
  assert.equal(owner.pullRequest.candidateHeadSha, "23e5bc067d700d19473e9a6aebe5deff1fd05102");
  assert.equal(owner.pullRequest.mergeCommitSha, "5e7ddf90ca31313947ba2697c695dfa306f83d88");
  assert.equal(owner.pullRequest.candidateTreeSha, "9124f2c617b251fa54fcaa2675d146a2bca58b05");
  assert.equal(owner.pullRequest.mergeTreeSha, owner.pullRequest.candidateTreeSha);
  assert.equal(owner.mainContainment.observedMainSha, owner.pullRequest.mergeCommitSha);
  assert.equal(owner.mainContainment.candidateContained, true);
  assert.equal(owner.mainContainment.contentContained, true);
  assert.equal(owner.mainContainment.compareStatus, "identical");
  assert.deepEqual(owner.blockers, []);
  assert.equal(owner.ownerArtifact.manifestSha256, "c5c3d973e0d41e88800e2d27ae79dd806cdbf158019a75fcb84255f1ddaa965d");
  assert.equal(owner.ownerArtifact.sourceSha256, "d4ecea86c03c1c8e495dc1bb9d08bf200509ad22367555cabce5a9604c0f84b6");
  assert.equal(owner.ownerArtifact.hashProof.repository, "csorodrigo/papiro");
  assert.equal(owner.ownerArtifact.hashProof.verifiedAtCommitSha, owner.pullRequest.mergeCommitSha);
  assert.equal(owner.ownerArtifact.hashProof.verifiedTreeSha, owner.pullRequest.mergeTreeSha);
  assert.equal(owner.ownerArtifact.hashProof.manifest.sha256, owner.ownerArtifact.manifestSha256);
  assert.equal(owner.ownerArtifact.hashProof.source.sha256, owner.ownerArtifact.sourceSha256);

  const inventoryBytes = await readFile(new URL("audit/t7-repo-policy-consumer-inventory.json", import.meta.url));
  const inventory = JSON.parse(inventoryBytes);
  const expectedPolicies = [
    "worktree-dependencies",
    "build-typecheck",
    "claims",
    "branch-creation",
    "deploy-target",
    "validation-receipt",
    "commit",
    "pull-request",
  ];
  assert.deepEqual(inventory.policies.map((item) => item.id), expectedPolicies);
  for (const policy of inventory.policies) {
    assert.deepEqual(policy.consumers.map((item) => item.repository).sort(), [
      "csorodrigo/canuto-framework",
      "csorodrigo/papiro",
    ]);
  }
  const deploy = inventory.policies.find((item) => item.id === "deploy-target");
  assert.deepEqual(deploy.consumers.find((item) => item.repository === "csorodrigo/canuto-framework"), {
    repository: "csorodrigo/canuto-framework",
    disposition: "no-policy",
    applicability: "not-applicable",
    evidence: "Canuto has no repository deploy command",
  });
  assert.deepEqual(
    deploy.consumers.find((item) => item.repository === "csorodrigo/papiro").expectedOptions.targets[0].commands,
    ["npm run deploy:prod"],
  );
  const build = inventory.policies.find((item) => item.id === "build-typecheck");
  assert.deepEqual(
    build.consumers.find((item) => item.repository === "csorodrigo/papiro").expectedOptions.commands,
    ["npm run typecheck:codex"],
  );
  const papiroValidation = inventory.policies.find((item) => item.id === "validation-receipt")
    .consumers.find((item) => item.repository === "csorodrigo/papiro");
  const papiroRepository = inventory.repositories.find((item) => item.id === "papiro-dobra");
  assert.equal(papiroRepository.candidateHeadSha, "09a444de0668ac913300c1d484521e925cbe924e");
  assert.equal(papiroRepository.candidateTreeSha, "a8a6e1bbe95ffd33a5492283fd6e9afe71b110a2");
  assert.equal(papiroRepository.mergeCommitSha, "676a3124429546cd9e7780dded9ff32e496547f5");
  assert.equal(papiroRepository.mergeTreeSha, papiroRepository.candidateTreeSha);
  assert.equal(papiroRepository.manifestSha256, "80b66071997182fd710755f321d39afee6845417a12194782669ea24331bfd47");
  assert.equal(papiroRepository.manifestStatus, "merged-versioned-contract-tested");
  assert.deepEqual(papiroValidation.expectedOptions.allowedArgv, [[
    "npm", "run", "test", "--", "tests/dobra-compose-writer-guard.test.ts",
  ]]);
  assert.deepEqual(papiroValidation.expectedOptions.requiredFiles, [
    ".agents/hooks/dobra-compose-writer-guard.sh",
    ".agents/hooks/dobra-compose-writer-guard.manifest.json",
    ".agents/hooks/dobra-compose-writer-guard-manager.mjs",
    ".claude/settings.json",
    "docs/operations/dobra-compose-writer-guard.md",
  ]);

  const consumerBytes = await readFile(new URL("audit/t7-consumer-migration-receipt.json", import.meta.url));
  const consumer = JSON.parse(consumerBytes);
  assert.equal(consumer.status, "ready");
  assert.equal(consumer.consumers[0].status, "versioned-contract-tested");
  assert.equal(consumer.consumers[0].manifestSha256, sha256(manifestBytes));
  assert.equal(consumer.inventory.expectedHash, sha256(inventoryBytes));
  assert.equal(consumer.consumers[1].repository, "csorodrigo/papiro");
  assert.equal(consumer.consumers[1].manifestSha256, papiroRepository.manifestSha256);
  assert.equal(consumer.consumers[1].publication.mergeCommitSha, papiroRepository.mergeCommitSha);
  assert.equal(consumer.consumers[1].publication.mergeTreeSha, papiroRepository.mergeTreeSha);
  assert.deepEqual(consumer.blockers, []);
  for (const manifestName of ["managed-hooks-retirements-t7.claude.json", "managed-hooks-retirements-t7.codex.json"]) {
    const retirement = JSON.parse(await readFile(new URL(manifestName, import.meta.url), "utf8"));
    assert.equal(retirement.preconditions[0].expectedHash, sha256(consumerBytes));
    assert.equal(retirement.preconditions[0].requiredStatus, "ready");
  }
  assert.doesNotMatch(consumerBytes.toString("utf8"), /t7-papiro-dobra-owner-receipt/);
  assert.doesNotMatch(consumerBytes.toString("utf8"), /CU-23/);
});

test("Canuto consumer manifest proves exact record, remote identity and Stop verification", async (t) => {
  const root = await mkdtemp(join(tmpdir(), "canuto-t7-consumer-"));
  const remote = `${root}-remote.git`;
  t.after(() => rm(root, { recursive: true, force: true }));
  t.after(() => rm(remote, { recursive: true, force: true }));
  await git(root, "init", "-b", "main");
  await git(root, "config", "user.name", "Canuto Fixture");
  await git(root, "config", "user.email", "canuto@example.invalid");
  await mkdir(join(root, ".agents", "hooks"), { recursive: true });
  await writeFile(join(root, ".agents", "hooks", "manifest.json"), await readFile(new URL("manifest.json", import.meta.url)));
  await writeFile(join(root, "test-framework.sh"), "#!/usr/bin/env bash\nexit 0\n");
  await git(root, "add", ".");
  await git(root, "commit", "-m", "fixture");
  await execFile("git", ["init", "--bare", remote], { encoding: "utf8" });
  await git(root, "remote", "add", "origin", remote);
  await git(root, "push", "-u", "origin", "main");

  const cli = new URL("policies/repo/validation-receipt-cli.mjs", import.meta.url).pathname;
  await assert.rejects(
    execFile(process.execPath, [cli, "record", "--session", "t7-consumer", "--file", "test-framework.sh", "--", "/usr/bin/true"], { cwd: root, encoding: "utf8" }),
    /validation argv is not declared/,
  );
  const recorded = await execFile(process.execPath, [
    cli,
    "record",
    "--session", "t7-consumer",
    "--file", "test-framework.sh",
    "--remote",
    "--", "bash", "test-framework.sh",
  ], { cwd: root, encoding: "utf8" });
  assert.equal(JSON.parse(recorded.stdout).operation, "record");

  const stopped = await runStop({
    session_id: "t7-consumer",
    cwd: root,
    hook_event_name: "Stop",
    stop_hook_active: false,
  });
  assert.equal(stopped.code, 0, stopped.stderr);
  assert.deepEqual(JSON.parse(stopped.stdout), {});
});

test("canonical ready consumer receipt enables T7 retirement, verification and rollback", async (t) => {
  const item = await scenario("managed-hooks-retirements-t7.claude.json", configFor(CLAUDE_TARGETS));
  const canonical = {
    ...item,
    manifestPath: new URL("managed-hooks-retirements-t7.claude.json", import.meta.url).pathname,
  };
  t.after(() => rm(item.root, { recursive: true, force: true }));
  const original = JSON.parse(await readFile(item.configPath, "utf8"));
  const plan = await buildPlan(canonical);
  assert.equal(plan.changed, true);
  assert.deepEqual(plan.entries.filter((entry) => entry.action === "remove").map((entry) => entry.id).sort(), [
    "CU-01", "CU-02", "CU-03", "CU-05", "CU-06", "CU-13", "CU-16", "CU-17", "CU-19", "CU-20",
    "CU-24", "CU-25", "CU-28", "CU-33", "CU-37", "CU-41", "CU-57",
  ].sort());
  const applied = await applyPlan({ ...canonical, fingerprint: plan.fingerprint });
  assert.equal((await verifyState(canonical)).ok, true);
  await rollbackBatch({ stateDir: item.stateDir, batchId: applied.batchId });
  assert.deepEqual(JSON.parse(await readFile(item.configPath, "utf8")), original);
});

test("T7 consumer receipt contract rejects repinned contradictory evidence", async (t) => {
  const cases = [
    ["remaining blocker", { mutateReceipt: (receipt) => { receipt.blockers = ["blocked"]; } }, /blockers must be an empty array/],
    ["consumer pending", { mutateReceipt: (receipt) => { receipt.consumers[0].pending = ["pending"]; } }, /pending must be an empty array/],
    ["extra consumer", { mutateReceipt: (receipt) => { receipt.consumers.push({ ...receipt.consumers[0], id: "extra", repository: "other/repo" }); } }, /repository set does not match/],
    ["duplicate consumer", { mutateReceipt: (receipt) => { receipt.consumers[1] = { ...receipt.consumers[0] }; } }, /repository set does not match/],
    ["invalid candidate head", { mutateReceipt: (receipt) => { receipt.consumers[1].publication.candidateHeadSha = "invalid"; } }, /candidateHeadSha is missing or invalid/],
    ["tree mismatch", { mutateReceipt: (receipt) => { receipt.consumers[1].publication.mergeTreeSha = "f".repeat(40); } }, /candidate and merge trees do not match/],
    ["gate proof mismatch", { mutateReceipt: (receipt) => { receipt.consumers[1].publication.gateProof.sha = "f".repeat(40); } }, /gate proof is not bound/],
    ["fully repinned alternate publication", {
      mutateReceipt: (receipt) => {
        const publication = receipt.consumers[1].publication;
        publication.pullRequest = 999;
        publication.candidateHeadSha = "b".repeat(40);
        publication.candidateTreeSha = "c".repeat(40);
        publication.mergeCommitSha = "d".repeat(40);
        publication.mergeTreeSha = publication.candidateTreeSha;
        publication.gateReceipt = "alternate:1";
        publication.gateProof = { sha: publication.candidateHeadSha, tree: publication.candidateTreeSha, verdict: "verde", runid: "alternate-run" };
        receipt.consumers[1].manifestSha256 = "e".repeat(64);
      },
      mutateInventory: (inventory) => {
        const repository = inventory.repositories[1];
        repository.candidateHeadSha = "b".repeat(40);
        repository.candidateTreeSha = "c".repeat(40);
        repository.mergeCommitSha = "d".repeat(40);
        repository.mergeTreeSha = repository.candidateTreeSha;
        repository.gateReceipt = "alternate:1";
        repository.manifestSha256 = "e".repeat(64);
      },
    }, /does not match the pinned publication/],
    ["missing gate result", { mutateReceipt: (receipt) => { delete receipt.consumers[1].publication.gateResult; } }, /gate result is invalid/],
    ["manifest mismatch", { mutateInventory: (inventory) => { inventory.repositories[1].manifestSha256 = "f".repeat(64); } }, /manifestSha256 differs/],
    ["Canuto manifest path mismatch", { mutateInventory: (inventory) => { inventory.repositories[0].manifest = "other.json"; } }, /Canuto manifest evidence differs/],
    ["Canuto manifest status mismatch", { mutateInventory: (inventory) => { inventory.repositories[0].manifestStatus = "blocked"; } }, /Canuto manifest evidence differs/],
    ["fully repinned Canuto publication and manifest", {
      mutateReceipt: (receipt) => {
        receipt.consumers[0].manifestSha256 = "f".repeat(64);
        receipt.consumers[0].publication.mergeCommitSha = "a".repeat(40);
        receipt.consumers[0].publication.containedInCanutoMainSha = "b".repeat(40);
      },
      mutateInventory: (inventory) => { inventory.repositories[0].manifestSha256 = "f".repeat(64); },
      mutateManifest: (manifest) => {
        manifest.preconditions[0].expectedCanutoManifestSha256 = "f".repeat(64);
        manifest.preconditions[0].expectedCanutoMergeCommitSha = "a".repeat(40);
        manifest.preconditions[0].expectedCanutoContainedInMainSha = "b".repeat(40);
      },
    }, /Canuto manifest hash mismatch/],
    ["Papiro build command drift", { mutateInventory: (inventory) => { inventory.policies.find((item) => item.id === "build-typecheck").consumers[1].expectedOptions.commands = ["npm run build"]; } }, /build\/typecheck inventory differs/],
    ["Papiro deploy command drift", { mutateInventory: (inventory) => { inventory.policies.find((item) => item.id === "deploy-target").consumers[1].expectedOptions.targets[0].commands = ["npm run deploy:other"]; } }, /deploy inventory differs/],
    ["Papiro validation argv drift", { mutateInventory: (inventory) => { inventory.policies.find((item) => item.id === "validation-receipt").consumers[1].expectedOptions.allowedArgv = [["npm", "test"]]; } }, /validation inventory differs/],
    ["Canuto validation argv drift", { mutateInventory: (inventory) => { inventory.policies.find((item) => item.id === "validation-receipt").consumers[0].expectedOptions.allowedArgv = [["bash", "other.sh"]]; } }, /Canuto validation inventory differs/],
    ["Papiro pull-request required files drift", { mutateInventory: (inventory) => { inventory.policies.find((item) => item.id === "pull-request").consumers[1].expectedRequiredFiles = ["other.txt"]; } }, /pull-request inventory differs/],
    ["Papiro receipt validation drift", { mutateReceipt: (receipt) => { receipt.consumers[1].validation.allowedArgv = [["npm", "test"]]; } }, /validation allowedArgv does not match/],
    ["unresolved policy", { mutateInventory: (inventory) => { inventory.policies.find((item) => item.id === "commit").consumers[1].disposition = "pending-versioned-manifest"; } }, /invalid applicability\/disposition pair/],
    ["blocked required policy", { mutateInventory: (inventory) => { inventory.policies.find((item) => item.id === "commit").consumers[1].disposition = "blocked"; } }, /invalid applicability\/disposition pair/],
    ["applicability mismatch", { mutateInventory: (inventory) => { inventory.policies.find((item) => item.id === "claims").consumers[1].applicability = "required"; } }, /invalid applicability\/disposition pair/],
    ["inventory hash mismatch", { mutateInventory: (inventory) => { inventory.repositories[1].gateReceipt = "changed"; }, preserveInventoryHash: true }, /inventory hash mismatch/],
    ["missing inventory", { omitInventory: true }, /inventory is missing/],
    ["inventory path escape", { mutateReceipt: (receipt) => { receipt.inventory.path = "../outside.json"; } }, /inventory (?:path does not match|must stay inside)/],
  ];
  for (const [name, options, expectedError] of cases) {
    await t.test(name, async (inner) => {
      const item = await consumerPreconditionScenario(options);
      inner.after(() => rm(item.root, { recursive: true, force: true }));
      await assert.rejects(buildPlan(item), expectedError);
      await assert.rejects(applyPlan({ ...item, fingerprint: "0".repeat(64) }), expectedError);
    });
  }
});

test("canonical ready CU-23 receipt enables exact retirement, verification and rollback", async (t) => {
  const manifestPath = new URL("managed-hooks-retirement-t7-cu23.claude.json", import.meta.url).pathname;
  const original = configFor(CU23_TARGETS);
  const cu23Group = original.hooks.PreToolUse.find((group) => group.matcher === "Bash");
  cu23Group.hooks.push(
    { type: "command", command: "~/.claude/hooks/dobra-compose-writer-guard.sh", timeout: null },
    { type: "command", command: "~/.claude/hooks/dobra-compose-writer-guard.sh", timeout: 5 },
    { type: "command", command: "~/.claude/hooks/dobra-compose-writer-guard.sh", env: { KEEP: "external" } },
  );
  const item = await scenario("managed-hooks-retirement-t7-cu23.claude.json", original);
  const canonical = { ...item, manifestPath };
  t.after(() => rm(item.root, { recursive: true, force: true }));
  const plan = await buildPlan(canonical);
  assert.deepEqual(plan.entries, [{ id: "CU-23", action: "remove" }]);
  assert.equal(countCommand(plan.nextConfig, "~/.claude/hooks/dobra-compose-writer-guard.sh"), 3);
  assert.deepEqual(
    plan.nextConfig.hooks.PreToolUse.find((group) => group.matcher === "Bash").hooks,
    cu23Group.hooks.slice(1),
  );
  const applied = await applyPlan({ ...canonical, fingerprint: plan.fingerprint });
  assert.equal((await verifyState(canonical)).ok, true);
  await rollbackBatch({ stateDir: item.stateDir, batchId: applied.batchId });
  assert.deepEqual(JSON.parse(await readFile(item.configPath, "utf8")), original);
});

test("CU-23 owner receipt contract rejects contradictory ready evidence", async (t) => {
  const cases = [
    ["missing artifact ID", (receipt) => { delete receipt.id; }, /artifact ID does not match/],
    ["wrong artifact ID", (receipt) => { receipt.id = "CU-99"; }, /artifact ID does not match/],
    ["missing repository", (receipt) => { delete receipt.repository; }, /owner repository does not match/],
    ["wrong repository", (receipt) => { receipt.repository = "other/repository"; }, /owner repository does not match/],
    ["missing owner", (receipt) => { delete receipt.owner; }, /owner identity does not match/],
    ["wrong owner", (receipt) => { receipt.owner = "repository:Other"; }, /owner identity does not match/],
    ["open PR", (receipt) => { receipt.pullRequest.state = "OPEN"; }, /pull request is not MERGED/],
    ["missing candidate head", (receipt) => { delete receipt.pullRequest.candidateHeadSha; }, /candidate head SHA is missing or invalid/],
    ["invalid candidate head", (receipt) => { receipt.pullRequest.candidateHeadSha = "not-a-hash"; }, /candidate head SHA is missing or invalid/],
    ["missing candidate tree", (receipt) => { delete receipt.pullRequest.candidateTreeSha; }, /candidate tree SHA is missing or invalid/],
    ["invalid candidate tree", (receipt) => { receipt.pullRequest.candidateTreeSha = "not-a-hash"; }, /candidate tree SHA is missing or invalid/],
    ["missing merge tree", (receipt) => { delete receipt.pullRequest.mergeTreeSha; }, /merge tree SHA is missing or invalid/],
    ["invalid merge tree", (receipt) => { receipt.pullRequest.mergeTreeSha = "not-a-hash"; }, /merge tree SHA is missing or invalid/],
    ["candidate and merge tree mismatch", (receipt) => { receipt.pullRequest.mergeTreeSha = "e".repeat(40); }, /candidate and merge tree SHAs do not match/],
    ["missing containment", (receipt) => { receipt.mainContainment.candidateContained = false; }, /candidate is not contained in main/],
    ["missing content containment", (receipt) => { delete receipt.mainContainment.contentContained; }, /candidate content is not contained in main/],
    ["false content containment", (receipt) => { receipt.mainContainment.contentContained = false; }, /candidate content is not contained in main/],
    ["diverged comparison", (receipt) => { receipt.mainContainment.compareStatus = "diverged"; }, /compare status is not ahead or identical/],
    ["identical comparison at another main SHA", (receipt) => { receipt.mainContainment.compareStatus = "identical"; }, /identical comparison does not observe the merge commit at main/],
    ["remaining blocker", (receipt) => { receipt.blockers = ["still blocked"]; }, /blockers must be an empty array/],
    ["empty manifest path", (receipt) => { receipt.ownerArtifact.path = ""; }, /paths are missing or empty/],
    ["empty source path", (receipt) => { receipt.ownerArtifact.sourcePath = ""; }, /paths are missing or empty/],
    ["missing canonical repository", (receipt) => { delete receipt.ownerArtifact.canonicalRepository; }, /canonical repository does not match/],
    ["wrong canonical repository", (receipt) => { receipt.ownerArtifact.canonicalRepository = "other/repository"; }, /canonical repository does not match/],
    ["missing package", (receipt) => { delete receipt.ownerArtifact.packageName; }, /owner package does not match/],
    ["wrong package", (receipt) => { receipt.ownerArtifact.packageName = "other"; }, /owner package does not match/],
    ["unproved hashes", (receipt) => { delete receipt.ownerArtifact.hashProof; }, /hash proof is not tied to the merge commit/],
    ["missing proved tree", (receipt) => { delete receipt.ownerArtifact.hashProof.verifiedTreeSha; }, /verified tree SHA is missing or invalid/],
    ["proved tree mismatch", (receipt) => { receipt.ownerArtifact.hashProof.verifiedTreeSha = "e".repeat(40); }, /hash proof is not tied to the merge tree/],
    ["proof repository missing", (receipt) => { delete receipt.ownerArtifact.hashProof.repository; }, /hash proof repository does not match/],
    ["proof repository wrong", (receipt) => { receipt.ownerArtifact.hashProof.repository = "other/repository"; }, /hash proof repository does not match/],
  ];
  for (const [name, mutateReceipt, expectedError] of cases) {
    await t.test(name, async (inner) => {
      const item = await readyPreconditionScenario(
        "managed-hooks-retirement-t7-cu23.claude.json",
        configFor(CU23_TARGETS),
        mutateReceipt,
      );
      inner.after(() => rm(item.root, { recursive: true, force: true }));
      await assert.rejects(buildPlan(item), expectedError);
      await assert.rejects(applyPlan({ ...item, fingerprint: "0".repeat(64) }), expectedError);
    });
  }
});

test("ready owner fixture retires only CU-23 and preserves external registrations", async (t) => {
  const original = configFor(CU23_TARGETS);
  const cu23Group = original.hooks.PreToolUse.find((group) => group.matcher === "Bash");
  cu23Group.hooks.push(
    { type: "command", command: "~/.claude/hooks/dobra-compose-writer-guard.sh", timeout: null },
    { type: "command", command: "~/.claude/hooks/dobra-compose-writer-guard.sh", timeout: 5 },
    { type: "command", command: "~/.claude/hooks/dobra-compose-writer-guard.sh", env: { KEEP: "external" } },
  );
  const item = await readyPreconditionScenario("managed-hooks-retirement-t7-cu23.claude.json", original);
  t.after(() => rm(item.root, { recursive: true, force: true }));
  const plan = await buildPlan(item);
  assert.equal(plan.entries.filter((entry) => entry.action === "remove").length, 1);
  assert.equal(plan.entries[0].id, "CU-23");
  assert.equal(countCommand(plan.nextConfig, "~/.claude/hooks/dobra-compose-writer-guard.sh"), 3);
  assert.deepEqual(
    plan.nextConfig.hooks.PreToolUse.find((group) => group.matcher === "Bash").hooks,
    cu23Group.hooks.slice(1),
  );
  assert.equal(countCommand(plan.nextConfig, EXTERNAL), 1);
  assert.equal(plan.nextConfig.theme, "preserved");
  const applied = await applyPlan({ ...item, fingerprint: plan.fingerprint });
  assert.equal((await verifyState(item)).ok, true);
  await rollbackBatch({ stateDir: item.stateDir, batchId: applied.batchId });
  assert.deepEqual(JSON.parse(await readFile(item.configPath, "utf8")), original);
});

test("T7 plan/apply/verify/rollback removes only selected Claude registrations", async (t) => {
  const original = configFor(CLAUDE_TARGETS);
  const item = await scenario("managed-hooks-retirements-t7.claude.json", original);
  t.after(() => rm(item.root, { recursive: true, force: true }));
  const plan = await buildPlan(item);
  assert.equal(plan.entries.filter((entry) => entry.action === "remove").length, CLAUDE_TARGETS.length);
  assert.equal(countCommand(plan.nextConfig, EXTERNAL), 1);
  assert.equal(plan.nextConfig.theme, "preserved");
  const applied = await applyPlan({ ...item, fingerprint: plan.fingerprint });
  assert.equal((await verifyState(item)).ok, true);
  await rollbackBatch({ stateDir: item.stateDir, batchId: applied.batchId });
  assert.deepEqual(JSON.parse(await readFile(item.configPath, "utf8")), original);
});

test("T7 Codex plan replaces legacy repository and machine gates with the shared repo runner", async (t) => {
  const original = configFor(CODEX_TARGETS);
  const item = await scenario("managed-hooks-retirements-t7.codex.json", original);
  t.after(() => rm(item.root, { recursive: true, force: true }));
  const plan = await buildPlan(item);
  assert.equal(plan.entries.filter((entry) => entry.action === "remove").length, 6);
  assert.equal(plan.entries.filter((entry) => entry.action === "add").length, 1);
  assert.equal(countCommand(plan.nextConfig, "~/.claude/hooks/repo-policy-hook.mjs"), 1);
  assert.equal(countCommand(plan.nextConfig, EXTERNAL), 1);
  const applied = await applyPlan({ ...item, fingerprint: plan.fingerprint });
  assert.equal((await verifyState(item)).ok, true);
  await rollbackBatch({ stateDir: item.stateDir, batchId: applied.batchId });
  assert.deepEqual(JSON.parse(await readFile(item.configPath, "utf8")), original);
});
