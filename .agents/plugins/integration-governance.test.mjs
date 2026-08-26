import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

const pluginsDir = path.dirname(new URL(import.meta.url).pathname);
const repoRoot = path.resolve(pluginsDir, "..", "..");
const installer = path.join(repoRoot, ".agents", "hooks", "install.sh");

function sandbox() {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "canuto-t8-plugin-"));
  const home = path.join(root, "home");
  const config = path.join(home, ".claude", "settings.json");
  const hooksDir = path.join(home, ".claude", "hooks");
  const codexConfig = path.join(home, ".codex", "hooks.json");
  const codexHooksDir = path.join(home, ".codex", "hooks");
  const state = path.join(home, ".canuto", "plugin-batches");
  fs.mkdirSync(path.dirname(config), { recursive: true });
  fs.mkdirSync(path.dirname(codexConfig), { recursive: true });
  return { root, home, config, hooksDir, codexConfig, codexHooksDir, state };
}

function run(args, box) {
  return JSON.parse(execFileSync("bash", [installer, ...args], {
    cwd: repoRoot,
    env: { ...process.env, HOME: box.home },
    encoding: "utf8",
    timeout: 10000,
  }));
}

function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, `${JSON.stringify(value, null, 2)}\n`);
}

function commandsIn(file) {
  const json = JSON.parse(fs.readFileSync(file, "utf8"));
  return Object.values(json.hooks ?? {}).flatMap((groups) =>
    groups.flatMap((group) => (group.hooks ?? []).map((hook) => hook.command))
  );
}

function assertManagedLifecycle({ plugin, surface, configKey, hooksKey, legacyConfig, expectedPrefix, expectedLegacyRetireIds }) {
  const box = sandbox();
  try {
    writeJson(box[configKey], legacyConfig);
    const initialDisable = run(["--plan-disable-plugin", plugin, surface, box[configKey], box[hooksKey]], box);
    assert.equal(initialDisable.changed, true, `${plugin}/${surface} disabled plan must retire legacy registrations before enable`);
    const initialRemovals = initialDisable.entries.filter((entry) => entry.action === "remove").map((entry) => entry.id).sort();
    assert.deepEqual(initialRemovals, expectedLegacyRetireIds.slice().sort());
    assert.deepEqual(initialDisable.files.filter((entry) => entry.action !== "preserve"), []);
    run(["--apply-disable-plugin", plugin, surface, initialDisable.fingerprint, box[configKey], box[hooksKey], box.state], box);
    assert.equal(run(["--verify-disable-plugin", plugin, surface, box[configKey], box[hooksKey]], box).ok, true);
    assert.deepEqual(commandsIn(box[configKey]), ["/opt/external/hook"]);
    assert.equal(fs.existsSync(box[hooksKey]), false);

    writeJson(box[configKey], legacyConfig);
    const plan = run(["--plan-plugin", plugin, surface, box[configKey], box[hooksKey]], box);
    assert.equal(plan.changed, true, `${plugin}/${surface} enable should change sandbox`);
    assert.equal(plan.external.action, "preserve");
    assert.ok(plan.entries.some((entry) => entry.action === "add"));
    const activeCommands = Object.values(plan.nextConfig.hooks ?? {}).flatMap((groups) =>
      groups.flatMap((group) => group.hooks.map((hook) => hook.command))
    );
    assert.ok(activeCommands.some((command) => command.startsWith(expectedPrefix)));

    const applied = run(["--apply-plugin", plugin, surface, plan.fingerprint, box[configKey], box[hooksKey], box.state], box);
    assert.equal(applied.applied, true);
    assert.equal(run(["--verify-plugin", plugin, surface, box[configKey], box[hooksKey]], box).ok, true);

    const disablePlan = run(["--plan-disable-plugin", plugin, surface, box[configKey], box[hooksKey]], box);
    assert.equal(disablePlan.changed, true, `${plugin}/${surface} disable should remove owned handlers`);
    run(["--apply-disable-plugin", plugin, surface, disablePlan.fingerprint, box[configKey], box[hooksKey], box.state], box);
    assert.equal(run(["--verify-disable-plugin", plugin, surface, box[configKey], box[hooksKey]], box).ok, true);

    const remaining = commandsIn(box[configKey]);
    assert.deepEqual(remaining, ["/opt/external/hook"]);
    assert.equal(fs.existsSync(box[hooksKey]) ? fs.readdirSync(box[hooksKey]).length : 0, 0);
  } finally {
    fs.rmSync(box.root, { recursive: true, force: true });
  }
}

