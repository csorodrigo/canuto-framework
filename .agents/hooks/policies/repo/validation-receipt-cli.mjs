#!/usr/bin/env node
import { execFile as execFileCallback } from "node:child_process";
import { promisify } from "node:util";

import { captureExecutionIdentity } from "../../core/execution-identity.mjs";
import { resolveRepoPolicy } from "../../repo-policy-loader.mjs";
import {
  clearStoredValidationCoverage,
  executeAndWriteValidationReceipt,
  readValidationReceipt,
  verifyValidationReceipt,
  validationArgvIsDeclared,
} from "./validation-receipt.mjs";

const execFile = promisify(execFileCallback);

function usage() {
  throw new Error("usage: validation-receipt-cli.mjs <record|verify|clear> --session <id> [--file <path>] [--remote] [-- <command> <args...>]");
}

function parse(argv) {
  const operation = argv.shift();
  if (!["record", "verify", "clear"].includes(operation)) usage();
  const options = { operation, files: [], remote: false, sessionId: "", argv: [] };
  while (argv.length > 0) {
    const flag = argv.shift();
    if (flag === "--") {
      options.argv = argv.splice(0);
      break;
    } else if (flag === "--remote") options.remote = true;
    else if (flag === "--session") options.sessionId = argv.shift() ?? "";
    else if (flag === "--file") options.files.push(argv.shift() ?? "");
    else usage();
  }
  if (!options.sessionId || options.files.some((file) => !file)) usage();
  if (operation === "record" && (options.argv.length === 0 || options.files.length === 0)) usage();
  if (operation !== "record" && options.argv.length > 0) usage();
  if (operation === "clear" && options.files.length === 0) usage();
  return options;
}

async function verifyRemote(identity) {
  if (!identity.remoteUrl) throw new Error("remote proof requires origin");
  if (!identity.branch) throw new Error("remote proof requires an attached branch");
  const { stdout } = await execFile("git", [
    "-C", identity.worktreeRoot,
    "ls-remote", "--exit-code", "--heads", "origin", `refs/heads/${identity.branch}`,
  ], { encoding: "utf8", env: { ...process.env, GIT_OPTIONAL_LOCKS: "0", LC_ALL: "C" }, timeout: 30_000 });
  const remoteSha = stdout.trim().split(/\s+/)[0];
  if (remoteSha !== identity.headSha) throw new Error(`remote branch is not pinned to local HEAD ${identity.headSha}`);
  return Object.freeze({ status: "verified", headSha: identity.headSha, remoteUrl: identity.remoteUrl });
}

const options = parse(process.argv.slice(2));
const identity = await captureExecutionIdentity({ cwd: process.cwd(), sessionId: options.sessionId });
const policyResolution = await resolveRepoPolicy({
  repoRoot: identity.worktreeRoot,
  policyId: "validation-receipt",
});
if (policyResolution.decision !== "apply") {
  throw new Error("repository does not declare validation-receipt policy");
}
const allowedArgv = policyResolution.policy.options?.allowedArgv;

if (options.operation === "record") {
  if (!validationArgvIsDeclared(options.argv, allowedArgv)) {
    throw new Error("validation argv is not declared by repository policy");
  }
  const result = await executeAndWriteValidationReceipt({
    identity,
    coveredFiles: options.files,
    argv: options.argv,
    remoteEvidenceReader: options.remote ? verifyRemote : null,
  });
  process.stdout.write(`${JSON.stringify({
    operation: "record",
    path: result.path,
    identityKey: result.receipt.execution.identity.identityKey,
  })}\n`);
} else if (options.operation === "clear") {
  const result = await clearStoredValidationCoverage({ identity, files: options.files, allowedArgv });
  process.stdout.write(`${JSON.stringify({ operation: "clear", path: result.path, changed: result.changed })}\n`);
} else {
  const receipt = await readValidationReceipt({ identity });
  const verification = verifyValidationReceipt(receipt, identity, {
    requiredFiles: options.files,
    requireRemote: options.remote,
    allowedArgv,
  });
  process.stdout.write(`${JSON.stringify({ operation: "verify", ...verification })}\n`);
  if (!verification.valid) process.exitCode = 2;
}
