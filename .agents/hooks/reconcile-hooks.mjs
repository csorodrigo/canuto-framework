#!/usr/bin/env node

import { createHash, randomUUID } from "node:crypto";
import {
  chmod,
  lstat,
  mkdir,
  readFile,
  rename,
  rm,
  writeFile,
} from "node:fs/promises";
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { pathToFileURL } from "node:url";

const HASH_RE = /^[a-f0-9]{64}$/;
const ROLES = new Set(["gate", "advisory", "observer", "automation"]);
const STATUSES = new Set(["active", "retired"]);
const FILE_OWNERSHIP_FIELDS = ["origin", "expectedHash", "mode"];

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

async function pathState(path) {
  try {
    const info = await lstat(path);
    if (info.isSymbolicLink()) fail(`refusing symbolic link: ${path}`);
    if (!info.isFile()) fail(`expected regular file: ${path}`);
    const bytes = await readFile(path);
    return { exists: true, hash: sha256(bytes), mode: info.mode & 0o777, bytes };
  } catch (error) {
    if (error.code === "ENOENT") return { exists: false, hash: null, mode: null, bytes: null };
    throw error;
  }
}

function parseJson(bytes, label) {
  try {
    return JSON.parse(bytes.toString("utf8"));
  } catch (error) {
    fail(`${label} is invalid JSON: ${error.message}`);
  }
}

function validateJsonSchema(value, schema, at = "$", errors = []) {
  const types = Array.isArray(schema.type) ? schema.type : schema.type ? [schema.type] : [];
  const actualType = value === null ? "null" : Array.isArray(value) ? "array" : Number.isInteger(value) ? "integer" : typeof value;
  if (types.length && !types.includes(actualType)) {
    errors.push(`${at} must have type ${types.join(" or ")}`);
    return errors;
  }
  if (Object.hasOwn(schema, "const") && value !== schema.const) errors.push(`${at} must equal ${JSON.stringify(schema.const)}`);
  if (schema.enum && !schema.enum.includes(value)) errors.push(`${at} must be one of ${schema.enum.join(", ")}`);
  if (typeof value === "string") {
    if (schema.minLength !== undefined && value.length < schema.minLength) errors.push(`${at} is too short`);
    if (schema.pattern && !new RegExp(schema.pattern).test(value)) errors.push(`${at} does not match required pattern`);
  }
  if (typeof value === "number" && schema.minimum !== undefined && value < schema.minimum) errors.push(`${at} must be at least ${schema.minimum}`);
  if (Array.isArray(value) && schema.items) value.forEach((item, index) => validateJsonSchema(item, schema.items, `${at}[${index}]`, errors));
  if (value && typeof value === "object" && !Array.isArray(value)) {
    for (const required of schema.required ?? []) if (!Object.hasOwn(value, required)) errors.push(`${at}.${required} is required`);
    const properties = schema.properties ?? {};
    if (schema.additionalProperties === false) {
      for (const key of Object.keys(value)) if (!Object.hasOwn(properties, key)) errors.push(`${at}.${key} is not allowed`);
    }
    for (const [key, childSchema] of Object.entries(properties)) {
      if (Object.hasOwn(value, key)) validateJsonSchema(value[key], childSchema, `${at}.${key}`, errors);
    }
  }
  return errors;
}

function fileOwnershipKind(entry) {
  const present = FILE_OWNERSHIP_FIELDS.filter((key) => Object.hasOwn(entry, key)).length;
  if (present === 0) return "none";
  if (present === FILE_OWNERSHIP_FIELDS.length) return "complete";
  return "partial";
}

function isRegistrationOnlyRetirement(entry) {
  return entry.status === "retired" && fileOwnershipKind(entry) === "none";
}

