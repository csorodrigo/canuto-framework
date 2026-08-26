#!/usr/bin/env node

import cp from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = process.env.CANUTO_HOOK_HOME || os.homedir();
const VAULT = process.env.CANUTO_HOOK_VAULT || path.join(ROOT, ".canuto", "vault");
const PROJECTS = path.join(VAULT, "projects");
const CANUTO = process.env.CANUTO_HOOK_CANUTO || path.join(ROOT, ".canuto", "bin", "canuto-brain.mjs");
const LOG = process.env.CANUTO_HOOK_LOG || path.join(ROOT, ".codex", "log", "canuto-hooks.log");
const LOG_MAX_BYTES = Number(process.env.CANUTO_HOOK_LOG_MAX_BYTES || 512 * 1024);
const STATE_DIR = process.env.CANUTO_HOOK_STATE_DIR || path.join(os.tmpdir(), "canuto-hooks");
const BRIEF_MAX_CHARS = Number(process.env.CANUTO_HOOK_BRIEF_MAX_CHARS || 4000);
const EVENT_HISTORY_LIMIT = 80;
const LOCK_TIMEOUT_MS = Number(process.env.CANUTO_HOOK_LOCK_TIMEOUT_MS || 1500);
const LOCK_STALE_MS = Number(process.env.CANUTO_HOOK_LOCK_STALE_MS || 2000);
const LOCK_RECOVERY_TIMEOUT_MS = Number(process.env.CANUTO_HOOK_LOCK_RECOVERY_TIMEOUT_MS || 250);
const LOCAL_COMMAND_TIMEOUT_MS = Number(process.env.CANUTO_HOOK_LOCAL_COMMAND_TIMEOUT_MS || 750);
const CLOSEOUT_QUEUE_DIR = process.env.CANUTO_HOOK_CLOSEOUT_QUEUE_DIR
  || path.join(ROOT, ".canuto", "state", "hook-closeout-queue");

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function log(line) {
  try {
    ensureDir(path.dirname(LOG));
    if (LOG_MAX_BYTES && fs.existsSync(LOG) && fs.statSync(LOG).size >= LOG_MAX_BYTES) {
      fs.rmSync(`${LOG}.1`, { force: true });
      fs.renameSync(LOG, `${LOG}.1`);
    }
    fs.appendFileSync(LOG, `[${new Date().toISOString()}] ${line}\n`);
  } catch {}
}

function readStdinJson() {
  try {
    const text = fs.readFileSync(0, "utf8").trim();
    return text ? JSON.parse(text) : {};
  } catch {
    return {};
  }
}

function slugify(input) {
  return String(input || "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 100) || "unknown";
}

function hash(input) {
  return crypto.createHash("sha1").update(String(input || "")).digest("hex").slice(0, 12);
}

function projectNames() {
  try {
    return fs.readdirSync(PROJECTS, { withFileTypes: true })
      .filter((entry) => entry.isDirectory())
      .map((entry) => entry.name)
      .sort();
  } catch {
    return [];
  }
}

function inferCwd(data) {
  return data.cwd || data.current_working_directory || data.workspace || process.cwd();
}

function canonicalPath(value) {
  const resolved = path.resolve(String(value || process.cwd()));
  try {
    return fs.realpathSync.native(resolved);
  } catch {
    return resolved;
  }
}

function gitValue(cwd, args) {
  try {
    const result = cp.spawnSync("git", ["-C", cwd, ...args], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
      timeout: LOCAL_COMMAND_TIMEOUT_MS,
    });
    return result.status === 0 ? String(result.stdout || "").trim() : "";
  } catch {
    return "";
  }
}

function executionScope(cwd) {
  const canonicalCwd = canonicalPath(cwd);
  const [worktreeRaw = "", commonRaw = ""] = gitValue(canonicalCwd, ["rev-parse", "--show-toplevel", "--git-common-dir"]).split("\n");
  const worktree = worktreeRaw ? canonicalPath(worktreeRaw) : "";
  const repository = commonRaw
    ? canonicalPath(path.isAbsolute(commonRaw) ? commonRaw : path.join(worktree || canonicalCwd, commonRaw))
    : "";
  return { repository, worktree, cwd: canonicalCwd };
}