function assertExternalRetirementPlugin({ plugin, fixtureFile, expectedIds }) {
  const verifyBox = sandbox();
  try {
    writeJson(verifyBox.config, JSON.parse(fs.readFileSync(path.join(pluginsDir, plugin, "fixtures", fixtureFile), "utf8")));
    const verifyPlan = run(["--plan-plugin", plugin, "claude", verifyBox.config, verifyBox.hooksDir], verifyBox);
    assert.equal(verifyPlan.changed, false, `${plugin} enabled flow should verify external owner registrations without writes`);
    assert.deepEqual(verifyPlan.entries, expectedIds.map((id) => ({ id, action: "preserve" })));
    assert.deepEqual(verifyPlan.files, []);
    assert.equal(run(["--verify-plugin", plugin, "claude", verifyBox.config, verifyBox.hooksDir], verifyBox).ok, true);
    assert.equal(fs.existsSync(verifyBox.hooksDir), false);
  } finally {
    fs.rmSync(verifyBox.root, { recursive: true, force: true });
  }

  const disableBox = sandbox();
  try {
    writeJson(disableBox.config, JSON.parse(fs.readFileSync(path.join(pluginsDir, plugin, "fixtures", fixtureFile), "utf8")));
    const disablePlan = run(["--plan-disable-plugin", plugin, "claude", disableBox.config, disableBox.hooksDir], disableBox);
    assert.equal(disablePlan.changed, true, `${plugin} disabled flow should retire owner-plugin registrations from host config`);
    assert.deepEqual(disablePlan.entries.filter((entry) => entry.action === "remove").map((entry) => entry.id).sort(), expectedIds.slice().sort());
    assert.deepEqual(disablePlan.files, []);
    assert.equal(disablePlan.external.action, "preserve");
    assert.equal(disablePlan.external.count, 1);
    run(["--apply-disable-plugin", plugin, "claude", disablePlan.fingerprint, disableBox.config, disableBox.hooksDir, disableBox.state], disableBox);
    assert.equal(run(["--verify-disable-plugin", plugin, "claude", disableBox.config, disableBox.hooksDir], disableBox).ok, true);
    assert.deepEqual(commandsIn(disableBox.config), ["/opt/external/hook"]);
    assert.equal(fs.existsSync(disableBox.hooksDir), false);
  } finally {
    fs.rmSync(disableBox.root, { recursive: true, force: true });
  }
}

