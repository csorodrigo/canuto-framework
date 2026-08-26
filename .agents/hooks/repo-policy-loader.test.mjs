import assert from "node:assert/strict";
import { execFile as execFileCallback } from "node:child_process";
import { mkdtemp, mkdir, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";
import test from "node:test";

import {
  loadRepoPolicyManifest,
  resolveRepoPolicy,
  validateRepoPolicyManifest,
} from "./repo-policy-loader.mjs";
import {
  captureExecutionIdentity,
  createExecutionReceipt,
  verifyExecutionReceipt,
} from "./core/execution-identity.mjs";

const execFile = promisify(execFileCallback);

async function git(cwd, ...args) {
  await execFile("git", ["-C", cwd, ...args], { encoding: "utf8" });
}

async function repositoryFixture() {
  const root = await mkdtemp(join(tmpdir(), "canuto-repo-policy-"));
  await git(root, "init", "-b", "main");
  await git(root, "config", "user.name", "Canuto Fixture");
  await git(root, "config", "user.email", "canuto@example.invalid");
  await writeFile(join(root, "tracked.txt"), "initial\n");
  await git(root, "add", "tracked.txt");
  await git(root, "commit", "-m", "fixture");
  return root;
}

async function writeManifest(root, manifest) {
  const hooks = join(root, ".agents", "hooks");
  await mkdir(hooks, { recursive: true });
  await writeFile(join(hooks, "manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`);
}

const validManifest = {
  $schema: "./repo-policy.schema.json",
  schemaVersion: 1,
  policies: [
    { id: "build-typecheck", options: { script: "typecheck:codex" } },
    { id: "pull-request" },
  ],
};

test("manifest is opt-in: missing and undeclared policies are no-op", async (t) => {
  const root = await repositoryFixture();
  t.after(() => rm(root, { recursive: true, force: true }));
  const missing = await resolveRepoPolicy({ repoRoot: root, policyId: "commit" });
  assert.equal(missing.manifestStatus, "absent");
  assert.equal(missing.decision, "no-op");

  await writeManifest(root, validManifest);
  const undeclared = await resolveRepoPolicy({ repoRoot: root, policyId: "claims" });
  assert.equal(undeclared.manifestStatus, "valid");
  assert.equal(undeclared.decision, "no-op");
  const declared = await resolveRepoPolicy({ repoRoot: root, policyId: "build-typecheck" });
  assert.equal(declared.decision, "apply");
  assert.equal(declared.policy.options.script, "typecheck:codex");
});

test("present invalid manifest blocks governed actions", async (t) => {
  const root = await repositoryFixture();
  t.after(() => rm(root, { recursive: true, force: true }));
  await writeManifest(root, { ...validManifest, schemaVersion: 2 });
  const unknownVersion = await resolveRepoPolicy({ repoRoot: root, policyId: "commit" });
  assert.equal(unknownVersion.manifestStatus, "invalid");
  assert.equal(unknownVersion.decision, "block");
  assert.match(unknownVersion.errors.join(" "), /schemaVersion/);

  await writeManifest(root, {
    ...validManifest,
    policies: [{ id: "commit" }, { id: "commit" }],
  });
  const duplicate = await loadRepoPolicyManifest({ repoRoot: root });
  assert.equal(duplicate.decision, "block");
  assert.match(duplicate.errors.join(" "), /duplicated/);

  await writeManifest(root, {
    $schema: "./repo-policy.schema.json",
    schemaVersion: 1,
    policies: [{ id: "secret-command" }],
    machinePolicies: { "secret-command": false },
  });
  const machineOverride = await loadRepoPolicyManifest({ repoRoot: root });
  assert.equal(machineOverride.decision, "block");
  assert.match(machineOverride.errors.join(" "), /machinePolicies|not a supported repository policy/);
});

test("manifest path rejects symlinks instead of reading outside policy state", async (t) => {
  const root = await repositoryFixture();
  t.after(() => rm(root, { recursive: true, force: true }));
  const hooks = join(root, ".agents", "hooks");
  await mkdir(hooks, { recursive: true });
  const target = join(root, "external-policy.json");
  await writeFile(target, `${JSON.stringify(validManifest)}\n`);
  await symlink(target, join(hooks, "manifest.json"));
  const loaded = await resolveRepoPolicy({ repoRoot: root, policyId: "commit" });
  assert.equal(loaded.manifestStatus, "invalid");
  assert.equal(loaded.decision, "block");
});

test("schema and template describe valid repository-owned policy examples", async () => {
  const template = JSON.parse(await readFile(new URL("../templates/hooks-manifest.json", import.meta.url), "utf8"));
  const schema = JSON.parse(await readFile(new URL("./repo-policy.schema.json", import.meta.url), "utf8"));
  assert.equal(schema.properties.schemaVersion.const, 1);
  assert.deepEqual(validateRepoPolicyManifest(template), []);
  assert.deepEqual(template.policies.map((policy) => policy.id), [
    "build-typecheck",
    "deploy-target",
    "validation-receipt",
    "commit",
    "pull-request",
  ]);
  const validation = template.policies.find((policy) => policy.id === "validation-receipt");
  assert.deepEqual(validation.options.allowedArgv, [["npm", "run", "test"]]);
});

test("validation receipt policy requires a non-empty exact argv allowlist", () => {
  const base = {
    $schema: "./repo-policy.schema.json",
    schemaVersion: 1,
    policies: [{
      id: "validation-receipt",
      options: { enabled: true, requiredFiles: [], allowedArgv: [] },
    }],
  };
  assert.match(validateRepoPolicyManifest(base).join(" "), /allowedArgv/);
  base.policies[0].options.allowedArgv = [["/usr/bin/true"], ["/usr/bin/true"]];
  assert.match(validateRepoPolicyManifest(base).join(" "), /duplicated/);
  base.policies[0].options.allowedArgv = [["npm", "run", "test"]];
  assert.deepEqual(validateRepoPolicyManifest(base), []);
});

test("execution identity separates worktrees and supports detached HEAD", async (t) => {
  const root = await repositoryFixture();
  const sibling = `${root}-worktree`;
  t.after(() => rm(root, { recursive: true, force: true }));
  t.after(() => rm(sibling, { recursive: true, force: true }));
  await git(root, "worktree", "add", "-b", "fixture-worktree", sibling);
  const first = await captureExecutionIdentity({ cwd: root, sessionId: "session-a" });
  const second = await captureExecutionIdentity({ cwd: sibling, sessionId: "session-a" });
  assert.equal(first.repoCommonDir, second.repoCommonDir);
  assert.notEqual(first.worktreeRoot, second.worktreeRoot);
  assert.notEqual(first.worktreeGitDir, second.worktreeGitDir);
  assert.notEqual(first.identityKey, second.identityKey);
  const firstReceipt = createExecutionReceipt({ identity: first, coveredFiles: ["tracked.txt"] });
  assert.equal(verifyExecutionReceipt(firstReceipt, second).valid, false);

  await git(sibling, "checkout", "--detach");
  const detached = await captureExecutionIdentity({ cwd: sibling, sessionId: "session-a" });
  assert.equal(detached.branch, null);
});

test("receipt is stale after tree, worktree, or session identity changes", async (t) => {
  const root = await repositoryFixture();
  t.after(() => rm(root, { recursive: true, force: true }));
  const identity = await captureExecutionIdentity({ cwd: root, sessionId: "session-a" });
  const receipt = createExecutionReceipt({ identity, coveredFiles: ["tracked.txt"] });
  assert.equal(verifyExecutionReceipt(receipt, identity, { requiredFiles: ["tracked.txt"] }).valid, true);

  await writeFile(join(root, "tracked.txt"), "changed after validation\n");
  const changed = await captureExecutionIdentity({ cwd: root, sessionId: "session-a" });
  const stale = verifyExecutionReceipt(receipt, changed, { requiredFiles: ["tracked.txt"] });
  assert.equal(stale.valid, false);
  assert.match(stale.reasons.join(" "), /worktreeFingerprint|identityKey/);

  await git(root, "add", "tracked.txt");
  await git(root, "commit", "-m", "change fixture tree");
  const committed = await captureExecutionIdentity({ cwd: root, sessionId: "session-a" });
  const changedSha = verifyExecutionReceipt(receipt, committed);
  assert.equal(changedSha.valid, false);
  assert.match(changedSha.reasons.join(" "), /headSha/);

  const otherSession = await captureExecutionIdentity({ cwd: root, sessionId: "session-b" });
  assert.equal(verifyExecutionReceipt(receipt, otherSession).valid, false);
});

test("receipt fails closed on incomplete coverage or unavailable remote evidence", async (t) => {
  const root = await repositoryFixture();
  t.after(() => rm(root, { recursive: true, force: true }));
  const identity = await captureExecutionIdentity({ cwd: root, sessionId: "session-a" });
  assert.equal(identity.remoteUrl, null);
  const receipt = createExecutionReceipt({ identity, coveredFiles: ["tracked.txt"] });
  const incomplete = verifyExecutionReceipt(receipt, identity, { requiredFiles: ["tracked.txt", "other.txt"] });
  assert.equal(incomplete.valid, false);
  assert.match(incomplete.reasons.join(" "), /does not cover other.txt/);

  const remoteRequired = verifyExecutionReceipt(receipt, identity, { requireRemote: true });
  assert.equal(remoteRequired.valid, false);
  assert.match(remoteRequired.reasons.join(" "), /no origin remote/);
  assert.match(remoteRequired.reasons.join(" "), /remote evidence is unavailable/);
});

test("receipt binds remote identity even when HEAD stays unchanged", async (t) => {
  const root = await repositoryFixture();
  t.after(() => rm(root, { recursive: true, force: true }));
  const firstRemote = "https://example.invalid/first.git";
  const secondRemote = "https://example.invalid/second.git";
  await git(root, "remote", "add", "origin", firstRemote);
  const first = await captureExecutionIdentity({ cwd: root, sessionId: "session-a" });
  const receipt = createExecutionReceipt({
    identity: first,
    coveredFiles: ["tracked.txt"],
    remoteEvidence: { status: "verified", headSha: first.headSha, remoteUrl: firstRemote },
  });
  assert.equal(receipt.identity.remoteUrl, firstRemote);
  assert.equal(verifyExecutionReceipt(receipt, first, { requireRemote: true }).valid, true);

  await git(root, "remote", "set-url", "origin", secondRemote);
  const second = await captureExecutionIdentity({ cwd: root, sessionId: "session-a" });
  assert.equal(second.headSha, first.headSha);
  assert.notEqual(second.identityKey, first.identityKey);
  const changedRemote = verifyExecutionReceipt(receipt, second, { requireRemote: true });
  assert.equal(changedRemote.valid, false);
  assert.match(changedRemote.reasons.join(" "), /remoteUrl|another remote/);
});
