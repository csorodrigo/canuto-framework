#!/usr/bin/env node
import { fileURLToPath, pathToFileURL } from "node:url";
import { dirname, join } from "node:path";
import { stdin, stdout } from "node:process";

async function readInput() {
  let raw = "";
  for await (const chunk of stdin) raw += chunk;
  return JSON.parse(raw);
}

let eventName = "PreToolUse";

try {
  const payload = await readInput();
  if (payload?.hook_event_name === "UserPromptSubmit") eventName = "UserPromptSubmit";
  const ownRoot = dirname(fileURLToPath(import.meta.url));
  let runtimeRoot = join(ownRoot, "canuto-runtime");
  try {
    await import(pathToFileURL(join(runtimeRoot, "runners", "repo-policy-runner.mjs")));
  } catch {
    runtimeRoot = ownRoot;
  }
  const [{ createRepoPolicyEvaluators }, { runRepoPolicies }] = await Promise.all([
    import(pathToFileURL(join(runtimeRoot, "policies", "repo", "index.mjs"))),
    import(pathToFileURL(join(runtimeRoot, "runners", "repo-policy-runner.mjs"))),
  ]);
  const platform = typeof payload.turn_id === "string" && typeof payload.model === "string" ? "codex" : "claude";
  const result = await runRepoPolicies({ platform, payload, evaluators: createRepoPolicyEvaluators() });
  stdout.write(`${JSON.stringify(result.response)}\n`);
} catch (error) {
  const message = `policy runner failed closed: ${error.message}`;
  const hookSpecificOutput = eventName === "UserPromptSubmit"
    ? { hookEventName: eventName, additionalContext: message }
    : { hookEventName: eventName, permissionDecision: "deny", permissionDecisionReason: message };
  stdout.write(`${JSON.stringify({ hookSpecificOutput })}\n`);
  process.exitCode = 2;
}
