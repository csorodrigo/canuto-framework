#!/usr/bin/env node
'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const CONTROL_DIR = '.canuto-skill-publisher';
const SAFE_ID = /^[a-z0-9][a-z0-9-]*$/;
const SAFE_RUN_ID = /^[A-Za-z0-9][A-Za-z0-9._-]*$/;

function fail(message, code = 1) {
  const error = new Error(message);
  error.exitCode = code;
  throw error;
}

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function expandHome(value, home = os.homedir()) {
  if (value === '~') return home;
  if (value.startsWith('~/')) return path.join(home, value.slice(2));
  return value;
}

function listFiles(root, current = '') {
  const absolute = path.join(root, current);
  const entries = fs.readdirSync(absolute, { withFileTypes: true })
    .sort((left, right) => left.name.localeCompare(right.name));
  const files = [];
  for (const entry of entries) {
    const relative = current ? path.join(current, entry.name) : entry.name;
    if (entry.isSymbolicLink()) fail(`Symlink not allowed in skill bundle: ${relative}`);
    if (entry.isDirectory()) files.push(...listFiles(root, relative));
    else if (entry.isFile()) files.push(relative);
    else fail(`Unsupported entry in skill bundle: ${relative}`);
  }
  return files;
}

function fingerprintDirectory(root) {
  if (!fs.existsSync(root) || !fs.statSync(root).isDirectory()) return null;
  const hash = crypto.createHash('sha256');
  for (const relative of listFiles(root)) {
    const absolute = path.join(root, relative);
    const executable = (fs.statSync(absolute).mode & 0o111) === 0 ? '0' : '1';
    hash.update(relative.split(path.sep).join('/'));
    hash.update('\0');
    hash.update(executable);
    hash.update('\0');
    hash.update(fs.readFileSync(absolute));
    hash.update('\0');
  }
  return hash.digest('hex');
}

function writeJsonAtomic(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temporary = `${file}.tmp-${process.pid}-${crypto.randomBytes(6).toString('hex')}`;
  fs.writeFileSync(temporary, `${JSON.stringify(value, null, 2)}\n`, { mode: 0o600 });
  fs.renameSync(temporary, file);
}