export function validateManifest(manifest) {
  const errors = [];
  if (!manifest || typeof manifest !== "object" || Array.isArray(manifest)) return ["manifest must be an object"];
  const topLevel = new Set(["$schema", "schemaVersion", "surface", "preconditions", "entries"]);
  for (const key of Object.keys(manifest)) if (!topLevel.has(key)) errors.push(`manifest has unknown property ${key}`);
  if (manifest.schemaVersion !== 1) errors.push("manifest schemaVersion must be 1");
  if (typeof manifest.surface !== "string" || !manifest.surface) errors.push("manifest surface is required");
  if (manifest.preconditions !== undefined && !Array.isArray(manifest.preconditions)) {
    errors.push("manifest preconditions must be an array");
  }
  const preconditionIds = new Set();
  for (const [index, precondition] of (manifest.preconditions ?? []).entries()) {
    const at = `preconditions[${index}]`;
    if (!precondition || typeof precondition !== "object" || Array.isArray(precondition)) {
      errors.push(`${at} must be an object`);
      continue;
    }
    const allowed = new Set(["id", "receipt", "expectedHash", "requiredStatus"]);
    for (const key of Object.keys(precondition)) if (!allowed.has(key)) errors.push(`${at} has unknown property ${key}`);
    if (typeof precondition.id !== "string" || !/^[a-z0-9-]+$/.test(precondition.id)) errors.push(`${at}.id is invalid`);
    if (preconditionIds.has(precondition.id)) errors.push(`duplicate precondition id ${precondition.id}`);
    preconditionIds.add(precondition.id);
    if (typeof precondition.receipt !== "string" || !precondition.receipt) errors.push(`${at}.receipt is required`);
    if (typeof precondition.expectedHash !== "string" || !HASH_RE.test(precondition.expectedHash)) errors.push(`${at}.expectedHash must be sha256`);
    if (precondition.requiredStatus !== "ready") errors.push(`${at}.requiredStatus must be ready`);
  }
  if (!Array.isArray(manifest.entries)) return [...errors, "manifest entries must be an array"];

  const ids = new Set();
  const executableCommands = new Set();
  const selectors = new Set();
  for (const [index, entry] of manifest.entries.entries()) {
    const at = `entries[${index}]`;
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
      errors.push(`${at} must be an object`);
      continue;
    }
    const allowed = new Set(["id", "version", "status", "origin", "event", "matcher", "timeout", "role", "command", "expectedHash", "mode"]);
    for (const key of Object.keys(entry)) if (!allowed.has(key)) errors.push(`${at} has unknown property ${key}`);
    if (typeof entry.id !== "string" || !/^[A-Z][A-Z0-9-]+$/.test(entry.id)) errors.push(`${at}.id is invalid`);
    else if (ids.has(entry.id)) errors.push(`duplicate managed id ${entry.id}`);
    else ids.add(entry.id);
    if (!Number.isInteger(entry.version) || entry.version < 1) errors.push(`${at}.version must be a positive integer`);
    if (!STATUSES.has(entry.status)) errors.push(`${at}.status must be active or retired`);
    const ownershipKind = fileOwnershipKind(entry);
    const hasFileMetadata = ownershipKind !== "none";
    if (entry.status === "active" && ownershipKind !== "complete") {
      errors.push(`${at} active entry requires origin, expectedHash, and mode`);
    } else if (ownershipKind === "partial") {
      errors.push(`${at} file ownership requires origin, expectedHash, and mode together`);
    }
    if (hasFileMetadata && (typeof entry.origin !== "string" || !entry.origin)) errors.push(`${at}.origin is required`);
    const registrationOnly = isRegistrationOnlyRetirement(entry);
    if (typeof entry.event !== "string" || !entry.event) errors.push(`${at}.event is required`);
    if (typeof entry.matcher !== "string") errors.push(`${at}.matcher must be a string`);
    if (entry.timeout !== null && (!Number.isInteger(entry.timeout) || entry.timeout < 1)) errors.push(`${at}.timeout must be null or a positive integer`);
    if (!ROLES.has(entry.role) && !(registrationOnly && entry.role === "probe")) errors.push(`${at}.role is invalid`);
    if (!registrationOnly && (typeof entry.command !== "string" || !/^~\/[A-Za-z0-9._/-]+$/.test(entry.command) || entry.command.split("/").includes(".."))) {
      errors.push(`${at}.command must be one tilde-relative executable path without arguments`);
    } else if (registrationOnly && (typeof entry.command !== "string" || !entry.command || /[\r\n\0]/.test(entry.command))) {
      errors.push(`${at}.command must be an exact command without control characters`);
    }
    if (hasFileMetadata && (typeof entry.expectedHash !== "string" || !HASH_RE.test(entry.expectedHash))) errors.push(`${at}.expectedHash must be sha256`);
    if (hasFileMetadata && entry.mode !== "0755") errors.push(`${at}.mode must be 0755`);
    if (!registrationOnly) {
      if (executableCommands.has(entry.command)) errors.push(`duplicate managed command ${entry.command}`);
      else executableCommands.add(entry.command);
    }
    const selector = `${entry.event}\0${entry.matcher}\0${entry.command}`;
    if (selectors.has(selector)) errors.push(`duplicate managed selector for ${entry.event}/${entry.matcher}/${entry.command}`);
    else selectors.add(selector);
  }
  return errors;
}

