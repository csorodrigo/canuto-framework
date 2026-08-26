#!/usr/bin/env node
import { dirname, join } from "node:path";
import { stdin, stdout } from "node:process";
import { fileURLToPath, pathToFileURL } from "node:url";

async function readInput() {
  let raw = "";
  for await (const chunk of stdin) raw += chunk;
  return JSON.parse(raw);
}

function block(reason) {
  return { decision: "block", reason };
}

try {
  const payload = await readInput();
  if (payload.stop_hook_active === true) {
    stdout.write("{}\n");
    process.exit(0);
  }
  if (payload.hook_event_name !== "Stop") throw new Error("validation finalizer only accepts Stop payloads");
  if (typeof payload.cwd !== "string" || !payload.cwd || typeof payload.session_id !== "string" || !payload.session_id) {
    throw new Error("Stop payload is missing cwd or session_id");
  }

  const ownRoot = dirname(fileURLToPath(import.meta.url));
  let runtimeRoot = join(ownRoot, "canuto-runtime");
  try {
    await import(pathToFileURL(join(runtimeRoot, "repo-policy-loader.mjs")));
  } catch {
    runtimeRoot = ownRoot;
  }
  const [{ captureExecutionIdentity }, { loadRepoPolicyManifest }, receiptModule] = await Promise.all([
    import(pathToFileURL(join(runtimeRoot, "core", "execution-identity.mjs"))),
    import(pathToFileURL(join(runtimeRoot, "repo-policy-loader.mjs"))),
    import(pathToFileURL(join(runtimeRoot, "policies", "repo", "validation-receipt.mjs"))),
  ]);

  const identity = await captureExecutionIdentity({ cwd: payload.cwd, sessionId: payload.session_id });
  const loaded = await loadRepoPolicyManifest({ repoRoot: identity.worktreeRoot });
  if (loaded.manifestStatus === "absent") {
    stdout.write("{}\n");
    process.exit(0);
  }
  if (loaded.manifestStatus !== "valid") {
    stdout.write(`${JSON.stringify(block(loaded.errors.join("; ")))}\n`);
    process.exit(0);
  }
  const policy = loaded.policies.find((candidate) => candidate.id === "validation-receipt");
  if (!policy) {
    stdout.write("{}\n");
    process.exit(0);
  }
  const receipt = await receiptModule.readValidationReceipt({ identity });
  const verification = receiptModule.verifyValidationReceipt(receipt, identity, {
    requiredFiles: Array.isArray(policy.options?.requiredFiles) ? policy.options.requiredFiles : [],
    allowedArgv: policy.options?.allowedArgv,
  });
  stdout.write(`${JSON.stringify(verification.valid ? {} : block(verification.reasons.join("; ")))}\n`);
} catch (error) {
  stdout.write(`${JSON.stringify(block(`validation finalizer failed closed: ${error.message}`))}\n`);
}
