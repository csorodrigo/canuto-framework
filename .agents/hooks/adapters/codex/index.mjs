import { createInvocation } from "../../core/invocation.mjs";

function requireObject(value, label) {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error(`${label} must be an object`);
  return value;
}

function requireString(value, label) {
  if (typeof value !== "string" || value.length === 0) throw new Error(`${label} must be a non-empty string`);
  return value;
}

export function normalizeCodexInvocation(payload) {
  requireObject(payload, "Codex payload");
  const event = requireString(payload.hook_event_name, "Codex event");
  if (event !== "PreToolUse") throw new Error(`unsupported Codex event ${event}`);
  requireString(payload.turn_id, "Codex turn id");
  requireString(payload.model, "Codex model");
  const input = requireObject(payload.tool_input, "Codex tool input");
  const toolName = requireString(payload.tool_name, "Codex tool name");
  const command = toolName === "Bash" ? requireString(input.command, "Codex Bash command") : "";
  return createInvocation({
    platform: "codex",
    event,
    sessionId: requireString(payload.session_id, "Codex session id"),
    cwd: requireString(payload.cwd, "Codex cwd"),
    toolName,
    subjectKind: command ? "command" : "none",
    subject: command,
  });
}

export function renderCodexPolicyResponse(event, composition) {
  if (event !== "PreToolUse") throw new Error(`unsupported Codex event ${event}`);
  const blocked = composition.verdict === "block";
  const additionalContext = composition.advisories.map((item) => item.message).join("\n");
  if (!blocked) {
    return additionalContext
      ? { hookSpecificOutput: { hookEventName: "PreToolUse", additionalContext } }
      : {};
  }
  return {
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: composition.reason,
      ...(additionalContext ? { additionalContext } : {}),
    },
  };
}