function normalizeCommand(command, homeDir) {
  if (typeof command !== "string") return command;
  if (homeDir && command.startsWith(`${homeDir}/`)) return `~/${command.slice(homeDir.length + 1)}`;
  return command;
}

function desiredHook(entry) {
  const hook = { type: "command", command: entry.command };
  if (entry.timeout !== null) hook.timeout = entry.timeout;
  return hook;
}

function hookMatches(entry, occurrence, homeDir) {
  const actual = occurrence.hook;
  return occurrence.event === entry.event
    && occurrence.matcher === entry.matcher
    && actual.type === "command"
    && normalizeCommand(actual.command, homeDir) === entry.command
    && (actual.timeout ?? null) === entry.timeout
    && Object.keys(actual).every((key) => ["type", "command", "timeout"].includes(key));
}

function flattenHooks(config) {
  const occurrences = [];
  const hooks = config.hooks ?? {};
  if (!hooks || typeof hooks !== "object" || Array.isArray(hooks)) fail("configuration hooks must be an object");
  for (const [event, groups] of Object.entries(hooks)) {
    if (!Array.isArray(groups)) fail(`configuration hooks.${event} must be an array`);
    groups.forEach((group, groupIndex) => {
      if (!group || typeof group !== "object" || Array.isArray(group)) fail(`configuration group ${event}[${groupIndex}] must be an object`);
      if (!Array.isArray(group.hooks)) fail(`configuration group ${event}[${groupIndex}].hooks must be an array`);
      group.hooks.forEach((hook, hookIndex) => {
        if (!hook || typeof hook !== "object" || Array.isArray(hook)) fail(`configuration hook ${event}[${groupIndex}][${hookIndex}] must be an object`);
        occurrences.push({ event, matcher: group.matcher ?? "", groupIndex, hookIndex, hook });
      });
    });
  }
  return occurrences;
}

function matchingOccurrences(entry, occurrences, homeDir) {
  return occurrences.filter((item) => {
    if (normalizeCommand(item.hook.command, homeDir) !== entry.command) return false;
    if (!isRegistrationOnlyRetirement(entry)) return true;
    return item.event === entry.event && item.matcher === entry.matcher;
  });
}

function renderNextConfig(config, entries, actions, occurrences, homeDir) {
  const next = structuredClone(config);
  next.hooks ??= {};
  const removeKeys = new Set();
  const replaceHooks = new Map();
  const addEntries = [];
  const actionById = new Map(actions.map((action) => [action.id, action.action]));

  for (const entry of entries) {
    const action = actionById.get(entry.id);
    const matching = matchingOccurrences(entry, occurrences, homeDir);
    let replacedInPlace = false;
    if (action === "update" && matching.length === 1 && matching[0].event === entry.event && matching[0].matcher === entry.matcher) {
      const item = matching[0];
      replaceHooks.set(`${item.event}\0${item.groupIndex}\0${item.hookIndex}`, desiredHook(entry));
      replacedInPlace = true;
    } else if (action === "remove" || action === "update") {
      for (const item of matching) removeKeys.add(`${item.event}\0${item.groupIndex}\0${item.hookIndex}`);
    }
    if (action === "add" || (action === "update" && !replacedInPlace)) addEntries.push(entry);
  }

  for (const [event, groups] of Object.entries(next.hooks)) {
    next.hooks[event] = groups.flatMap((group, groupIndex) => {
      const kept = group.hooks.flatMap((hook, hookIndex) => {
        const key = `${event}\0${groupIndex}\0${hookIndex}`;
        if (removeKeys.has(key)) return [];
        return [replaceHooks.get(key) ?? hook];
      });
      if (kept.length === 0 && group.hooks.length > 0 && Object.keys(group).every((key) => ["matcher", "hooks"].includes(key))) return [];
      return [{ ...group, hooks: kept }];
    });
  }

  for (const entry of addEntries) {
    const groups = next.hooks[entry.event] ??= [];
    let group = groups.find((candidate) => (candidate.matcher ?? "") === entry.matcher);
    if (!group) {
      group = { matcher: entry.matcher, hooks: [] };
      groups.push(group);
    }
    group.hooks.push(desiredHook(entry));
  }
  return next;
}

