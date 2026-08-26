import { createHash } from "node:crypto";
import { execFile as execFileCallback } from "node:child_process";
import { lstat, readFile, readlink, realpath } from "node:fs/promises";
import { isAbsolute, relative, resolve, sep } from "node:path";
import { promisify } from "node:util";

const execFile = promisify(execFileCallback);

function requireString(value, label) {
  if (typeof value !== "string" || value.length === 0) throw new Error(`${label} must be a non-empty string`);
  return value;
}

async function defaultGit(cwd, args, { allowFailure = false } = {}) {
  try {
    const { stdout } = await execFile("git", ["-C", cwd, ...args], {
      encoding: "utf8",
      env: { ...process.env, GIT_OPTIONAL_LOCKS: "0", LC_ALL: "C" },
      maxBuffer: 32 * 1024 * 1024,
      timeout: 10_000,
    });
    return stdout.replace(/\n$/, "");
  } catch (error) {
    if (allowFailure) return null;
    throw new Error(`git ${args.join(" ")} failed`, { cause: error });
  }
}

function resolveGitPath(repoRoot, value) {
  return resolve(isAbsolute(value) ? value : resolve(repoRoot, value));
}

function appendField(hash, label, value) {
  hash.update(`${label}\0${value.length}\0`);
  hash.update(value);
  hash.update("\0");
}

async function appendWorkingPath(hash, repoRoot, gitPath) {
  const absolutePath = resolve(repoRoot, gitPath);
  const inside = relative(repoRoot, absolutePath);
  if (!inside || inside === ".." || inside.startsWith(`..${sep}`) || isAbsolute(inside)) {
    throw new Error(`git path escaped the worktree: ${gitPath}`);
  }
  appendField(hash, "path", gitPath);
  try {
    const state = await lstat(absolutePath);
    appendField(hash, "mode", String(state.mode & 0o7777));
    if (state.isSymbolicLink()) {
      appendField(hash, "symlink", await readlink(absolutePath));
    } else if (state.isFile()) {
      appendField(hash, "file", await readFile(absolutePath));
    } else if (state.isDirectory()) {
      appendField(hash, "directory", "");
    } else {
      appendField(hash, "special", String(state.mode));
    }
  } catch (error) {
    if (error?.code !== "ENOENT") throw error;
    appendField(hash, "missing", "");
  }
}

async function workingTreeFingerprint(repoRoot, git) {
  const [listed, status] = await Promise.all([
    git(repoRoot, ["ls-files", "-z", "--cached", "--others", "--exclude-standard"]),
    git(repoRoot, ["status", "--porcelain=v2", "-z", "--untracked-files=all", "--ignore-submodules=none"]),
  ]);
  const paths = listed.split("\0").filter(Boolean).sort();
  const hash = createHash("sha256");
  appendField(hash, "status", status);
  for (const gitPath of paths) await appendWorkingPath(hash, repoRoot, gitPath);
  return hash.digest("hex");
}

function identityKey(identity) {
  const hash = createHash("sha256");
  for (const field of [
    "repoCommonDir", "worktreeRoot", "worktreeGitDir", "sessionId",
    "headSha", "headTreeSha", "worktreeFingerprint", "remoteUrl",
  ]) appendField(hash, field, identity[field] ?? "");
  return hash.digest("hex");
}

export async function discoverExecutionRoot({ cwd, git = defaultGit }) {
  requireString(cwd, "cwd");
  try {
    const reportedRoot = await git(cwd, ["rev-parse", "--show-toplevel"]);
    return reportedRoot ? realpath(reportedRoot) : null;
  } catch (error) {
    if (error?.cause?.code === 128) return null;
    throw error;
  }
}

