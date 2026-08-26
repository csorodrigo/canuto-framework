import { spawn } from "node:child_process";

import { composePolicyResults } from "../core/policy-result.mjs";

const PLATFORMS = new Set(["claude", "codex"]);
const EVENTS = new Set(["PreToolUse", "PostToolUse", "PostToolUseFailure"]);
const ROLES = new Set(["gate", "advisory"]);

function requireObject(value, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error(`${label} must be an object`);
  }
  return value;
}

function requireString(value, label) {
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`${label} must be a non-empty string`);
  }
  return value;
}

function requireOwn(value, key, label) {
  if (!Object.hasOwn(value, key)) throw new Error(`${label}.${key} is required`);
  return value[key];
}

function validateCommonPayload(payload, event) {
  requireString(payload.session_id, "payload.session_id");
  requireString(payload.cwd, "payload.cwd");
  requireString(payload.hook_event_name, "payload.hook_event_name");
  if (payload.hook_event_name !== event) {
    throw new Error(`payload event ${payload.hook_event_name} does not match ${event}`);
  }
  requireString(payload.tool_name, "payload.tool_name");
  requireObject(payload.tool_input, "payload.tool_input");
  requireString(payload.tool_use_id, "payload.tool_use_id");
}

function validateClaude(payload, event) {
  validateCommonPayload(payload, event);
  requireString(payload.transcript_path, "payload.transcript_path");
  if (event === "PostToolUse") requireObject(payload.tool_response, "payload.tool_response");
  if (event === "PostToolUseFailure") requireString(payload.error, "payload.error");
}

function validateCodex(payload, event) {
  if (event === "PostToolUseFailure") {
    throw new Error("Codex represents tool failure inside PostToolUse.tool_response");
  }
  validateCommonPayload(payload, event);
  requireString(payload.model, "payload.model");
  requireString(payload.permission_mode, "payload.permission_mode");
  requireString(payload.turn_id, "payload.turn_id");
  requireOwn(payload, "transcript_path", "payload");
  if (payload.transcript_path !== null) requireString(payload.transcript_path, "payload.transcript_path");
  if (event === "PostToolUse") requireObject(payload.tool_response, "payload.tool_response");
}

export function normalizeFixture(value) {
  const fixture = requireObject(value, "fixture");
  const platform = requireString(fixture.platform, "fixture.platform");
  const event = requireString(fixture.event, "fixture.event");
  if (!PLATFORMS.has(platform)) throw new Error(`unsupported platform ${platform}`);
  if (!EVENTS.has(event)) throw new Error(`unsupported event ${event}`);
  const env = requireObject(fixture.env ?? {}, "fixture.env");
  const expectedOutcome = requireString(fixture.expectedOutcome, "fixture.expectedOutcome");
  if (!new Set(["pending", "success", "failure", "unsupported"]).has(expectedOutcome)) {
    throw new Error(`unsupported expected outcome ${expectedOutcome}`);
  }
  if (platform === "codex" && event === "PostToolUseFailure") {
    if (expectedOutcome !== "unsupported" || fixture.payload !== null) {
      throw new Error("Codex PostToolUseFailure must be an explicit unsupported fixture");
    }
    return {
      platform,
      event,
      supported: false,
      expectedOutcome,
      reason: requireString(fixture.reason, "fixture.reason"),
    };
  }
  const payload = requireObject(fixture.payload, "fixture.payload");

  if (platform === "claude") validateClaude(payload, event);
  else validateCodex(payload, event);

  if (event === "PreToolUse" && expectedOutcome !== "pending") {
    throw new Error("PreToolUse fixture outcome must be pending");
  }
  if (event === "PostToolUseFailure" && expectedOutcome !== "failure") {
    throw new Error("PostToolUseFailure fixture outcome must be failure");
  }
  if (platform === "codex" && event === "PostToolUse" && expectedOutcome !== "success") {
    throw new Error("Codex PostToolUse fixture outcome must be success");
  }

  return {
    platform,
    event,
    supported: true,
    cwd: payload.cwd,
    executionCwd: payload.cwd,
    projectDir: typeof env.CLAUDE_PROJECT_DIR === "string" ? env.CLAUDE_PROJECT_DIR : null,
    env,
    toolName: payload.tool_name,
    toolInput: payload.tool_input,
    toolResponse: payload.tool_response ?? null,
    error: payload.error ?? null,
    expectedOutcome,
  };
}

export function composeDecisions(decisions) {
  return composePolicyResults(decisions);
}

