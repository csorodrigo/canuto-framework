#!/usr/bin/env node
import { fileURLToPath, pathToFileURL } from "node:url";
import { dirname, join } from "node:path";
import { stdin, stdout } from "node:process";

async function readInput() {
  let raw = "";
  for await (const chunk of stdin) raw += chunk;
  return JSON.parse(raw);
}

try {
  const payload = await readInput();
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
  stdout.write(`${JSON.stringify({
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: `repository policy runner failed closed: ${error.message}`,
    },
  })}\n`);
  process.exitCode = 2;
}
