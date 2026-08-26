import assert from "node:assert/strict";
import { execFileSync, spawn } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

const pluginDir = path.dirname(new URL(import.meta.url).pathname);
const hookSource = path.join(pluginDir, "hooks", "canuto-hook.mjs");
const hooksInstaller = path.resolve(pluginDir, "..", "..", "hooks", "install.sh");

function sandbox() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "canuto-hook-test-"));
  const home = path.join(root, "home");
  const state = path.join(root, "state");
  const cwd = path.join(root, "project");
  fs.mkdirSync(home, { recursive: true });
  fs.mkdirSync(state, { recursive: true });
  fs.mkdirSync(cwd, { recursive: true });
  return { root, home, state, cwd };
}

function hookEnv(box, overrides = {}) {
  return {
    ...process.env,
    CANUTO_HOOK_HOME: box.home,
    CANUTO_HOOK_VAULT: path.join(box.home, ".canuto", "vault"),
    CANUTO_HOOK_STATE_DIR: box.state,
    CANUTO_HOOK_CLOSEOUT_QUEUE_DIR: path.join(box.root, "closeout-queue"),
    CANUTO_HOOK_LOG: path.join(box.home, ".codex", "log", "canuto-hooks.log"),
    CANUTO_HOOK_LOCK_TIMEOUT_MS: "80",
    CANUTO_HOOK_LOCK_STALE_MS: "10000",
    ...overrides,
  };
}

function runHook(box, mode, payload, overrides = {}) {
  return execFileSync(process.execPath, [hookSource, mode], {
    cwd: box.cwd,
    env: hookEnv(box, overrides),
    input: JSON.stringify(payload),
    encoding: "utf8",
    timeout: 5000,
  });
}

function runHookAsync(box, mode, payload, overrides = {}) {
  return new Promise((resolve, reject) => {
    const child = spawn(process.execPath, [hookSource, mode], {
      cwd: box.cwd,
      env: hookEnv(box, overrides),
      stdio: ["pipe", "pipe", "pipe"],
    });
    let stderr = "";
    child.stderr.setEncoding("utf8");
    child.stderr.on("data", (chunk) => { stderr += chunk; });
    child.once("error", reject);
    child.once("close", (code, signal) => {
      if (code === 0) resolve();
      else reject(new Error(`hook exited code=${code} signal=${signal || "none"}: ${stderr}`));
    });
    child.stdin.end(JSON.stringify(payload));
  });
}

function runInstaller(box, ...args) {
  return JSON.parse(execFileSync("bash", [hooksInstaller, ...args], {
    cwd: path.resolve(pluginDir, "..", "..", ".."),
    env: { ...process.env, HOME: box.home },
    encoding: "utf8",
    timeout: 5000,
  }));
}

async function waitFor(predicate, timeoutMs = 3000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  assert.fail(`condition not met within ${timeoutMs}ms`);
}

test("SessionStart emits valid Codex JSON when the session lock is occupied", () => {
  const box = sandbox();
  try {
    const payload = { session_id: "contended-session", cwd: box.cwd };
    const first = JSON.parse(runHook(box, "start", payload));
    assert.equal(first.hookSpecificOutput.hookEventName, "SessionStart");

    const stateFile = fs.readdirSync(box.state).find((name) => name.endsWith(".json"));
    assert.ok(stateFile);
    const statePath = path.join(box.state, stateFile);
    const before = fs.readFileSync(statePath, "utf8");
    const lockPath = path.join(box.state, stateFile.replace(/\.json$/, ".lock"));
    fs.writeFileSync(lockPath, JSON.stringify({ schema_version: 1, owner: "test", pid: process.pid, created_at_ms: Date.now() }));

    const started = Date.now();
    const output = runHook(box, "start", payload, { CANUTO_HOOK_LOCK_TIMEOUT_MS: "30" });
    const elapsed = Date.now() - started;
    const parsed = JSON.parse(output);
    assert.equal(parsed.hookSpecificOutput.hookEventName, "SessionStart");
    assert.match(parsed.additionalContext, /session state is busy/);
    assert.ok(elapsed < 1000, `contended hook took ${elapsed}ms`);
    assert.equal(fs.readFileSync(statePath, "utf8"), before);
    assert.ok(fs.existsSync(lockPath));
  } finally {
    fs.rmSync(box.root, { recursive: true, force: true });
  }
});

test("concurrent apply_patch tracking keeps atomic JSON state", async () => {
  const box = sandbox();
  try {
    const calls = Array.from({ length: 8 }, (_, index) => runHookAsync(box, "posttool", {
        session_id: "parallel-session",
        cwd: box.cwd,
        tool_name: "apply_patch",
        tool_use_id: `patch-${index}`,
        tool_input: { patch: `*** patch ${index}` },
        tool_response: { success: true },
      }, { CANUTO_HOOK_LOCK_TIMEOUT_MS: "2000" }));
    await Promise.all(calls);
    const stateFile = fs.readdirSync(box.state).find((name) => name.endsWith(".json"));
    const state = JSON.parse(fs.readFileSync(path.join(box.state, stateFile), "utf8"));
    assert.equal(state.editSeen, true);
    assert.equal(state.processedEvents.length, 8);
    assert.equal(new Set(state.processedEvents).size, 8);
    assert.equal(fs.readdirSync(box.state).some((name) => name.endsWith(".tmp")), false);
  } finally {
    fs.rmSync(box.root, { recursive: true, force: true });
  }
});