export async function composeConcurrentGates(gates) {
  if (!Array.isArray(gates) || gates.length < 2) {
    throw new Error("at least two concurrent Gates are required");
  }
  const decisions = await Promise.all(gates.map(async (gate) => {
    const value = requireObject(gate, "concurrent Gate");
    if (typeof value.execute !== "function") throw new Error("concurrent Gate execute must be a function");
    return value.execute();
  }));
  return composeDecisions(decisions);
}

export function renderNativeResponse(platform, event, composition) {
  if (!PLATFORMS.has(platform)) throw new Error(`unsupported platform ${platform}`);
  if (!EVENTS.has(event)) throw new Error(`unsupported event ${event}`);
  requireObject(composition, "composition");
  const additionalContext = composition.advisories.map((item) => item.message).join("\n");

  if (event === "PreToolUse") {
    const blocked = composition.verdict === "block";
    if (platform === "codex" && !blocked) {
      return {
        exitCode: 0,
        stdout: additionalContext
          ? { hookSpecificOutput: { hookEventName: "PreToolUse", additionalContext } }
          : {},
        stderr: "",
      };
    }
    return {
      exitCode: 0,
      stdout: {
        hookSpecificOutput: {
          hookEventName: "PreToolUse",
          permissionDecision: blocked ? "deny" : "allow",
          ...(blocked ? { permissionDecisionReason: composition.reason } : {}),
          ...(additionalContext ? { additionalContext } : {}),
        },
      },
      stderr: "",
    };
  }

  const hookEventName = platform === "claude" && event === "PostToolUseFailure"
    ? "PostToolUseFailure"
    : "PostToolUse";
  const stdout = additionalContext
    ? { hookSpecificOutput: { hookEventName, additionalContext } }
    : {};
  if (composition.verdict === "block" && event === "PostToolUse") {
    stdout.decision = "block";
    stdout.reason = composition.reason;
  }
  return { exitCode: 0, stdout, stderr: "" };
}

function assertOnlyKeys(value, keys, label) {
  for (const key of Object.keys(value)) {
    if (!keys.has(key)) throw new Error(`${label}.${key} is unsupported`);
  }
}

function interpretNativeResponse(platform, event, structured) {
  if (structured === null) return { verdict: null, reason: "" };
  assertOnlyKeys(
    structured,
    new Set(["continue", "decision", "hookSpecificOutput", "reason", "stopReason", "suppressOutput", "systemMessage"]),
    "handler stdout",
  );
  const output = structured.hookSpecificOutput;
  if (output !== undefined) {
    requireObject(output, "handler stdout.hookSpecificOutput");
    const expectedName = platform === "claude" && event === "PostToolUseFailure"
      ? "PostToolUseFailure"
      : event;
    if (output.hookEventName !== expectedName) {
      throw new Error(`handler stdout hook event must be ${expectedName}`);
    }
  }

  if (event === "PreToolUse") {
    if (platform === "codex") {
      if (structured.continue === false) throw new Error("Codex PreToolUse does not support continue:false");
      if (structured.stopReason !== undefined) throw new Error("Codex PreToolUse does not support stopReason");
      if (structured.suppressOutput === true) throw new Error("Codex PreToolUse does not support suppressOutput:true");
    } else if (structured.continue === false) {
      const reason = structured.stopReason ?? structured.reason ?? "Claude hook stopped execution";
      return { verdict: "block", reason };
    }
    if (structured.decision === "block") {
      return { verdict: "block", reason: requireString(structured.reason, "handler stdout.reason") };
    }
    if (structured.decision !== undefined) throw new Error(`unsupported decision ${structured.decision}`);
    if (structured.reason !== undefined) throw new Error("reason requires decision:block");
    assertOnlyKeys(
      output ?? {},
      new Set(["hookEventName", "permissionDecision", "permissionDecisionReason", "additionalContext", "updatedInput"]),
      "handler stdout.hookSpecificOutput",
    );
    const permissionDecision = output?.permissionDecision;
    if (output?.updatedInput !== undefined && permissionDecision !== "allow") {
      throw new Error("updatedInput requires permissionDecision:allow");
    }
    if (permissionDecision === "deny") {
      const reason = requireString(output.permissionDecisionReason, "handler stdout permissionDecisionReason");
      return { verdict: "block", reason };
    }
    if (permissionDecision === "allow") {
      if (platform === "codex" && output.updatedInput === undefined) {
        throw new Error("Codex permissionDecision:allow requires updatedInput");
      }
      return { verdict: "allow", reason: "" };
    }
    if (permissionDecision !== undefined) throw new Error(`unsupported permissionDecision ${permissionDecision}`);
    if (output?.permissionDecisionReason !== undefined) {
      throw new Error("permissionDecisionReason requires permissionDecision");
    }
    return { verdict: null, reason: "" };
  }

  assertOnlyKeys(
    output ?? {},
    new Set(["hookEventName", "additionalContext", "updatedMCPToolOutput", "updatedToolOutput"]),
    "handler stdout.hookSpecificOutput",
  );
  if (platform === "codex" && structured.suppressOutput === true) {
    throw new Error("Codex PostToolUse does not support suppressOutput:true");
  }
  if (platform === "codex" && output?.updatedMCPToolOutput !== undefined) {
    throw new Error("Codex PostToolUse does not support updatedMCPToolOutput");
  }
  if (platform === "codex" && output?.updatedToolOutput !== undefined) {
    throw new Error("Codex PostToolUse does not support updatedToolOutput");
  }
  if (structured.decision === "block") {
    return { verdict: "block", reason: requireString(structured.reason, "handler stdout.reason") };
  }
  if (structured.decision !== undefined) throw new Error(`unsupported decision ${structured.decision}`);
  if (structured.reason !== undefined) throw new Error("reason requires decision:block");
  return { verdict: null, reason: "" };
}