export async function captureExecutionIdentity({ cwd, sessionId, git = defaultGit }) {
  requireString(cwd, "cwd");
  requireString(sessionId, "session id");
  const worktreeRoot = await discoverExecutionRoot({ cwd, git });
  if (!worktreeRoot) throw new Error("cwd is not inside a Git worktree");
  const [gitDirValue, commonDirValue, headSha, headTreeSha, branch, remoteUrl] = await Promise.all([
    git(worktreeRoot, ["rev-parse", "--git-dir"]),
    git(worktreeRoot, ["rev-parse", "--git-common-dir"]),
    git(worktreeRoot, ["rev-parse", "--verify", "HEAD"]),
    git(worktreeRoot, ["rev-parse", "--verify", "HEAD^{tree}"]),
    git(worktreeRoot, ["symbolic-ref", "--quiet", "--short", "HEAD"], { allowFailure: true }),
    git(worktreeRoot, ["remote", "get-url", "origin"], { allowFailure: true }),
  ]);
  const worktreeGitDir = await realpath(resolveGitPath(worktreeRoot, gitDirValue));
  const repoCommonDir = await realpath(resolveGitPath(worktreeRoot, commonDirValue));
  const base = {
    schemaVersion: 1,
    repoCommonDir,
    worktreeRoot,
    worktreeGitDir,
    sessionId,
    headSha,
    headTreeSha,
    branch: branch || null,
    remoteUrl: remoteUrl || null,
    worktreeFingerprint: await workingTreeFingerprint(worktreeRoot, git),
  };
  return Object.freeze({ ...base, identityKey: identityKey(base) });
}

function normalizeCoveredFile(worktreeRoot, file) {
  requireString(file, "covered file");
  const absolute = resolve(worktreeRoot, file);
  const normalized = relative(worktreeRoot, absolute);
  if (!normalized || normalized === ".." || normalized.startsWith(`..${sep}`) || isAbsolute(normalized)) {
    throw new Error(`covered file must stay inside the worktree: ${file}`);
  }
  return normalized;
}

export function createExecutionReceipt({ identity, coveredFiles, remoteEvidence = null }) {
  if (!identity || identity.schemaVersion !== 1 || typeof identity.identityKey !== "string") {
    throw new Error("a valid execution identity is required");
  }
  if (!Array.isArray(coveredFiles)) throw new Error("covered files must be an array");
  const normalizedFiles = [...new Set(coveredFiles.map((file) => normalizeCoveredFile(identity.worktreeRoot, file)))].sort();
  return Object.freeze({
    schemaVersion: 1,
    identity: Object.freeze({
      identityKey: identity.identityKey,
      repoCommonDir: identity.repoCommonDir,
      worktreeRoot: identity.worktreeRoot,
      worktreeGitDir: identity.worktreeGitDir,
      sessionId: identity.sessionId,
      headSha: identity.headSha,
      headTreeSha: identity.headTreeSha,
      worktreeFingerprint: identity.worktreeFingerprint,
      remoteUrl: identity.remoteUrl,
    }),
    coveredFiles: Object.freeze(normalizedFiles),
    remoteEvidence: remoteEvidence ? Object.freeze({ ...remoteEvidence }) : null,
  });
}

export function verifyExecutionReceipt(receipt, currentIdentity, { requiredFiles = [], requireRemote = false } = {}) {
  const reasons = [];
  if (!receipt || receipt.schemaVersion !== 1 || !receipt.identity) {
    return Object.freeze({ valid: false, reasons: ["receipt is malformed"] });
  }
  const fields = [
    "identityKey", "repoCommonDir", "worktreeRoot", "worktreeGitDir", "sessionId",
    "headSha", "headTreeSha", "worktreeFingerprint", "remoteUrl",
  ];
  for (const field of fields) {
    if (receipt.identity[field] !== currentIdentity?.[field]) reasons.push(`receipt ${field} is stale or belongs to another execution`);
  }
  let normalizedRequired = [];
  try {
    normalizedRequired = requiredFiles.map((file) => normalizeCoveredFile(currentIdentity.worktreeRoot, file));
  } catch (error) {
    reasons.push(error.message);
  }
  const covered = new Set(Array.isArray(receipt.coveredFiles) ? receipt.coveredFiles : []);
  for (const file of normalizedRequired) {
    if (!covered.has(file)) reasons.push(`receipt does not cover ${file}`);
  }
  if (requireRemote) {
    const evidence = receipt.remoteEvidence;
    if (!currentIdentity?.remoteUrl) reasons.push("repository has no origin remote");
    if (!evidence || evidence.status !== "verified") reasons.push("remote evidence is unavailable");
    else {
      if (evidence.headSha !== currentIdentity.headSha) reasons.push("remote evidence is stale");
      if (evidence.remoteUrl !== currentIdentity.remoteUrl) reasons.push("remote evidence belongs to another remote");
    }
  }
  return Object.freeze({ valid: reasons.length === 0, reasons: Object.freeze(reasons) });
}
