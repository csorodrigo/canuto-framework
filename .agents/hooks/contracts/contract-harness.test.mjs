import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, realpathSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

import {
  composeDecisions,
  composeConcurrentGates,
  executionDecision,
  normalizeFixture,
  renderNativeResponse,
  runContractHandler,
} from "./contract-harness.mjs";

function fixture(name) {
  return JSON.parse(readFileSync(new URL(`fixtures/${name}.json`, import.meta.url), "utf8"));
}

function runtimeFixture(name = "codex-pretool-bash") {
  const value = fixture(name);
  value.payload.cwd = process.cwd();
  if (value.env?.CLAUDE_PROJECT_DIR) value.env.CLAUDE_PROJECT_DIR = process.cwd();
  return value;
}

function gate(id, verdict, reason = `${id} ${verdict}`) {
  return { id, role: "gate", verdict, reason };
}

function advisory(id, reason) {
  return { id, role: "advisory", verdict: "observe", reason };
}

test("sanitized Claude and Codex PreToolUse fixtures normalize to one core input", () => {
  const claude = normalizeFixture(fixture("claude-pretool-bash"));
  const codex = normalizeFixture(fixture("codex-pretool-bash"));
  assert.deepEqual(
    { event: claude.event, toolName: claude.toolName, toolInput: claude.toolInput, outcome: claude.expectedOutcome },
    { event: codex.event, toolName: codex.toolName, toolInput: codex.toolInput, outcome: codex.expectedOutcome },
  );
  assert.equal(claude.cwd, "/workspace/feature-a");
  assert.equal(claude.projectDir, "/workspace/main");
  assert.notEqual(claude.cwd, claude.projectDir);
});

test("Codex fixtures cover Bash and apply_patch without treating them as one tool", () => {
  const bash = normalizeFixture(fixture("codex-pretool-bash"));
  const patch = normalizeFixture(fixture("codex-pretool-apply-patch"));
  assert.equal(bash.toolName, "Bash");
  assert.equal(patch.toolName, "apply_patch");
  assert.ok(Object.hasOwn(patch.toolInput, "patch"));
});

test("PostToolUse success and failure normalize across native event differences", () => {
  const values = [
    normalizeFixture(fixture("claude-posttool-success")),
    normalizeFixture(fixture("claude-posttool-failure")),
    normalizeFixture(fixture("codex-posttool-success")),
    normalizeFixture(fixture("codex-posttool-failure")),
  ];
  assert.deepEqual(values.map((value) => value.expectedOutcome), ["success", "failure", "success", "unsupported"]);
  assert.equal(values[1].event, "PostToolUseFailure");
  assert.equal(values[3].event, "PostToolUseFailure");
  assert.equal(values[3].supported, false);
});

test("invalid fixtures fail closed instead of becoming an implicit allow", () => {
  const invalidJson = "{\"platform\":\"codex\"";
  assert.throws(() => normalizeFixture(JSON.parse(invalidJson)), SyntaxError);

  const missingInput = fixture("codex-pretool-bash");
  delete missingInput.payload.tool_input;
  assert.throws(() => normalizeFixture(missingInput), /tool_input/);

  const mismatched = fixture("codex-posttool-failure");
  mismatched.expectedOutcome = "success";
  assert.throws(() => normalizeFixture(mismatched), /explicit unsupported fixture/);
});

test("two concurrent Gates compose by intersection", () => {
  assert.equal(composeDecisions([gate("gate-a", "allow"), gate("gate-b", "allow")]).verdict, "allow");
  const blocked = composeDecisions([gate("gate-a", "allow"), gate("gate-b", "block", "blocked by b")]);
  assert.equal(blocked.verdict, "block");
  assert.equal(blocked.reason, "blocked by b");
  assert.deepEqual(blocked.gateIds, ["gate-a", "gate-b"]);
});

test("concurrent Gates start together and compose independently of completion order", async () => {
  let started = 0;
  let releaseStarted;
  let releaseFast;
  let releaseSlow;
  const allStarted = new Promise((resolve) => { releaseStarted = resolve; });
  const fast = new Promise((resolve) => { releaseFast = resolve; });
  const slow = new Promise((resolve) => { releaseSlow = resolve; });
  const completed = [];
  const execute = (decision, release) => async () => {
    started += 1;
    if (started === 2) releaseStarted();
    await release;
    completed.push(decision.id);
    return decision;
  };
  const pending = composeConcurrentGates([
    { execute: execute(gate("slow-allow", "allow"), slow) },
    { execute: execute(gate("fast-block", "block", "concurrent block"), fast) },
  ]);
  await allStarted;
  releaseFast();
  await new Promise((resolve) => setImmediate(resolve));
  releaseSlow();
  const result = await pending;
  assert.equal(started, 2);
  assert.deepEqual(completed, ["fast-block", "slow-allow"]);
  assert.equal(result.verdict, "block");
  assert.deepEqual(result.gateIds, ["slow-allow", "fast-block"]);
});

