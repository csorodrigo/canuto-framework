import assert from "node:assert/strict";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { applyPlan, buildPlan, rollbackBatch, validateManifest, verifyState } from "./reconcile-hooks.mjs";

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
  const ids = new Set([...claude.entries, ...codex.entries].map((entry) => entry.id));
  assert.equal(ids.has("CU-23"), false, "Dobra remains externally owned until its source is proved");
  assert.deepEqual([...ids].sort(), ["CU-01", "CU-02", "CU-03", "CU-05", "CU-06", "CU-25", "CU-28", "CU-33", "CU-37", "CX-11", "CX-13", "CX-18"].sort());
  const ownership = JSON.parse(await readFile(new URL("audit/t7-owner-dispositions.json", import.meta.url), "utf8"));
  const dobra = ownership.entries.find((entry) => entry.id === "CU-23");
  assert.deepEqual(dobra, {
    id: "CU-23",
    owner: "repository:Papiro/Dobra",
    replacement: null,
    status: "blocked-owner-receipt",
  });
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