function inferProject(cwd, scope = executionScope(cwd)) {
  const names = projectNames();
  if (names.length === 0) return "";
  const scopedPaths = [scope.cwd, scope.worktree, scope.repository].filter(Boolean);
  for (const scopedPath of scopedPaths) {
    const basename = slugify(path.basename(scopedPath));
    if (names.includes(basename)) return basename;
  }
  const remote = gitValue(scope.cwd, ["remote", "get-url", "origin"]);
  const remoteName = slugify(path.basename(remote).replace(/\.git$/, ""));
  if (names.includes(remoteName)) return remoteName;
  const pathMatch = names.find((name) => scopedPaths.some((scopedPath) =>
    scopedPath.split(path.sep).filter(Boolean).includes(name)));
  return pathMatch || "";
}

function sessionKey(data, cwd, scope = executionScope(cwd)) {
  const raw = data.session_id || data.sessionId || data.thread_id || data.threadId || data.transcript_path || scope.cwd;
  const identity = JSON.stringify({ session: String(raw), ...scope });
  return `${slugify(path.basename(String(raw)))}-${hash(identity)}`;
}

function statePath(key) {
  ensureDir(STATE_DIR);
  return path.join(STATE_DIR, `${key}.json`);
}

function lockPath(key) {
  ensureDir(STATE_DIR);
  return path.join(STATE_DIR, `${key}.lock`);
}

function processAlive(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    return true;
  } catch (error) {
    return error?.code === "EPERM";
  }
}

function readProcessIdentity(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return null;
  try {
    const result = cp.spawnSync("ps", ["-p", String(pid), "-o", "lstart=,command="], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
      timeout: LOCAL_COMMAND_TIMEOUT_MS,
    });
    if (result.status !== 0) return null;
    const line = String(result.stdout || "").trim();
    const match = line.match(/^(\S+\s+\S+\s+\S+\s+\S+\s+\S+)\s+(.+)$/);
    if (!match) return null;
    return { lstart: match[1], commandHash: hash(match[2]) };
  } catch {
    return null;
  }
}

function currentLockOwner() {
  const identity = readProcessIdentity(process.pid);
  return {
    schema_version: 1,
    owner: "canuto_hook",
    pid: process.pid,
    created_at: new Date().toISOString(),
    created_at_ms: Date.now(),
    lstart: identity?.lstart || "",
    commandHash: identity?.commandHash || "",
  };
}

function readLockOwner(lock) {
  try {
    const parsed = JSON.parse(fs.readFileSync(lock, "utf8"));
    return parsed && typeof parsed === "object" ? parsed : null;
  } catch {
    return null;
  }
}

function lockOwnerIncompatible(owner) {
  const pid = Number(owner?.pid);
  if (!Number.isInteger(pid) || pid <= 0) return false;
  const current = readProcessIdentity(pid);
  if (!current) return false;
  if (owner.lstart && current.lstart && owner.lstart !== current.lstart) return true;
  return Boolean(owner.commandHash && current.commandHash && owner.commandHash !== current.commandHash);
}

function lockIdentity(stat) {
  return [stat.dev, stat.ino, stat.size, stat.mtimeMs].join(":");
}

function recoveryGatePath(lock) {
  return `${lock}.recovery`;
}

function acquireRecoveryGate(lock) {
  const gate = recoveryGatePath(lock);
  try {
    fs.mkdirSync(gate, { mode: 0o700 });
    return true;
  } catch (error) {
    if (error?.code !== "EEXIST") return false;
    try {
      if (Date.now() - fs.statSync(gate).mtimeMs <= LOCK_RECOVERY_TIMEOUT_MS) return false;
      fs.rmSync(gate, { recursive: true, force: true });
      fs.mkdirSync(gate, { mode: 0o700 });
      return true;
    } catch {
      return false;
    }
  }
}

function releaseRecoveryGate(lock) {
  try {
    fs.rmdirSync(recoveryGatePath(lock));
  } catch {}
}