test("Advisory remains observable and cannot block", () => {
  const result = composeDecisions([
    gate("machine-gate", "allow"),
    advisory("host-advisory", "host pressure is elevated"),
  ]);
  assert.equal(result.verdict, "allow");
  assert.deepEqual(result.advisories, [{ id: "host-advisory", message: "host pressure is elevated" }]);
  assert.throws(
    () => composeDecisions([{ id: "bad-advisory", role: "advisory", verdict: "block", reason: "must not block" }]),
    /must be observe/,
  );
});

test("one core allow decision renders each native PreToolUse response", () => {
  const decision = composeDecisions([gate("shared-gate", "allow")]);
  const claude = renderNativeResponse("claude", "PreToolUse", decision);
  const codex = renderNativeResponse("codex", "PreToolUse", decision);
  assert.deepEqual(claude.stdout, {
    hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "allow" },
  });
  assert.deepEqual(codex.stdout, {});
  assert.equal(claude.exitCode, 0);
  assert.equal(codex.exitCode, 0);
});

test("one core block decision renders native Claude and Codex PreToolUse denials", () => {
  const decision = composeDecisions([
    gate("gate-a", "allow"),
    gate("gate-b", "block", "fixture policy blocked the call"),
  ]);
  for (const platform of ["claude", "codex"]) {
    const response = renderNativeResponse(platform, "PreToolUse", decision);
    assert.equal(response.stdout.hookSpecificOutput.permissionDecision, "deny");
    assert.equal(response.stdout.hookSpecificOutput.permissionDecisionReason, "fixture policy blocked the call");
  }
});

test("PostToolUse feedback uses the native failure event only on Claude", () => {
  const decision = composeDecisions([
    gate("post-gate", "allow"),
    advisory("post-advisory", "inspect the fixture result"),
  ]);
  const claude = renderNativeResponse("claude", "PostToolUseFailure", decision);
  const codex = renderNativeResponse("codex", "PostToolUse", decision);
  assert.equal(claude.stdout.hookSpecificOutput.hookEventName, "PostToolUseFailure");
  assert.equal(codex.stdout.hookSpecificOutput.hookEventName, "PostToolUse");
  assert.equal(claude.stdout.hookSpecificOutput.additionalContext, "inspect the fixture result");
  assert.equal(codex.stdout.hookSpecificOutput.additionalContext, "inspect the fixture result");
});

test("PostToolUse block is feedback after execution, not a nonzero exit", () => {
  const decision = composeDecisions([gate("post-check", "block", "result needs correction")]);
  for (const platform of ["claude", "codex"]) {
    const response = renderNativeResponse(platform, "PostToolUse", decision);
    assert.equal(response.exitCode, 0);
    assert.equal(response.stdout.decision, "block");
    assert.equal(response.stdout.reason, "result needs correction");
  }
});

test("handler harness captures stdout, stderr, structured response, and exit code", async () => {
  const script = [
    "process.stdin.resume();",
    "process.stdin.on('end', () => {",
    "  process.stdout.write(JSON.stringify({hookSpecificOutput:{hookEventName:'PreToolUse',permissionDecision:'allow'}}));",
    "  process.stderr.write('fixture diagnostic');",
    "});",
  ].join("\n");
  const run = await runContractHandler({
    command: process.execPath,
    args: ["-e", script],
    fixture: runtimeFixture("claude-pretool-bash"),
  });
  assert.equal(run.status, "completed");
  assert.equal(run.exitCode, 0);
  assert.equal(run.stderr, "fixture diagnostic");
  assert.equal(run.structured.hookSpecificOutput.permissionDecision, "allow");
});

test("handler exit 2 is captured as an explicit block", async () => {
  const run = await runContractHandler({
    command: process.execPath,
    args: ["-e", "process.stderr.write('blocked by fixture'); process.exit(2)"],
    fixture: runtimeFixture(),
  });
  assert.equal(run.status, "blocked");
  assert.equal(run.exitCode, 2);
  assert.equal(run.stderr, "blocked by fixture");
});

test("invalid structured stdout never becomes a completed authorization", async () => {
  const run = await runContractHandler({
    command: process.execPath,
    args: ["-e", "process.stdout.write('{not-json')"],
    fixture: runtimeFixture(),
  });
  assert.equal(run.status, "invalid-output");
  assert.match(run.error, /invalid structured stdout/);
  assert.equal(executionDecision({ id: "invalid-gate", role: "gate", run }).verdict, "block");
});

test("timeout is bounded and fails a Gate closed", async () => {
  const startedAt = Date.now();
  const run = await runContractHandler({
    command: process.execPath,
    args: ["-e", "setInterval(() => {}, 1000)"],
    fixture: runtimeFixture(),
    timeoutMs: 40,
  });
  assert.equal(run.status, "timeout");
  assert.ok(Date.now() - startedAt < 1_000);
  assert.equal(executionDecision({ id: "timeout-gate", role: "gate", run }).verdict, "block");
});