async function loadInputs({ manifestPath, configPath, hooksDir, homeDir = process.env.HOME }) {
  const manifestState = await pathState(manifestPath);
  if (!manifestState.exists) fail(`manifest file is missing: ${manifestPath}`);
  const manifest = parseJson(manifestState.bytes, "manifest");
  if (typeof manifest.$schema !== "string" || !manifest.$schema) fail("manifest $schema is required");
  const manifestDir = resolve(dirname(manifestPath));
  const schemaPath = resolve(manifestDir, manifest.$schema);
  const schemaRelative = relative(manifestDir, schemaPath);
  if (!schemaRelative || schemaRelative === ".." || schemaRelative.startsWith(`..${sep}`) || isAbsolute(schemaRelative)) fail("manifest schema must stay inside manifest directory");
  const schemaState = await pathState(schemaPath);
  if (!schemaState.exists) fail(`manifest schema is missing: ${manifest.$schema}`);
  const schema = parseJson(schemaState.bytes, "manifest schema");
  const schemaErrors = validateJsonSchema(manifest, schema);
  if (schemaErrors.length) fail(`manifest does not satisfy schema: ${schemaErrors.join("; ")}`);
  const manifestErrors = validateManifest(manifest);
  if (manifestErrors.length) fail(`invalid manifest: ${manifestErrors.join("; ")}`);

  for (const precondition of manifest.preconditions ?? []) {
    const receiptPath = resolve(manifestDir, precondition.receipt);
    const receiptRelative = relative(manifestDir, receiptPath);
    if (!receiptRelative || receiptRelative === ".." || receiptRelative.startsWith(`..${sep}`) || isAbsolute(receiptRelative)) {
      fail(`precondition receipt must stay inside manifest directory for ${precondition.id}`);
    }
    const receiptState = await pathState(receiptPath);
    if (!receiptState.exists) fail(`precondition ${precondition.id} receipt is missing`);
    if (receiptState.hash !== precondition.expectedHash) fail(`precondition ${precondition.id} receipt hash mismatch`);
    const receipt = parseJson(receiptState.bytes, `precondition ${precondition.id} receipt`);
    if (receipt.status !== precondition.requiredStatus) {
      fail(`precondition ${precondition.id} is ${receipt.status ?? "unknown"}, expected ${precondition.requiredStatus}`);
    }
  }

  const configState = await pathState(configPath);
  const config = configState.exists ? parseJson(configState.bytes, "configuration") : {};
  if (!config || typeof config !== "object" || Array.isArray(config)) fail("configuration must be a JSON object");
  const occurrences = flattenHooks(config);
  const sourceStates = new Map();
  const targetStates = new Map();
  for (const entry of manifest.entries) {
    const matches = matchingOccurrences(entry, occurrences, homeDir);
    if (matches.length > 1) fail(`duplicate Canuto entry ${entry.id} (${entry.command})`);
    if (isRegistrationOnlyRetirement(entry)) continue;
    const sourcePath = resolve(manifestDir, entry.origin);
    const sourceRelative = relative(manifestDir, sourcePath);
    if (!sourceRelative || sourceRelative === ".." || sourceRelative.startsWith(`..${sep}`) || isAbsolute(sourceRelative)) {
      fail(`origin must stay inside manifest directory for ${entry.id}`);
    }
    let source = sourceStates.get(sourcePath);
    if (!source) {
      source = await pathState(sourcePath);
      sourceStates.set(sourcePath, source);
    }
    if (!source.exists) fail(`origin is missing for ${entry.id}: ${entry.origin}`);
    if (source.hash !== entry.expectedHash) fail(`origin hash mismatch for ${entry.id}`);

    const commandName = basename(entry.command.trim().split(/\s+/)[0]);
    if (!commandName || commandName === "." || commandName === "..") fail(`invalid command target for ${entry.id}`);
    const targetPath = join(hooksDir, commandName);
    let target = targetStates.get(targetPath);
    if (!target) {
      target = await pathState(targetPath);
      targetStates.set(targetPath, target);
    }
  }
  return { manifest, manifestState, config, configState, occurrences, sourceStates, targetStates, homeDir };
}