function removeAbandonedLock(lock) {
  let observed;
  try {
    observed = fs.statSync(lock);
  } catch {
    return false;
  }
  if (Date.now() - observed.mtimeMs < LOCK_STALE_MS) return false;
  const owner = readLockOwner(lock);
  const pid = Number(owner?.pid);
  if (!Number.isInteger(pid) || pid <= 0) return false;
  if (processAlive(pid) && !lockOwnerIncompatible(owner)) return false;
  if (!acquireRecoveryGate(lock)) return false;
  try {
    const current = fs.statSync(lock);
    if (lockIdentity(current) !== lockIdentity(observed)) return false;
    const currentOwner = readLockOwner(lock);
    const currentPid = Number(currentOwner?.pid);
    if (!Number.isInteger(currentPid) || currentPid <= 0) return false;
    if (processAlive(currentPid) && !lockOwnerIncompatible(currentOwner)) return false;
    fs.rmSync(lock);
    log(`lock_removed key=${path.basename(lock)} pid=${currentPid}`);
    return true;
  } catch {
    return false;
  } finally {
    releaseRecoveryGate(lock);
  }
}

function loadStateUnlocked(key, defaults) {
  try {
    return { ...defaults, ...JSON.parse(fs.readFileSync(statePath(key), "utf8")) };
  } catch {
    return { ...defaults };
  }
}

function saveStateUnlocked(key, state) {
  const file = statePath(key);
  const temporary = `${file}.${process.pid}.${crypto.randomUUID()}.tmp`;
  fs.writeFileSync(temporary, JSON.stringify({ ...state, updatedAt: new Date().toISOString() }, null, 2));
  fs.renameSync(temporary, file);
}

function withState(key, defaults, updater, timeoutMs = LOCK_TIMEOUT_MS) {
  const lock = lockPath(key);
  const deadline = Date.now() + Math.max(0, timeoutMs);
  let fd = null;
  while (fd === null) {
    try {
      fd = fs.openSync(lock, "wx", 0o600);
      fs.writeFileSync(fd, `${JSON.stringify(currentLockOwner())}\n`);
      fs.fsyncSync(fd);
    } catch (error) {
      if (fd !== null) {
        try { fs.closeSync(fd); } catch {}
        fd = null;
        try { fs.rmSync(lock, { force: true }); } catch {}
      }
      if (error?.code !== "EEXIST") throw error;
      removeAbandonedLock(lock);
      if (Date.now() >= deadline) return { busy: true, state: null, result: null };
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 20);
    }
  }
  try {
    const state = loadStateUnlocked(key, defaults);
    const result = updater(state);
    saveStateUnlocked(key, state);
    return { busy: false, state, result };
  } finally {
    try { fs.closeSync(fd); } catch {}
    try { fs.rmSync(lock, { force: true }); } catch {}
  }
}

function runCanuto(args, options = {}) {
  return cp.spawnSync(process.execPath, [CANUTO, ...args], {
    cwd: options.cwd || ROOT,
    encoding: "utf8",
    stdio: ["ignore", "pipe", "pipe"],
    timeout: options.timeout || 20000,
  });
}

function generateBrief(project, key) {
  if (!project) return { pathname: "", text: "" };
  const pathname = path.join(os.tmpdir(), `canuto-brief-${project}-${key}.md`);
  const result = runCanuto(["brief", project], { timeout: 25000 });
  if (result.status === 0 && String(result.stdout || "").trim()) {
    fs.writeFileSync(pathname, result.stdout);
    return { pathname, text: result.stdout };
  }
  log(`brief_failed project=${project} status=${result.status}`);
  return { pathname: "", text: "" };
}

function readBrief(pathname) {
  try {
    return pathname ? fs.readFileSync(pathname, "utf8") : "";
  } catch {
    return "";
  }
}

function boundedBrief(text) {
  const clean = String(text || "").replace(/\r/g, "").trim();
  if (clean.length <= BRIEF_MAX_CHARS) return clean;
  return `${clean.slice(0, BRIEF_MAX_CHARS)}\n\n[Canuto brief truncated at ${BRIEF_MAX_CHARS} chars]`;
}