function loadJson(file, fallback = null) {
  if (!fs.existsSync(file)) return fallback;
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function validateManifest(manifest) {
  if (manifest.schemaVersion !== 1 || !SAFE_ID.test(manifest.bundleId || '')) {
    fail('Unsupported skill bundle manifest');
  }
  if (!Array.isArray(manifest.skills) || manifest.skills.length === 0) {
    fail('Skill bundle manifest has no skills');
  }
  const names = new Set();
  for (const skill of manifest.skills) {
    if (!skill || !SAFE_ID.test(skill.name || '')) {
      fail(`Invalid skill name in manifest: ${skill && skill.name}`);
    }
    if (names.has(skill.name)) fail(`Duplicate skill in manifest: ${skill.name}`);
    if (!/^[a-f0-9]{64}$/.test(skill.sha256 || '')) {
      fail(`Invalid fingerprint for skill: ${skill.name}`);
    }
    names.add(skill.name);
  }
}

function resolveBundle(manifestFile) {
  const absoluteManifest = path.resolve(manifestFile);
  const manifest = loadJson(absoluteManifest);
  if (!manifest) fail(`Manifest not found: ${absoluteManifest}`);
  validateManifest(manifest);
  const repositoryRoot = path.resolve(path.dirname(absoluteManifest), '..');
  for (const skill of manifest.skills) {
    const source = path.join(repositoryRoot, 'global-skills', skill.name);
    const actual = fingerprintDirectory(source);
    if (actual !== skill.sha256) {
      fail(`Source fingerprint mismatch for ${skill.name}: expected ${skill.sha256}, got ${actual || 'missing'}`);
    }
  }
  return { manifest, manifestFile: absoluteManifest, repositoryRoot };
}

function targetPaths(targetRoot, bundleId) {
  const control = path.join(targetRoot, CONTROL_DIR);
  return {
    control,
    state: path.join(control, 'state', `${bundleId}.json`),
    receipts: path.join(control, 'receipts'),
    backups: path.join(control, 'backups'),
    staging: path.join(control, 'staging'),
    rollbackArchives: path.join(control, 'rollback-archives'),
  };
}

function assertSafeTargetRoot(targetRoot) {
  if (targetRoot === path.parse(targetRoot).root || targetRoot === os.homedir()) {
    fail(`Unsafe target root: ${targetRoot}`);
  }
  if (path.basename(targetRoot) !== 'skills') {
    fail(`Target root must be an explicit provider skills directory: ${targetRoot}`);
  }
}

function buildPlan(bundle, targetRoot) {
  const target = path.resolve(expandHome(targetRoot));
  assertSafeTargetRoot(target);
  const paths = targetPaths(target, bundle.manifest.bundleId);
  const state = loadJson(paths.state, { schemaVersion: 1, bundleId: bundle.manifest.bundleId, skills: {} });
  const items = bundle.manifest.skills.map((skill) => {
    const destination = path.join(target, skill.name);
    const actual = fingerprintDirectory(destination);
    const managed = state.skills && state.skills[skill.name];
    let action;
    if (actual === null) action = 'CREATE';
    else if (actual === skill.sha256) action = 'IDENTICAL';
    else if (managed && managed.installedSha256 === actual) action = 'UPDATE';
    else action = 'CONFLICT';
    return {
      name: skill.name,
      action,
      expectedSha256: skill.sha256,
      actualSha256: actual,
      destination,
    };
  });
  return {
    schemaVersion: 1,
    command: 'plan',
    bundleId: bundle.manifest.bundleId,
    sourceRef: bundle.manifest.source.ref,
    targetRoot: target,
    conflicts: items.filter((item) => item.action === 'CONFLICT').length,
    changes: items.filter((item) => item.action === 'CREATE' || item.action === 'UPDATE').length,
    identical: items.filter((item) => item.action === 'IDENTICAL').length,
    items,
    state,
    paths,
  };
}

function copyDirectory(source, destination) {
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.cpSync(source, destination, { recursive: true, errorOnExist: true, force: false, preserveTimestamps: false });
}

function safeRunId() {
  return `${new Date().toISOString().replace(/[:.]/g, '-')}-${process.pid}-${crypto.randomBytes(4).toString('hex')}`;
}

function ensureExpectedCurrent(item, expected) {
  const current = fingerprintDirectory(item.destination);
  if (current !== expected) {
    fail(`Concurrent change detected for ${item.name}: expected ${expected || 'missing'}, got ${current || 'missing'}`);
  }
}

function applyBundle(bundle, targetRoot) {
  const plan = buildPlan(bundle, targetRoot);
  if (plan.conflicts > 0) fail(`Apply refused: ${plan.conflicts} unmanaged conflict(s)`, 2);
  const runId = safeRunId();
  const runStaging = path.join(plan.paths.staging, runId);
  const runBackups = path.join(plan.paths.backups, runId);
  const previousState = plan.state;
  const actions = [];
  fs.mkdirSync(plan.targetRoot, { recursive: true });

  try {
    for (const item of plan.items) {
      const source = path.join(bundle.repositoryRoot, 'global-skills', item.name);
      if (item.action === 'IDENTICAL') {
        actions.push({ ...item, backup: null });
        continue;
      }

      ensureExpectedCurrent(item, item.actualSha256);
      const staged = path.join(runStaging, item.name);
      copyDirectory(source, staged);
      if (fingerprintDirectory(staged) !== item.expectedSha256) fail(`Staging verification failed for ${item.name}`);

      let backup = null;
      if (item.action === 'UPDATE') {
        backup = path.join(runBackups, item.name);
        fs.mkdirSync(path.dirname(backup), { recursive: true });
        fs.renameSync(item.destination, backup);
        actions.push({ ...item, backup });
      }
      fs.renameSync(staged, item.destination);
      if (item.action === 'CREATE') actions.push({ ...item, backup });
    }
  } catch (error) {
    for (const action of [...actions].reverse()) {
      if (action.action === 'IDENTICAL') continue;
      if (fs.existsSync(action.destination)) {
        const failed = path.join(runStaging, `failed-${action.name}`);
        fs.renameSync(action.destination, failed);
      }
      if (action.backup && fs.existsSync(action.backup)) fs.renameSync(action.backup, action.destination);
    }
    throw error;
  }

  const nextState = {
    schemaVersion: 1,
    bundleId: bundle.manifest.bundleId,
    source: bundle.manifest.source,
    updatedAt: new Date().toISOString(),
    skills: Object.fromEntries(bundle.manifest.skills.map((skill) => [skill.name, {
      installedSha256: skill.sha256,
      sourceRef: bundle.manifest.source.ref,
    }])),
  };
  const receipt = {
    schemaVersion: 1,
    command: 'apply',
    runId,
    bundleId: bundle.manifest.bundleId,
    source: bundle.manifest.source,
    targetRoot: plan.targetRoot,
    createdAt: new Date().toISOString(),
    previousState,
    actions,
  };
  writeJsonAtomic(plan.paths.state, nextState);
  const receiptFile = path.join(plan.paths.receipts, `${runId}.json`);
  writeJsonAtomic(receiptFile, receipt);
  return { ...receipt, receiptFile };
}

function verifyBundle(bundle, targetRoot) {
  const plan = buildPlan(bundle, targetRoot);
  const items = plan.items.map((item) => ({
    name: item.name,
    ok: item.actualSha256 === item.expectedSha256,
    expectedSha256: item.expectedSha256,
    actualSha256: item.actualSha256,
  }));
  return {
    schemaVersion: 1,
    command: 'verify',
    bundleId: bundle.manifest.bundleId,
    sourceRef: bundle.manifest.source.ref,
    targetRoot: plan.targetRoot,
    ok: items.every((item) => item.ok),
    items,
  };
}

function rollbackReceipt(receiptFile) {
  const absoluteReceipt = path.resolve(expandHome(receiptFile));
  const receipt = loadJson(absoluteReceipt);
  if (!receipt || receipt.command !== 'apply' || !receipt.targetRoot || !SAFE_ID.test(receipt.bundleId || '')) {
    fail(`Invalid apply receipt: ${absoluteReceipt}`);
  }
  const targetRoot = path.resolve(expandHome(receipt.targetRoot));
  assertSafeTargetRoot(targetRoot);
  if (targetRoot !== receipt.targetRoot || !SAFE_RUN_ID.test(receipt.runId || '') || !Array.isArray(receipt.actions)) {
    fail(`Invalid apply receipt: ${absoluteReceipt}`);
  }
  const paths = targetPaths(targetRoot, receipt.bundleId);
  for (const action of receipt.actions) {
    const expectedDestination = action && SAFE_ID.test(action.name || '')
      ? path.join(targetRoot, action.name)
      : null;
    const expectedBackup = action && action.action === 'UPDATE'
      ? path.join(paths.backups, receipt.runId, action.name)
      : null;
    if (!action
      || !['CREATE', 'UPDATE', 'IDENTICAL'].includes(action.action)
      || action.destination !== expectedDestination
      || action.backup !== expectedBackup
      || !/^[a-f0-9]{64}$/.test(action.expectedSha256 || '')) {
      fail(`Invalid action in apply receipt: ${absoluteReceipt}`);
    }
  }
  const rollbackId = safeRunId();
  const archiveRoot = path.join(paths.rollbackArchives, rollbackId);

  for (const action of receipt.actions) {
    if (action.action === 'IDENTICAL') continue;
    ensureExpectedCurrent(action, action.expectedSha256);
    if (action.backup && !fs.existsSync(action.backup)) {
      fail(`Rollback backup missing for ${action.name}: ${action.backup}`);
    }
  }
  for (const action of [...receipt.actions].reverse()) {
    if (action.action === 'IDENTICAL') continue;
    const archive = path.join(archiveRoot, action.name);
    fs.mkdirSync(path.dirname(archive), { recursive: true });
    fs.renameSync(action.destination, archive);
    if (action.backup) {
      fs.renameSync(action.backup, action.destination);
    }
  }
  writeJsonAtomic(paths.state, receipt.previousState || { schemaVersion: 1, bundleId: receipt.bundleId, skills: {} });
  const rollback = {
    schemaVersion: 1,
    command: 'rollback',
    rollbackId,
    applyReceipt: absoluteReceipt,
    bundleId: receipt.bundleId,
    targetRoot,
    archiveRoot,
    createdAt: new Date().toISOString(),
  };
  const rollbackFile = path.join(paths.receipts, `${rollbackId}-rollback.json`);
  writeJsonAtomic(rollbackFile, rollback);
  return { ...rollback, receiptFile: rollbackFile };
}

function parseArgs(argv) {
  const [command, ...rest] = argv;
  const options = {};
  for (let index = 0; index < rest.length; index += 1) {
    const argument = rest[index];
    if (!argument.startsWith('--')) fail(`Unexpected argument: ${argument}`);
    const key = argument.slice(2);
    const value = rest[index + 1];
    if (!value || value.startsWith('--')) fail(`Missing value for --${key}`);
    options[key] = value;
    index += 1;
  }
  return { command, options };
}

function printHelp() {
  process.stdout.write([
    'Usage:',
    '  skill-bundle-publisher.js plan --manifest <file> --target <skills-root>',
    '  skill-bundle-publisher.js apply --manifest <file> --target <skills-root>',
    '  skill-bundle-publisher.js verify --manifest <file> --target <skills-root>',
    '  skill-bundle-publisher.js rollback --receipt <apply-receipt>',
    '',
    'Every command prints JSON. Apply refuses unmanaged conflicts and writes an auditable receipt.',
  ].join('\n'));
}

function main(argv = process.argv.slice(2)) {
  const { command, options } = parseArgs(argv);
  if (!command || command === 'help' || command === '--help') {
    printHelp();
    return 0;
  }
  let result;
  if (command === 'rollback') {
    if (!options.receipt) fail('rollback requires --receipt');
    result = rollbackReceipt(options.receipt);
  } else {
    if (!options.manifest || !options.target) fail(`${command} requires --manifest and --target`);
    const bundle = resolveBundle(options.manifest);
    if (command === 'plan') result = buildPlan(bundle, options.target);
    else if (command === 'apply') result = applyBundle(bundle, options.target);
    else if (command === 'verify') result = verifyBundle(bundle, options.target);
    else fail(`Unknown command: ${command}`);
  }
  const printable = { ...result };
  delete printable.state;
  delete printable.paths;
  process.stdout.write(`${JSON.stringify(printable, null, 2)}\n`);
  if (command === 'plan' && result.conflicts > 0) return 2;
  if (command === 'verify' && !result.ok) return 3;
  return 0;
}

if (require.main === module) {
  try {
    process.exitCode = main();
  } catch (error) {
    process.stderr.write(`${error.message}\n`);
    process.exitCode = error.exitCode || 1;
  }
}

module.exports = {
  applyBundle,
  buildPlan,
  fingerprintDirectory,
  main,
  resolveBundle,
  rollbackReceipt,
  verifyBundle,
  writeJsonAtomic,
};