export async function buildPlan(options) {
  const paths = {
    manifestPath: resolve(options.manifestPath),
    configPath: resolve(options.configPath),
    hooksDir: resolve(options.hooksDir),
  };
  const inputs = await loadInputs({ ...paths, homeDir: options.homeDir });
  const actions = inputs.manifest.entries.map((entry) => {
    const matches = matchingOccurrences(entry, inputs.occurrences, inputs.homeDir);
    if (entry.status === "retired") return { id: entry.id, action: matches.length ? "remove" : "preserve" };
    if (matches.length === 0) return { id: entry.id, action: "add" };
    return { id: entry.id, action: hookMatches(entry, matches[0], inputs.homeDir) ? "preserve" : "update" };
  });

  const activeTargets = new Map();
  const retiredTargets = new Map();
  const ownedTargets = new Map();
  for (const entry of inputs.manifest.entries) {
    if (isRegistrationOnlyRetirement(entry)) continue;
    const target = join(paths.hooksDir, basename(entry.command.trim().split(/\s+/)[0]));
    const owner = ownedTargets.get(target);
    if (owner && (owner.expectedHash !== entry.expectedHash || owner.origin !== entry.origin)) fail(`conflicting file ownership for ${target}`);
    ownedTargets.set(target, entry);
    const collection = entry.status === "active" ? activeTargets : retiredTargets;
    const existing = collection.get(target);
    if (existing && (existing.expectedHash !== entry.expectedHash || existing.origin !== entry.origin)) fail(`conflicting file ownership for ${target}`);
    collection.set(target, entry);
  }

  const files = [];
  for (const [target, entry] of [...activeTargets.entries()].sort(([a], [b]) => a.localeCompare(b))) {
    const state = inputs.targetStates.get(target);
    const expectedMode = Number.parseInt(entry.mode, 8);
    const action = !state.exists ? "add" : state.hash !== entry.expectedHash || state.mode !== expectedMode ? "update" : "preserve";
    files.push({ target, origin: resolve(dirname(paths.manifestPath), entry.origin), expectedHash: entry.expectedHash, mode: entry.mode, action });
  }
  for (const [target, entry] of [...retiredTargets.entries()].sort(([a], [b]) => a.localeCompare(b))) {
    if (activeTargets.has(target)) continue;
    const state = inputs.targetStates.get(target);
    files.push({ target, origin: resolve(dirname(paths.manifestPath), entry.origin), expectedHash: entry.expectedHash, mode: entry.mode, action: state.exists ? "remove" : "preserve" });
  }

  const nextConfig = renderNextConfig(inputs.config, inputs.manifest.entries, actions, inputs.occurrences, inputs.homeDir);
  const externalEntries = inputs.occurrences
    .filter((item) => !inputs.manifest.entries.some((entry) => matchingOccurrences(entry, [item], inputs.homeDir).length === 1))
    .map((item) => canonical(item.hook));
  const fingerprintInput = {
    schemaVersion: 1,
    surface: inputs.manifest.surface,
    manifestHash: inputs.manifestState.hash,
    configHash: inputs.configState.hash,
    actions,
    files: files.map(({ target, expectedHash, mode, action }) => ({ target, expectedHash, mode, action })),
    installed: [...inputs.targetStates.entries()].sort(([a], [b]) => a.localeCompare(b)).map(([path, state]) => ({ path, hash: state.hash, mode: state.mode })),
  };
  const fingerprint = sha256(Buffer.from(canonical(fingerprintInput)));
  return {
    schemaVersion: 1,
    surface: inputs.manifest.surface,
    fingerprint,
    config: {
      path: paths.configPath,
      beforeHash: inputs.configState.hash,
      afterHash: sha256(Buffer.from(`${JSON.stringify(nextConfig, null, 2)}\n`)),
      action: inputs.configState.hash === sha256(Buffer.from(`${JSON.stringify(nextConfig, null, 2)}\n`)) ? "preserve" : (inputs.configState.exists ? "update" : "add"),
    },
    entries: actions,
    files,
    external: { action: "preserve", count: externalEntries.length, entryFingerprints: externalEntries.map((item) => sha256(Buffer.from(item))) },
    nextConfig,
    changed: actions.some((item) => item.action !== "preserve") || files.some((item) => item.action !== "preserve") || inputs.configState.hash !== sha256(Buffer.from(`${JSON.stringify(nextConfig, null, 2)}\n`)),
  };
}