function emitStartContext(context) {
  console.log(JSON.stringify({
    additionalContext: context,
    hookSpecificOutput: { hookEventName: "SessionStart", additionalContext: context },
  }));
}

function toolName(data) {
  return String(data.tool_name || data.toolName || data.name || data.tool || data.matcher || "Bash");
}

function toolCommand(data) {
  const input = data.tool_input || data.toolInput || data.input || {};
  return String(input.command || input.cmd || input.script || input.code || input.patch || "");
}

function looksLikeEdit(tool, command) {
  const normalizedTool = tool.toLowerCase();
  const normalizedCommand = command.toLowerCase();
  if (/(^|\.)(edit|write|multiedit|apply_patch|notebookedit)$/.test(normalizedTool)) return true;
  return /\b(apply_patch|git\s+(commit|add|rebase|merge|cherry-pick))\b/.test(normalizedCommand)
    || /\b(sed|perl)\s+(-i|.*\s-i\b)/.test(normalizedCommand)
    || /\bnode\b.*\bwritefilesync\b/.test(normalizedCommand)
    || /\bpython3?\b.*\b(open|write_text|write_bytes)\b/.test(normalizedCommand);
}

function looksLikeValidation(command) {
  return /\b(npm|pnpm|yarn|bun)\s+(run\s+)?(test|lint|build|typecheck)\b|\b(pytest|vitest)\b|\bnode\s+(--check|--test)\b|\bgit\s+diff\s+--check\b/i.test(command);
}

function looksLikeCloseout(command) {
  return /canuto-brain(?:\.mjs)?\s+closeout|canuto-closeout/i.test(command);
}

function eventId(mode, data) {
  const explicit = data.tool_use_id || data.toolUseId || data.tool_call_id || data.toolCallId || data.call_id || data.callId || data.event_id || data.eventId;
  if (explicit) return `${mode}:${explicit}`;
  return `${mode}:${hash(JSON.stringify({ cwd: inferCwd(data), tool: toolName(data), command: toolCommand(data), response: data.tool_response || data.toolResponse || data.response || null }))}`;
}

function markProcessed(state, id) {
  state.processedEvents = Array.isArray(state.processedEvents) ? state.processedEvents : [];
  if (state.processedEvents.includes(id)) return false;
  state.processedEvents.push(id);
  state.processedEvents = state.processedEvents.slice(-EVENT_HISTORY_LIMIT);
  return true;
}

function provenSuccess(data) {
  const response = data.tool_response || data.toolResponse || data.response || data.result || {};
  const codes = [response.exit_code, response.exitCode, response.status_code, response.statusCode, response?.metadata?.exit_code, response?.metadata?.exitCode];
  return codes.some((value) => value === 0 || value === "0")
    || response.ok === true
    || response.success === true
    || (typeof response.status === "string" && /^(success|succeeded|ok|completed)$/i.test(response.status));
}

function defaultState(key, scope, project) {
  return {
    key,
    cwd: scope.cwd,
    repository: scope.repository,
    worktree: scope.worktree,
    project,
    editSeen: false,
    validationSeen: false,
    closeoutSeen: false,
    attempts: [],
    processedEvents: [],
  };
}

