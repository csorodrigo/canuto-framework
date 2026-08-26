#!/usr/bin/env node

// Behavioral acceptance harness for the external Codex Companion owner.
// It never touches the user's live settings: every scenario uses mkdtemp.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const ownerRoot = process.env.CODEX_COMPANION_OWNER_ROOT ??
  path.join(os.homedir(), ".claude", "plugins", "cache", "openai-codex", "codex", "1.0.5");
const scriptsRoot = path.join(ownerRoot, "scripts");
const stopHook = path.join(scriptsRoot, "stop-review-gate-hook.mjs");
const lifecycleHook = path.join(scriptsRoot, "session-lifecycle-hook.mjs");
const stateModule = path.join(scriptsRoot, "lib", "state.mjs");
const brokerModule = path.join(scriptsRoot, "lib", "broker-lifecycle.mjs");

function tempBox(label) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), `canuto-${label}-`));
  const workspace = path.join(root, "workspace");
  fs.mkdirSync(workspace, { recursive: true });
  execFileSync("git", ["init", "-q"], { cwd: workspace });
  return { root, workspace, pluginData: path.join(root, "plugin-data") };
}

function runStop(box, mode) {
  const wrapper = `
import childProcess from "node:child_process";
import { syncBuiltinESMExports } from "node:module";
import { setConfig } from ${JSON.stringify(pathToFileURL(stateModule).href)};
const mode = ${JSON.stringify(mode)};
const stop = ${JSON.stringify(pathToFileURL(stopHook).href)};
const original = childProcess.spawnSync;
childProcess.spawnSync = (command, args = [], options = {}) => {
  if (command === "codex" && args[0] === "--version") return { status: 0, stdout: "codex-canary\\n", stderr: "" };
  if (command === process.execPath && String(args[0] ?? "").endsWith("/codex-companion.mjs")) {
    if (mode === "timeout") return { status: null, stdout: "", stderr: "", error: Object.assign(new Error("timed out"), { code: "ETIMEDOUT" }) };
    if (mode === "error") return { status: 1, stdout: "", stderr: "simulated review failure" };
    if (mode === "invalid") return { status: 0, stdout: "not-json", stderr: "" };
    const rawOutput = mode === "block" ? "BLOCK: canary finding" : "ALLOW: canary clean";
    return { status: 0, stdout: JSON.stringify({ rawOutput }), stderr: "" };
  }
  return original(command, args, options);
};
syncBuiltinESMExports();
setConfig(${JSON.stringify(box.workspace)}, "stopReviewGate", true);
await import(stop);
`;
  const output = execFileSync(process.execPath, ["--input-type=module", "-e", wrapper], {
    cwd: box.workspace,
    env: { ...process.env, CLAUDE_PLUGIN_DATA: box.pluginData },
    input: `${JSON.stringify({ cwd: box.workspace, session_id: "canary-session", last_assistant_message: "sanitized" })}\n`,
    encoding: "utf8",
    timeout: 30000,
  }).trim();
  return output ? JSON.parse(output) : null;
}