test("the same session id is isolated by canonical repository, worktree, and cwd", () => {
  const box = sandbox();
  try {
    const repoA = path.join(box.root, "repo-a");
    const repoB = path.join(box.root, "repo-b");
    for (const repo of [repoA, repoB]) {
      fs.mkdirSync(repo);
      execFileSync("git", ["init", "-q", repo]);
      runHook(box, "posttool", {
        session_id: "shared-session",
        cwd: repo,
        tool_name: "apply_patch",
        tool_use_id: `edit-${path.basename(repo)}`,
        tool_response: { success: true },
      });
    }
    const stateFiles = fs.readdirSync(box.state).filter((name) => name.endsWith(".json"));
    assert.equal(stateFiles.length, 2);
    const states = stateFiles.map((name) => JSON.parse(fs.readFileSync(path.join(box.state, name), "utf8")));
    assert.deepEqual(new Set(states.map((state) => state.cwd)), new Set([fs.realpathSync(repoA), fs.realpathSync(repoB)]));
    assert.equal(new Set(states.map((state) => state.repository)).size, 2);
    assert.equal(states.every((state) => state.worktree === state.cwd), true);
  } finally {
    fs.rmSync(box.root, { recursive: true, force: true });
  }
});

test("project inference recognizes an arbitrarily named Canuto worktree by origin", () => {
  const box = sandbox();
  try {
    const checkout = path.join(box.root, "canuto-hooks-orchestration", "work", "t8-canuto-integration");
    fs.mkdirSync(checkout, { recursive: true });
    execFileSync("git", ["init", "-q", checkout]);
    execFileSync("git", ["-C", checkout, "remote", "add", "origin", "git@github.com:csorodrigo/canuto-framework.git"]);
    for (const project of ["canuto", "canuto-framework", "canuto-hooks-orchestration"]) {
      fs.mkdirSync(path.join(box.home, ".canuto", "vault", "projects", project), { recursive: true });
    }

    runHook(box, "start", { session_id: "t8-project", cwd: checkout });
    const stateFile = fs.readdirSync(box.state).find((name) => name.endsWith(".json"));
    const state = JSON.parse(fs.readFileSync(path.join(box.state, stateFile), "utf8"));
    assert.equal(state.project, "canuto-framework");
    assert.equal(state.cwd, fs.realpathSync(checkout));
  } finally {
    fs.rmSync(box.root, { recursive: true, force: true });
  }
});

test("SessionEnd persists a durable job and starts its worker below the three-second clamp", async () => {
  const box = sandbox();
  try {
    const marker = path.join(box.root, "worker-started.log");
    const fakeCanuto = path.join(box.root, "fake-canuto.mjs");
    fs.writeFileSync(fakeCanuto, [
      'import fs from "node:fs";',
      'fs.appendFileSync(process.env.CANUTO_HOOK_WORKER_MARKER, `${process.argv.slice(2).join(" ")}\\n`);',
      'await new Promise((resolve) => setTimeout(resolve, 250));',
    ].join("\n"));
    const overrides = { CANUTO_HOOK_CANUTO: fakeCanuto, CANUTO_HOOK_WORKER_MARKER: marker };

    const started = Date.now();
    runHook(box, "end", { session_id: "fast-end", cwd: box.cwd }, overrides);
    const elapsed = Date.now() - started;
    assert.ok(elapsed < 1500, `SessionEnd hook took ${elapsed}ms`);

    const queue = path.join(box.root, "closeout-queue");
    assert.ok(fs.readdirSync(queue).some((name) => /\.(pending|running|done)\.json$/.test(name)));
    await waitFor(() => fs.existsSync(marker));
    assert.match(fs.readFileSync(marker, "utf8"), /closeout --auto --session/);
    await waitFor(() => fs.readdirSync(queue).some((name) => name.endsWith(".done.json")));
    assert.match(fs.readFileSync(path.join(box.home, ".codex", "log", "canuto-hooks.log"), "utf8"), /closeout_worker_started/);
  } finally {
    fs.rmSync(box.root, { recursive: true, force: true });
  }
});

