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
];
const CODEX_TARGETS = [
  ["PreToolUse", "^Bash$", 30, "~/.claude/hooks/lib/codex-adapt.sh ~/.claude/hooks/assert-deploy-target.sh"],
  ["PreToolUse", "^Bash$", 180, "~/.claude/hooks/lib/codex-adapt.sh ~/.claude/hooks/pre-pr-bash-gate.sh"],
];
const EXTERNAL = "/opt/external/preserve-me";

function configFor(targets) {
  const hooks = { PreToolUse: [{ matcher: "External", hooks: [{ type: "command", command: EXTERNAL, timeout: 9 }] }] };
  for (const [event, matcher, timeout, command] of targets) {
    const groups = hooks[event] ??= [];
    let group = groups.find((candidate) => candidate.matcher === matcher);
    if (!group) {
      group = { matcher, hooks: [] };
      groups.push(group);
    }
    group.hooks.push({ type: "command", command, timeout });
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

test("T7 retirement manifests are valid and keep unsupported owner migrations out", async () => {
  const claude = JSON.parse(await readFile(new URL("managed-hooks-retirements-t7.claude.json", import.meta.url), "utf8"));
  const codex = JSON.parse(await readFile(new URL("managed-hooks-retirements-t7.codex.json", import.meta.url), "utf8"));
  assert.deepEqual(validateManifest(claude), []);
  assert.deepEqual(validateManifest(codex), []);
  for (const manifest of [claude, codex]) {
    assert.deepEqual(manifest.preconditions.map((item) => item.id), ["repo-policy-consumers"]);
    assert.deepEqual(manifest.preconditions.map((item) => item.receipt), ["audit/t7-consumer-migration-receipt.json"]);
  }
  const ids = new Set([...claude.entries, ...codex.entries].map((entry) => entry.id));
  assert.equal(ids.has("CU-23"), false, "Dobra remains externally owned until its source is proved");
  assert.deepEqual([...ids].sort(), ["CU-01", "CU-02", "CU-03", "CU-05", "CU-06", "CU-25", "CU-28", "CU-33", "CU-37", "CX-11", "CX-13", "CX-18"].sort());
  const ownership = JSON.parse(await readFile(new URL("audit/t7-owner-dispositions.json", import.meta.url), "utf8"));
  const dobra = ownership.entries.find((entry) => entry.id === "CU-23");
  assert.deepEqual(dobra, {
    id: "CU-23",
    owner: "repository:Papiro/Dobra",
    replacement: ".agents/hooks/dobra-compose-writer-guard.manifest.json",
    status: "blocked-owner-main-containment",
    receipt: "audit/t7-papiro-dobra-owner-receipt.json",
  });
});

test("T7 consumer inventory and separate owner receipt are pinned and truthfully blocked", async () => {
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
  assert.equal(owner.status, "blocked");
  assert.equal(owner.pullRequest.number, 849);
  assert.equal(owner.pullRequest.state, "OPEN");
  assert.equal(owner.pullRequest.candidateHeadSha, "74f1462b021535aea9a7bfee8f27b6a924e47e43");
  assert.equal(owner.mainContainment.observedMainSha, "bd8c248b6bd4177bb2fd26f86a436026fe984fb5");
  assert.equal(owner.mainContainment.candidateContained, false);
  assert.equal(owner.mainContainment.compareStatus, "diverged");

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
  assert.deepEqual(papiroValidation.expectedOptions.allowedArgv, [[
    "npm", "run", "test", "--", "tests/dobra-compose-writer-guard.test.ts",
  ]]);

  const consumerBytes = await readFile(new URL("audit/t7-consumer-migration-receipt.json", import.meta.url));
  const consumer = JSON.parse(consumerBytes);
  assert.equal(consumer.status, "blocked");
  assert.equal(consumer.consumers[0].status, "contract-tested");
  assert.equal(consumer.consumers[0].manifestSha256, sha256(manifestBytes));
  assert.equal(consumer.inventory.expectedHash, sha256(inventoryBytes));
  assert.match(consumer.blockers.join(" "), /candidate-SHA/);
  assert.match(consumer.blockers.join(" "), /Papiro candidate head has no versioned/);
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

test("canonical T7 retirements stay blocked until the consumer migration receipt is ready", async (t) => {
  const item = await scenario("managed-hooks-retirements-t7.claude.json", configFor(CLAUDE_TARGETS));
  t.after(() => rm(item.root, { recursive: true, force: true }));
  await assert.rejects(
    buildPlan({ ...item, manifestPath: new URL("managed-hooks-retirements-t7.claude.json", import.meta.url).pathname }),
    /precondition repo-policy-consumers is blocked, expected ready/,
  );
  await assert.rejects(
    applyPlan({
      ...item,
      manifestPath: new URL("managed-hooks-retirements-t7.claude.json", import.meta.url).pathname,
      fingerprint: "0".repeat(64),
    }),
    /precondition repo-policy-consumers is blocked, expected ready/,
  );
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

test("T7 Codex plan replaces legacy deploy/PR gates with the shared repo runner", async (t) => {
  const original = configFor(CODEX_TARGETS);
  const item = await scenario("managed-hooks-retirements-t7.codex.json", original);
  t.after(() => rm(item.root, { recursive: true, force: true }));
  const plan = await buildPlan(item);
  assert.equal(plan.entries.filter((entry) => entry.action === "remove").length, 2);
  assert.equal(plan.entries.filter((entry) => entry.action === "add").length, 1);
  assert.equal(countCommand(plan.nextConfig, "~/.claude/hooks/repo-policy-hook.mjs"), 1);
  assert.equal(countCommand(plan.nextConfig, EXTERNAL), 1);
  const applied = await applyPlan({ ...item, fingerprint: plan.fingerprint });
  assert.equal((await verifyState(item)).ok, true);
  await rollbackBatch({ stateDir: item.stateDir, batchId: applied.batchId });
  assert.deepEqual(JSON.parse(await readFile(item.configPath, "utf8")), original);
});