function runCleanup(box) {
  const wrapper = `
import { saveState } from ${JSON.stringify(pathToFileURL(stateModule).href)};
import { saveBrokerSession } from ${JSON.stringify(pathToFileURL(brokerModule).href)};
saveState(${JSON.stringify(box.workspace)}, { config: { stopReviewGate: true }, jobs: [
  { id: "same-session", sessionId: "session-a", status: "completed" },
  { id: "other-session", sessionId: "session-b", status: "completed" }
] });
const dir = ${JSON.stringify(path.join(box.root, "broker-a"))};
const pidFile = ${JSON.stringify(path.join(box.root, "broker-a", "broker.pid"))};
const logFile = ${JSON.stringify(path.join(box.root, "broker-a", "broker.log"))};
await import("node:fs").then(({ default: fs }) => { fs.mkdirSync(dir, { recursive: true }); fs.writeFileSync(pidFile, "0\\n"); fs.writeFileSync(logFile, "canary\\n"); });
saveBrokerSession(${JSON.stringify(box.workspace)}, { endpoint: null, pidFile, logFile, sessionDir: dir, pid: null });
`;
  execFileSync(process.execPath, ["--input-type=module", "-e", wrapper], { cwd: box.workspace, env: { ...process.env, CLAUDE_PLUGIN_DATA: box.pluginData } });
  const otherWorkspace = path.join(box.root, "other-workspace");
  fs.mkdirSync(otherWorkspace, { recursive: true });
  execFileSync("git", ["init", "-q"], { cwd: otherWorkspace });
  const otherState = path.join(box.root, "other-plugin-data");
  const otherBrokerDir = path.join(box.root, "broker-b");
  fs.mkdirSync(otherBrokerDir, { recursive: true });
  const otherPid = path.join(otherBrokerDir, "broker.pid");
  const otherLog = path.join(otherBrokerDir, "broker.log");
  fs.writeFileSync(otherPid, "0\n");
  fs.writeFileSync(otherLog, "preserve\n");
  const otherSetup = `
import { saveState } from ${JSON.stringify(pathToFileURL(stateModule).href)};
import { saveBrokerSession } from ${JSON.stringify(pathToFileURL(brokerModule).href)};
saveState(${JSON.stringify(otherWorkspace)}, { config: { stopReviewGate: true }, jobs: [{ id: "other", sessionId: "session-b", status: "completed" }] });
saveBrokerSession(${JSON.stringify(otherWorkspace)}, { endpoint: null, pidFile: ${JSON.stringify(otherPid)}, logFile: ${JSON.stringify(otherLog)}, sessionDir: ${JSON.stringify(otherBrokerDir)}, pid: null });
`;
  execFileSync(process.execPath, ["--input-type=module", "-e", otherSetup], { cwd: otherWorkspace, env: { ...process.env, CLAUDE_PLUGIN_DATA: otherState } });
  execFileSync(process.execPath, [lifecycleHook, "SessionEnd"], {
    cwd: box.workspace,
    env: { ...process.env, CLAUDE_PLUGIN_DATA: box.pluginData },
    input: `${JSON.stringify({ hook_event_name: "SessionEnd", cwd: box.workspace, session_id: "session-a" })}\n`,
    encoding: "utf8",
  });
  const remaining = JSON.parse(fs.readFileSync(path.join(box.pluginData, "state", `${path.basename(box.workspace)}-${crypto.createHash("sha256").update(fs.realpathSync.native(box.workspace)).digest("hex").slice(0, 16)}`, "state.json"), "utf8"));
  assert.deepEqual(remaining.jobs.map((job) => job.id), ["other-session"]);
  assert.equal(fs.existsSync(path.join(box.root, "broker-a")), false);
  assert.equal(fs.existsSync(otherPid), true);
  assert.equal(fs.existsSync(otherLog), true);
  return { remainingJobs: remaining.jobs.length, sameWorkspaceBrokerRemoved: true, foreignBrokerPreserved: true };
}

if (!fs.existsSync(stopHook) || !fs.existsSync(lifecycleHook)) {
  throw new Error(`Codex Companion owner missing under ${ownerRoot}`);
}

const box = tempBox("codex-companion-canary");
try {
  const decisions = Object.fromEntries(["allow", "block", "error", "invalid", "timeout"].map((mode) => [mode, runStop(box, mode)]));
  assert.equal(decisions.allow, null);
  for (const mode of ["block", "error", "invalid", "timeout"]) assert.equal(decisions[mode]?.decision, "block");
  const cleanup = runCleanup(box);
  const sourceHash = crypto.createHash("sha256").update(fs.readFileSync(stopHook)).digest("hex");
  process.stdout.write(`${JSON.stringify({ ownerRoot, stopHookSha256: sourceHash, decisions: Object.fromEntries(Object.entries(decisions).map(([mode, value]) => [mode, value ? value.decision : "allow"])), cleanup })}\n`);
} finally {
  fs.rmSync(box.root, { recursive: true, force: true });
}