test("managed T8 plugins are opt-in and disable without orphan handlers", () => {
  assertManagedLifecycle({
    plugin: "canuto",
    surface: "claude",
    configKey: "config",
    hooksKey: "hooksDir",
    expectedPrefix: "~/.claude/hooks/canuto-",
    legacyConfig: {
      hooks: {
        Stop: [{ matcher: "", hooks: [
          { type: "command", command: "~/.claude/hooks/session-save.sh", timeout: 30 },
          { type: "command", command: "/opt/external/hook" },
        ] }],
        Notification: [{ matcher: "", hooks: [{ type: "command", command: "~/.claude/hooks/pre-compact-save.sh", timeout: 15 }] }],
        SessionStart: [
          { matcher: "", hooks: [{ type: "command", command: "~/.claude/hooks/session-start.sh", timeout: 5 }] },
          { matcher: "compact", hooks: [{ type: "command", command: "~/.claude/hooks/post-compact-reread.sh", timeout: 8 }] },
        ],
      },
    },
    expectedLegacyRetireIds: ["CU-38", "CU-43", "CU-45", "CU-49"],
  });

  assertManagedLifecycle({
    plugin: "browser-qa",
    surface: "claude",
    configKey: "config",
    hooksKey: "hooksDir",
    expectedPrefix: "~/.claude/hooks/browser-qa-",
    legacyConfig: {
      hooks: {
        PreToolUse: [
          { matcher: "External", hooks: [{ type: "command", command: "/opt/external/hook" }] },
          { matcher: "mcp__playwright__browser_take_screenshot|mcp__claude-in-chrome__computer", hooks: [{ type: "command", command: "~/.claude/hooks/screenshot-guard.sh", timeout: 3 }] },
        ],
      },
    },
    expectedLegacyRetireIds: ["CU-32"],
  });

  assertManagedLifecycle({
    plugin: "obsidian",
    surface: "claude",
    configKey: "config",
    hooksKey: "hooksDir",
    expectedPrefix: "~/.claude/hooks/obsidian-",
    legacyConfig: {
      hooks: {
        SessionStart: [{ matcher: "startup|resume|clear|compact", hooks: [
          { type: "command", command: "~/.codex/hooks/obsidian_mcp_cleanup.sh", timeout: 10 },
          { type: "command", command: "/opt/external/hook" },
        ] }],
      },
    },
    expectedLegacyRetireIds: ["CU-48"],
  });

  assertManagedLifecycle({
    plugin: "obsidian",
    surface: "codex",
    configKey: "codexConfig",
    hooksKey: "codexHooksDir",
    expectedPrefix: "~/.codex/hooks/obsidian-",
    legacyConfig: {
      hooks: {
        SessionEnd: [{ matcher: "", hooks: [
          { type: "command", command: "~/.codex/hooks/obsidian_mcp_cleanup.sh", timeout: 3 },
          { type: "command", command: "/opt/external/hook" },
        ] }],
      },
    },
    expectedLegacyRetireIds: ["CX-16"],
  });
});

test("external Vercel and Codex Companion receipts are accepted by plugin retirement flow", () => {
  assertExternalRetirementPlugin({
    plugin: "vercel",
    fixtureFile: "plugin-hooks-settings.json",
    expectedIds: ["PV-01", "PV-02", "PV-03", "PV-04"],
  });

  assertExternalRetirementPlugin({
    plugin: "codex-companion",
    fixtureFile: "plugin-hooks-settings.json",
    expectedIds: ["PC-01", "PC-02", "PC-03"],
  });
});

test("browser QA screenshot state is isolated by session id and repository identity", () => {
  const box = sandbox();
  const tmp = path.join(box.root, "tmp");
  fs.mkdirSync(tmp);
  const repoA = path.join(box.root, "repo-a");
  const repoB = path.join(box.root, "repo-b");
  fs.mkdirSync(repoA);
  fs.mkdirSync(repoB);
  execFileSync("git", ["init", "-q"], { cwd: repoA });
  execFileSync("git", ["init", "-q"], { cwd: repoB });
  const hook = path.join(pluginsDir, "browser-qa", "hooks", "screenshot-guard.sh");
  const input = (session_id, cwd) => JSON.stringify({ session_id, cwd, tool_name: "mcp__playwright__browser_take_screenshot" });
  const env = { ...process.env, TMPDIR: tmp, CANUTO_SCREENSHOT_LIMIT: "1" };
  execFileSync("bash", [hook], { input: input("same-session", repoA), env, cwd: repoA });
  execFileSync("bash", [hook], { input: input("same-session", repoB), env, cwd: repoB });
  assert.throws(() => execFileSync("bash", [hook], { input: input("same-session", repoA), env, cwd: repoA }), /screenshot-guard/);
  const countFiles = fs.readdirSync(tmp).filter((name) => name.startsWith("canuto-screenshot-count-")).sort();
  assert.equal(countFiles.length, 2);
  assert.deepEqual(countFiles.map((name) => fs.readFileSync(path.join(tmp, name), "utf8").trim()), ["1", "1"]);
  fs.rmSync(box.root, { recursive: true, force: true });
});