function start(data) {
  const scope = executionScope(inferCwd(data));
  const cwd = scope.cwd;
  const key = sessionKey(data, cwd, scope);
  const project = inferProject(cwd, scope);
  const defaults = defaultState(key, scope, project);
  const initial = withState(key, defaults, (state) => {
    state.cwd = cwd;
    state.project = project || state.project || "";
    state.startedAt ||= new Date().toISOString();
    return { project: state.project, briefPath: state.briefPath || "" };
  });
  if (initial.busy) {
    log(`start_busy key=${key}`);
    emitStartContext(`Canuto brief unavailable: session state is busy.\nCWD: ${cwd}`);
    return;
  }

  let briefPath = initial.result.briefPath;
  if (initial.result.project && !briefPath) {
    const sync = runCanuto(["sync", "--quiet", "--timeout", "10"], { timeout: 15000 });
    log(`start_sync key=${key} status=${sync.status}`);
    const generated = generateBrief(initial.result.project, key);
    if (generated.pathname) {
      const committed = withState(key, defaults, (state) => {
        state.briefPath ||= generated.pathname;
        state.briefStatus = "generated";
        state.briefChars = generated.text.length;
        return state.briefPath;
      });
      briefPath = committed.busy ? generated.pathname : committed.result;
    }
  }

  const briefText = readBrief(briefPath);
  const context = initial.result.project && briefText
    ? [`Canuto project brief for ${initial.result.project} (bounded hook context).`, `CWD: ${cwd}`, `Brief file: ${briefPath}`, "", boundedBrief(briefText)].join("\n")
    : ["Canuto brief: no project brief was injected for this session.", `CWD: ${cwd}`, initial.result.project ? `Project: ${initial.result.project}; brief unavailable.` : "Project: none inferred."].join("\n");
  log(`start key=${key} project=${initial.result.project || "none"}`);
  emitStartContext(context);
}

function pretool(data) {
  const scope = executionScope(inferCwd(data));
  const cwd = scope.cwd;
  const key = sessionKey(data, cwd, scope);
  const project = inferProject(cwd, scope);
  const command = toolCommand(data);
  const tool = toolName(data);
  const result = withState(key, defaultState(key, scope, project), (state) => {
    if (!markProcessed(state, eventId("pretool", data))) return { editAttempt: false, needsBrief: false };
    state.cwd = cwd;
    state.project ||= project;
    const editAttempt = looksLikeEdit(tool, command);
    state.attempts = Array.isArray(state.attempts) ? state.attempts : [];
    state.attempts.push({ at: new Date().toISOString(), editAttempt, validationAttempt: looksLikeValidation(command), closeoutAttempt: looksLikeCloseout(command), commandHash: hash(command) });
    state.attempts = state.attempts.slice(-EVENT_HISTORY_LIMIT);
    return { editAttempt, needsBrief: Boolean(editAttempt && state.project && !state.briefPath), project: state.project };
  });
  if (result.busy) {
    log(`pretool_busy key=${key}`);
    return;
  }
  if (result.result.needsBrief) {
    const brief = generateBrief(result.result.project, key);
    if (brief.pathname) {
      withState(key, defaultState(key, scope, project), (state) => { state.briefPath ||= brief.pathname; });
    }
    const warning = `Canuto soft warning: project '${result.result.project}' had no session brief before an edit attempt. Generated ${brief.pathname || "no brief"}; read it before substantial changes.`;
    console.error(warning);
    console.log(JSON.stringify({ hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecisionReason: warning } }));
  }
}

function posttool(data) {
  const scope = executionScope(inferCwd(data));
  const cwd = scope.cwd;
  const key = sessionKey(data, cwd, scope);
  const project = inferProject(cwd, scope);
  const result = withState(key, defaultState(key, scope, project), (state) => {
    if (!markProcessed(state, eventId("posttool", data))) return;
    const command = toolCommand(data);
    if (!provenSuccess(data)) return;
    if (looksLikeValidation(command)) state.validationSeen = true;
    if (looksLikeCloseout(command)) state.closeoutSeen = true;
    if (looksLikeEdit(toolName(data), command)) {
      state.editSeen = true;
      state.firstEditAt ||= new Date().toISOString();
    }
  });
  if (result.busy) log(`posttool_busy key=${key}`);
}

function atomicJson(pathname, value) {
  ensureDir(path.dirname(pathname));
  const temporary = `${pathname}.${process.pid}.${crypto.randomUUID()}.tmp`;
  fs.writeFileSync(temporary, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600 });
  fs.renameSync(temporary, pathname);
}

function enqueueCloseout(job) {
  ensureDir(CLOSEOUT_QUEUE_DIR);
  const pathname = path.join(CLOSEOUT_QUEUE_DIR, `${Date.now()}-${process.pid}-${crypto.randomUUID()}.pending.json`);
  atomicJson(pathname, job);
  return pathname;
}

