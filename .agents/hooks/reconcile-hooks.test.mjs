import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import {
  chmodSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readdirSync,
  readFileSync,
  rmSync,
  statSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import {
  applyPlan,
  buildPlan,
  rollbackBatch,
  validateManifest,
  verifyState,
} from "./reconcile-hooks.mjs";

function digest(value) {
  return createHash("sha256").update(value).digest("hex");
}

function writeJson(path, value) {
  writeFileSync(path, `${JSON.stringify(value, null, 2)}\n`);
}

function managedHook(command = "~/.claude/hooks/example.sh", timeout = 3) {
  return { type: "command", command, timeout };
}

function fixture({ config, status = "active", source = "#!/usr/bin/env bash\nexit 0\n", install = false } = {}) {
  const root = mkdtempSync(join(tmpdir(), "canuto-reconcile-"));
  const manifestDir = join(root, "source");
  const hooksDir = join(root, "installed-hooks");
  const stateDir = join(root, "state");
  const configPath = join(root, "settings.json");
  const manifestPath = join(manifestDir, "managed-hooks.json");
  const sourcePath = join(manifestDir, "example.sh");
  mkdirSync(manifestDir, { recursive: true });
  mkdirSync(hooksDir, { recursive: true });
  writeFileSync(
    join(manifestDir, "managed-hooks.schema.json"),
    readFileSync(new URL("managed-hooks.schema.json", import.meta.url)),
  );
  writeFileSync(sourcePath, source, { mode: 0o755 });
  chmodSync(sourcePath, 0o755);
  const entry = {
    id: "CU-TEST",
    version: 1,
    status,
    origin: "example.sh",
    event: "PreToolUse",
    matcher: "Bash",
    timeout: 3,
    role: "gate",
    command: "~/.claude/hooks/example.sh",
    expectedHash: digest(source),
    mode: "0755",
  };
  writeJson(manifestPath, { $schema: "./managed-hooks.schema.json", schemaVersion: 1, surface: "fixture", entries: [entry] });
  if (config !== undefined) writeJson(configPath, config);
  if (install) {
    writeFileSync(join(hooksDir, "example.sh"), source, { mode: 0o755 });
    chmodSync(join(hooksDir, "example.sh"), 0o755);
  }
  return { root, manifestDir, hooksDir, stateDir, configPath, manifestPath, sourcePath, entry };
}

function options(value) {
  return {
    manifestPath: value.manifestPath,
    configPath: value.configPath,
    hooksDir: value.hooksDir,
    stateDir: value.stateDir,
    homeDir: join(value.root, "home"),
  };
}

test("versioned compatibility snippet renders every active managed identity", () => {
  const manifest = JSON.parse(readFileSync(new URL("managed-hooks.json", import.meta.url), "utf8"));
  const snippet = JSON.parse(readFileSync(new URL("settings-snippet.json", import.meta.url), "utf8"));
  const rendered = [];
  for (const [event, groups] of Object.entries(snippet.hooks)) {
    for (const group of groups) {
      for (const hook of group.hooks) rendered.push({ event, matcher: group.matcher ?? "", command: hook.command, timeout: hook.timeout ?? null });
    }
  }
  const desired = manifest.entries
    .filter((entry) => entry.status === "active")
    .map(({ event, matcher, command, timeout }) => ({ event, matcher, command, timeout }));
  assert.deepEqual(rendered, desired);
  for (const entry of manifest.entries) {
    const origin = readFileSync(new URL(entry.origin, new URL("managed-hooks.json", import.meta.url)));
    assert.equal(digest(origin), entry.expectedHash, `stale expectedHash for ${entry.id}`);
  }
});

test("empty configuration plans deterministically and second apply is idempotent", async () => {
  const value = fixture();
  const first = await buildPlan(options(value));
  const repeated = await buildPlan(options(value));
  assert.equal(first.fingerprint, repeated.fingerprint);
  assert.equal(first.entries[0].action, "add");
  assert.equal(first.files[0].action, "add");

  const applied = await applyPlan({ ...options(value), fingerprint: first.fingerprint });
  assert.equal(applied.applied, true);
  const verify = await verifyState(options(value));
  assert.equal(verify.ok, true, verify.errors?.join("; "));

  const converged = await buildPlan(options(value));
  assert.equal(converged.changed, false);
  const second = await applyPlan({ ...options(value), fingerprint: converged.fingerprint });
  assert.deepEqual(second, { applied: false, fingerprint: converged.fingerprint, reason: "already-converged" });
});

test("external entries and empty external groups survive reconciliation unchanged", async () => {
  const external = { type: "command", command: "/opt/external/hook", timeout: 9, env: { KEEP: "exact" } };
  const emptyGroup = { matcher: "", hooks: [], metadata: { owner: "external" } };
  const value = fixture({
    config: {
      hooks: {
        SessionStart: [emptyGroup],
        PreToolUse: [{ matcher: "External", hooks: [external] }],
      },
      unrelated: { preserve: true },
    },
  });
  const before = JSON.stringify(external);
  const plan = await buildPlan(options(value));
  assert.equal(plan.external.count, 1);
  await applyPlan({ ...options(value), fingerprint: plan.fingerprint });
  const after = JSON.parse(readFileSync(value.configPath, "utf8"));
  assert.equal(JSON.stringify(after.hooks.PreToolUse[0].hooks[0]), before);
  assert.deepEqual(after.hooks.SessionStart[0], emptyGroup);
  assert.deepEqual(after.unrelated, { preserve: true });
});

test("duplicate Canuto registrations block planning", async () => {
  const hook = managedHook();
  const value = fixture({
    config: { hooks: { PreToolUse: [{ matcher: "Bash", hooks: [hook] }, { matcher: "Write", hooks: [hook] }] } },
    install: true,
  });
  await assert.rejects(buildPlan(options(value)), /duplicate Canuto entry CU-TEST/);
});

test("retired registration and file are removed and rollback restores exact hashes", async () => {
  const config = { hooks: { PreToolUse: [{ matcher: "Bash", hooks: [managedHook()] }] }, marker: "before" };
  const value = fixture({ config, status: "retired", install: true });
  const configBefore = readFileSync(value.configPath);
  const fileBefore = readFileSync(join(value.hooksDir, "example.sh"));
  const plan = await buildPlan(options(value));
  assert.equal(plan.entries[0].action, "remove");
  assert.equal(plan.files[0].action, "remove");
  const applied = await applyPlan({ ...options(value), fingerprint: plan.fingerprint });
  assert.equal(existsSync(join(value.hooksDir, "example.sh")), false);

  const rolledBack = await rollbackBatch({ stateDir: value.stateDir, batchId: applied.batchId });
  assert.equal(rolledBack.rolledBack, true);
  assert.equal(digest(readFileSync(value.configPath)), digest(configBefore));
  assert.equal(digest(readFileSync(join(value.hooksDir, "example.sh"))), digest(fileBefore));
  assert.equal(statSync(join(value.hooksDir, "example.sh")).mode & 0o777, 0o755);
  await assert.rejects(
    rollbackBatch({ stateDir: value.stateDir, batchId: applied.batchId }),
    /not eligible for rollback/,
  );
  await assert.rejects(
    rollbackBatch({ stateDir: value.stateDir, batchId: "unknown" }),
    /rollback receipt is missing/,
  );
});

test("locally changed matcher is an update, not a second registration", async () => {
  const value = fixture({
    config: { hooks: { PreToolUse: [{ matcher: "Write", hooks: [managedHook()] }] } },
    install: true,
  });
  const plan = await buildPlan(options(value));
  assert.equal(plan.entries[0].action, "update");
  await applyPlan({ ...options(value), fingerprint: plan.fingerprint });
  const config = JSON.parse(readFileSync(value.configPath, "utf8"));
  assert.equal(config.hooks.PreToolUse.length, 1);
  assert.equal(config.hooks.PreToolUse[0].matcher, "Bash");
});

test("update preserves order inside multiple groups with the same matcher", async () => {
  const before = managedHook("/external/before", 1);
  const after = managedHook("/external/after", 1);
  const firstGroup = managedHook("/external/first", 1);
  const value = fixture({
    config: {
      hooks: {
        PreToolUse: [
          { matcher: "Bash", hooks: [firstGroup] },
          { matcher: "Bash", hooks: [before, managedHook("~/.claude/hooks/example.sh", 99), after] },
        ],
      },
    },
    install: true,
  });
  const plan = await buildPlan(options(value));
  assert.equal(plan.entries[0].action, "update");
  await applyPlan({ ...options(value), fingerprint: plan.fingerprint });
  const config = JSON.parse(readFileSync(value.configPath, "utf8"));
  assert.deepEqual(
    config.hooks.PreToolUse.flatMap((group) => group.hooks.map((hook) => hook.command)),
    ["/external/first", "/external/before", "~/.claude/hooks/example.sh", "/external/after"],
  );
});

test("retirement preserves group metadata when its last managed hook is removed", async () => {
  const value = fixture({
    config: { hooks: { PreToolUse: [{ matcher: "Bash", hooks: [managedHook()], metadata: { owner: "human" } }] } },
    status: "retired",
    install: true,
  });
  const plan = await buildPlan(options(value));
  await applyPlan({ ...options(value), fingerprint: plan.fingerprint });
  const config = JSON.parse(readFileSync(value.configPath, "utf8"));
  assert.deepEqual(config.hooks.PreToolUse, [{ matcher: "Bash", hooks: [], metadata: { owner: "human" } }]);
});

test("invalid JSON, missing origin, and divergent origin hash fail closed", async (t) => {
  await t.test("truncated manifest", async () => {
    const value = fixture();
    writeFileSync(value.manifestPath, '{"entries":');
    await assert.rejects(buildPlan(options(value)), /manifest is invalid JSON/);
  });
  await t.test("truncated configuration", async () => {
    const value = fixture();
    writeFileSync(value.configPath, '{"hooks":');
    await assert.rejects(buildPlan(options(value)), /configuration is invalid JSON/);
  });
  await t.test("missing origin", async () => {
    const value = fixture();
    const manifest = JSON.parse(readFileSync(value.manifestPath, "utf8"));
    manifest.entries[0].origin = "missing.sh";
    writeJson(value.manifestPath, manifest);
    await assert.rejects(buildPlan(options(value)), /origin is missing for CU-TEST/);
  });
  await t.test("hash mismatch", async () => {
    const value = fixture();
    const manifest = JSON.parse(readFileSync(value.manifestPath, "utf8"));
    manifest.entries[0].expectedHash = "0".repeat(64);
    writeJson(value.manifestPath, manifest);
    await assert.rejects(buildPlan(options(value)), /origin hash mismatch for CU-TEST/);
  });
  await t.test("origin traversal", async () => {
    const value = fixture();
    const manifest = JSON.parse(readFileSync(value.manifestPath, "utf8"));
    manifest.entries[0].origin = "../escape.sh";
    writeFileSync(join(value.root, "escape.sh"), readFileSync(value.sourcePath), { mode: 0o755 });
    writeJson(value.manifestPath, manifest);
    await assert.rejects(buildPlan(options(value)), /origin must stay inside manifest directory/);
  });
  await t.test("schema violation", async () => {
    const value = fixture();
    const manifest = JSON.parse(readFileSync(value.manifestPath, "utf8"));
    manifest.unexpected = true;
    writeJson(value.manifestPath, manifest);
    await assert.rejects(buildPlan(options(value)), /manifest does not satisfy schema:.*unexpected is not allowed/);
  });
});

test("duplicate manifest ids are rejected", () => {
  const value = fixture();
  const manifest = JSON.parse(readFileSync(value.manifestPath, "utf8"));
  manifest.entries.push({ ...manifest.entries[0] });
  assert.ok(validateManifest(manifest).some((error) => error.includes("duplicate managed id CU-TEST")));
  manifest.entries[0].command = "bash ~/.claude/hooks/example.sh";
  assert.ok(validateManifest(manifest).some((error) => error.includes("without arguments")));
});

test("active and retired entries cannot claim one target with divergent sources", async () => {
  const value = fixture();
  const otherSource = "#!/usr/bin/env bash\nexit 1\n";
  writeFileSync(join(value.manifestDir, "other.sh"), otherSource, { mode: 0o755 });
  const manifest = JSON.parse(readFileSync(value.manifestPath, "utf8"));
  manifest.entries.push({
    ...manifest.entries[0],
    id: "CU-RETIRED",
    status: "retired",
    origin: "other.sh",
    command: "~/legacy/example.sh",
    expectedHash: digest(otherSource),
  });
  writeJson(value.manifestPath, manifest);
  await assert.rejects(buildPlan(options(value)), /conflicting file ownership/);
});

test("apply rejects configuration drift after the reviewed plan", async () => {
  const value = fixture({ config: { hooks: {} } });
  const plan = await buildPlan(options(value));
  writeJson(value.configPath, { hooks: {}, externalDrift: true });
  await assert.rejects(
    applyPlan({ ...options(value), fingerprint: plan.fingerprint }),
    /plan fingerprint mismatch or input drift/,
  );
});

test("failure after a partial write restores prior configuration and files", async () => {
  const value = fixture({ config: { hooks: {}, marker: "unchanged" } });
  const configBefore = readFileSync(value.configPath);
  const plan = await buildPlan(options(value));
  await assert.rejects(
    applyPlan({ ...options(value), fingerprint: plan.fingerprint, failAfterWrites: 1 }),
    /simulated partial write failure/,
  );
  assert.equal(digest(readFileSync(value.configPath)), digest(configBefore));
  assert.equal(existsSync(join(value.hooksDir, "example.sh")), false);
});

test("failure before the verified receipt is durable restores prior configuration and files", async () => {
  const value = fixture({ config: { hooks: {}, marker: "unchanged" } });
  const configBefore = readFileSync(value.configPath);
  const plan = await buildPlan(options(value));
  await assert.rejects(
    applyPlan({ ...options(value), fingerprint: plan.fingerprint, failVerificationReceiptWrite: true }),
    /simulated receipt write failure/,
  );
  assert.equal(digest(readFileSync(value.configPath)), digest(configBefore));
  assert.equal(existsSync(join(value.hooksDir, "example.sh")), false);

  const [batchId] = readdirSync(join(value.stateDir, "batches"));
  const receipt = JSON.parse(readFileSync(join(value.stateDir, "batches", batchId, "receipt.json"), "utf8"));
  assert.equal(receipt.status, "restored-after-failure");
  assert.equal(receipt.verification.ok, true);
  assert.deepEqual(receipt.entries, plan.entries);
});

test("explicit rollback recovers a mixed prepared batch after interruption", async () => {
  const value = fixture();
  const plan = await buildPlan(options(value));
  const applied = await applyPlan({ ...options(value), fingerprint: plan.fingerprint });
  const receiptPath = join(value.stateDir, "batches", applied.batchId, "receipt.json");
  const receipt = JSON.parse(readFileSync(receiptPath, "utf8"));
  receipt.status = "prepared";
  delete receipt.appliedAt;
  delete receipt.verification;
  writeJson(receiptPath, receipt);
  rmSync(value.configPath);

  const result = await rollbackBatch({ stateDir: value.stateDir, batchId: applied.batchId });
  assert.equal(result.rolledBack, true);
  assert.equal(existsSync(value.configPath), false);
  assert.equal(existsSync(join(value.hooksDir, "example.sh")), false);
});

test("verify checks installed permissions as well as content hashes", async () => {
  const value = fixture();
  const plan = await buildPlan(options(value));
  await applyPlan({ ...options(value), fingerprint: plan.fingerprint });
  chmodSync(join(value.hooksDir, "example.sh"), 0o644);
  const verify = await verifyState(options(value));
  assert.equal(verify.ok, false);
  assert.ok(verify.errors.some((error) => error.includes("requires update")));
});