test("Codex Canuto plugin is opt-in, preserves external hooks, and disables without orphans", () => {
  const box = sandbox();
  try {
    const config = path.join(box.home, ".codex", "hooks.json");
    const hooksDir = path.join(box.home, ".codex", "hooks");
    const batches = path.join(box.home, ".canuto", "plugin-batches");
    fs.mkdirSync(path.dirname(config), { recursive: true });
    fs.writeFileSync(config, `${JSON.stringify({
      hooks: {
        PreToolUse: [{ matcher: "External", hooks: [{ type: "command", command: "/opt/external/hook", timeout: 9, env: { KEEP: "yes" } }] }],
        SessionStart: [{ matcher: "", hooks: [{ type: "command", command: `node ${path.join(box.home, ".codex", "hooks", "canuto_hook.mjs")} start`, timeout: 45 }] }],
        PostToolUse: [{ matcher: "", hooks: [
          { type: "command", command: `node ${path.join(box.home, ".codex", "hooks", "canuto_hook.mjs")} posttool`, timeout: 3 },
          { type: "command", command: `node ${path.join(box.home, ".codex", "hooks", "canuto_hook.mjs")} pretool`, timeout: 3 },
        ] }],
        SessionEnd: [{ matcher: "", hooks: [{ type: "command", command: `node ${path.join(box.home, ".codex", "hooks", "canuto_hook.mjs")} end`, timeout: 70 }] }],
      },
    }, null, 2)}\n`);

    const metadata = JSON.parse(fs.readFileSync(path.join(pluginDir, "plugin.json"), "utf8"));
    assert.equal(metadata.defaultEnabled, false);
    assert.equal(fs.existsSync(hooksDir), false);

    const plan = runInstaller(box, "--plan-codex-canuto-plugin", config, hooksDir);
    assert.equal(plan.changed, true);
    assert.deepEqual(plan.entries.map((entry) => entry.action), ["add", "add", "add", "add"]);
    assert.equal(plan.legacyEntries.length, 4);
    assert.equal(plan.legacyEntries.every((entry) => entry.action === "remove"), true);
    const declaredTimeouts = Object.fromEntries(plan.nextConfig.hooks
      ? Object.entries(plan.nextConfig.hooks).flatMap(([event, groups]) => groups
        .flatMap((group) => group.hooks
          .filter((hook) => hook.command.startsWith("~/.codex/hooks/canuto-"))
          .map((hook) => [event, hook.timeout])))
      : []);
    assert.deepEqual(declaredTimeouts, {
      SessionStart: 45,
      PreToolUse: 30,
      PostToolUse: 3,
      SessionEnd: 3,
    });
    const applied = runInstaller(box, "--apply-codex-canuto-plugin", plan.fingerprint, config, hooksDir, batches);
    const receipt = JSON.parse(fs.readFileSync(applied.receiptPath, "utf8"));
    assert.equal(receipt.status, "applied");
    assert.equal(receipt.legacyEntries.length, 4);
    const verified = runInstaller(box, "--verify-codex-canuto-plugin", config, hooksDir);
    assert.equal(verified.ok, true);

    const enabledConfig = JSON.parse(fs.readFileSync(config, "utf8"));
    const commands = Object.values(enabledConfig.hooks).flatMap((groups) => groups.flatMap((group) => group.hooks.map((hook) => hook.command)));
    assert.equal(commands.filter((command) => command.startsWith("~/.codex/hooks/canuto-")).length, 4);
    assert.equal(commands.some((command) => command.includes("canuto_hook.mjs")), false);
    assert.equal(enabledConfig.hooks.PreToolUse[0].hooks[0].env.KEEP, "yes");
    for (const filename of ["canuto-session-start.mjs", "canuto-pretool.mjs", "canuto-posttool.mjs", "canuto-session-end.mjs"]) {
      assert.ok(fs.existsSync(path.join(hooksDir, filename)));
    }
    const installedStart = execFileSync(path.join(hooksDir, "canuto-session-start.mjs"), [], {
      cwd: box.cwd,
      env: hookEnv(box),
      input: JSON.stringify({ session_id: "installed-start", cwd: box.cwd }),
      encoding: "utf8",
      timeout: 5000,
    });
    assert.equal(JSON.parse(installedStart).hookSpecificOutput.hookEventName, "SessionStart");

    const disablePlan = runInstaller(box, "--plan-disable-codex-canuto-plugin", config, hooksDir);
    assert.equal(disablePlan.changed, true);
    runInstaller(box, "--apply-disable-codex-canuto-plugin", disablePlan.fingerprint, config, hooksDir, batches);
    const disabled = runInstaller(box, "--verify-disable-codex-canuto-plugin", config, hooksDir);
    assert.equal(disabled.ok, true);

    const disabledConfig = JSON.parse(fs.readFileSync(config, "utf8"));
    const remaining = Object.values(disabledConfig.hooks).flatMap((groups) => groups.flatMap((group) => group.hooks.map((hook) => hook.command)));
    assert.deepEqual(remaining, ["/opt/external/hook"]);
    assert.equal(fs.readdirSync(hooksDir).length, 0);
  } finally {
    fs.rmSync(box.root, { recursive: true, force: true });
  }
});