function launchCloseoutWorker(jobPathname, cwd) {
  const child = cp.spawn(process.execPath, [fileURLToPath(import.meta.url), "worker", jobPathname], {
    cwd,
    detached: true,
    env: process.env,
    stdio: "ignore",
  });
  child.unref();
  return child.pid;
}

function runCloseoutWorker(jobPathname) {
  if (!jobPathname || !jobPathname.endsWith(".pending.json")) return;
  const runningPath = jobPathname.replace(/\.pending\.json$/, ".running.json");
  try {
    fs.renameSync(jobPathname, runningPath);
  } catch (error) {
    if (error?.code !== "ENOENT") log(`closeout_worker_claim_failed path=${jobPathname} error=${error.message}`);
    return;
  }
  try {
    const job = JSON.parse(fs.readFileSync(runningPath, "utf8"));
    const closed = runCanuto(["closeout", "--auto", "--session", job.key, "--cwd", job.cwd, "--validation", job.validation], {
      cwd: job.cwd,
      timeout: 60000,
    });
    const donePath = runningPath.replace(/\.running\.json$/, closed.status === 0 ? ".done.json" : ".failed.json");
    atomicJson(runningPath, { ...job, workerPid: process.pid, completedAt: new Date().toISOString(), status: closed.status });
    log(`end_auto_closeout key=${job.key} status=${closed.status}`);
    fs.renameSync(runningPath, donePath);
  } catch (error) {
    const failedPath = runningPath.replace(/\.running\.json$/, ".failed.json");
    try { fs.renameSync(runningPath, failedPath); } catch {}
    log(`closeout_worker_failed path=${jobPathname} error=${error?.stack || error}`);
  }
}

function end(data) {
  const scope = executionScope(inferCwd(data));
  const cwd = scope.cwd;
  const key = sessionKey(data, cwd, scope);
  // SessionEnd stays below Codex's three-second hard clamp. Project identity
  // was persisted by earlier events; do not add remote discovery to this path.
  const project = "";
  const result = withState(key, defaultState(key, scope, project), (state) => {
    state.endedAt = new Date().toISOString();
    state.sessionEndAdvisory = { editSeen: Boolean(state.editSeen), validationSeen: Boolean(state.validationSeen), closeoutSeen: Boolean(state.closeoutSeen), project: state.project || project || "" };
    return { closeoutNeeded: !state.closeoutSeen, validationSeen: Boolean(state.validationSeen), editSeen: Boolean(state.editSeen) };
  }, Math.min(LOCK_TIMEOUT_MS, 500));
  if (result.busy) {
    log(`end_busy key=${key}`);
    return;
  }
  if (result.result.closeoutNeeded) {
    const validation = [result.result.validationSeen ? "validation-seen" : "", result.result.editSeen ? "edits-seen" : ""].filter(Boolean).join(",");
    const jobPathname = enqueueCloseout({ schemaVersion: 1, key, cwd, validation, queuedAt: new Date().toISOString() });
    const workerPid = launchCloseoutWorker(jobPathname, cwd);
    log(`closeout_worker_started key=${key} pid=${workerPid} job=${jobPathname}`);
  }
}

function inferredMode() {
  const name = path.basename(fileURLToPath(import.meta.url));
  return ({
    "canuto-session-start.mjs": "start",
    "canuto-pretool.mjs": "pretool",
    "canuto-posttool.mjs": "posttool",
    "canuto-session-end.mjs": "end",
  })[name] || "";
}

const mode = process.argv[2] || inferredMode();
const data = mode === "worker" ? {} : readStdinJson();

try {
  if (mode === "start") start(data);
  else if (mode === "pretool") pretool(data);
  else if (mode === "posttool") posttool(data);
  else if (mode === "end") end(data);
  else if (mode === "worker") runCloseoutWorker(process.argv[3]);
  else log(`unknown_mode mode=${mode}`);
} catch (error) {
  log(`error mode=${mode} message=${error?.stack || error}`);
  if (mode === "start") {
    emitStartContext(`Canuto brief unavailable: hook degraded safely.\nCWD: ${inferCwd(data)}`);
  }
}