async function atomicWrite(path, bytes, mode) {
  await mkdir(dirname(path), { recursive: true });
  const temporary = join(dirname(path), `.${basename(path)}.canuto-${process.pid}-${randomUUID()}.tmp`);
  try {
    await writeFile(temporary, bytes, { mode });
    await chmod(temporary, mode);
    await rename(temporary, path);
  } catch (error) {
    await rm(temporary, { force: true }).catch(() => {});
    throw error;
  }
}

async function writeReceipt(path, receipt, { simulateFailure = false } = {}) {
  if (simulateFailure) fail("simulated receipt write failure");
  await atomicWrite(path, Buffer.from(`${JSON.stringify(receipt, null, 2)}\n`), 0o600);
}

async function restoreBatch(receipt, receiptPath, { automatic = false, allowPartial = false } = {}) {
  const configCurrent = await pathState(receipt.config.path);
  const validConfigStates = allowPartial
    ? [[receipt.config.beforeHash, receipt.config.beforeMode], [receipt.config.afterHash, receipt.config.afterMode]]
    : [[receipt.config.afterHash, receipt.config.afterMode]];
  if (!automatic && !validConfigStates.some(([hash, mode]) => configCurrent.hash === hash && configCurrent.mode === mode)) {
    fail("rollback rejected: configuration drift detected");
  }
  for (const file of receipt.files) {
    const current = await pathState(file.path);
    const validFileStates = allowPartial
      ? [[file.beforeHash, file.beforeMode], [file.afterHash, file.afterMode]]
      : [[file.afterHash, file.afterMode]];
    if (!automatic && !validFileStates.some(([hash, mode]) => current.hash === hash && current.mode === mode)) {
      fail(`rollback rejected: file drift detected for ${file.path}`);
    }
  }

  if (receipt.config.beforeExists) {
    const backup = await readFile(receipt.config.backupPath);
    await atomicWrite(receipt.config.path, backup, receipt.config.beforeMode);
  } else {
    await rm(receipt.config.path, { force: true });
  }
  for (const file of receipt.files) {
    if (file.beforeExists) {
      const backup = await readFile(file.backupPath);
      await atomicWrite(file.path, backup, file.beforeMode);
    } else {
      await rm(file.path, { force: true });
    }
  }

  const restored = await pathState(receipt.config.path);
  if (restored.hash !== receipt.config.beforeHash || restored.mode !== receipt.config.beforeMode) fail("rollback failed to restore configuration hash or mode");
  for (const file of receipt.files) {
    const state = await pathState(file.path);
    if (state.hash !== file.beforeHash || state.mode !== file.beforeMode) fail(`rollback failed to restore ${file.path}`);
  }
  receipt.status = automatic ? "restored-after-failure" : "rolled-back";
  receipt.rolledBackAt = new Date().toISOString();
  await writeReceipt(receiptPath, receipt);
  return receipt;
}