test("Obsidian cleanup wrapper runs only when the plugin is active", () => {
  const box = sandbox();
  try {
    const marker = path.join(box.root, "guard.log");
    const guard = path.join(box.root, "obsidian-mcp-guard");
    fs.writeFileSync(guard, `#!/usr/bin/env bash\nprintf '%s\\n' "$*" >> "${marker}"\n`);
    fs.chmodSync(guard, 0o755);
    const hook = path.join(pluginsDir, "obsidian", "hooks", "obsidian-mcp-cleanup.sh");
    execFileSync("bash", [hook], { env: { ...process.env, HOME: box.home, CANUTO_OBSIDIAN_MCP_GUARD: guard } });
    assert.equal(fs.existsSync(marker), false);
    execFileSync("bash", [hook], { env: { ...process.env, HOME: box.home, CANUTO_OBSIDIAN_PLUGIN_ACTIVE: "1", CANUTO_OBSIDIAN_MCP_GUARD: guard } });
    assert.equal(fs.readFileSync(marker, "utf8").trim(), "--cleanup-only");
  } finally {
    fs.rmSync(box.root, { recursive: true, force: true });
  }
});

test("external plugin contracts keep ownership outside Canuto and declare T8 risks", () => {
  const receipts = JSON.parse(fs.readFileSync(path.join(repoRoot, ".agents", "hooks", "audit", "plugin-source-receipts.json"), "utf8"));
  const gstack = JSON.parse(fs.readFileSync(path.join(pluginsDir, "gstack", "contracts", "gstack-hooks.contract.json"), "utf8"));
  const herdr = JSON.parse(fs.readFileSync(path.join(pluginsDir, "herdr", "contracts", "herdr-agent-state.contract.json"), "utf8"));
  const vercel = JSON.parse(fs.readFileSync(path.join(pluginsDir, "vercel", "contracts", "vercel-hooks.contract.json"), "utf8"));
  const companion = JSON.parse(fs.readFileSync(path.join(pluginsDir, "codex-companion", "contracts", "codex-companion-hooks.contract.json"), "utf8"));

  assert.deepEqual(gstack.hooks.map((hook) => hook.id).sort(), ["CU-11", "CU-12", "CU-35", "CU-42"]);
  assert.equal(gstack.sourceReceipt.status, "owner-ready");
  assert.equal(gstack.sourceReceipt.commitSha, "ad8400543cd9ce8d07641362db48d44a95417e33");
  assert.equal(gstack.sourceReceipt.retirementState, "owner-ready-via-gstack-settings-hook");
  assert.equal(gstack.sourceReceipt.ownerPathSha256["~/.claude/skills/gstack/bin/gstack-settings-hook"], "87407502b1411213e009d7bb40c9800cb88c91a1e0f0dc1fbd42dcddd985bb1c");
  assert.deepEqual(herdr.activation.requiredEnv, ["HERDR_ENV=1", "HERDR_SOCKET_PATH", "HERDR_PANE_ID"]);
  assert.equal(herdr.payload.network, "unix-socket-only");
  assert.equal(herdr.registration.ownerProfileSha256, "78188468602c3e6d0de6f650d7f6e3a9f7108535c2323716b91e24fd2d507975");
  assert.equal(herdr.retirementState, "global-retirement-only-owner-profile-ready");

  assert.deepEqual(vercel.hooks.map((hook) => hook.id), ["PV-01", "PV-02", "PV-03", "PV-04"]);
  assert.equal(vercel.reconcileFlow.kind, "external-owner-retirement-only");
  assert.equal(vercel.reconcileFlow.ownerHookConfigSha256, receipts.plugins["vercel@0.45.1"].hookConfig.sha256);
  assert.equal(vercel.network.allowed, true);
  assert.ok(vercel.network.declaredUses.includes("telemetry.vercel.com"));
  assert.ok(vercel.telemetry.payloadExclusions.includes("prompt text"));
  assert.equal(receipts.plugins["vercel@0.45.1"].artifacts["hooks/session-start-profiler.mjs"], "1537565338358a9f6fb7a0022a5840e44264288cd3397fa3db7fd5ada5813bd7");
  assert.equal(vercel.observedOwnerReceipt.hookConfigSha256, vercel.reconcileFlow.ownerHookConfigSha256);
  assert.equal(vercel.observedOwnerReceipt.artifacts["hooks/session-start-profiler.mjs"], "215e6502c4e8fc6edf683e13939ecdee096b1d4e27be29b12599e059693d9416");
  assert.equal(vercel.observedOwnerReceipt.artifacts["hooks/session-end-cleanup.mjs"], "1db52d969130cbcb954cad129eb06dbe4a89ed636b51bad6ba6b33a22ec80a0a");

  assert.deepEqual(companion.hooks.map((hook) => hook.id), ["PC-01", "PC-02", "PC-03"]);
  assert.equal(companion.reconcileFlow.kind, "external-owner-retirement-only");
  assert.equal(companion.reconcileFlow.ownerHookConfigSha256, receipts.plugins["codex-companion@1.0.5"].hookConfig.sha256);
  assert.equal(companion.defaultConfig.stopReviewGate, false);
  assert.equal(companion.stopReviewGate.default, false);
  assert.match(companion.stopReviewGate.enabledBehavior, /blocks/);
  assert.match(companion.stopReviewGate.errorBehavior, /blocks/);
  assert.match(companion.stopReviewGate.cleanup, /SessionEnd/);
  assert.equal(receipts.plugins["codex-companion@1.0.5"].artifacts["scripts/stop-review-gate-hook.mjs"], "caf98d78d995f98df5da3903690c20ab701b56240b6ca8b9fd10ef38bc9119fc");
});

