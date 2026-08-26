#!/usr/bin/env node

import { createHash, randomUUID } from "node:crypto";
import { chmod, lstat, mkdir, readFile, rename, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { buildPlan, rollbackBatch } from "../../hooks/reconcile-hooks.mjs";

const LEGACY_MODES = new Set(["start", "pretool", "posttool", "end"]);
const MANAGED_COMMANDS = new Set([
  "~/.codex/hooks/canuto-session-start.mjs",
  "~/.codex/hooks/canuto-pretool.mjs",
  "~/.codex/hooks/canuto-posttool.mjs",
  "~/.codex/hooks/canuto-session-end.mjs",
]);

function fail(message) {
  throw new Error(message);
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function canonical(value) {
  if (Array.isArray(value)) return `[${value.map(canonical).join(",")}]`;
  if (value && typeof value === "object") {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`).join(",")}}`;
  }
  return JSON.stringify(value);
}

async function pathState(pathname) {
  try {
    const info = await lstat(pathname);
    if (info.isSymbolicLink()) fail(`refusing symbolic link: ${pathname}`);
    if (!info.isFile()) fail(`expected regular file: ${pathname}`);
    const bytes = await readFile(pathname);
    return { exists: true, hash: sha256(bytes), mode: info.mode & 0o777, bytes };
  } catch (error) {
    if (error?.code === "ENOENT") return { exists: false, hash: null, mode: null, bytes: null };
    throw error;
  }
}

async function atomicWrite(pathname, bytes, mode) {
  await mkdir(path.dirname(pathname), { recursive: true });
  const temporary = path.join(path.dirname(pathname), `.${path.basename(pathname)}.canuto-${process.pid}-${randomUUID()}.tmp`);
  try {
    await writeFile(temporary, bytes, { mode });
    await chmod(temporary, mode);
    await rename(temporary, pathname);
  } catch (error) {
    await rm(temporary, { force: true }).catch(() => {});
    throw error;
  }
}

function parseLegacyCommand(command, homeDir) {
  if (typeof command !== "string") return "";
  const match = command.match(/^node\s+(?:"([^"]+)"|'([^']+)'|(\S+))\s+(start|pretool|posttool|end)$/);
  if (!match || !LEGACY_MODES.has(match[4])) return "";
  const executable = match[1] || match[2] || match[3];
  const expected = path.join(homeDir, ".codex", "hooks", "canuto_hook.mjs");
  const expanded = executable === "~/.codex/hooks/canuto_hook.mjs" ? expected : executable;
  return path.resolve(expanded) === path.resolve(expected) ? match[4] : "";
}

function removeLegacyHooks(config, homeDir) {
  const next = structuredClone(config);
  const removed = [];
  for (const [event, groups] of Object.entries(next.hooks || {})) {
    if (!Array.isArray(groups)) continue;
    next.hooks[event] = groups.flatMap((group, groupIndex) => {
      if (!Array.isArray(group?.hooks)) return [group];
      const hooks = group.hooks.filter((hook, hookIndex) => {
        const mode = hook?.type === "command" ? parseLegacyCommand(hook.command, homeDir) : "";
        if (!mode) return true;
        removed.push({
          id: `CX-CANUTO-LEGACY-${mode.toUpperCase()}-${removed.length + 1}`,
          action: "remove",
          event,
          matcher: group.matcher ?? "",
          command: hook.command,
          groupIndex,
          hookIndex,
        });
        return false;
      });
      if (hooks.length === 0 && group.hooks.length > 0 && Object.keys(group).every((key) => ["matcher", "hooks"].includes(key))) return [];
      return [{ ...group, hooks }];
    });
  }
  return { nextConfig: next, removed };
}

function renderedConfig(config) {
  return Buffer.from(`${JSON.stringify(config, null, 2)}\n`);
}

function externalEntries(config) {
  const entries = [];
  for (const groups of Object.values(config.hooks || {})) {
    if (!Array.isArray(groups)) continue;
    for (const group of groups) {
      if (!Array.isArray(group?.hooks)) continue;
      for (const hook of group.hooks) {
        if (!MANAGED_COMMANDS.has(hook?.command)) entries.push(canonical(hook));
      }
    }
  }
  return entries;
}

export async function buildPluginPlan(options) {
  const requestedHome = options.homeDir || process.env.HOME;
  if (!requestedHome) fail("a concrete home directory is required");
  const homeDir = path.resolve(requestedHome);
  if (homeDir === path.parse(homeDir).root) fail("a concrete home directory is required");
  const base = await buildPlan({ ...options, homeDir });
  const migration = removeLegacyHooks(base.nextConfig, homeDir);
  const configBytes = renderedConfig(migration.nextConfig);
  const external = externalEntries(migration.nextConfig);
  const fingerprint = sha256(Buffer.from(canonical({
    schemaVersion: 1,
    surface: base.surface,
    baseFingerprint: base.fingerprint,
    legacy: migration.removed,
    finalConfigHash: sha256(configBytes),
  })));
  return {
    ...base,
    fingerprint,
    reconcilerFingerprint: base.fingerprint,
    config: {
      ...base.config,
      afterHash: sha256(configBytes),
      action: base.config.beforeHash === sha256(configBytes) ? "preserve" : (base.config.beforeHash ? "update" : "add"),
    },
    legacyEntries: migration.removed,
    external: {
      action: "preserve",
      count: external.length,
      entryFingerprints: external.map((entry) => sha256(Buffer.from(entry))),
    },
    nextConfig: migration.nextConfig,
    changed: base.files.some((file) => file.action !== "preserve")
      || base.entries.some((entry) => entry.action !== "preserve")
      || migration.removed.length > 0
      || base.config.beforeHash !== sha256(configBytes),
  };
}

export async function verifyPluginState(options) {
  try {
    const plan = await buildPluginPlan(options);
    const errors = [];
    for (const entry of plan.entries) if (entry.action !== "preserve") errors.push(`entry ${entry.id} requires ${entry.action}`);
    for (const entry of plan.legacyEntries) errors.push(`legacy entry ${entry.id} requires remove`);
    for (const file of plan.files) if (file.action !== "preserve") errors.push(`file ${file.target} requires ${file.action}`);
    if (plan.config.action !== "preserve") errors.push(`configuration requires ${plan.config.action}`);
    return { ok: errors.length === 0, fingerprint: plan.fingerprint, errors };
  } catch (error) {
    return { ok: false, fingerprint: null, errors: [error.message] };
  }
}

export async function applyPluginPlan(options) {
  const plan = await buildPluginPlan(options);
  if (plan.fingerprint !== options.fingerprint) fail("apply rejected: plan fingerprint mismatch or input drift");
  if (!plan.changed) return { applied: false, fingerprint: plan.fingerprint, reason: "already-converged" };

  const stateDir = path.resolve(options.stateDir);
  const batchId = `${new Date().toISOString().replace(/[-:.TZ]/g, "")}-${plan.fingerprint.slice(0, 12)}`;
  const batchDir = path.join(stateDir, "batches", batchId);
  const receiptPath = path.join(batchDir, "receipt.json");
  await mkdir(path.dirname(batchDir), { recursive: true, mode: 0o700 });
  await mkdir(batchDir, { recursive: false, mode: 0o700 });

  const configBefore = await pathState(plan.config.path);
  const configBackup = path.join(batchDir, "configuration.before");
  if (configBefore.exists) await atomicWrite(configBackup, configBefore.bytes, 0o600);
  const receipt = {
    schemaVersion: 1,
    batchId,
    fingerprint: plan.fingerprint,
    reconcilerFingerprint: plan.reconcilerFingerprint,
    status: "prepared",
    createdAt: new Date().toISOString(),
    entries: plan.entries,
    legacyEntries: plan.legacyEntries,
    config: {
      path: plan.config.path,
      beforeExists: configBefore.exists,
      beforeHash: configBefore.hash,
      beforeMode: configBefore.mode,
      afterHash: plan.config.afterHash,
      afterMode: configBefore.mode ?? 0o600,
      backupPath: configBefore.exists ? configBackup : null,
    },
    files: [],
  };

  for (const [index, file] of plan.files.filter((item) => item.action !== "preserve").entries()) {
    const before = await pathState(file.target);
    const backupPath = path.join(batchDir, `file-${index}.before`);
    if (before.exists) await atomicWrite(backupPath, before.bytes, 0o600);
    receipt.files.push({
      path: file.target,
      action: file.action,
      beforeExists: before.exists,
      beforeHash: before.hash,
      beforeMode: before.mode,
      afterHash: file.action === "remove" ? null : file.expectedHash,
      afterMode: file.action === "remove" ? null : Number.parseInt(file.mode, 8),
      backupPath: before.exists ? backupPath : null,
    });
  }
  await atomicWrite(receiptPath, renderedConfig(receipt), 0o600);

  try {
    for (const file of plan.files.filter((item) => item.action !== "preserve")) {
      if (file.action === "remove") await rm(file.target, { force: true });
      else await atomicWrite(file.target, await readFile(file.origin), Number.parseInt(file.mode, 8));
    }
    await atomicWrite(plan.config.path, renderedConfig(plan.nextConfig), configBefore.mode ?? 0o600);
    receipt.status = "applied";
    receipt.appliedAt = new Date().toISOString();
    await atomicWrite(receiptPath, renderedConfig(receipt), 0o600);
    const verified = await verifyPluginState(options);
    if (!verified.ok) fail(`post-apply verification failed: ${verified.errors.join("; ")}`);
    receipt.verification = { ok: true, stateFingerprint: verified.fingerprint, verifiedAt: new Date().toISOString() };
    await atomicWrite(receiptPath, renderedConfig(receipt), 0o600);
  } catch (error) {
    await rollbackBatch({ stateDir, batchId }).catch((rollbackError) => {
      error.message = `${error.message}; automatic rollback failed: ${rollbackError.message}`;
    });
    throw error;
  }
  return { applied: true, batchId, fingerprint: plan.fingerprint, receiptPath };
}

function parseCli(argv) {
  const [command, ...rest] = argv;
  const options = {};
  for (let index = 0; index < rest.length; index += 1) {
    const token = rest[index];
    if (!token.startsWith("--")) fail(`unexpected argument ${token}`);
    const key = token.slice(2).replace(/-([a-z])/g, (_, letter) => letter.toUpperCase());
    const value = rest[index + 1];
    if (!value || value.startsWith("--")) fail(`missing value for ${token}`);
    options[key] = value;
    index += 1;
  }
  if (options.manifest) options.manifestPath = options.manifest;
  if (options.config) options.configPath = options.config;
  return { command, options };
}

async function main() {
  const { command, options } = parseCli(process.argv.slice(2));
  if (!command || !["plan", "apply", "verify", "rollback"].includes(command)) {
    fail("usage: codex-plugin-reconcile.mjs <plan|apply|verify|rollback> --manifest FILE --config FILE --hooks-dir DIR [--state-dir DIR] [--fingerprint HASH] [--batch-id ID]");
  }
  let result;
  if (command === "rollback") {
    if (!options.stateDir || !options.batchId) fail("rollback requires --state-dir and --batch-id");
    result = await rollbackBatch(options);
  } else {
    for (const required of ["manifestPath", "configPath", "hooksDir"]) if (!options[required]) fail(`${command} requires --${required.replace(/[A-Z]/g, (letter) => `-${letter.toLowerCase()}`)}`);
    if (command === "plan") result = await buildPluginPlan(options);
    if (command === "apply") {
      if (!options.stateDir || !options.fingerprint) fail("apply requires --state-dir and --fingerprint");
      result = await applyPluginPlan(options);
    }
    if (command === "verify") result = await verifyPluginState(options);
  }
  process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  if (command === "verify" && !result.ok) process.exitCode = 1;
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((error) => {
    process.stderr.write(`${JSON.stringify({ ok: false, error: error.message })}\n`);
    process.exitCode = 1;
  });
}