export async function applyPlan(options) {
  const plan = await buildPlan(options);
  if (plan.fingerprint !== options.fingerprint) fail("apply rejected: plan fingerprint mismatch or input drift");
  if (!plan.changed) return { applied: false, fingerprint: plan.fingerprint, reason: "already-converged" };

  const stateDir = resolve(options.stateDir);
  const batchId = `${new Date().toISOString().replace(/[-:.TZ]/g, "")}-${plan.fingerprint.slice(0, 12)}`;
  const batchDir = join(stateDir, "batches", batchId);
  const receiptPath = join(batchDir, "receipt.json");
  await mkdir(dirname(batchDir), { recursive: true, mode: 0o700 });
  await mkdir(batchDir, { recursive: false, mode: 0o700 });

  const configBefore = await pathState(plan.config.path);
  const configBackup = join(batchDir, "configuration.before");
  if (configBefore.exists) await atomicWrite(configBackup, configBefore.bytes, 0o600);
  const receipt = {
    schemaVersion: 1,
    batchId,
    fingerprint: plan.fingerprint,
    status: "prepared",
    createdAt: new Date().toISOString(),
    entries: plan.entries,
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
    const backupPath = join(batchDir, `file-${index}.before`);
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
  await writeReceipt(receiptPath, receipt);

  let writes = 0;
  try {
    for (const file of plan.files.filter((item) => item.action !== "preserve")) {
      if (file.action === "remove") await rm(file.target, { force: true });
      else await atomicWrite(file.target, await readFile(file.origin), Number.parseInt(file.mode, 8));
      writes += 1;
      if (options.failAfterWrites === writes) fail("simulated partial write failure");
    }
    await atomicWrite(plan.config.path, Buffer.from(`${JSON.stringify(plan.nextConfig, null, 2)}\n`), configBefore.mode ?? 0o600);
    writes += 1;
    if (options.failAfterWrites === writes) fail("simulated partial write failure");
    receipt.status = "applied";
    receipt.appliedAt = new Date().toISOString();
    await writeReceipt(receiptPath, receipt);
    const verified = await verifyState(options);
    if (!verified.ok) fail(`post-apply verification failed: ${verified.errors.join("; ")}`);
    receipt.verification = {
      ok: true,
      stateFingerprint: verified.fingerprint,
      verifiedAt: new Date().toISOString(),
    };
    await writeReceipt(receiptPath, receipt, { simulateFailure: options.failVerificationReceiptWrite });
  } catch (error) {
    await restoreBatch(receipt, receiptPath, { automatic: true });
    throw error;
  }
  return { applied: true, batchId, fingerprint: plan.fingerprint, receiptPath };
}

export async function verifyState(options) {
  try {
    const plan = await buildPlan(options);
    const errors = [];
    for (const entry of plan.entries) if (entry.action !== "preserve") errors.push(`entry ${entry.id} requires ${entry.action}`);
    for (const file of plan.files) if (file.action !== "preserve") errors.push(`file ${file.target} requires ${file.action}`);
    if (plan.config.action !== "preserve") errors.push(`configuration requires ${plan.config.action}`);
    return { ok: errors.length === 0, fingerprint: plan.fingerprint, errors };
  } catch (error) {
    return { ok: false, fingerprint: null, errors: [error.message] };
  }
}

export async function rollbackBatch({ stateDir, batchId }) {
  const receiptPath = join(resolve(stateDir), "batches", batchId, "receipt.json");
  const state = await pathState(receiptPath);
  if (!state.exists) fail(`rollback receipt is missing for batch ${batchId}`);
  const receipt = parseJson(state.bytes, "rollback receipt");
  if (receipt.batchId !== batchId || !["applied", "prepared"].includes(receipt.status)) fail(`batch ${batchId} is not eligible for rollback`);
  await restoreBatch(receipt, receiptPath, { allowPartial: receipt.status === "prepared" });
  return { rolledBack: true, batchId, restoredConfigHash: receipt.config.beforeHash };
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
    fail("usage: reconcile-hooks.mjs <plan|apply|verify|rollback> --manifest FILE --config FILE --hooks-dir DIR [--state-dir DIR] [--fingerprint HASH] [--batch-id ID]");
  }
  let result;
  if (command === "rollback") {
    if (!options.stateDir || !options.batchId) fail("rollback requires --state-dir and --batch-id");
    result = await rollbackBatch(options);
  } else {
    const requiredOptions = { manifestPath: "--manifest", configPath: "--config", hooksDir: "--hooks-dir" };
    for (const [required, flag] of Object.entries(requiredOptions)) if (!options[required]) fail(`${command} requires ${flag}`);
    if (command === "plan") result = await buildPlan(options);
    if (command === "verify") result = await verifyState(options);
    if (command === "apply") {
      if (!options.stateDir || !options.fingerprint) fail("apply requires --state-dir and --fingerprint");
      result = await applyPlan(options);
    }
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