test("missing process is observable and fails a Gate closed", async () => {
  const run = await runContractHandler({
    command: "/fixture/does-not-exist/hook",
    fixture: runtimeFixture(),
  });
  assert.equal(run.status, "spawn-error");
  assert.equal(executionDecision({ id: "missing-gate", role: "gate", run }).verdict, "block");
  const observed = executionDecision({ id: "missing-advisory", role: "advisory", run });
  assert.equal(observed.verdict, "observe");
  assert.match(observed.reason, /spawn-error/);
});

test("invalid payload is rejected before a handler can authorize it", async () => {
  const invalid = runtimeFixture();
  delete invalid.payload.tool_input;
  await assert.rejects(
    async () => runContractHandler({
      command: process.execPath,
      args: ["-e", "process.stdout.write('{}')"],
      fixture: invalid,
    }),
    /tool_input/,
  );
});

test("invalid native response fails closed for a Gate", async () => {
  const run = await runContractHandler({
    command: process.execPath,
    args: ["-e", "process.stdout.write(JSON.stringify({unexpected:true}))"],
    fixture: runtimeFixture(),
  });
  assert.equal(run.status, "invalid-output");
  assert.equal(executionDecision({ id: "response-gate", role: "gate", run }).verdict, "block");
});

test("Codex rejects a bare permissionDecision allow", async () => {
  const script = "process.stdout.write(JSON.stringify({hookSpecificOutput:{hookEventName:'PreToolUse',permissionDecision:'allow'}}))";
  const run = await runContractHandler({
    command: process.execPath,
    args: ["-e", script],
    fixture: runtimeFixture(),
  });
  assert.equal(run.status, "invalid-output");
  assert.match(run.error, /requires updatedInput/);
  assert.equal(executionDecision({ id: "codex-allow-gate", role: "gate", run }).verdict, "block");
});

test("Codex legacy decision:block remains a native block", async () => {
  const script = "process.stdout.write(JSON.stringify({decision:'block',reason:'legacy native block'}))";
  const run = await runContractHandler({
    command: process.execPath,
    args: ["-e", script],
    fixture: runtimeFixture(),
  });
  assert.equal(run.status, "completed");
  assert.equal(run.nativeDecision.verdict, "block");
  assert.equal(executionDecision({ id: "legacy-gate", role: "gate", run }).verdict, "block");
});

test("unsupported Codex PreToolUse controls fail closed", async () => {
  for (const stdout of [
    { continue: false },
    { stopReason: "stop" },
    { suppressOutput: true },
    { hookSpecificOutput: { hookEventName: "PreToolUse", updatedInput: { command: "fixture" } } },
  ]) {
    const script = `process.stdout.write(${JSON.stringify(JSON.stringify(stdout))})`;
    const run = await runContractHandler({
      command: process.execPath,
      args: ["-e", script],
      fixture: runtimeFixture(),
    });
    assert.equal(run.status, "invalid-output");
    assert.equal(executionDecision({ id: "unsupported-gate", role: "gate", run }).verdict, "block");
  }
});

test("unsupported Codex PostToolUse controls fail closed", async () => {
  for (const stdout of [
    { suppressOutput: true },
    { hookSpecificOutput: { hookEventName: "PostToolUse", updatedMCPToolOutput: { fixture: true } } },
    { hookSpecificOutput: { hookEventName: "PostToolUse", updatedToolOutput: "fixture replacement" } },
  ]) {
    const script = `process.stdout.write(${JSON.stringify(JSON.stringify(stdout))})`;
    const run = await runContractHandler({
      command: process.execPath,
      args: ["-e", script],
      fixture: runtimeFixture("codex-posttool-success"),
    });
    assert.equal(run.status, "invalid-output");
    assert.equal(executionDecision({ id: "unsupported-post-gate", role: "gate", run }).verdict, "block");
  }
});

test("handler execution uses payload cwd rather than stale CLAUDE_PROJECT_DIR", async () => {
  const root = mkdtempSync(join(tmpdir(), "canuto-contract-cwd-"));
  const executionCwd = mkdtempSync(join(root, "worktree-"));
  const staleProjectDir = mkdtempSync(join(root, "main-"));
  const value = fixture("claude-pretool-bash");
  value.payload.cwd = executionCwd;
  value.env.CLAUDE_PROJECT_DIR = staleProjectDir;
  const script = [
    "const context = `${process.cwd()}|${process.env.CLAUDE_PROJECT_DIR}`;",
    "process.stdout.write(JSON.stringify({hookSpecificOutput:{hookEventName:'PreToolUse',additionalContext:context}}));",
  ].join("\n");
  const run = await runContractHandler({ command: process.execPath, args: ["-e", script], fixture: value });
  assert.equal(run.status, "completed");
  assert.equal(run.invocation.executionCwd, executionCwd);
  assert.equal(
    run.structured.hookSpecificOutput.additionalContext,
    `${realpathSync(executionCwd)}|${staleProjectDir}`,
  );
});
