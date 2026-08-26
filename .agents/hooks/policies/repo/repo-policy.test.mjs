import assert from "node:assert/strict";
import { execFile as execFileCallback, spawn } from "node:child_process";
import { cp, mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";
import test from "node:test";

import { captureExecutionIdentity } from "../../core/execution-identity.mjs";
import { evaluateBuildTypecheck } from "./build-typecheck.mjs";
import { evaluateDeployTarget } from "./deploy-target.mjs";
import { createRepoPolicyEvaluators } from "./index.mjs";
import {
  clearValidationCoverage,
  createValidationReceipt,
  executeAndWriteValidationReceipt,
  verifyValidationReceipt,
  writeValidationReceipt,
} from "./validation-receipt.mjs";

const execFile = promisify(execFileCallback);

async function git(cwd, ...args) {
  await execFile("git", ["-C", cwd, ...args], { encoding: "utf8" });
}

async function repositoryFixture() {
  const root = await mkdtemp(join(tmpdir(), "canuto-t7-policy-"));
  await git(root, "init", "-b", "main");
  await git(root, "config", "user.name", "Canuto Fixture");
  await git(root, "config", "user.email", "canuto@example.invalid");
  await writeFile(join(root, "first.txt"), "first\n");
  await writeFile(join(root, "second.txt"), "second\n");
  await git(root, "add", ".");
  await git(root, "commit", "-m", "fixture");
  return root;
}

async function runHook(payload, hookPath = new URL("../../repo-policy-hook.mjs", import.meta.url).pathname) {
  const child = spawn(process.execPath, [hookPath], {
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

function runFinalizeHook(payload) {
  return runHook(payload, new URL("../../validation-finalize-hook.mjs", import.meta.url).pathname);
}

function context(subject, options) {
  return {
    invocation: { subject },
    policy: { id: "fixture", options },
  };
}

test("formatter/typecheck and deploy targets are exact repository opt-ins", () => {
  const build = evaluateBuildTypecheck(context("rtk npm run typecheck:codex", {
    commands: ["npm run typecheck:codex"],
  }));
  assert.equal(build.verdict, "allow");
  const unknownBuild = evaluateBuildTypecheck(context("npm run build", {
    commands: ["npm run typecheck:codex"],
  }));
  assert.equal(unknownBuild.verdict, "block");

  const deploy = evaluateDeployTarget(context("vercel --prod", {
    targets: [{ name: "production", commands: ["vercel --prod"] }],
  }));
  assert.equal(deploy.verdict, "allow");
  const wrongTarget = evaluateDeployTarget(context("railway up", {
    targets: [{ name: "production", commands: ["vercel --prod"] }],
  }));
  assert.equal(wrongTarget.verdict, "block");
});

test("validation receipts bind worktree, session, SHA and tree", async (t) => {
  const root = await repositoryFixture();
  const sibling = `${root}-sibling`;
  t.after(() => rm(root, { recursive: true, force: true }));
  t.after(() => rm(sibling, { recursive: true, force: true }));
  await git(root, "remote", "add", "origin", "https://example.invalid/owner/repo.git");
  await git(root, "worktree", "add", "-b", "sibling", sibling);
  const identity = await captureExecutionIdentity({ cwd: root, sessionId: "session-a" });
  const receipt = createValidationReceipt({
    identity,
    coveredFiles: ["first.txt", "second.txt"],
    validation: { argv: ["npm", "run", "test", "--", "first.test.mjs"], exitCode: 0 },
    remoteEvidence: { status: "verified", headSha: identity.headSha, remoteUrl: identity.remoteUrl },
  });
  const undeclared = verifyValidationReceipt(receipt, identity);
  assert.equal(undeclared.valid, false);
  assert.match(undeclared.reasons.join(" "), /not declared/);
  assert.equal(verifyValidationReceipt(receipt, identity, {
    requiredFiles: ["first.txt"],
    requireRemote: true,
    allowedArgv: [["npm", "run", "test", "--", "first.test.mjs"]],
  }).valid, true);

  const otherWorktree = await captureExecutionIdentity({ cwd: sibling, sessionId: "session-a" });
  assert.equal(verifyValidationReceipt(receipt, otherWorktree, { allowedArgv: [receipt.validation.argv] }).valid, false);
  const otherSession = await captureExecutionIdentity({ cwd: root, sessionId: "session-b" });
  assert.equal(verifyValidationReceipt(receipt, otherSession, { allowedArgv: [receipt.validation.argv] }).valid, false);
  await writeFile(join(root, "first.txt"), "changed\n");
  const changedTree = await captureExecutionIdentity({ cwd: root, sessionId: "session-a" });
  assert.equal(verifyValidationReceipt(receipt, changedTree, { allowedArgv: [receipt.validation.argv] }).valid, false);
});

test("coverage clearing removes only edited files", async (t) => {
  const root = await repositoryFixture();
  t.after(() => rm(root, { recursive: true, force: true }));
  const identity = await captureExecutionIdentity({ cwd: root, sessionId: "session-a" });
  const receipt = createValidationReceipt({
    identity,
    coveredFiles: ["first.txt", "second.txt"],
    validation: { argv: ["node", "--test"], exitCode: 0 },
  });
  const allowedArgv = [["node", "--test"]];
  const cleared = clearValidationCoverage(receipt, identity, ["first.txt"], { allowedArgv });
  assert.equal(cleared.changed, true);
  assert.deepEqual(cleared.receipt.execution.coveredFiles, ["second.txt"]);
  assert.equal(verifyValidationReceipt(cleared.receipt, identity, { requiredFiles: ["first.txt"], allowedArgv }).valid, false);
  assert.equal(verifyValidationReceipt(cleared.receipt, identity, { requiredFiles: ["second.txt"], allowedArgv }).valid, true);
});

test("validation receipt CLI records, verifies and selectively clears project coverage", async (t) => {
  const root = await repositoryFixture();
  const remote = `${root}-remote.git`;
  t.after(() => rm(root, { recursive: true, force: true }));
  t.after(() => rm(remote, { recursive: true, force: true }));
  await execFile("git", ["init", "--bare", remote], { encoding: "utf8" });
  await git(root, "remote", "add", "origin", remote);
  await git(root, "push", "-u", "origin", "main");
  const cli = new URL("validation-receipt-cli.mjs", import.meta.url).pathname;
  const hooks = join(root, ".agents", "hooks");
  const successfulArgv = [process.execPath, "-e", "process.exit(0)"];
  const failingArgv = [process.execPath, "-e", "process.exit(7)"];
  await mkdir(hooks, { recursive: true });
  await writeFile(join(hooks, "manifest.json"), `${JSON.stringify({
    $schema: "./repo-policy.schema.json",
    schemaVersion: 1,
    policies: [{
      id: "validation-receipt",
      options: { enabled: true, requiredFiles: [], allowedArgv: [successfulArgv, failingArgv] },
    }],
  })}\n`);
  await assert.rejects(
    execFile(process.execPath, [cli, "record", "--session", "session-failed", "--file", "first.txt", "--", ...failingArgv], { cwd: root, encoding: "utf8" }),
  );
  await assert.rejects(
    execFile(process.execPath, [cli, "verify", "--session", "session-failed", "--file", "first.txt"], { cwd: root, encoding: "utf8" }),
    (error) => error.code === 2 && JSON.parse(error.stdout).valid === false,
  );
  await assert.rejects(
    execFile(process.execPath, [cli, "record", "--session", "session-forged", "--command", "true", "--file", "first.txt"], { cwd: root, encoding: "utf8" }),
  );
  await assert.rejects(
    execFile(process.execPath, [cli, "record", "--session", "session-true", "--file", "first.txt", "--", "/usr/bin/true"], { cwd: root, encoding: "utf8" }),
    /validation argv is not declared/,
  );

  const forgedIdentity = await captureExecutionIdentity({ cwd: root, sessionId: "session-forged-receipt" });
  await writeValidationReceipt({
    identity: forgedIdentity,
    coveredFiles: ["first.txt"],
    validation: { argv: ["/usr/bin/true"], exitCode: 0 },
  });
  await assert.rejects(
    execFile(process.execPath, [cli, "verify", "--session", "session-forged-receipt", "--file", "first.txt"], { cwd: root, encoding: "utf8" }),
    (error) => error.code === 2 && /not declared/.test(JSON.parse(error.stdout).reasons.join(" ")),
  );

  const recorded = await execFile(process.execPath, [cli, "record", "--session", "session-cli", "--file", "first.txt", "--file", "second.txt", "--remote", "--", ...successfulArgv], { cwd: root, encoding: "utf8" });
  assert.equal(JSON.parse(recorded.stdout).operation, "record");
  const verified = await execFile(process.execPath, [cli, "verify", "--session", "session-cli", "--file", "first.txt", "--remote"], { cwd: root, encoding: "utf8" });
  assert.equal(JSON.parse(verified.stdout).valid, true);
  const cleared = await execFile(process.execPath, [cli, "clear", "--session", "session-cli", "--file", "first.txt"], { cwd: root, encoding: "utf8" });
  assert.equal(JSON.parse(cleared.stdout).changed, true);
  await assert.rejects(
    execFile(process.execPath, [cli, "verify", "--session", "session-cli", "--file", "first.txt"], { cwd: root, encoding: "utf8" }),
    (error) => error.code === 2 && JSON.parse(error.stdout).valid === false,
  );
  const secondStillCovered = await execFile(process.execPath, [cli, "verify", "--session", "session-cli", "--file", "second.txt"], { cwd: root, encoding: "utf8" });
  assert.equal(JSON.parse(secondStillCovered.stdout).valid, true);
});

test("commit and pull-request evaluators require current receipts; PR also requires remote proof", async (t) => {
  const root = await repositoryFixture();
  t.after(() => rm(root, { recursive: true, force: true }));
  await git(root, "remote", "add", "origin", "https://example.invalid/owner/repo.git");
  const identity = await captureExecutionIdentity({ cwd: root, sessionId: "session-a" });
  const localReceipt = createValidationReceipt({
    identity,
    coveredFiles: ["first.txt"],
    validation: { argv: ["node", "--test"], exitCode: 0 },
  });
  const policyResolver = async () => ({
    decision: "apply",
    policy: { options: { allowedArgv: [["node", "--test"]] } },
  });
  const localEvaluators = createRepoPolicyEvaluators({ receiptReader: async () => localReceipt, policyResolver });
  const commit = await localEvaluators.commit({ identity, policy: { options: { requiredFiles: ["first.txt"] } } });
  assert.equal(commit.verdict, "allow");
  const pullRequest = await localEvaluators["pull-request"]({ identity, policy: { options: { requiredFiles: ["first.txt"] } } });
  assert.equal(pullRequest.verdict, "block");
  assert.match(pullRequest.reason, /remote evidence is unavailable/);

  const remoteReceipt = createValidationReceipt({
    identity,
    coveredFiles: ["first.txt"],
    validation: { argv: ["node", "--test"], exitCode: 0 },
    remoteEvidence: { status: "verified", headSha: identity.headSha, remoteUrl: identity.remoteUrl },
  });
  const remoteEvaluators = createRepoPolicyEvaluators({ receiptReader: async () => remoteReceipt, policyResolver });
  const allowedPullRequest = await remoteEvaluators["pull-request"]({
    identity,
    policy: { options: { requiredFiles: ["first.txt"] } },
  });
  assert.equal(allowedPullRequest.verdict, "allow");
});

test("installed hook is inert outside opt-in repos and fails closed inside one", async (t) => {
  const root = await repositoryFixture();
  t.after(() => rm(root, { recursive: true, force: true }));
  const payload = {
    session_id: "session-a",
    cwd: root,
    hook_event_name: "PreToolUse",
    tool_name: "Bash",
    tool_input: { command: "git commit -m fixture" },
  };
  const inert = await runHook(payload);
  assert.equal(inert.code, 0, inert.stderr);
  assert.equal(JSON.parse(inert.stdout).hookSpecificOutput.permissionDecision, "allow");

  const hooks = join(root, ".agents", "hooks");
  await mkdir(hooks, { recursive: true });
  await writeFile(join(hooks, "manifest.json"), `${JSON.stringify({
    $schema: "./repo-policy.schema.json",
    schemaVersion: 1,
    policies: [{ id: "commit", options: { requiredFiles: ["first.txt"] } }],
  })}\n`);
  const governed = await runHook(payload);
  assert.equal(governed.code, 0, governed.stderr);
  const response = JSON.parse(governed.stdout);
  assert.equal(response.hookSpecificOutput.permissionDecision, "deny");
  assert.match(response.hookSpecificOutput.permissionDecisionReason, /validation (?:receipt|argv)/);

  const installedRoot = await mkdtemp(join(tmpdir(), "canuto-t7-installed-hook-"));
  t.after(() => rm(installedRoot, { recursive: true, force: true }));
  const sourceRoot = new URL("../../", import.meta.url);
  const installedHook = join(installedRoot, "repo-policy-hook.mjs");
  await cp(new URL("repo-policy-hook.mjs", sourceRoot), installedHook);
  for (const directory of ["core", "adapters", "runners", "policies"]) {
    await cp(new URL(`${directory}/`, sourceRoot), join(installedRoot, "canuto-runtime", directory), { recursive: true });
  }
  await cp(new URL("repo-policy-loader.mjs", sourceRoot), join(installedRoot, "canuto-runtime", "repo-policy-loader.mjs"));
  const installed = await runHook(payload, installedHook);
  assert.equal(installed.code, 0, installed.stderr);
  assert.equal(JSON.parse(installed.stdout).hookSpecificOutput.permissionDecision, "deny");
});

test("Stop finalizer requires a current validation receipt for opted-in repositories", async (t) => {
  const root = await repositoryFixture();
  t.after(() => rm(root, { recursive: true, force: true }));
  const hooks = join(root, ".agents", "hooks");
  await mkdir(hooks, { recursive: true });
  await writeFile(join(hooks, "manifest.json"), `${JSON.stringify({
    $schema: "./repo-policy.schema.json",
    schemaVersion: 1,
    policies: [{
      id: "validation-receipt",
      options: {
        enabled: true,
        requiredFiles: ["first.txt"],
        allowedArgv: [[process.execPath, "-e", "process.exit(0)"]],
      },
    }],
  })}\n`);
  const payload = {
    session_id: "session-stop",
    cwd: root,
    hook_event_name: "Stop",
    stop_hook_active: false,
  };
  const missing = await runFinalizeHook(payload);
  assert.equal(missing.code, 0, missing.stderr);
  assert.equal(JSON.parse(missing.stdout).decision, "block");
  assert.match(JSON.parse(missing.stdout).reason, /validation receipt/);

  const identity = await captureExecutionIdentity({ cwd: root, sessionId: payload.session_id });
  await executeAndWriteValidationReceipt({
    identity,
    coveredFiles: ["first.txt"],
    argv: [process.execPath, "-e", "process.exit(0)"],
  });
  const current = await runFinalizeHook(payload);
  assert.equal(current.code, 0, current.stderr);
  assert.deepEqual(JSON.parse(current.stdout), {});

  await writeFile(join(root, "first.txt"), "stale\n");
  const stale = await runFinalizeHook(payload);
  assert.equal(JSON.parse(stale.stdout).decision, "block");
  assert.match(JSON.parse(stale.stdout).reason, /stale/);

  const recursive = await runFinalizeHook({ ...payload, stop_hook_active: true });
  assert.deepEqual(JSON.parse(recursive.stdout), {});
});