function parseStructuredOutput(stdout) {
  if (stdout.trim() === "") return null;
  try {
    return requireObject(JSON.parse(stdout), "handler stdout");
  } catch (error) {
    throw new Error(`invalid structured stdout: ${error.message}`);
  }
}

export function runContractHandler({ command, args = [], fixture, timeoutMs = 5_000 }) {
  requireString(command, "command");
  if (!Array.isArray(args)) throw new Error("args must be an array");
  if (!Number.isInteger(timeoutMs) || timeoutMs <= 0) throw new Error("timeoutMs must be positive");
  const invocation = normalizeFixture(fixture);
  if (!invocation.supported) throw new Error(`${invocation.event} is unsupported on ${invocation.platform}`);

  return new Promise((resolve) => {
    let stdout = "";
    let stderr = "";
    let settled = false;
    let child;
    const finish = (result) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      resolve({ stdout, stderr, structured: null, ...result });
    };
    const timer = setTimeout(() => {
      child?.kill("SIGKILL");
      finish({ status: "timeout", exitCode: null, signal: "SIGKILL" });
    }, timeoutMs);

    try {
      child = spawn(command, args, {
        cwd: invocation.executionCwd,
        env: { ...process.env, ...invocation.env },
        stdio: ["pipe", "pipe", "pipe"],
      });
    } catch (error) {
      finish({ status: "spawn-error", exitCode: null, signal: null, error: error.message });
      return;
    }
    child.stdout.on("data", (chunk) => { stdout += chunk; });
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.on("error", (error) => {
      finish({ status: "spawn-error", exitCode: null, signal: null, error: error.message });
    });
    child.on("close", (exitCode, signal) => {
      if (settled) return;
      let structured = null;
      try {
        structured = parseStructuredOutput(stdout);
        const nativeDecision = interpretNativeResponse(invocation.platform, invocation.event, structured);
        const status = exitCode === 0 ? "completed" : exitCode === 2 ? "blocked" : "failed";
        finish({ status, exitCode, signal, structured, nativeDecision, invocation });
      } catch (error) {
        finish({ status: "invalid-output", exitCode, signal, error: error.message });
      }
    });
    child.stdin.end(`${JSON.stringify(fixture.payload)}\n`);
  });
}

export function executionDecision({ id, role, run }) {
  requireString(id, "id");
  if (!ROLES.has(role)) throw new Error(`unsupported role ${role}`);
  requireObject(run, "run");
  if (run.status === "completed") {
    if (run.nativeDecision?.verdict === "block") {
      return { id, role, verdict: role === "gate" ? "block" : "observe", reason: run.nativeDecision.reason };
    }
    return role === "gate"
      ? { id, role, verdict: "allow", reason: "handler completed" }
      : { id, role, verdict: "observe", reason: run.stderr.trim() || "handler completed" };
  }
  const reason = `${id} ${run.status}${run.error ? `: ${run.error}` : ""}`;
  return role === "gate"
    ? { id, role, verdict: "block", reason }
    : { id, role, verdict: "observe", reason };
}
