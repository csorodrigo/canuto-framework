import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import {
  chmodSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import { applyPlan, buildPlan, rollbackBatch, validateManifest, verifyState } from "./reconcile-hooks.mjs";

const TARGET_IDS = new Set(["CU-40", "CU-44", "CU-46", "CU-51", "CU-52", "CU-53", "CU-54", "CU-55", "CU-56", "CX-02"]);
const CCGRAM_COMMAND = "~/.local/share/uv/tools/ccgram/bin/python -m ccgram.main hook";
const PROBE_COMMAND = "~/.claude/hooks/lib/codex-adapt.sh ~/.claude/hooks/probe-canuto-chain.sh";

function digest(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function readJson(url) {
  return JSON.parse(readFileSync(url, "utf8"));
}

function hookCount(config) {
  return Object.values(config.hooks ?? {}).reduce(
    (total, groups) => total + groups.reduce((eventTotal, group) => eventTotal + group.hooks.length, 0),
    0,
  );
}

function findCommands(config, command) {
  return Object.values(config.hooks ?? {}).flatMap((groups) => groups.flatMap((group) => group.hooks.filter((hook) => hook.command === command)));
}

function externalState(config, entries) {
  const topLevel = Object.fromEntries(Object.entries(config).filter(([key]) => key !== "hooks"));
  const hooks = [];
  for (const [event, groups] of Object.entries(config.hooks ?? {})) {
    for (const group of groups) {
      const matcher = group.matcher ?? "";
      const externalHooks = group.hooks.filter((hook) => !entries.some(
        (entry) => entry.event === event && entry.matcher === matcher && entry.command === hook.command,
      ));
      const metadata = Object.fromEntries(Object.entries(group).filter(([key]) => key !== "hooks"));
      const hasMetadata = Object.keys(metadata).some((key) => key !== "matcher");
      if (externalHooks.length > 0 || group.hooks.length === 0 || hasMetadata) {
        hooks.push({ event, group: { ...metadata, hooks: externalHooks } });
      }
    }
  }
  return { topLevel, hooks };
}

function makeScenario(manifestName, fixtureName) {
  const root = mkdtempSync(join(tmpdir(), "canuto-t5a-"));
  const sourceDir = join(root, "source");
  const hooksDir = join(root, "installed-hooks");
  const stateDir = join(root, "state");
  const configPath = join(root, fixtureName);
  const manifestPath = join(sourceDir, manifestName);
  mkdirSync(sourceDir, { recursive: true });
  mkdirSync(hooksDir, { recursive: true });
  writeFileSync(manifestPath, readFileSync(new URL(manifestName, import.meta.url)));
  writeFileSync(join(sourceDir, "managed-hooks.schema.json"), readFileSync(new URL("managed-hooks.schema.json", import.meta.url)));
  writeFileSync(configPath, readFileSync(new URL(`contracts/fixtures/${fixtureName}`, import.meta.url)), { mode: 0o600 });
  chmodSync(configPath, 0o600);
  return { root, hooksDir, stateDir, configPath, manifestPath };
}

function options(scenario) {
  return {
    manifestPath: scenario.manifestPath,
    configPath: scenario.configPath,
    hooksDir: scenario.hooksDir,
    stateDir: scenario.stateDir,
    homeDir: "/Users/tester",
  };
}

test("T5a desired state names only the approved ccgram and Codex probe retirements", () => {
  const claude = readJson(new URL("managed-hooks-retirements.claude.json", import.meta.url));
  const codex = readJson(new URL("managed-hooks-retirements.codex.json", import.meta.url));
  const entries = [...claude.entries, ...codex.entries];

  assert.deepEqual(new Set(entries.map((entry) => entry.id)), TARGET_IDS);
  assert.equal(entries.every((entry) => entry.status === "retired" && !Object.hasOwn(entry, "origin")), true);
  assert.equal(entries.filter((entry) => entry.command === CCGRAM_COMMAND).length, 9);
  assert.equal(entries.filter((entry) => entry.command === PROBE_COMMAND).length, 1);
  assert.equal(entries.some((entry) => entry.id === "CU-20" || entry.command.includes("log-commands.sh")), false);
  assert.deepEqual(validateManifest(claude), []);
  assert.deepEqual(validateManifest(codex), []);
});

test("T5a plans are deterministic, scoped to ten removals, and preserve external state", async (t) => {
  const cases = [
    {
      manifest: "managed-hooks-retirements.claude.json",
      fixture: "t5a-claude-before.json",
      removals: 9,
      preserved: ["~/.claude/hooks/log-commands.sh", "~/.claude/hooks/delivery-proof-gate.sh"],
    },
    {
      manifest: "managed-hooks-retirements.codex.json",
      fixture: "t5a-codex-before.json",
      removals: 1,
      preserved: ["~/.codex/hooks/external-before.sh", "~/.codex/hooks/external-after.sh"],
    },
  ];

  for (const item of cases) {
    await t.test(item.manifest, async () => {
      const scenario = makeScenario(item.manifest, item.fixture);
      t.after(() => rmSync(scenario.root, { recursive: true, force: true }));
      const before = readFileSync(scenario.configPath);
      const beforeConfig = JSON.parse(before);
      const manifest = JSON.parse(readFileSync(scenario.manifestPath, "utf8"));
      const externalBefore = externalState(beforeConfig, manifest.entries);
      const beforeMode = statSync(scenario.configPath).mode & 0o777;
      const first = await buildPlan(options(scenario));
      const repeated = await buildPlan(options(scenario));

      assert.equal(first.fingerprint, repeated.fingerprint);
      assert.equal(first.changed, true);
      assert.equal(first.entries.length, item.removals);
      assert.equal(first.entries.every((entry) => entry.action === "remove"), true);
      assert.deepEqual(first.files, []);
      assert.equal(hookCount(first.nextConfig), hookCount(beforeConfig) - item.removals);
      assert.deepEqual(externalState(first.nextConfig, manifest.entries), externalBefore);
      for (const command of item.preserved) assert.equal(findCommands(first.nextConfig, command).length, 1);

      const applied = await applyPlan({ ...options(scenario), fingerprint: first.fingerprint });
      assert.equal(applied.applied, true);
      assert.equal((await verifyState(options(scenario))).ok, true);
      assert.deepEqual(externalState(JSON.parse(readFileSync(scenario.configPath, "utf8")), manifest.entries), externalBefore);
      const appliedReceipt = JSON.parse(readFileSync(applied.receiptPath, "utf8"));
      assert.deepEqual(appliedReceipt.entries, first.entries);
      assert.equal(appliedReceipt.entries.every((entry) => entry.action === "remove"), true);
      assert.equal(appliedReceipt.verification.ok, true);
      assert.match(appliedReceipt.verification.stateFingerprint, /^[a-f0-9]{64}$/);
      const rolledBack = await rollbackBatch({ stateDir: scenario.stateDir, batchId: applied.batchId });
      assert.equal(rolledBack.rolledBack, true);
      assert.equal(digest(readFileSync(scenario.configPath)), digest(before));
      assert.equal(statSync(scenario.configPath).mode & 0o777, beforeMode);
      const rolledBackReceipt = JSON.parse(readFileSync(applied.receiptPath, "utf8"));
      assert.equal(rolledBackReceipt.status, "rolled-back");
      assert.deepEqual(rolledBackReceipt.entries, first.entries);
    });
  }
});

test("T5a preserves the approved active-count boundary of 71", () => {
  const baseline = readJson(new URL("audit/fixtures/active-hooks-2026-08-24.json", import.meta.url));
  const remaining = baseline.records.filter((record) => !TARGET_IDS.has(record.id));
  const count = (surface) => remaining.filter((record) => record.surface === surface).length;

  assert.equal(baseline.records.length, 81);
  assert.equal(remaining.length, 71);
  assert.equal(count("claude-user"), 48);
  assert.equal(count("codex-user"), 16);
  assert.equal(remaining.filter((record) => record.surface.startsWith("plugin-")).length, 7);
  assert.equal(remaining.some((record) => record.id === "CU-20"), true);
  assert.equal(remaining.some((record) => record.id === "CU-41"), true);
});

test("registration-only retirement is exact and cannot become an executable managed entry", () => {
  const manifest = readJson(new URL("managed-hooks-retirements.codex.json", import.meta.url));
  manifest.entries[0].status = "active";
  const activeErrors = validateManifest(manifest);
  assert.ok(activeErrors.some((error) => error.includes("requires origin, expectedHash, and mode")));
  assert.ok(activeErrors.some((error) => error.includes("role is invalid")));
  assert.ok(activeErrors.some((error) => error.includes("without arguments")));

  manifest.entries[0].status = "retired";
  manifest.entries[0].command = "~/hook.sh\nsecond-command";
  assert.ok(validateManifest(manifest).some((error) => error.includes("without control characters")));

  manifest.entries[0].command = PROBE_COMMAND;
  manifest.entries.push({ ...manifest.entries[0], id: "CX-DUPLICATE" });
  assert.ok(validateManifest(manifest).some((error) => error.includes("duplicate managed selector")));
});

test("registration-only retirement removes only exact registrations and preserves variants", async (t) => {
  const scenario = makeScenario("managed-hooks-retirements.codex.json", "t5a-codex-before.json");
  t.after(() => rmSync(scenario.root, { recursive: true, force: true }));
  const config = JSON.parse(readFileSync(scenario.configPath, "utf8"));
  config.hooks.PostToolUse = [{ matcher: "^Bash$", hooks: [{ type: "command", command: PROBE_COMMAND, timeout: 10 }] }];
  writeFileSync(scenario.configPath, `${JSON.stringify(config, null, 2)}\n`, { mode: 0o600 });

  const plan = await buildPlan(options(scenario));
  assert.equal(findCommands(plan.nextConfig, PROBE_COMMAND).length, 1);
  assert.equal(plan.nextConfig.hooks.PostToolUse[0].hooks[0].command, PROBE_COMMAND);

  config.hooks.PreToolUse[0].hooks.push(
    { type: "command", command: PROBE_COMMAND, timeout: 20 },
    { type: "command", command: PROBE_COMMAND, timeout: 10, env: { KEEP: "external" } },
  );
  writeFileSync(scenario.configPath, `${JSON.stringify(config, null, 2)}\n`, { mode: 0o600 });
  const exactPlan = await buildPlan(options(scenario));
  assert.equal(exactPlan.entries[0].action, "remove");
  assert.deepEqual(findCommands(exactPlan.nextConfig, PROBE_COMMAND), [
    { type: "command", command: PROBE_COMMAND, timeout: 20 },
    { type: "command", command: PROBE_COMMAND, timeout: 10, env: { KEEP: "external" } },
    { type: "command", command: PROBE_COMMAND, timeout: 10 },
  ]);
});