test("Codex Companion owner Stop gate and SessionEnd cleanup are behaviorally fail-closed", { concurrency: false }, (t) => {
  if (process.env.CANUTO_RUN_EXTERNAL_CANARIES !== "1") {
    t.skip("set CANUTO_RUN_EXTERNAL_CANARIES=1 for the isolated external-owner canary");
    return;
  }
  const ownerRoot = path.join(os.homedir(), ".claude", "plugins", "cache", "openai-codex", "codex", "1.0.5");
  if (!fs.existsSync(path.join(ownerRoot, "scripts", "stop-review-gate-hook.mjs"))) {
    t.skip("external Codex Companion owner is not installed in this environment");
    return;
  }
  const canary = path.join(pluginsDir, "codex-companion", "behavior-canary.mjs");
  const result = JSON.parse(execFileSync(process.execPath, [canary], {
    cwd: repoRoot,
    env: { ...process.env, CODEX_COMPANION_OWNER_ROOT: ownerRoot },
    encoding: "utf8",
    timeout: 120000,
  }));
  assert.equal(result.stopHookSha256, "caf98d78d995f98df5da3903690c20ab701b56240b6ca8b9fd10ef38bc9119fc");
  assert.deepEqual(result.decisions, { allow: "allow", block: "block", error: "block", invalid: "block", timeout: "block" });
  assert.deepEqual(result.cleanup, { remainingJobs: 1, sameWorkspaceBrokerRemoved: true, foreignBrokerPreserved: true });
});

