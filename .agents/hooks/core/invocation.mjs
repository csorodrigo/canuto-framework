const EVENTS = new Set(["PreToolUse", "UserPromptSubmit"]);
const PLATFORMS = new Set(["claude", "codex"]);

function requireString(value, label) {
  if (typeof value !== "string" || value.length === 0) {
    throw new Error(`${label} must be a non-empty string`);
  }
  return value;
}

export function createInvocation({ platform, event, sessionId, cwd, toolName = null, subjectKind, subject }) {
  if (!PLATFORMS.has(platform)) throw new Error(`unsupported platform ${platform}`);
  if (!EVENTS.has(event)) throw new Error(`unsupported event ${event}`);
  requireString(sessionId, "session id");
  requireString(cwd, "cwd");
  if (!new Set(["command", "prompt", "none"]).has(subjectKind)) {
    throw new Error(`unsupported subject kind ${subjectKind}`);
  }
  if (subjectKind === "none") {
    if (subject !== "") throw new Error("none subject must be empty");
  } else {
    requireString(subject, "policy subject");
  }
  if (event === "PreToolUse") requireString(toolName, "tool name");
  if (event === "UserPromptSubmit" && subjectKind !== "prompt") {
    throw new Error("UserPromptSubmit requires a prompt subject");
  }
  return Object.freeze({ platform, event, sessionId, cwd, toolName, subjectKind, subject });
}

