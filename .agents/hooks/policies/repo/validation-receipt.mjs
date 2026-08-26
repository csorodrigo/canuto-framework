import { createHash } from "node:crypto";
import { execFile as execFileCallback } from "node:child_process";
import { mkdir, readFile, rename, unlink, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { promisify } from "node:util";

import { captureExecutionIdentity, createExecutionReceipt, verifyExecutionReceipt } from "../../core/execution-identity.mjs";
import { allow, block } from "../../core/policy-result.mjs";

const execFile = promisify(execFileCallback);

function receiptName(identity) {
  return createHash("sha256").update(`${identity.worktreeRoot}\0${identity.sessionId}`).digest("hex");
}

export function validationReceiptPath(identity) {
  return join(identity.worktreeGitDir, "canuto-receipts", `validation-${receiptName(identity)}.json`);
}

function normalizeValidation(validation) {
  if (!validation || typeof validation !== "object") throw new Error("validation evidence is required");
  if (!Array.isArray(validation.argv) || validation.argv.length === 0
    || validation.argv.some((item) => typeof item !== "string" || !item)) {
    throw new Error("validation argv is required");
  }
  if (validation.exitCode !== 0) throw new Error("only a successful validation can create a receipt");
  return Object.freeze({ argv: Object.freeze([...validation.argv]), exitCode: 0 });
}

export function validationArgvIsDeclared(argv, allowedArgv) {
  if (!Array.isArray(argv) || !Array.isArray(allowedArgv)) return false;
  return allowedArgv.some((candidate) => Array.isArray(candidate)
    && candidate.length === argv.length
    && candidate.every((item, index) => item === argv[index]));
}

export function createValidationReceipt({ identity, coveredFiles, validation, remoteEvidence = null }) {
  return Object.freeze({
    kind: "canuto-validation-receipt",
    schemaVersion: 1,
    execution: createExecutionReceipt({ identity, coveredFiles, remoteEvidence }),
    validation: normalizeValidation(validation),
  });
}

export async function writeValidationReceipt({ identity, coveredFiles, validation, remoteEvidence = null, path = null }) {
  const destination = path ?? validationReceiptPath(identity);
  const receipt = createValidationReceipt({ identity, coveredFiles, validation, remoteEvidence });
  await mkdir(dirname(destination), { recursive: true, mode: 0o700 });
  const temporary = `${destination}.tmp.${process.pid}`;
  await writeFile(temporary, `${JSON.stringify(receipt, null, 2)}\n`, { mode: 0o600 });
  await rename(temporary, destination);
  return Object.freeze({ path: destination, receipt });
}

export async function executeAndWriteValidationReceipt({
  identity,
  coveredFiles,
  argv,
  remoteEvidence = null,
  remoteEvidenceReader = null,
  path = null,
  execute = execFile,
}) {
  if (!Array.isArray(argv) || argv.length === 0 || argv.some((item) => typeof item !== "string" || !item)) {
    throw new Error("validation argv is required");
  }
  await execute(argv[0], argv.slice(1), {
    cwd: identity.worktreeRoot,
    encoding: "utf8",
    env: { ...process.env, GIT_OPTIONAL_LOCKS: "0", LC_ALL: "C" },
    maxBuffer: 32 * 1024 * 1024,
    timeout: 10 * 60 * 1000,
  });
  const currentIdentity = await captureExecutionIdentity({
    cwd: identity.worktreeRoot,
    sessionId: identity.sessionId,
  });
  const currentRemoteEvidence = remoteEvidenceReader
    ? await remoteEvidenceReader(currentIdentity)
    : remoteEvidence;
  return writeValidationReceipt({
    identity: currentIdentity,
    coveredFiles,
    validation: { argv, exitCode: 0 },
    remoteEvidence: currentRemoteEvidence,
    path,
  });
}

export async function readValidationReceipt({ identity, path = null }) {
  const source = path ?? validationReceiptPath(identity);
  try {
    return JSON.parse(await readFile(source, "utf8"));
  } catch (error) {
    if (error?.code === "ENOENT") return null;
    throw error;
  }
}

export function verifyValidationReceipt(receipt, identity, {
  requiredFiles = [],
  requireRemote = false,
  allowedArgv = [],
} = {}) {
  if (!receipt || receipt.kind !== "canuto-validation-receipt" || receipt.schemaVersion !== 1) {
    return Object.freeze({ valid: false, reasons: Object.freeze(["validation receipt is missing or malformed"]) });
  }
  if (receipt.validation?.exitCode !== 0 || !Array.isArray(receipt.validation?.argv) || receipt.validation.argv.length === 0) {
    return Object.freeze({ valid: false, reasons: Object.freeze(["validation receipt has no successful command evidence"]) });
  }
  if (!validationArgvIsDeclared(receipt.validation.argv, allowedArgv)) {
    return Object.freeze({ valid: false, reasons: Object.freeze(["validation argv is not declared by repository policy"]) });
  }
  return verifyExecutionReceipt(receipt.execution, identity, { requiredFiles, requireRemote });
}

export function clearValidationCoverage(receipt, identity, files, { allowedArgv = [] } = {}) {
  const verified = verifyValidationReceipt(receipt, identity, { allowedArgv });
  if (!verified.valid) return Object.freeze({ changed: false, receipt: null, reasons: verified.reasons });
  const removed = new Set(files);
  const coveredFiles = receipt.execution.coveredFiles.filter((file) => !removed.has(file));
  if (coveredFiles.length === receipt.execution.coveredFiles.length) {
    return Object.freeze({ changed: false, receipt, reasons: Object.freeze([]) });
  }
  if (coveredFiles.length === 0) return Object.freeze({ changed: true, receipt: null, reasons: Object.freeze([]) });
  return Object.freeze({
    changed: true,
    receipt: createValidationReceipt({
      identity,
      coveredFiles,
      validation: receipt.validation,
      remoteEvidence: receipt.execution.remoteEvidence,
    }),
    reasons: Object.freeze([]),
  });
}

export async function clearStoredValidationCoverage({ identity, files, path = null, allowedArgv = [] }) {
  const destination = path ?? validationReceiptPath(identity);
  const current = await readValidationReceipt({ identity, path: destination });
  const cleared = clearValidationCoverage(current, identity, files, { allowedArgv });
  if (!cleared.changed) return Object.freeze({ ...cleared, path: destination });
  if (!cleared.receipt) {
    await unlink(destination).catch((error) => { if (error?.code !== "ENOENT") throw error; });
  } else {
    const temporary = `${destination}.tmp.${process.pid}`;
    await writeFile(temporary, `${JSON.stringify(cleared.receipt, null, 2)}\n`, { mode: 0o600 });
    await rename(temporary, destination);
  }
  return Object.freeze({ ...cleared, path: destination });
}

export function evaluateValidationReceipt({ policy }) {
  return policy.options?.enabled === true && Array.isArray(policy.options?.allowedArgv) && policy.options.allowedArgv.length > 0
    ? allow("validation-receipt", "repository validation receipt workflow is enabled")
    : block("validation-receipt", "validation receipt workflow requires an exact repository-owned argv allowlist");
}

export function evaluateReceiptConsumer(policyId, { identity, policy, receipt, allowedArgv }) {
  const requiredFiles = Array.isArray(policy.options?.requiredFiles) ? policy.options.requiredFiles : [];
  const requireRemote = policyId === "pull-request";
  const verification = verifyValidationReceipt(receipt, identity, { requiredFiles, requireRemote, allowedArgv });
  return verification.valid
    ? allow(policyId, `${policyId} receipt matches worktree, session, SHA and tree`)
    : block(policyId, verification.reasons.join("; "));
}