test("Herdr retirement-only manifest removes only the global legacy hook", () => {
  const box = sandbox();
  try {
    const fixture = JSON.parse(fs.readFileSync(path.join(pluginsDir, "herdr", "fixtures", "legacy-global-settings.json"), "utf8"));
    fixture.hooks.SessionStart[0].hooks[0].command = fixture.hooks.SessionStart[0].hooks[0].command.replace("/Users/rodrigooliveira", box.home);
    writeJson(box.config, fixture);

    const plan = run(["--plan-plugin", "herdr", "claude", box.config, box.hooksDir], box);
    assert.equal(plan.changed, true);
    assert.deepEqual(plan.entries, [{ id: "CU-50", action: "remove" }]);
    assert.deepEqual(plan.files, []);
    assert.equal(plan.external.action, "preserve");
    assert.equal(plan.external.count, 1);
    assert.deepEqual(Object.keys(plan.nextConfig.hooks), ["SessionStart"]);
    assert.deepEqual(plan.nextConfig.hooks.SessionStart[0].hooks, [{ type: "command", command: "/opt/external/hook", timeout: 7 }]);

    run(["--apply-plugin", "herdr", "claude", plan.fingerprint, box.config, box.hooksDir, box.state], box);
    assert.equal(run(["--verify-plugin", "herdr", "claude", box.config, box.hooksDir], box).ok, true);
    assert.equal(run(["--plan-disable-plugin", "herdr", "claude", box.config, box.hooksDir], box).changed, false);
    assert.deepEqual(commandsIn(box.config), ["/opt/external/hook"]);
    assert.equal(fs.existsSync(box.hooksDir), false);
  } finally {
    fs.rmSync(box.root, { recursive: true, force: true });
  }
});

test("Herdr disabled retirement removes global legacy hook without touching owner profile", () => {
  const box = sandbox();
  try {
    const fixture = JSON.parse(fs.readFileSync(path.join(pluginsDir, "herdr", "fixtures", "legacy-global-settings.json"), "utf8"));
    fixture.hooks.SessionStart[0].hooks[0].command = fixture.hooks.SessionStart[0].hooks[0].command.replace("/Users/rodrigooliveira", box.home);
    writeJson(box.config, fixture);

    const ownerProfile = path.join(box.home, ".config", "herdr", "agent-routes", "profiles", "claude", "settings.json");
    writeJson(ownerProfile, { hooks: { SessionStart: [{ matcher: "*", hooks: [{ type: "command", command: "profile-owned" }] }] } });
    const beforeProfile = fs.readFileSync(ownerProfile, "utf8");

    const disablePlan = run(["--plan-disable-plugin", "herdr", "claude", box.config, box.hooksDir], box);
    assert.equal(disablePlan.changed, true);
    assert.deepEqual(disablePlan.entries, [{ id: "CU-50", action: "remove" }]);
    assert.deepEqual(disablePlan.files, []);
    run(["--apply-disable-plugin", "herdr", "claude", disablePlan.fingerprint, box.config, box.hooksDir, box.state], box);

    assert.equal(run(["--verify-disable-plugin", "herdr", "claude", box.config, box.hooksDir], box).ok, true);
    assert.deepEqual(commandsIn(box.config), ["/opt/external/hook"]);
    assert.equal(fs.readFileSync(ownerProfile, "utf8"), beforeProfile);
    assert.equal(fs.existsSync(box.hooksDir), false);
  } finally {
    fs.rmSync(box.root, { recursive: true, force: true });
  }
});

test("core hook registry no longer owns T8 plugin handlers", () => {
  const coreManifest = JSON.parse(fs.readFileSync(path.join(repoRoot, ".agents", "hooks", "managed-hooks.json"), "utf8"));
  const ids = new Set(coreManifest.entries.map((entry) => entry.id));
  for (const moved of ["CU-32", "CU-38", "CU-43", "CU-45"]) assert.equal(ids.has(moved), false, `${moved} must not stay core-owned`);

  const settingsSnippet = fs.readFileSync(path.join(repoRoot, ".agents", "hooks", "settings-snippet.json"), "utf8");
  for (const command of ["screenshot-guard.sh", "session-save.sh", "pre-compact-save.sh", "session-start.sh"]) {
    assert.equal(settingsSnippet.includes(`~/.claude/hooks/${command}`), false, `${command} must not be in core settings snippet`);
  }

  const installScript = fs.readFileSync(path.join(repoRoot, "install.sh"), "utf8");
  for (const command of [
    'install_hook ".agents/hooks/screenshot-guard.sh"',
    'install_hook ".agents/hooks/session-save.sh"',
    'install_hook ".agents/hooks/pre-compact-save.sh"',
    'install_hook ".agents/hooks/session-start.sh"',
  ]) {
    assert.equal(installScript.includes(command), false, `${command} must not be globally installed by core`);
  }
});
