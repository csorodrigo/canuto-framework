import { createInvocation } from "../../core/invocation.mjs";

function requireObject(value, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error(`${label} must be an object`);
  return value;
}

function requireString(value, label) {
  if (typeof value !== "string" || value.length === 0) throw new Error(`${label} must be a non-empty string`);
  return value;
}

export function normalizeClaudeInvocation(payload) {
  requireObject(payload, "Claude payload");
  const event = requireString(payload.hook_event_name, "Claude event");
  if (event === "UserPromptSubmit") {
    return createInvocation({
      platform: "claude",
      event,
      sessionId: requireString(payload.session_id, "Claude session id"),
      cwd: requireString(payload.cwd, "Claude cwd"),
      subjectKind: "prompt",
      subject: requireString(payload.prompt, "Claude prompt"),
    });
  }
  if (event !== "PreToolUse") throw new Error(`unsupported Claude event ${event}`);
  const input = requireObject(payload.tool_input, "Claude tool input");
  const toolName = requireString(payload.tool_name, "Claude tool name");
  const command = toolName === "Bash" ? requireString(input.command, "Claude Bash command") : "";
  return createInvocation({
    platform: "claude",
    event,
    sessionId: requireString(payload.session_id, "Claude session id"),
    cwd: requireString(payload.cwd, "Claude cwd"),
    toolName,
    subjectKind: command ? "command" : "none",
    subject: command,
  });
}

export function renderClaudePolicyResponse(event, composition) {
  if (event === "UserPromptSubmit") {
    const additionalContext = composition.advisories.map((item) => item.message).join("\n");
    return additionalContext
      ? { hookSpecificOutput: { hookEventName: "UserPromptSubmit", additionalContext } }
      : {};
  }
  if (event !== "PreToolUse") throw new Error(`unsupported Claude event ${event}`);
  const blocked = composition.verdict === "block";
  const additionalContext = composition.advisories.map((item) => item.message).join("\n");
  return {
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: blocked ? "deny" : "allow",
      ...(blocked ? { permissionDecisionReason: composition.reason } : {}),
      ...(additionalContext ? { additionalContext } : {}),
    },
  };
}

