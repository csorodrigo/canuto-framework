'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync, spawn } = require('node:child_process');

const TOOL = 'canuto-skill-refactor';
const SCHEMA_VERSION = 1;
const MAX_ENTRYPOINT_LINES = 500;
const MAX_FILE_BYTES = 5 * 1024 * 1024;
const MAX_BUNDLE_FILES = 500;
const MAX_BUNDLE_BYTES = 32 * 1024 * 1024;
const MAX_RESULT_BYTES = 8 * 1024 * 1024;
const MAX_STDERR_BYTES = 16 * 1024;
const MAX_QUEUE_ITEMS = 200;
const MAX_WORKERS = 4;
const MAX_DELEGATE_ATTEMPTS = 2;
const DEFAULT_DELEGATE_TIMEOUT_MS = 15 * 60 * 1000;
const DELEGATE_KILL_GRACE_MS = 5 * 1000;
const HASH_PREFIX_LENGTH = 16;
const DEFAULT_HMAC_KEY = 'canuto-skill-refactor-inventory';
const MAX_WORKSPACE_FILE_BYTES = 32 * 1024 * 1024;
const MAX_VALIDATOR_OUTPUT_BYTES = 64 * 1024;
const STATE_LOCK_NAME = '.state.lock';

const CLASSIFICATIONS = Object.freeze([
  'KEEP',
  'REFACTOR',
  'MANAGED',
  'INACTIVE',
  'BLOCKED_PROVENANCE',
]);

const JOB_STATES = Object.freeze([
  'PENDING',
  'RUNNING',
  'GENERATED',
  'VALIDATED',
  'BLOCKED',
  'FAILED',
]);

const MAX_LINE_BYTES = MAX_FILE_BYTES;

let gardener;
try {
  gardener = require(path.join(__dirname, '..', 'skill-gardener', 'canuto-skill-gardener-lib'));
} catch {
  gardener = require(path.join(__dirname, '..', 'lib', 'canuto-skill-gardener-lib'));
}

class RefactorError extends Error {
  constructor(code, message = code, details = {}) {
    super(message);
    this.name = 'RefactorError';
    this.code = code;
    this.details = details;
  }
}

function stableJson(value) {
  if (Array.isArray(value)) return `[${value.map(stableJson).join(',')}]`;
  if (value && typeof value === 'object') {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stableJson(value[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function normalizeName(value) {
  return gardener.normalizeName(value);
}

function parseFrontmatter(value) {
  return gardener.parseFrontmatter(String(value || ''));
}

function isoNow() {
  return new Date().toISOString();
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function sameFileIdentity(left, right) {
  for (const key of ['dev', 'ino', 'size', 'mtimeMs', 'ctimeMs']) {
    if (left?.[key] !== undefined && right?.[key] !== undefined && left[key] !== right[key]) return false;
  }
  return true;
}

function sameFileObject(left, right) {
  return left?.dev !== undefined && right?.dev !== undefined && left.dev === right.dev
    && left?.ino !== undefined && right?.ino !== undefined && left.ino === right.ino;
}

function readFileBounded(filePath, limit, options = {}) {
  const target = path.resolve(filePath);
  const failureCode = options.failureCode || 'file-read-failed';
  const tooLargeCode = options.tooLargeCode || failureCode;
  let fd;
  try {
    const pathBefore = fs.lstatSync(target);
    if (!pathBefore.isFile() || pathBefore.isSymbolicLink()) throw new RefactorError(failureCode, failureCode);
    const noFollow = fs.constants.O_NOFOLLOW || 0;
    fd = fs.openSync(target, fs.constants.O_RDONLY | noFollow);
    const before = fs.fstatSync(fd);
    if (!before.isFile()) throw new RefactorError(failureCode, failureCode);
    if (before.size > limit) throw new RefactorError(tooLargeCode, tooLargeCode);
    if (!sameFileIdentity(pathBefore, before)) throw new RefactorError(failureCode, failureCode);
    const buffer = Buffer.alloc(before.size);
    let offset = 0;
    while (offset < buffer.length) {
      const bytes = fs.readSync(fd, buffer, offset, buffer.length - offset, offset);
      if (!bytes) throw new RefactorError(failureCode, failureCode);
      offset += bytes;
    }
    const after = fs.fstatSync(fd);
    const pathAfter = fs.lstatSync(target);
    if (!pathAfter.isFile() || pathAfter.isSymbolicLink() || !sameFileIdentity(before, after) || !sameFileIdentity(after, pathAfter)) {
      throw new RefactorError(failureCode, failureCode);
    }
    return buffer;
  } catch (error) {
    if (error instanceof RefactorError) throw error;
    throw new RefactorError(failureCode, failureCode, { cause: error.code || error.message || 'read-failed' });
  } finally {
    if (fd !== undefined) {
      try { fs.closeSync(fd); } catch { /* best effort */ }
    }
  }
}

function asArray(value) {
  return Array.isArray(value) ? value : [];
}

function pathKey(value) {
  return path.resolve(String(value || ''));
}

function isWithin(base, target) {
  const relative = path.relative(path.resolve(base), path.resolve(target));
  return relative === '' || (relative !== '..' && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative));
}

function pathsOverlap(left, right) {
  return isWithin(left, right) || isWithin(right, left);
}

function modeOf(filePath) {
  try { return fs.statSync(filePath).mode & 0o777; } catch { return 0; }
}

function ensureDirectory(directory, mode = 0o700) {
  const target = path.resolve(directory);
  let existed = false;
  try {
    const stat = fs.lstatSync(target);
    existed = true;
    if (!stat.isDirectory() || stat.isSymbolicLink()) throw new RefactorError('workspace-unsafe', 'workspace path is not a directory');
  } catch (error) {
    if (error instanceof RefactorError) throw error;
    if (error.code !== 'ENOENT') throw error;
  }
  if (!existed) fs.mkdirSync(target, { recursive: true, mode });
  if (!fs.statSync(target).isDirectory()) throw new RefactorError('workspace-unsafe', 'workspace path is not a directory');
  if (!existed) fs.chmodSync(target, mode);
  return target;
}

function ensureWorkspace(workspace) {
  const target = pathKey(workspace);
  if (!path.isAbsolute(workspace)) throw new RefactorError('workspace-absolute-required', 'workspace must be an absolute path');
  return ensureDirectory(target, 0o700);
}

function writeAtomic(filePath, value, mode = 0o600) {
  const target = path.resolve(filePath);
  ensureDirectory(path.dirname(target), 0o700);
  try {
    const existing = fs.lstatSync(target);
    if (existing.isSymbolicLink()) throw new RefactorError('unsafe-state-file', 'state target cannot be a symlink');
  } catch (error) {
    if (error instanceof RefactorError) throw error;
    if (error.code !== 'ENOENT') throw error;
  }
  const temporary = `${target}.tmp-${process.pid}-${crypto.randomBytes(6).toString('hex')}`;
  const data = Buffer.isBuffer(value) ? value : Buffer.from(String(value));
  let fd;
  try {
    fd = fs.openSync(temporary, 'wx', mode);
    fs.writeFileSync(fd, data);
    fs.fsyncSync(fd);
    fs.closeSync(fd);
    fd = undefined;
    fs.chmodSync(temporary, mode);
    fs.renameSync(temporary, target);
    fs.chmodSync(target, mode);
  } catch (error) {
    if (fd !== undefined) fs.closeSync(fd);
    try { fs.unlinkSync(temporary); } catch { /* best effort cleanup */ }
    throw error;
  }
}

function writeJsonAtomic(filePath, value, mode = 0o600) {
  writeAtomic(filePath, `${JSON.stringify(value, null, 2)}\n`, mode);
}

function readJson(filePath, code = 'workspace-invalid') {
  try {
    const raw = readFileBounded(filePath, MAX_WORKSPACE_FILE_BYTES, {
      failureCode: 'workspace-read-failed',
      tooLargeCode: 'workspace-file-too-large',
    });
    return JSON.parse(raw.toString('utf8'));
  } catch (error) {
    if (error instanceof RefactorError && error.code === 'workspace-file-too-large') throw error;
    if (error instanceof SyntaxError) throw new RefactorError(code, code);
    if (error.code === 'ENOENT') throw new RefactorError(code, code);
    throw new RefactorError(code, code);
  }
}

function readTextBounded(filePath, limit = MAX_RESULT_BYTES) {
  return readFileBounded(filePath, limit, {
    failureCode: 'result-read-failed',
    tooLargeCode: 'result-too-large',
  }).toString('utf8');
}

function publicHash(value) {
  return /^[a-f0-9]{64}$/i.test(String(value || '')) ? String(value).toLowerCase() : sha256(String(value || ''));
}

function hashPrefix(value) {
  return publicHash(value).slice(0, HASH_PREFIX_LENGTH);
}

function normalizeAlias(value) {
  const normalized = normalizeName(value);
  return normalized || 'unmapped';
}

function homePath(value, home = os.homedir()) {
  const text = String(value || '');
  if (text === '~') return home;
  if (text.startsWith('~/')) return path.join(home, text.slice(2));
  return text.replace(/^\$HOME(?=\/|$)/, home);
}

function absoluteConfiguredPath(value, home = os.homedir()) {
  return path.resolve(process.cwd(), homePath(value, home));
}

function rootEntryPath(entry) {
  if (typeof entry === 'string') return entry;
  if (entry && typeof entry === 'object') return entry.path || entry.root || '';
  return '';
}

function rootBase(value) {
  const normalized = value.replace(/\\/g, '/');
  const wildcard = normalized.search(/[?*[]/);
  if (wildcard < 0) return normalized;
  const slash = normalized.lastIndexOf('/', wildcard);
  return slash < 0 ? '.' : normalized.slice(0, slash + 1);
}

function configuredRoots(config, home = os.homedir(), frameworkRoot = defaultFrameworkRoot()) {
  const values = [];
  for (const project of Object.values(config.projects || {})) {
    for (const surface of Object.values(project.surfaces || {})) {
      for (const root of asArray(surface.roots)) values.push(rootEntryPath(root));
    }
  }
  for (const settings of Object.values(config.providers || {})) {
    for (const key of ['roots', 'pluginRoots', 'systemRoots']) {
      for (const root of asArray(settings[key])) values.push(rootEntryPath(root));
    }
  }
  values.push(path.join(frameworkRoot, '.agents', 'skills'));
  return [...new Set(values.filter(Boolean).map((value) => absoluteConfiguredPath(rootBase(String(value)), home)))];
}

function existingRealPath(value) {
  let current = path.resolve(value);
  const suffix = [];
  while (true) {
    try {
      return path.resolve(fs.realpathSync(current), ...suffix.reverse());
    } catch {
      const parent = path.dirname(current);
      if (parent === current) return path.resolve(value);
      suffix.unshift(path.basename(current));
      current = parent;
    }
  }
}

function validateWorkspaceLocation(workspace, config, inventory, options = {}) {
  if (!path.isAbsolute(workspace)) throw new RefactorError('workspace-absolute-required', 'workspace must be an absolute path');
  const target = path.resolve(workspace);
  const targetReal = existingRealPath(target);
  const roots = configuredRoots(config, options.home || os.homedir(), options.frameworkRoot || defaultFrameworkRoot());
  for (const installation of inventory?._installations || []) {
    if (installation?._sourcePath) roots.push(path.dirname(installation._sourcePath));
  }
  const uniqueRoots = [...new Set(roots.map((value) => path.resolve(value)))];
  for (const root of uniqueRoots) {
    if (!fs.existsSync(root) && !fs.existsSync(path.dirname(root))) continue;
    const rootReal = existingRealPath(root);
    if (pathsOverlap(target, root) || pathsOverlap(targetReal, rootReal)) {
      throw new RefactorError('workspace-live-root', 'workspace overlaps a discovered live skill root');
    }
  }
  return target;
}

function defaultConfigPath() {
  if (process.env.CANUTO_SKILL_GARDENER_CONFIG) return path.resolve(process.env.CANUTO_SKILL_GARDENER_CONFIG);
  const installed = path.join(os.homedir(), '.canuto', 'config', 'skill-gardener.json');
  if (fs.existsSync(installed)) return path.resolve(installed);
  return path.resolve(path.join(__dirname, '..', 'config', 'skill-gardener.json'));
}

function defaultFrameworkRoot() {
  return path.resolve(process.env.CANUTO_SKILL_REFACTOR_FRAMEWORK_ROOT
    || process.env.CANUTO_SKILL_GARDENER_FRAMEWORK_ROOT
    || path.join(__dirname, '..'));
}

function defaultContractPath() {
  return path.resolve(process.env.CANUTO_SKILL_REFACTOR_CONTRACT
    || path.join(os.homedir(), '.codex', 'skills', '.system', 'skill-creator', 'SKILL.md'));
}

function defaultValidatorPath() {
  return path.resolve(path.join(os.homedir(), '.codex', 'skills', '.system', 'skill-creator', 'scripts', 'quick_validate.py'));
}

function defaultDelegatePath() {
  return path.join(os.homedir(), '.codex', 'bin', 'codex-delegate.sh');
}

function inventoryForConfig(config, options = {}) {
  return gardener.collectInventory(config, {
    home: options.home || os.homedir(),
    frameworkRoot: options.frameworkRoot || defaultFrameworkRoot(),
    hmacKey: DEFAULT_HMAC_KEY,
  });
}

function inactiveComponent(component) {
  const value = String(component || '').toLowerCase();
  if (!value) return false;
  if (value === '_archive' || value === 'archive' || value === 'archives') return true;
  if (value === 'backup' || value === 'backups' || value === 'retired') return true;
  if (value === 'node_modules' || value === '.next') return true;
  if (value.includes('.bak') || value.startsWith('_retired-')) return true;
  return false;
}

function isInactiveSourcePath(sourcePath) {
  return path.resolve(sourcePath).split(path.sep).some(inactiveComponent);
}

function secretComponent(component) {
  const value = String(component || '').toLowerCase();
  if (!value) return false;
  if (/^\.env(?:\.|$)/i.test(value)) return true;
  if (/\.(?:pem|key)$/i.test(value)) return true;
  if (/(?:^|[-_.])(credentials?|cookies?|tokens?|secrets?|auth-state)(?:$|[-_.])/i.test(value)) return true;
  return false;
}

function isSecretLookingPath(relativePath) {
  return String(relativePath || '').split(/[\\/]+/).some(secretComponent);
}

function safeRelative(base, target) {
  const relative = path.relative(base, target).split(path.sep).join('/');
  return relative || '.';
}

function frontmatterContract(content, expectedName) {
  const text = String(content || '');
  const match = text.match(/^---\r?\n([\s\S]*?)\r?\n---(?:\r?\n|$)/);
  if (!match) return { valid: false, reasons: ['frontmatter-delimiters'] };
  const parsed = parseFrontmatter(text);
  const name = typeof parsed.data?.name === 'string' ? parsed.data.name.trim() : '';
  const description = typeof parsed.data?.description === 'string' ? parsed.data.description.trim() : '';
  const reasons = [];
  const allowedKeys = new Set(['name', 'description', 'license', 'allowed-tools', 'metadata']);
  if (Object.keys(parsed.data || {}).some((key) => !allowedKeys.has(key))) reasons.push('unexpected-frontmatter-key');
  if (!name) reasons.push('missing-name');
  else if (name !== expectedName || !/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(name) || name.length > 64) reasons.push('name-mismatch');
  if (!description) reasons.push('missing-description');
  else {
    const normalizedDescription = normalizeName(description);
    if (description.length < 8 || description.length > 1024 || /[<>]/.test(description)
      || normalizedDescription === expectedName || ['skill', 'a-skill', 'description', 'todo', 'tbd'].includes(normalizedDescription)) {
      reasons.push('non-discriminating-description');
    }
  }
  return { valid: reasons.length === 0, reasons, data: parsed.data, body: parsed.body, rawName: name, description };
}

function linesIn(value) {
  return String(value || '').split(/\r?\n/).length;
}

function gitProvenance(sourcePath) {
  const sourceDir = path.dirname(sourcePath);
  try {
    const top = execFileSync('git', ['-C', sourceDir, 'rev-parse', '--show-toplevel'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
    const common = execFileSync('git', ['-C', sourceDir, 'rev-parse', '--git-common-dir'], {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
    }).trim();
    const topPath = existingRealPath(path.resolve(sourceDir, top));
    const commonPath = existingRealPath(path.resolve(sourceDir, common));
    return {
      commonDir: commonPath,
      relativeFile: safeRelative(topPath, existingRealPath(sourcePath)),
      key: `${commonPath}\u0000${safeRelative(topPath, existingRealPath(sourcePath))}`,
    };
  } catch {
    const real = existingRealPath(sourcePath);
    return { commonDir: '', relativeFile: real, key: `NO_GIT\u0000${real}` };
  }
}

function readSourceEntrypoint(installation, expectedName) {
  const sourcePath = path.resolve(installation._sourcePath);
  if (isSecretLookingPath(sourcePath)) {
    return { sourcePath, secret: true, content: '', actualHash: '', frontmatter: { valid: false, reasons: ['secret-looking-file'] } };
  }
  try {
    const stat = fs.lstatSync(sourcePath);
    if (!stat.isFile() || stat.isSymbolicLink()) return { sourcePath, missing: true, content: '', actualHash: '', frontmatter: { valid: false, reasons: ['source-not-regular-file'] } };
    if (stat.size > MAX_FILE_BYTES) return { sourcePath, oversized: true, content: '', actualHash: '', frontmatter: { valid: false, reasons: ['source-file-too-large'] } };
    const content = readFileBounded(sourcePath, MAX_FILE_BYTES, {
      failureCode: 'source-mutated',
      tooLargeCode: 'source-file-too-large',
    }).toString('utf8');
    return {
      sourcePath,
      content,
      actualHash: sha256(content),
      frontmatter: frontmatterContract(content, expectedName),
      lines: linesIn(content),
      mutated: installation.contentHash && sha256(content) !== installation.contentHash,
    };
  } catch (error) {
    if (error instanceof RefactorError && error.code === 'source-file-too-large') {
      return { sourcePath, oversized: true, content: '', actualHash: '', frontmatter: { valid: false, reasons: ['source-file-too-large'] } };
    }
    return { sourcePath, missing: true, content: '', actualHash: '', frontmatter: { valid: false, reasons: ['source-unreadable'] } };
  }
}

function compareEntryManifests(left, right) {
  const normalize = (entries) => asArray(entries).map((entry) => ({
    relative: entry.relative,
    type: entry.type,
    bytes: entry.bytes || 0,
    hash: entry.hash || '',
    targetRelative: entry.targetRelative || '',
  })).sort((a, b) => a.relative.localeCompare(b.relative));
  return stableJson(normalize(left)) === stableJson(normalize(right));
}

function inspectSourceBundle(sourcePath) {
  const lexicalPath = path.resolve(sourcePath);
  if (isSecretLookingPath(lexicalPath)) return { ok: false, reason: 'secret-looking-file', sourcePath: lexicalPath };
  let stat;
  try { stat = fs.lstatSync(lexicalPath); } catch { return { ok: false, reason: 'source-mutated', sourcePath: lexicalPath }; }
  if (!stat.isFile() && !stat.isDirectory()) return { ok: false, reason: 'source-not-regular-file', sourcePath: lexicalPath };
  if (stat.isSymbolicLink()) return { ok: false, reason: 'source-path-escape', sourcePath: lexicalPath };
  const resolved = stat.isDirectory()
    ? existingRealPath(lexicalPath)
    : path.join(existingRealPath(path.dirname(lexicalPath)), path.basename(lexicalPath));

  if (stat.isFile() && path.basename(resolved) !== 'SKILL.md') {
    if (stat.size > MAX_FILE_BYTES) return { ok: false, reason: 'source-file-too-large', sourcePath: resolved };
    try {
      const content = readFileBounded(resolved, MAX_FILE_BYTES, {
        failureCode: 'source-mutated',
        tooLargeCode: 'source-file-too-large',
      });
      return {
        ok: true,
        mode: 'legacy',
        sourcePath: resolved,
        root: path.dirname(resolved),
        entrypointRelative: 'SKILL.md',
        entries: [{ relative: 'SKILL.md', type: 'file', bytes: content.length, hash: sha256(content), sourceRelative: path.basename(resolved) }],
        totalBytes: content.length,
        fileCount: 1,
      };
    } catch (error) {
      return { ok: false, reason: error.code === 'source-file-too-large' ? error.code : 'source-mutated', sourcePath: resolved };
    }
  }

  const root = existingRealPath(path.dirname(resolved));
  const entries = [];
  const visitedDirectories = new Set();
  let totalBytes = 0;
  let fileCount = 0;
  let failure = null;

  function walk(directory, depth) {
    if (failure) return;
    if (depth > 32) { failure = 'source-depth-exceeded'; return; }
    let realDirectory;
    try { realDirectory = fs.realpathSync(directory); } catch { failure = 'source-mutated'; return; }
    if (!isWithin(root, realDirectory)) { failure = 'source-path-escape'; return; }
    if (visitedDirectories.has(realDirectory)) return;
    visitedDirectories.add(realDirectory);
    let entriesOnDisk;
    try { entriesOnDisk = fs.readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name)); } catch { failure = 'source-mutated'; return; }
    for (const diskEntry of entriesOnDisk) {
      if (failure) return;
      const candidate = path.join(directory, diskEntry.name);
      const relative = safeRelative(root, candidate);
      if (isSecretLookingPath(relative)) { failure = 'secret-looking-file'; return; }
      let itemStat;
      try { itemStat = fs.lstatSync(candidate); } catch { failure = 'source-mutated'; return; }
      if (itemStat.isSymbolicLink()) {
        let target;
        try { target = fs.realpathSync(candidate); } catch { failure = 'source-path-escape'; return; }
        if (!isWithin(root, target) || isSecretLookingPath(safeRelative(root, target))) { failure = 'source-path-escape'; return; }
        const targetStat = fs.statSync(candidate);
        entries.push({ relative, type: 'symlink', bytes: 0, hash: sha256(fs.readlinkSync(candidate)), targetRelative: safeRelative(root, target) });
        if (targetStat.isFile()) fileCount += 1;
        continue;
      }
      if (itemStat.isDirectory()) {
        walk(candidate, depth + 1);
        continue;
      }
      if (!itemStat.isFile()) { failure = 'source-special-file'; return; }
      if (itemStat.size > MAX_FILE_BYTES) { failure = 'source-file-too-large'; return; }
      totalBytes += itemStat.size;
      fileCount += 1;
      if (fileCount > MAX_BUNDLE_FILES || totalBytes > MAX_BUNDLE_BYTES) { failure = 'source-bundle-too-large'; return; }
      let content;
      try {
        content = readFileBounded(candidate, MAX_FILE_BYTES, {
          failureCode: 'source-mutated',
          tooLargeCode: 'source-file-too-large',
        });
      } catch (error) {
        failure = error.code || 'source-mutated';
        return;
      }
      entries.push({ relative, type: 'file', bytes: content.length, hash: sha256(content) });
    }
  }

  walk(root, 0);
  if (failure) return { ok: false, reason: failure, sourcePath: resolved };
  if (fileCount > MAX_BUNDLE_FILES || totalBytes > MAX_BUNDLE_BYTES) return { ok: false, reason: 'source-bundle-too-large', sourcePath: resolved };
  const entrypoint = entries.find((entry) => entry.relative === 'SKILL.md' && entry.type === 'file');
  if (!entrypoint) return { ok: false, reason: 'missing-entrypoint', sourcePath: resolved };
  return {
    ok: true,
    mode: 'folder',
    sourcePath: resolved,
    root,
    entrypointRelative: 'SKILL.md',
    entries: entries.sort((a, b) => a.relative.localeCompare(b.relative)),
    totalBytes,
    fileCount,
  };
}

function copySourceBundle(bundle, destination) {
  if (!bundle.ok) throw new RefactorError(bundle.reason, bundle.reason);
  ensureDirectory(destination, 0o700);
  for (const entry of bundle.entries) {
    const target = path.join(destination, entry.relative);
    if (!isWithin(destination, target)) throw new RefactorError('source-path-escape', 'snapshot path escaped its destination');
    ensureDirectory(path.dirname(target), 0o700);
    if (entry.type === 'symlink') {
      const targetDestination = path.join(destination, entry.targetRelative);
      const link = path.relative(path.dirname(target), targetDestination) || '.';
      fs.symlinkSync(link, target);
      continue;
    }
    const source = bundle.mode === 'legacy' ? bundle.sourcePath : path.join(bundle.root, entry.relative);
    if (!isWithin(bundle.mode === 'legacy' ? path.dirname(bundle.sourcePath) : bundle.root, source)) throw new RefactorError('source-path-escape', 'snapshot source escaped its folder');
    const content = readFileBounded(source, MAX_FILE_BYTES, {
      failureCode: 'source-mutated',
      tooLargeCode: 'source-file-too-large',
    });
    if (content.length !== entry.bytes || sha256(content) !== entry.hash) throw new RefactorError('source-mutated', 'source changed while snapshotting');
    fs.writeFileSync(target, content, { mode: 0o600 });
    fs.chmodSync(target, 0o600);
  }
}

function sealSourceBundle(directory) {
  const root = path.resolve(directory);
  function walk(current) {
    for (const entry of fs.readdirSync(current, { withFileTypes: true })) {
      const target = path.join(current, entry.name);
      const stat = fs.lstatSync(target);
      if (stat.isSymbolicLink()) continue;
      if (stat.isDirectory()) {
        walk(target);
        fs.chmodSync(target, 0o500);
      } else if (stat.isFile()) fs.chmodSync(target, 0o400);
    }
  }
  walk(root);
  fs.chmodSync(root, 0o500);
}

function sourceBundleSummary(bundle) {
  return {
    mode: bundle.mode,
    entries: bundle.entries.map((entry) => ({
      relative: entry.relative,
      type: entry.type,
      bytes: entry.bytes || 0,
      hash: entry.hash || '',
      targetRelative: entry.targetRelative || '',
    })),
    totalBytes: bundle.totalBytes,
    fileCount: bundle.fileCount,
  };
}

function sourceBundleMatches(sourceRecord) {
  const bundle = inspectSourceBundle(sourceRecord._sourcePath || sourceRecord.sourcePath);
  if (!bundle.ok) return { ok: false, reason: bundle.reason, bundle };
  if (bundle.mode !== sourceRecord.mode || !compareEntryManifests(bundle.entries, sourceRecord.entries)) {
    return { ok: false, reason: 'source-mutated', bundle };
  }
  const entrypoint = bundle.entries.find((entry) => entry.relative === 'SKILL.md' && entry.type === 'file');
  if (!entrypoint || entrypoint.hash !== sourceRecord.entrypointHash) return { ok: false, reason: 'source-mutated', bundle };
  return { ok: true, bundle };
}

function sourceReasonSet(records) {
  const reasons = new Set();
  for (const record of records) {
    for (const reason of record.frontmatter?.reasons || []) reasons.add(reason);
    if (record.lines > MAX_ENTRYPOINT_LINES) reasons.add('entrypoint-over-500-lines');
    if (record.mutated) reasons.add('source-mutated');
    if (record.missing || record.oversized) reasons.add('source-unreadable');
    if (record.bundleReason) reasons.add(record.bundleReason);
  }
  return reasons;
}

function classifyLogicalName(name, installations) {
  const all = installations.slice().sort((a, b) => String(a.sourcePath).localeCompare(String(b.sourcePath)));
  const active = all.filter((item) => !item.inactive);
  const activeAuthor = active.filter((item) => !['plugin', 'system'].includes(item.installationKind));
  const reasons = new Set();
  if (active.length === 0) return { name, classification: 'INACTIVE', reasons: ['inactive-source'], active, activeAuthor, all };
  if (activeAuthor.length === 0) {
    const managedReasons = sourceReasonSet(active);
    managedReasons.add('managed-installation');
    return { name, classification: 'MANAGED', reasons: [...managedReasons].sort(), active, activeAuthor, all };
  }

  const project = activeAuthor.filter((item) => item.installationKind === 'project');
  const provenanceKeys = [...new Set(project.map((item) => item.provenance.key))].sort();
  if (provenanceKeys.length > 1) {
    return {
      name,
      classification: 'BLOCKED_PROVENANCE',
      reasons: ['multiple-project-provenance'],
      provenanceCount: provenanceKeys.length,
      active,
      activeAuthor,
      all,
    };
  }

  const variantHashes = [...new Set(active.map((item) => item.contentHash))].sort();
  if (variantHashes.length > 1) reasons.add('divergent-content-variants');
  const bundleHashes = [...new Set(active.map((item) => item.bundleHash).filter(Boolean))].sort();
  if (bundleHashes.length > 1) reasons.add('divergent-resource-bundles');
  if (active.some((item) => ['plugin', 'system'].includes(item.installationKind)) && (variantHashes.length > 1 || bundleHashes.length > 1)) {
    reasons.add('managed-name-collision');
  }
  const structuralReasons = sourceReasonSet(activeAuthor);
  for (const reason of structuralReasons) reasons.add(reason);
  const classification = reasons.size ? 'REFACTOR' : 'KEEP';
  if (!reasons.size) reasons.add('single-valid-variant');
  return { name, classification, reasons: [...reasons].sort(), active, activeAuthor, all, provenanceCount: provenanceKeys.length };
}

function installationAnalysis(installation, name, cache) {
  const sourcePath = path.resolve(installation._sourcePath);
  const cacheKey = existingRealPath(sourcePath);
  let entry = cache.get(cacheKey);
  if (!entry) {
    entry = readSourceEntrypoint(installation, name);
    cache.set(cacheKey, entry);
  }
  const bundle = entry.secret ? { ok: false, reason: 'secret-looking-file' } : inspectSourceBundle(sourcePath);
  const bundleHash = bundle.ok ? sha256(stableJson(sourceBundleSummary(bundle))) : '';
  const managedSystemPath = sourcePath.split(path.sep).some((component) => component.toLowerCase() === '.system');
  return {
    name,
    sourcePath,
    contentHash: installation.contentHash,
    provider: installation.provider || 'unknown',
    installationKind: managedSystemPath ? 'system' : installation.installationKind || 'unknown',
    sourceAlias: normalizeAlias(installation.sourceAlias || installation.surfaceId || 'unmapped'),
    logicalProjectId: installation.logicalProjectId || 'UNMAPPED',
    surfaceId: installation.surfaceId || 'UNMAPPED',
    inactive: isInactiveSourcePath(sourcePath),
    provenance: gitProvenance(sourcePath),
    frontmatter: entry.frontmatter,
    lines: entry.lines || 0,
    missing: entry.missing,
    oversized: entry.oversized,
    secret: entry.secret,
    mutated: Boolean(entry.mutated || (entry.actualHash && installation.contentHash && entry.actualHash !== installation.contentHash)),
    actualHash: entry.actualHash || '',
    bundleHash,
    bundleReason: bundle.ok ? '' : bundle.reason,
  };
}

function workItemId(name) {
  return `wi-${sha256(`work-item:${name}`).slice(0, 24)}`;
}

function makeVariantId(contentHash, used) {
  const full = publicHash(contentHash);
  let length = HASH_PREFIX_LENGTH;
  let candidate = `v-${full.slice(0, length)}`;
  while (used.has(candidate) && length < full.length) {
    length += 4;
    candidate = `v-${full.slice(0, length)}`;
  }
  used.add(candidate);
  return candidate;
}

function publicSkillRecord(classification, grouped, itemId) {
  const all = grouped.all;
  const active = grouped.active;
  const variants = [...new Set(active.map((item) => item.contentHash))].sort();
  const bundles = [...new Set(active.map((item) => item.bundleHash || item.contentHash))].sort();
  const providers = [...new Set(all.map((item) => item.provider))].sort();
  const kinds = [...new Set(all.map((item) => item.installationKind))].sort();
  const aliases = [...new Set(all.map((item) => normalizeAlias(item.sourceAlias)))].sort();
  const bundleInspectionFailed = active.some((item) => Boolean(item.bundleReason));
  return {
    name: classification.name,
    classification: classification.classification,
    reasons: classification.reasons,
    variantHashes: variants,
    variantHashPrefixes: variants.map(hashPrefix),
    bundleHashes: bundles,
    bundleHashPrefixes: bundles.map(hashPrefix),
    counts: {
      installations: all.length,
      activeInstallations: active.length,
      inactiveInstallations: all.length - active.length,
      variants: variants.length,
    },
    providers,
    kinds,
    aliases,
    workItemId: classification.classification === 'REFACTOR' ? itemId : null,
    state: classification.classification === 'REFACTOR' ? 'PENDING' : classification.classification === 'BLOCKED_PROVENANCE' || bundleInspectionFailed ? 'BLOCKED' : 'NOT_APPLICABLE',
  };
}

function sanitizePublic(value) {
  if (Array.isArray(value)) return value.map(sanitizePublic);
  if (!value || typeof value !== 'object') return value;
  const output = {};
  for (const [key, item] of Object.entries(value)) {
    if (/^(?:sourcePath|filePath|absolutePath|prompt|command|modelOutput|sessionId|cwd|rawPath)$/i.test(key)) continue;
    output[key] = sanitizePublic(item);
  }
  return output;
}

function assertPublicManifest(manifest) {
  const forbiddenKeys = /^(?:sourcePath|filePath|absolutePath|rawPath|prompt|command|modelOutput|sessionId|cwd)$/i;
  function visit(value) {
    if (Array.isArray(value)) {
      for (const item of value) visit(item);
      return;
    }
    if (!value || typeof value !== 'object') {
      if (typeof value === 'string' && (/\/private\/|\/Users\/|\/tmp\/|[A-Za-z]:[\\/]/.test(value))) throw new RefactorError('public-manifest-unsafe', 'public manifest contains a path');
      return;
    }
    for (const [key, item] of Object.entries(value)) {
      if (forbiddenKeys.test(key)) throw new RefactorError('public-manifest-unsafe', 'public manifest contains private fields');
      visit(item);
    }
  }
  visit(manifest);
}

function fileManifestForSources(itemSources) {
  return itemSources.map((source) => ({
    variantId: source.variantId,
    contentHash: source.contentHash,
    entrypointHash: source.entrypointHash,
    sourcePath: source.sourcePath,
    sourcePaths: [...new Set([...(source.installations || []), source.sourcePath].map((value) => path.resolve(value)))].sort(),
    mode: source.mode,
    entries: source.entries,
  }));
}

function analyzeEstate(config, inventory, options = {}) {
  const byName = new Map();
  const cache = new Map();
  for (const installation of inventory._installations || []) {
    if (!installation?._sourcePath) continue;
    const name = normalizeName(installation.name);
    if (!name) continue;
    const analyzed = installationAnalysis(installation, name, cache);
    const values = byName.get(name) || [];
    values.push(analyzed);
    byName.set(name, values);
  }

  const skills = [];
  const privateItems = {};
  const usedVariantIds = new Set();
  for (const name of [...byName.keys()].sort()) {
    const classification = classifyLogicalName(name, byName.get(name));
    const itemId = workItemId(name);
    const publicRecord = publicSkillRecord(classification, classification, itemId);
    const item = {
      name,
      workItemId: itemId,
      classification: classification.classification,
      reasons: classification.reasons,
      sources: [],
      sourceErrors: [],
    };
    if (classification.classification === 'REFACTOR') {
      const byVariant = new Map();
      for (const installation of classification.active) {
        if (installation.secret) item.sourceErrors.push('secret-looking-file');
        const sourceKey = existingRealPath(installation.sourcePath);
        const variantHash = installation.bundleHash || installation.contentHash;
        const sourceGroup = byVariant.get(variantHash) || { installations: [], sourceKeys: new Set() };
        sourceGroup.installations.push(installation);
        sourceGroup.sourceKeys.add(sourceKey);
        byVariant.set(variantHash, sourceGroup);
      }
      for (const [bundleHash, group] of [...byVariant.entries()].sort(([a], [b]) => a.localeCompare(b))) {
        const representative = group.installations.slice().sort((a, b) => a.sourcePath.localeCompare(b.sourcePath))[0];
        const variantId = makeVariantId(bundleHash, usedVariantIds);
        if (representative.secret) {
          item.sourceErrors.push('secret-looking-file');
          continue;
        }
        const bundle = inspectSourceBundle(representative.sourcePath);
        if (!bundle.ok) {
          item.sourceErrors.push(bundle.reason);
          continue;
        }
        try {
          const source = {
            variantId,
            contentHash: bundleHash,
            entrypointHash: representative.contentHash,
            sourcePath: representative.sourcePath,
            mode: bundle.mode,
            entries: sourceBundleSummary(bundle).entries,
            totalBytes: bundle.totalBytes,
            fileCount: bundle.fileCount,
            provenance: representative.provenance,
            installations: [...group.sourceKeys].sort(),
          };
          item.sources.push(source);
        } catch (error) {
          item.sourceErrors.push(error.code || 'source-snapshot-failed');
        }
      }
      if (item.sourceErrors.length) publicRecord.reasons = [...new Set([...publicRecord.reasons, ...item.sourceErrors])].sort();
      privateItems[itemId] = item;
    }
    skills.push(publicRecord);
  }

  const counts = {
    classifications: Object.fromEntries(CLASSIFICATIONS.map((state) => [state, skills.filter((item) => item.classification === state).length])),
    installations: (inventory._installations || []).length,
    uniqueNames: skills.length,
    variants: new Set((inventory._installations || []).map((item) => `${normalizeName(item.name)}\u0000${item.contentHash}`)).size,
  };
  const publicBase = { schemaVersion: SCHEMA_VERSION, tool: TOOL, skills, counts };
  const privateBase = { schemaVersion: SCHEMA_VERSION, items: privateItems };
  const scanFingerprint = sha256(stableJson({
    config: config,
    public: publicBase,
    provenance: privateBase,
  }));
  return { skills, counts, privateItems, scanFingerprint, inventory };
}

function scanManifest(fingerprint, analysis) {
  const items = analysis.skills.map((skill) => ({
    name: skill.name,
    classification: skill.classification,
    reasons: skill.reasons,
    variantHashes: skill.variantHashes,
    variantHashPrefixes: skill.variantHashPrefixes,
    bundleHashes: skill.bundleHashes,
    bundleHashPrefixes: skill.bundleHashPrefixes,
    counts: skill.counts,
    providers: skill.providers,
    kinds: skill.kinds,
    aliases: skill.aliases,
    workItemId: skill.workItemId,
    state: skill.state,
  }));
  const manifest = sanitizePublic({
    schemaVersion: SCHEMA_VERSION,
    tool: TOOL,
    scanFingerprint: fingerprint,
    items,
    counts: analysis.counts,
  });
  assertPublicManifest(manifest);
  return manifest;
}

function itemDirectory(workspace, name) {
  const normalized = normalizeName(name);
  if (!normalized || normalized !== name || normalized.includes('..') || path.isAbsolute(normalized)) throw new RefactorError('workspace-invalid', 'invalid logical skill name');
  const directory = path.resolve(workspace, 'work-items', normalized);
  if (!isWithin(workspace, directory)) throw new RefactorError('workspace-invalid', 'work item escaped workspace');
  return directory;
}

function manifestFile(workspace) {
  return path.join(workspace, 'manifest.json');
}

function provenanceFile(workspace) {
  return path.join(workspace, 'provenance.json');
}

function loadManifest(workspace) {
  const manifest = readJson(manifestFile(workspace), 'workspace-missing');
  if (manifest.schemaVersion !== SCHEMA_VERSION || manifest.tool !== TOOL || !Array.isArray(manifest.items)) throw new RefactorError('workspace-schema-incompatible', 'workspace schema is incompatible');
  return manifest;
}

function loadProvenance(workspace) {
  const provenance = readJson(provenanceFile(workspace), 'workspace-incomplete');
  if (provenance.schemaVersion !== SCHEMA_VERSION || !provenance.items || typeof provenance.items !== 'object') throw new RefactorError('workspace-schema-incompatible', 'workspace schema is incompatible');
  if (provenance.configPath !== undefined && (typeof provenance.configPath !== 'string' || !path.isAbsolute(provenance.configPath))) throw new RefactorError('workspace-schema-incompatible', 'workspace config path is incompatible');
  if (provenance.frameworkRoot !== undefined && (typeof provenance.frameworkRoot !== 'string' || !path.isAbsolute(provenance.frameworkRoot))) throw new RefactorError('workspace-schema-incompatible', 'workspace framework root is incompatible');
  if (provenance.home !== undefined && (typeof provenance.home !== 'string' || !path.isAbsolute(provenance.home))) throw new RefactorError('workspace-schema-incompatible', 'workspace home is incompatible');
  return provenance;
}

function stateFile(workspace, name) {
  return path.join(itemDirectory(workspace, name), 'state.json');
}

function loadItemState(workspace, skill) {
  if (!skill.workItemId) return { state: skill.state || 'NOT_APPLICABLE', attempts: 0, workItemId: null, name: skill.name };
  const state = readJson(stateFile(workspace, skill.name), 'workspace-incomplete');
  if (state.schemaVersion !== SCHEMA_VERSION || state.workItemId !== skill.workItemId || state.name !== skill.name || !JOB_STATES.includes(state.state)) throw new RefactorError('workspace-schema-incompatible', 'work item state is incompatible');
  return state;
}

function workspaceSafetyContext(workspace, provenance) {
  const configPath = provenance.configPath || defaultConfigPath();
  let config;
  try { config = gardener.loadConfig(configPath); } catch (error) { throw new RefactorError(error.message || 'config-invalid', error.message || 'config-invalid'); }
  const home = provenance.home || os.homedir();
  const frameworkRoot = provenance.frameworkRoot || defaultFrameworkRoot();
  const inventory = inventoryForConfig(config, { home, frameworkRoot });
  validateWorkspaceLocation(workspace, config, inventory, { home, frameworkRoot });
  return { config, inventory, configPath, home, frameworkRoot };
}

function assertWorkspaceSafe(workspace) {
  const target = pathKey(workspace);
  let stat;
  try { stat = fs.lstatSync(target); } catch { throw new RefactorError('workspace-invalid', 'workspace is unavailable'); }
  if (!stat.isDirectory() || stat.isSymbolicLink()) throw new RefactorError('workspace-unsafe', 'workspace path is not a directory');
  const provenance = loadProvenance(target);
  return workspaceSafetyContext(target, provenance);
}

function loadedWorkspace(workspace) {
  const target = pathKey(workspace);
  const provenance = loadProvenance(target);
  const safety = workspaceSafetyContext(target, provenance);
  const manifest = loadManifest(target);
  const entries = manifest.items.map((skill) => ({ skill, state: loadItemState(target, skill), privateItem: provenance.items[skill.workItemId] || null }));
  return { workspace: target, manifest, provenance, entries, ...safety };
}

function writeItemState(workspace, name, state) {
  writeJsonAtomic(stateFile(workspace, name), state, 0o600);
}

function updateManifestStateUnsafe(workspace, name, state) {
  const manifest = loadManifest(workspace);
  const skill = manifest.items.find((item) => item.name === name);
  if (!skill) throw new RefactorError('workspace-incomplete', 'work item is missing from manifest');
  skill.state = state;
  assertPublicManifest(manifest);
  writeJsonAtomic(manifestFile(workspace), manifest, 0o644);
}

const TRANSITIONS = Object.freeze({
  PENDING: new Set(['RUNNING', 'BLOCKED', 'FAILED']),
  RUNNING: new Set(['GENERATED', 'BLOCKED', 'FAILED']),
  GENERATED: new Set(['VALIDATED', 'BLOCKED', 'FAILED']),
  VALIDATED: new Set(['BLOCKED', 'FAILED']),
});

function transitionItem(workspace, skill, nextState, patch = {}) {
  assertWorkspaceSafe(workspace);
  return withStateLock(workspace, () => {
    assertWorkspaceSafe(workspace);
    const current = loadItemState(workspace, skill);
    if (current.state !== nextState && !TRANSITIONS[current.state]?.has(nextState)) throw new RefactorError('invalid-state-transition', 'invalid work item state transition');
    const next = { ...current, ...patch, schemaVersion: SCHEMA_VERSION, name: skill.name, workItemId: skill.workItemId, state: nextState };
    writeItemState(workspace, skill.name, next);
    updateManifestStateUnsafe(workspace, skill.name, nextState);
    return next;
  });
}

function recoverableState(workspace, skill, state, patch = {}) {
  assertWorkspaceSafe(workspace);
  return withStateLock(workspace, () => {
    assertWorkspaceSafe(workspace);
    const next = { ...state, ...patch, schemaVersion: SCHEMA_VERSION, name: skill.name, workItemId: skill.workItemId };
    writeItemState(workspace, skill.name, next);
    updateManifestStateUnsafe(workspace, skill.name, next.state);
    return next;
  });
}

function itemPrivateSources(workspace, skill, privateItem) {
  if (!privateItem || !Array.isArray(privateItem.sources)) return [];
  return privateItem.sources.map((source) => ({ ...source, sourcePath: path.resolve(source.sourcePath) }));
}

function revalidateItemSources(workspace, skill, privateItem) {
  const sources = itemPrivateSources(workspace, skill, privateItem);
  if (!sources.length) return { ok: false, reason: 'no-safe-source-snapshot', sources: [] };
  const results = [];
  for (const source of sources) {
    const sourcePaths = [...new Set([...(source.sourcePaths || []), source.sourcePath].filter(Boolean).map((value) => path.resolve(value)))];
    for (const sourcePath of sourcePaths) {
      results.push({ source: { ...source, sourcePath }, result: sourceBundleMatches({ ...source, sourcePath }) });
    }
  }
  const failed = results.find((entry) => !entry.result.ok);
  return failed ? { ok: false, reason: failed.result.reason || 'source-mutated', sources: results } : { ok: true, sources: results };
}

function revalidateItemSnapshots(workspace, skill, privateItem) {
  const sources = itemPrivateSources(workspace, skill, privateItem);
  if (!sources.length) return { ok: false, reason: 'no-safe-source-snapshot', sources: [] };
  const results = sources.map((source) => {
    const snapshotEntrypoint = path.join(itemDirectory(workspace, skill.name), 'sources', source.variantId, 'SKILL.md');
    const bundle = inspectSourceBundle(snapshotEntrypoint);
    if (!bundle.ok) return { source: { ...source, sourcePath: snapshotEntrypoint }, result: { ok: false, reason: bundle.reason, bundle } };
    const entrypoint = bundle.entries.find((entry) => entry.relative === 'SKILL.md' && entry.type === 'file');
    const matches = compareEntryManifests(bundle.entries, source.entries) && entrypoint?.hash === source.entrypointHash;
    return {
      source: { ...source, sourcePath: snapshotEntrypoint },
      result: matches ? { ok: true, bundle } : { ok: false, reason: 'source-snapshot-mutated', bundle },
    };
  });
  const failed = results.find((entry) => !entry.result.ok);
  return failed ? { ok: false, reason: 'source-snapshot-mutated', sources: results } : { ok: true, sources: results };
}

function writeSourceManifests(workspace, item, privateItem) {
  const directory = itemDirectory(workspace, item.name);
  ensureDirectory(directory, 0o700);
  for (const source of privateItem.sources || []) {
    writeJsonAtomic(path.join(directory, 'source-manifests', `${source.variantId}.json`), {
      schemaVersion: SCHEMA_VERSION,
      variantId: source.variantId,
      contentHash: source.contentHash,
      entrypointHash: source.entrypointHash,
      mode: source.mode,
      entries: source.entries,
      totalBytes: source.totalBytes,
      fileCount: source.fileCount,
    }, 0o600);
  }
}

function coveragePath(workspace, skill) {
  return path.join(itemDirectory(workspace, skill.name), 'coverage.md');
}

function writeCoverageReceipt(workspace, skill, privateItem, status = 'prepared') {
  const lines = [
    '# Candidate coverage receipt',
    '',
    `logical-name: ${skill.name}`,
    `status: ${status}`,
    '',
    'source variants:',
  ];
  for (const source of privateItem?.sources || []) {
    lines.push(`- ${source.variantId}: ${source.contentHash}`);
    lines.push('  preservation-decision: PENDING');
  }
  lines.push('');
  writeAtomic(coveragePath(workspace, skill), `${lines.join('\n')}\n`, 0o600);
}

function stageContract(workspace, skill) {
  const source = defaultContractPath();
  const target = path.join(itemDirectory(workspace, skill.name), 'contract', 'SKILL.md');
  if (!fs.existsSync(source)) throw new RefactorError('contract-missing', 'skill-creator contract is unavailable');
  ensureDirectory(path.dirname(target), 0o700);
  const content = readFileBounded(source, MAX_FILE_BYTES, {
    failureCode: 'contract-invalid',
    tooLargeCode: 'contract-invalid',
  });
  writeAtomic(target, content, 0o600);
  return target;
}

function makePrompt(skill, privateItem) {
  const sources = (privateItem.sources || []).map((source) => `- sources/${source.variantId} (variant hash ${source.contentHash})`);
  return [
    'You are creating one isolated candidate skill for review.',
    '',
    `Logical skill name: ${skill.name}`,
    `Classification reasons: ${(skill.reasons || []).join(', ')}`,
    '',
    'Read the skill-creator contract at contract/SKILL.md before editing.',
    'Source snapshots are read-only and relative to this work item:',
    ...sources,
    '',
    `Edit only candidate/${skill.name} and coverage.md. Never touch live paths, source snapshots, sibling work items, or the workspace outside this item.`,
    'Create a valid SKILL.md with normalized matching name and a discriminating description.',
    'Preserve operational invariants, invocation policy, resources, and useful progressive disclosure. Do not add README.md or changelog files.',
    'In coverage.md, change status to completed and replace every PENDING value with a concrete preservation or reconciliation decision for that exact source hash.',
    'Use the source variants as evidence; do not apply, install, archive, delete, symlink, or modify any live skill.',
    '',
    'Do not include absolute paths, credentials, tokens, or model/session details in coverage.md.',
    '',
  ].join('\n');
}

function stageWorkItem(workspace, publicSkill, privateItem) {
  const directory = itemDirectory(workspace, publicSkill.name);
  ensureDirectory(directory, 0o700);
  ensureDirectory(path.join(directory, 'sources'), 0o700);
  ensureDirectory(path.join(directory, 'candidate'), 0o700);
  ensureDirectory(path.join(directory, 'attempts'), 0o700);
  let snapshotError = null;
  for (const source of privateItem.sources || []) {
    try {
      const bundle = inspectSourceBundle(source.sourcePath);
      if (!bundle.ok) throw new RefactorError(bundle.reason, bundle.reason);
      if (!compareEntryManifests(bundle.entries, source.entries)) throw new RefactorError('source-mutated', 'source changed before snapshot');
      copySourceBundle(bundle, path.join(directory, 'sources', source.variantId));
      sealSourceBundle(path.join(directory, 'sources', source.variantId));
    } catch (error) {
      snapshotError = error.code || 'source-snapshot-failed';
      break;
    }
  }
  writeSourceManifests(workspace, publicSkill, privateItem);
  writeCoverageReceipt(workspace, publicSkill, privateItem);
  if (snapshotError || privateItem.sourceErrors?.length) {
    const reason = snapshotError || privateItem.sourceErrors[0];
    const state = {
      schemaVersion: SCHEMA_VERSION,
      workItemId: publicSkill.workItemId,
      name: publicSkill.name,
      state: 'BLOCKED',
      reason,
      attempts: 0,
      pid: null,
      delegatePid: null,
      createdAt: isoNow(),
    };
    writeItemState(workspace, publicSkill.name, state);
    publicSkill.state = 'BLOCKED';
    return state;
  }
  writeAtomic(path.join(directory, 'task.md'), `${makePrompt(publicSkill, privateItem)}\n`, 0o600);
  const state = {
    schemaVersion: SCHEMA_VERSION,
    workItemId: publicSkill.workItemId,
    name: publicSkill.name,
    state: 'PENDING',
    reason: '',
    attempts: 0,
    pid: null,
    delegatePid: null,
    createdAt: isoNow(),
  };
  writeItemState(workspace, publicSkill.name, state);
  return state;
}

function workspaceHasFiles(directory) {
  try { return fs.readdirSync(directory).length > 0; } catch { return false; }
}

function scanWorkspace(options = {}) {
  const configPath = path.resolve(options.configPath || defaultConfigPath());
  let config;
  try { config = gardener.loadConfig(configPath); } catch (error) { throw new RefactorError(error.message || 'config-invalid', error.message || 'config-invalid'); }
  const home = options.home || os.homedir();
  const frameworkRoot = options.frameworkRoot || defaultFrameworkRoot();
  const inventory = inventoryForConfig(config, { home, frameworkRoot });
  const workspace = validateWorkspaceLocation(options.workspace, config, inventory, { home, frameworkRoot });
  let existing = false;
  try { existing = fs.existsSync(workspace); } catch { existing = false; }
  if (existing && !fs.statSync(workspace).isDirectory()) throw new RefactorError('workspace-unsafe', 'workspace path is not a directory');
  const analysis = analyzeEstate(config, inventory, { home, frameworkRoot });
  const manifest = scanManifest(analysis.scanFingerprint, analysis);

  if (existing && fs.existsSync(manifestFile(workspace))) {
    const current = loadManifest(workspace);
    if (current.scanFingerprint !== manifest.scanFingerprint) throw new RefactorError('workspace-scan-mismatch', 'workspace already contains a different scan');
    loadProvenance(workspace);
    return { status: 'READY', changed: false, manifest: current, analysis, workspace };
  }
  if (existing && workspaceHasFiles(workspace)) throw new RefactorError('workspace-incomplete', 'workspace contains state without a compatible manifest');
  ensureWorkspace(workspace);
  ensureDirectory(path.join(workspace, 'work-items'), 0o700);
  const privateItems = {};
  for (const skill of analysis.skills) {
    if (skill.classification !== 'REFACTOR') continue;
    const privateItem = analysis.privateItems[skill.workItemId] || { name: skill.name, sources: [], sourceErrors: ['no-safe-source-snapshot'] };
    privateItems[skill.workItemId] = {
      name: privateItem.name,
      workItemId: privateItem.workItemId,
      classification: privateItem.classification,
      reasons: privateItem.reasons,
      sourceErrors: privateItem.sourceErrors || [],
      sources: fileManifestForSources(privateItem.sources || []),
    };
    stageWorkItem(workspace, skill, privateItem);
  }
  const provenance = {
    schemaVersion: SCHEMA_VERSION,
    scanFingerprint: analysis.scanFingerprint,
    configPath,
    home,
    frameworkRoot,
    items: privateItems,
  };
  writeJsonAtomic(provenanceFile(workspace), provenance, 0o600);
  for (const skill of analysis.skills) {
    if (skill.classification === 'REFACTOR') {
      const state = readJson(stateFile(workspace, skill.name), 'workspace-incomplete');
      skill.state = state.state;
    }
  }
  const finalManifest = scanManifest(analysis.scanFingerprint, analysis);
  writeJsonAtomic(manifestFile(workspace), finalManifest, 0o644);
  return { status: 'READY', changed: true, manifest: finalManifest, analysis, workspace };
}

function processStartMarker(pid) {
  if (!Number.isInteger(pid) || pid <= 0) return '';
  const procStat = `/proc/${pid}/stat`;
  let fd;
  try {
    fd = fs.openSync(procStat, fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW || 0));
    const stat = fs.fstatSync(fd);
    if (stat.size > 0 && stat.size > 4096) return '';
    const buffer = Buffer.alloc(4096);
    const bytes = fs.readSync(fd, buffer, 0, buffer.length, 0);
    const text = buffer.subarray(0, bytes).toString('utf8');
    const endOfCommand = text.lastIndexOf(')');
    const fields = endOfCommand < 0 ? [] : text.slice(endOfCommand + 1).trim().split(/\s+/);
    return fields[19] || '';
  } catch {
    try {
      return execFileSync('ps', ['-p', String(pid), '-o', 'lstart='], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], maxBuffer: 1024 }).trim();
    } catch {
      return '';
    }
  } finally {
    if (fd !== undefined) {
      try { fs.closeSync(fd); } catch { /* best effort */ }
    }
  }
}

function isPidAlive(pid, startMarker = '') {
  if (!Number.isInteger(pid) || pid <= 0) return false;
  try {
    process.kill(pid, 0);
    if (!startMarker) return true;
    const currentMarker = processStartMarker(pid);
    return !currentMarker || currentMarker === startMarker;
  } catch (error) { return error.code === 'EPERM'; }
}

function readLockOwner(target) {
  try {
    return JSON.parse(readFileBounded(target, 16 * 1024, {
      failureCode: 'lock-read-failed',
      tooLargeCode: 'lock-invalid',
    }).toString('utf8'));
  } catch {
    return null;
  }
}

function sameLockOwner(expected, actual) {
  if (!expected || !actual) return false;
  if (expected.token && actual.token) return expected.token === actual.token;
  if (expected.device !== undefined && actual.device !== undefined && expected.device !== actual.device) return false;
  if (expected.inode !== undefined && actual.inode !== undefined && expected.inode !== actual.inode) return false;
  return expected.pid === actual.pid && expected.createdAt === actual.createdAt;
}

function releaseExclusiveLock(lock) {
  if (lock?.fd === undefined) return;
  try {
    const stat = fs.fstatSync(lock.fd);
    if (stat.dev !== lock.device || stat.ino !== lock.inode) return;
    const released = { ...lock.owner, releasedAt: isoNow() };
    const payload = Buffer.from(JSON.stringify(released));
    fs.ftruncateSync(lock.fd, 0);
    fs.writeSync(lock.fd, payload, 0, payload.length, 0);
    fs.fsyncSync(lock.fd);
  } catch { /* a failed release remains conservatively locked */ }
  finally {
    try { fs.closeSync(lock.fd); } catch { /* best effort */ }
  }
}

function acquireExclusiveLock(target) {
  const resolved = path.resolve(target);
  ensureDirectory(path.dirname(resolved), 0o700);
  for (let attempt = 0; attempt < 4; attempt += 1) {
    const token = crypto.randomBytes(16).toString('hex');
    const staged = `${resolved}.owner-${process.pid}-${token}`;
    let fd;
    try {
      fd = fs.openSync(staged, 'wx', 0o600);
      const fileStat = fs.fstatSync(fd);
      const owner = {
        pid: process.pid,
        startMarker: processStartMarker(process.pid),
        token,
        device: fileStat.dev,
        inode: fileStat.ino,
        createdAt: isoNow(),
      };
      fs.writeFileSync(fd, JSON.stringify(owner));
      fs.fsyncSync(fd);
      fs.linkSync(staged, resolved);
      fs.unlinkSync(staged);
      const lockFd = fd;
      fd = undefined;
      return () => releaseExclusiveLock({ target: resolved, token, device: fileStat.dev, inode: fileStat.ino, fd: lockFd, owner });
    } catch (error) {
      if (fd !== undefined) {
        try { fs.closeSync(fd); } catch { /* best effort */ }
      }
      try { fs.unlinkSync(staged); } catch { /* exact private staging path only */ }
      if (error.code !== 'EEXIST') throw error;
      let observedStat;
      try { observedStat = fs.lstatSync(resolved); } catch { continue; }
      const owner = readLockOwner(resolved);
      if (owner?.pid && !owner.releasedAt && isPidAlive(owner.pid, owner.startMarker)) return null;
      const currentOwner = readLockOwner(resolved);
      let currentStat;
      try { currentStat = fs.lstatSync(resolved); } catch { continue; }
      if (!sameFileIdentity(observedStat, currentStat) || (owner && currentOwner && !sameLockOwner(owner, currentOwner))) continue;
      const stalePath = `${resolved}.stale-${process.pid}-${crypto.randomBytes(6).toString('hex')}`;
      try { fs.renameSync(resolved, stalePath); } catch (renameError) {
        if (renameError.code === 'ENOENT') continue;
        return null;
      }
      const movedOwner = readLockOwner(stalePath);
      let movedStat;
      try { movedStat = fs.lstatSync(stalePath); } catch { movedStat = null; }
      if (!movedStat || !sameFileObject(observedStat, movedStat) || (owner && !sameLockOwner(owner, movedOwner))) {
        try { if (!fs.existsSync(resolved)) fs.renameSync(stalePath, resolved); } catch { /* preserve an unproven lock */ }
        return null;
      }
      try { fs.unlinkSync(stalePath); } catch { /* exact stale path only */ }
    }
  }
  return null;
}

function withStateLock(workspace, callback) {
  const unlock = acquireExclusiveLock(path.join(path.resolve(workspace), STATE_LOCK_NAME));
  if (!unlock) throw new RefactorError('state-busy', 'workspace state is busy');
  try { return callback(); } finally { unlock(); }
}

function acquireLock(workspace, skill) {
  return acquireExclusiveLock(path.join(itemDirectory(workspace, skill.name), '.claim.lock'));
}

function redactPrivateText(value) {
  return String(value || '')
    .replace(/(?:\/Users\/|\/private\/|\/tmp\/|[A-Za-z]:[\\/])[^\n\r ]+/g, '[path-redacted]')
    .replace(/(?:token|secret|password|cookie|credential)[=:][^\s\n\r]+/gi, '[secret-redacted]');
}

function writeAttemptArtifacts(directory, attempt, resultPath, stderr) {
  const attempts = path.join(directory, 'attempts');
  ensureDirectory(attempts, 0o700);
  if (fs.existsSync(resultPath)) {
    try {
      const content = readFileBounded(resultPath, MAX_RESULT_BYTES, {
        failureCode: 'result-read-failed',
        tooLargeCode: 'result-too-large',
      });
      writeAtomic(path.join(attempts, `attempt-${attempt}.result`), content, 0o600);
    } catch (error) {
      if (error.code === 'result-too-large') writeAtomic(path.join(attempts, `attempt-${attempt}.result`), '[result-redacted: oversized]\n', 0o600);
      /* preserve the state even if artifact copy fails */
    }
  }
  writeAtomic(path.join(attempts, `attempt-${attempt}.stderr`), redactPrivateText(String(stderr || '').slice(-MAX_STDERR_BYTES)), 0o600);
}

const DELEGATE_ENV_ALLOWLIST = Object.freeze([
  'HOME', 'PATH', 'TMPDIR', 'TMP', 'TEMP', 'LANG', 'LC_ALL', 'LC_CTYPE', 'TZ', 'USER', 'LOGNAME', 'SHELL', 'CODEX_HOME',
  'FAKE_DELEGATE_FAIL', 'FAKE_COUNTER', 'FAKE_ENV_OUTPUT', 'FAKE_DELAY_MS',
]);

function minimalDelegateEnv(cwd) {
  const env = {};
  for (const key of DELEGATE_ENV_ALLOWLIST) {
    if (process.env[key] !== undefined) env[key] = process.env[key];
  }
  env.CODEX_DELEGATE_SANDBOX = 'workspace-write';
  env.CODEX_DELEGATE_CWD = cwd;
  return env;
}

function trustedDelegatePath(delegatePath, allowTestDelegate = false) {
  if (typeof delegatePath !== 'string' || !path.isAbsolute(delegatePath)) return false;
  const target = path.resolve(delegatePath);
  let stat;
  try {
    const lexical = fs.lstatSync(target);
    if (lexical.isSymbolicLink() || !lexical.isFile()) return false;
    stat = fs.statSync(target);
  } catch {
    return false;
  }
  if (process.platform !== 'win32' && (stat.mode & 0o111) === 0) return false;
  const production = path.resolve(path.join(os.homedir(), '.codex', 'bin', 'codex-delegate.sh'));
  if (target === production) return true;
  return allowTestDelegate === true;
}

function openPinnedDelegate(delegatePath, allowTestDelegate = false) {
  if (!trustedDelegatePath(delegatePath, allowTestDelegate)) throw new RefactorError('delegate-untrusted', 'delegate path is not trusted');
  const target = path.resolve(delegatePath);
  const production = path.resolve(path.join(os.homedir(), '.codex', 'bin', 'codex-delegate.sh'));
  if (allowTestDelegate && target !== production) {
    return { executable: target, prefixArgs: [], fd: undefined, stdio: ['ignore', 'pipe', 'pipe'] };
  }
  let fd;
  try {
    const pathBefore = fs.lstatSync(target);
    fd = fs.openSync(target, fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW || 0));
    const opened = fs.fstatSync(fd);
    const pathAfter = fs.lstatSync(target);
    if (!opened.isFile() || !sameFileIdentity(pathBefore, opened) || !sameFileIdentity(opened, pathAfter)) {
      throw new RefactorError('delegate-untrusted', 'delegate changed while being opened');
    }
    return { executable: '/bin/bash', prefixArgs: ['/dev/fd/3'], fd, stdio: ['ignore', 'pipe', 'pipe', fd] };
  } catch (error) {
    if (fd !== undefined) try { fs.closeSync(fd); } catch { /* best effort */ }
    if (error instanceof RefactorError) throw error;
    throw new RefactorError('delegate-untrusted', 'delegate could not be pinned');
  }
}

function signalDelegate(child, signal) {
  if (!child?.pid) return;
  try {
    if (process.platform !== 'win32') process.kill(-child.pid, signal);
    else child.kill(signal);
  } catch { /* exact process group may have already exited */ }
}

function spawnDelegate(delegatePath, taskPath, resultPath, cwd, options = {}) {
  return new Promise((resolve) => {
    let child;
    let pinned;
    let settled = false;
    let timeout;
    const finish = (result) => {
      if (settled) return;
      settled = true;
      if (timeout) clearTimeout(timeout);
      resolve(result);
    };
    try {
      pinned = openPinnedDelegate(delegatePath, options.allowTestDelegate === true);
      child = spawn(pinned.executable, [...pinned.prefixArgs, 'coder', taskPath, resultPath, cwd], {
        cwd,
        env: minimalDelegateEnv(cwd),
        detached: process.platform !== 'win32',
        stdio: pinned.stdio,
      });
      if (pinned.fd !== undefined) {
        fs.closeSync(pinned.fd);
        pinned.fd = undefined;
      }
    } catch (error) {
      if (pinned?.fd !== undefined) try { fs.closeSync(pinned.fd); } catch { /* best effort */ }
      finish({ code: -1, signal: null, stderr: String(error.message || error), child: null });
      return;
    }
    let stderr = '';
    let stdout = '';
    child.stderr.on('data', (chunk) => { stderr = `${stderr}${chunk}`.slice(-MAX_STDERR_BYTES); });
    child.stdout.on('data', (chunk) => { stdout = `${stdout}${chunk}`.slice(-MAX_STDERR_BYTES); });
    child.once('error', (error) => finish({ code: -1, signal: null, stderr: `${stderr}\n${error.message || error}`, stdout, child }));
    child.once('close', (code, signal) => finish({ code: Number.isInteger(code) ? code : -1, signal, stderr, stdout, child }));
    const timeoutMs = Number.isSafeInteger(options.timeoutMs) ? Math.max(10, options.timeoutMs) : DEFAULT_DELEGATE_TIMEOUT_MS;
    timeout = setTimeout(() => {
      stderr = `${stderr}\ndelegate-timeout`;
      signalDelegate(child, 'SIGTERM');
      const force = setTimeout(() => signalDelegate(child, 'SIGKILL'), DELEGATE_KILL_GRACE_MS);
      force.unref?.();
    }, timeoutMs);
    timeout.unref?.();
    if (options.onSpawn) options.onSpawn(child);
  });
}

function candidateFileEntries(candidateRoot) {
  const lexicalRoot = path.resolve(candidateRoot);
  let lexicalStat;
  try { lexicalStat = fs.lstatSync(lexicalRoot); } catch { return { ok: false, reasons: ['candidate-missing'], entries: [] }; }
  if (lexicalStat.isSymbolicLink()) return { ok: false, reasons: ['candidate-path-escape'], entries: [] };
  const root = existingRealPath(lexicalRoot);
  if (root !== lexicalRoot) return { ok: false, reasons: ['candidate-path-escape'], entries: [] };
  let rootStat;
  try { rootStat = fs.lstatSync(root); } catch { return { ok: false, reasons: ['candidate-missing'], entries: [] }; }
  if (!rootStat.isDirectory() || rootStat.isSymbolicLink()) return { ok: false, reasons: ['candidate-not-folder'], entries: [] };
  const entries = [];
  const visited = new Set();
  let totalBytes = 0;
  let regularFiles = 0;
  const reasons = [];
  function walk(directory, depth) {
    if (reasons.length) return;
    if (depth > 32) { reasons.push('candidate-depth-exceeded'); return; }
    let real;
    try { real = fs.realpathSync(directory); } catch { reasons.push('candidate-path-escape'); return; }
    if (!isWithin(root, real)) { reasons.push('candidate-path-escape'); return; }
    if (visited.has(real)) return;
    visited.add(real);
    let diskEntries;
    try { diskEntries = fs.readdirSync(directory, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name)); } catch { reasons.push('candidate-unreadable'); return; }
    for (const diskEntry of diskEntries) {
      const full = path.join(directory, diskEntry.name);
      const relative = safeRelative(root, full);
      if (isSecretLookingPath(relative)) { reasons.push('secret-looking-file'); return; }
      let stat;
      try { stat = fs.lstatSync(full); } catch { reasons.push('candidate-unreadable'); return; }
      if (stat.isSymbolicLink()) {
        let target;
        try { target = fs.realpathSync(full); } catch { reasons.push('candidate-path-escape'); return; }
        if (!isWithin(root, target) || isSecretLookingPath(safeRelative(root, target))) { reasons.push('candidate-path-escape'); return; }
        entries.push({ relative, type: 'symlink', bytes: 0, hash: sha256(fs.readlinkSync(full)), targetRelative: safeRelative(root, target) });
        continue;
      }
      if (stat.isDirectory()) { walk(full, depth + 1); continue; }
      if (!stat.isFile()) { reasons.push('candidate-special-file'); return; }
      if (stat.size > MAX_FILE_BYTES) { reasons.push('candidate-file-too-large'); return; }
      totalBytes += stat.size;
      regularFiles += 1;
      if (regularFiles > MAX_BUNDLE_FILES || totalBytes > MAX_BUNDLE_BYTES) { reasons.push('candidate-bundle-too-large'); return; }
      let content;
      try {
        content = readFileBounded(full, MAX_FILE_BYTES, {
          failureCode: 'candidate-unreadable',
          tooLargeCode: 'candidate-file-too-large',
        });
      } catch (error) {
        reasons.push(error.code || 'candidate-unreadable');
        return;
      }
      entries.push({ relative, type: 'file', bytes: content.length, hash: sha256(content) });
    }
  }
  walk(root, 0);
  return {
    ok: reasons.length === 0,
    reasons: [...new Set(reasons)],
    entries: entries.sort((a, b) => a.relative.localeCompare(b.relative)),
    totalBytes,
    fileCount: regularFiles,
  };
}

function markdownReferences(content) {
  const references = [];
  const text = String(content || '').replace(/```[\s\S]*?```/g, '');
  const pattern = /!?(?:\[[^\]]*\])\(([^)]+)\)/g;
  let match;
  while ((match = pattern.exec(text))) {
    let reference = match[1].trim().replace(/^<|>$/g, '');
    if (reference.startsWith('<') && reference.includes('>')) reference = reference.slice(1, reference.indexOf('>'));
    reference = reference.split(/[?#]/, 1)[0].trim();
    if (!reference || reference.startsWith('#') || /^[a-z][a-z0-9+.-]*:/i.test(reference)) continue;
    references.push(reference);
  }
  return [...new Set(references)];
}

function openaiDefaultPrompt(content) {
  const match = String(content || '').match(/(?:^|\n)[ \t]*default_prompt[ \t]*:[ \t]*(?:"((?:\\.|[^"\\])*)"|'([^']*)'|([^\n#]*))/m);
  if (!match) return '';
  return String(match[1] ?? match[2] ?? match[3] ?? '').replace(/\\([\\"])/g, '$1').trim();
}

function validateCandidate(candidateRoot, name, sourceHashes = [], options = {}) {
  const root = existingRealPath(path.resolve(candidateRoot));
  const files = candidateFileEntries(root);
  const reasons = [...files.reasons];
  const skillPath = path.join(root, 'SKILL.md');
  let skillContent = '';
  if (!reasons.length) {
    try {
      skillContent = readFileBounded(skillPath, MAX_FILE_BYTES, {
        failureCode: 'candidate-unreadable',
        tooLargeCode: 'candidate-file-too-large',
      }).toString('utf8');
    } catch (error) {
      reasons.push(error.code === 'candidate-file-too-large' ? error.code : 'missing-skill-md');
    }
  }
  if (!fs.existsSync(skillPath)) reasons.push('missing-skill-md');
  const frontmatter = skillContent ? frontmatterContract(skillContent, name) : { valid: false, reasons: ['frontmatter-delimiters'] };
  if (!frontmatter.valid) reasons.push(...frontmatter.reasons);
  const corpus = files.entries.filter((entry) => entry.type === 'file');
  for (const entry of corpus) {
    const file = path.join(root, entry.relative);
    let bytes;
    let content;
    try {
      bytes = readFileBounded(file, MAX_FILE_BYTES, {
        failureCode: 'candidate-unreadable',
        tooLargeCode: 'candidate-file-too-large',
      });
      content = bytes.toString('utf8');
    } catch (error) {
      reasons.push(error.code || 'candidate-unreadable');
      continue;
    }
    if (entry.bytes !== bytes.length || entry.hash !== sha256(bytes)) reasons.push('candidate-mutated');
    if (/(?:^|\n)[ \t]*(?:TODO|FIXME)(?:[ \t]*:.*)?[ \t]*(?:\n|$)|\[TODO:[^\]]*\]/i.test(content)) reasons.push('unfinished-scaffold-marker');
  }
  for (const reference of markdownReferences(skillContent)) {
    const target = path.resolve(root, reference);
    if (!isWithin(root, target)) { reasons.push('reference-escapes-candidate'); continue; }
    try {
      if (!fs.statSync(target).isFile()) reasons.push('missing-local-reference');
    } catch { reasons.push('missing-local-reference'); }
  }
  const openaiPath = path.join(root, 'agents', 'openai.yaml');
  if (fs.existsSync(openaiPath)) {
    let openai = '';
    try {
      openai = readFileBounded(openaiPath, MAX_FILE_BYTES, {
        failureCode: 'openai-yaml-unreadable',
        tooLargeCode: 'candidate-file-too-large',
      }).toString('utf8');
    } catch (error) {
      reasons.push(error.code || 'openai-yaml-unreadable');
    }
    if (openai && openaiDefaultPrompt(openai).includes(`$${name}`) === false) reasons.push('openai-default-prompt-missing-name');
  }
  const candidateHash = skillContent ? sha256(skillContent) : '';
  if (skillContent && linesIn(skillContent) > MAX_ENTRYPOINT_LINES) reasons.push('entrypoint-over-500-lines');
  if (options.requireChanged && candidateHash && asArray(sourceHashes).includes(candidateHash)) reasons.push('unchanged-source');
  const uniqueReasons = [...new Set(reasons)].sort();
  const result = {
    valid: uniqueReasons.length === 0,
    reasons: uniqueReasons,
    candidateHash,
    lineCount: skillContent ? linesIn(skillContent) : 0,
    fileCount: files.fileCount,
    totalBytes: files.totalBytes,
    entries: files.entries,
  };
  return result;
}

function runOfficialValidator(candidateRoot, options = {}) {
  const validator = path.resolve(options.validatorPath || defaultValidatorPath());
  const canonical = defaultValidatorPath();
  if (validator !== canonical && options.allowTestValidator !== true) return { ok: false, reason: 'quick-validate-unavailable' };
  let fd;
  try {
    const before = fs.lstatSync(validator);
    if (before.isSymbolicLink() || !before.isFile() || before.size > MAX_FILE_BYTES) return { ok: false, reason: 'quick-validate-unavailable' };
    fd = fs.openSync(validator, fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW || 0));
    const opened = fs.fstatSync(fd);
    const after = fs.lstatSync(validator);
    if (!opened.isFile() || !sameFileIdentity(before, opened) || !sameFileIdentity(opened, after)) return { ok: false, reason: 'quick-validate-unavailable' };
    const output = execFileSync('python3', ['/dev/fd/3', path.resolve(candidateRoot)], {
      cwd: path.resolve(candidateRoot),
      env: minimalDelegateEnv(path.resolve(candidateRoot)),
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'pipe', fd],
      timeout: 30 * 1000,
      maxBuffer: MAX_VALIDATOR_OUTPUT_BYTES,
    });
    return { ok: true, output: String(output || '').slice(0, MAX_VALIDATOR_OUTPUT_BYTES) };
  } catch {
    return { ok: false, reason: 'quick-validate-failed' };
  } finally {
    if (fd !== undefined) try { fs.closeSync(fd); } catch { /* best effort */ }
  }
}

function validateStagedCandidate(candidateRoot, name, sourceHashes = [], options = {}) {
  const validation = validateCandidate(candidateRoot, name, sourceHashes, { requireChanged: options.requireChanged === true });
  if (validation.valid && options.requireOfficial !== false) {
    const official = runOfficialValidator(candidateRoot, options);
    if (!official.ok) validation.reasons.push(official.reason);
  }
  validation.reasons = [...new Set(validation.reasons)].sort();
  validation.valid = validation.reasons.length === 0;
  return validation;
}

function coverageValid(workspace, skill, privateItem) {
  const file = coveragePath(workspace, skill);
  if (!fs.existsSync(file)) return false;
  let content;
  try {
    content = readFileBounded(file, MAX_FILE_BYTES, {
      failureCode: 'coverage-read-failed',
      tooLargeCode: 'coverage-too-large',
    }).toString('utf8');
  } catch { return false; }
  if (!/^status:\s*completed\s*$/mi.test(content) || /preservation-decision:\s*PENDING\b/i.test(content)) return false;
  return (privateItem?.sources || []).every((source) => {
    const marker = `: ${source.contentHash}`;
    const start = content.indexOf(marker);
    if (start < 0) return false;
    const next = content.indexOf('\n- ', start + marker.length);
    const block = content.slice(start, next < 0 ? content.length : next);
    const decision = block.match(/preservation-decision:\s*([^\n\r]+)/i)?.[1]?.trim() || '';
    return decision.length >= 12 && decision.toUpperCase() !== 'PENDING';
  });
}

function writeValidationReceipt(workspace, skill, privateItem, validation) {
  const target = path.join(itemDirectory(workspace, skill.name), 'validation.receipt.json');
  writeJsonAtomic(target, {
    schemaVersion: SCHEMA_VERSION,
    name: skill.name,
    workItemId: skill.workItemId,
    valid: validation.valid,
    reasons: validation.reasons,
    candidateHash: validation.candidateHash,
    lineCount: validation.lineCount,
    fileCount: validation.fileCount,
    totalBytes: validation.totalBytes,
    candidateEntries: validation.entries,
    sourceHashes: (privateItem?.sources || []).map((source) => ({ variantId: source.variantId, contentHash: source.contentHash })),
    coveragePresent: coverageValid(workspace, skill, privateItem),
    validatedAt: isoNow(),
  }, 0o600);
}

function readValidationReceipt(workspace, skill) {
  const target = path.join(itemDirectory(workspace, skill.name), 'validation.receipt.json');
  if (!fs.existsSync(target)) return null;
  try { return readJson(target, 'validation-receipt-invalid'); } catch { return null; }
}

function validCandidateReceipt(workspace, skill, privateItem, options = {}) {
  const sources = revalidateItemSources(workspace, skill, privateItem);
  if (!sources.ok) return false;
  const snapshots = revalidateItemSnapshots(workspace, skill, privateItem);
  if (!snapshots.ok) return false;
  const receipt = readValidationReceipt(workspace, skill);
  if (!receipt?.valid || receipt.name !== skill.name || receipt.workItemId !== skill.workItemId || !coverageValid(workspace, skill, privateItem)) return false;
  const candidate = path.join(itemDirectory(workspace, skill.name), 'candidate', skill.name);
  const validation = validateStagedCandidate(candidate, skill.name, (privateItem?.sources || []).map((source) => source.entrypointHash), {
    requireChanged: true,
    validatorPath: options.validatorPath,
    allowTestValidator: options.allowTestValidator === true,
  });
  const sourceHashes = (privateItem?.sources || []).map((source) => ({ variantId: source.variantId, contentHash: source.contentHash }));
  return validation.valid
    && receipt.candidateHash === validation.candidateHash
    && compareEntryManifests(receipt.candidateEntries, validation.entries)
    && stableJson(receipt.sourceHashes || []) === stableJson(sourceHashes);
}

async function processItem(workspace, skill, state, privateItem, options = {}) {
  const unlock = acquireLock(workspace, skill);
  if (!unlock) return { name: skill.name, state: state.state, claimed: false, reason: 'claim-busy' };
  let current = state;
  const directory = itemDirectory(workspace, skill.name);
  try {
    const before = revalidateItemSources(workspace, skill, privateItem);
    if (!before.ok) {
      current = transitionItem(workspace, skill, 'BLOCKED', { reason: before.reason, pid: null, delegatePid: null });
      return { name: skill.name, state: current.state, claimed: true, reason: before.reason };
    }
    const snapshotBefore = revalidateItemSnapshots(workspace, skill, privateItem);
    if (!snapshotBefore.ok) {
      current = transitionItem(workspace, skill, 'BLOCKED', { reason: snapshotBefore.reason, pid: null, delegatePid: null });
      return { name: skill.name, state: current.state, claimed: true, reason: snapshotBefore.reason };
    }
    const taskPath = path.join(directory, 'task.md');
    let contractPath;
    try { contractPath = stageContract(workspace, skill); } catch (error) {
      current = transitionItem(workspace, skill, 'BLOCKED', { reason: error.code || 'contract-missing', pid: null, delegatePid: null });
      return { name: skill.name, state: current.state, claimed: true, reason: current.reason };
    }
    if (!fs.existsSync(taskPath)) writeAtomic(taskPath, `${makePrompt(skill, privateItem)}\n`, 0o600);
    if (!contractPath) throw new RefactorError('contract-missing', 'skill-creator contract is unavailable');
    const configuredDelegate = options.delegatePath || defaultDelegatePath();
    const delegate = path.isAbsolute(configuredDelegate) || configuredDelegate.includes(path.sep)
      ? path.resolve(configuredDelegate)
      : configuredDelegate;
    if (process.env.CANUTO_SKILL_REFACTOR_OFFLINE === '1') {
      current = transitionItem(workspace, skill, 'BLOCKED', { reason: 'offline-delegate', pid: null, delegatePid: null });
      return { name: skill.name, state: current.state, claimed: true, reason: current.reason };
    }
    if (!trustedDelegatePath(delegate, options.allowTestDelegate === true)) {
      current = transitionItem(workspace, skill, 'BLOCKED', { reason: 'delegate-untrusted', pid: null, delegatePid: null });
      return { name: skill.name, state: current.state, claimed: true, reason: current.reason };
    }
    if (!fs.existsSync(delegate)) {
      current = transitionItem(workspace, skill, 'BLOCKED', { reason: 'delegate-missing', pid: null, delegatePid: null });
      return { name: skill.name, state: current.state, claimed: true, reason: current.reason };
    }
    const resultPath = path.join(directory, 'result.md');
    let finalFailure = 'delegate-failed';
    for (let attempt = Math.max(1, Number(current.attempts || 0) + 1); attempt <= MAX_DELEGATE_ATTEMPTS; attempt += 1) {
      current = recoverableState(workspace, skill, { ...current, state: 'RUNNING' }, { attempts: attempt, pid: process.pid, startMarker: processStartMarker(process.pid), delegatePid: null, lastAttemptAt: isoNow() });
      const afterClaim = revalidateItemSources(workspace, skill, privateItem);
      if (!afterClaim.ok) {
        current = transitionItem(workspace, skill, 'BLOCKED', { reason: afterClaim.reason, pid: null, delegatePid: null });
        return { name: skill.name, state: current.state, claimed: true, reason: afterClaim.reason };
      }
      writeCoverageReceipt(workspace, skill, privateItem, 'prepared');
      const result = await spawnDelegate(delegate, taskPath, resultPath, directory, {
        timeoutMs: options.delegateTimeoutMs,
        allowTestDelegate: options.allowTestDelegate === true,
        onSpawn: (child) => {
          current = recoverableState(workspace, skill, current, { pid: process.pid, startMarker: processStartMarker(process.pid), delegatePid: child.pid, delegateStartMarker: processStartMarker(child.pid) });
        },
      });
      writeAttemptArtifacts(directory, attempt, resultPath, `${result.stderr || ''}\n${result.stdout || ''}`);
      const after = revalidateItemSources(workspace, skill, privateItem);
      if (!after.ok) {
        current = transitionItem(workspace, skill, 'BLOCKED', { reason: after.reason, pid: null, delegatePid: null });
        return { name: skill.name, state: current.state, claimed: true, reason: after.reason };
      }
      const snapshotAfter = revalidateItemSnapshots(workspace, skill, privateItem);
      if (!snapshotAfter.ok) {
        current = transitionItem(workspace, skill, 'BLOCKED', { reason: snapshotAfter.reason, pid: null, delegatePid: null });
        return { name: skill.name, state: current.state, claimed: true, reason: snapshotAfter.reason };
      }
      if (result.code === 0) {
        const candidatePath = path.join(directory, 'candidate', skill.name);
        const validation = validateStagedCandidate(candidatePath, skill.name, (privateItem?.sources || []).map((source) => source.entrypointHash), {
          requireChanged: true,
          validatorPath: options.validatorPath,
          allowTestValidator: options.allowTestValidator === true,
        });
        validation.coveragePresent = coverageValid(workspace, skill, privateItem);
        if (!validation.coveragePresent) validation.reasons.push('coverage-receipt-missing');
        validation.valid = validation.valid && validation.coveragePresent;
        writeValidationReceipt(workspace, skill, privateItem, validation);
        if (validation.valid) {
          current = transitionItem(workspace, skill, 'GENERATED', { reason: '', pid: null, delegatePid: null, candidateHash: validation.candidateHash });
          current = transitionItem(workspace, skill, 'VALIDATED', { reason: '', pid: null, delegatePid: null, candidateHash: validation.candidateHash });
          return { name: skill.name, state: current.state, claimed: true, reason: '' };
        }
        finalFailure = 'candidate-invalid';
      } else {
        finalFailure = 'delegate-failed';
      }
      if (attempt < MAX_DELEGATE_ATTEMPTS) options.onProgress?.(`${skill.name}: retrying delegate once`);
    }
    current = transitionItem(workspace, skill, 'FAILED', { reason: finalFailure, pid: null, delegatePid: null });
    return { name: skill.name, state: current.state, claimed: true, reason: current.reason };
  } catch (error) {
    const reason = error.code || 'delegate-execution-failed';
    if (current.state === 'RUNNING' || current.state === 'PENDING') {
      current = transitionItem(workspace, skill, 'FAILED', { reason, pid: null, delegatePid: null });
    }
    return { name: skill.name, state: current.state, claimed: true, reason };
  } finally {
    unlock();
  }
}

function candidatePathFor(workspace, skill) {
  return path.join(itemDirectory(workspace, skill.name), 'candidate', skill.name);
}

function selectRunItems(loaded, options = {}) {
  const selected = [];
  const generated = [];
  for (const entry of loaded.entries.filter((item) => item.skill.classification === 'REFACTOR').sort((a, b) => a.skill.name.localeCompare(b.skill.name))) {
    if (entry.state.state === 'PENDING') selected.push({ ...entry, mode: 'delegate' });
    else if (entry.state.state === 'RUNNING' && options.resume) {
      if (validCandidateReceipt(loaded.workspace, entry.skill, entry.privateItem, options)) generated.push({ ...entry, mode: 'reconcile' });
      else if (isPidAlive(entry.state.delegatePid || entry.state.pid, entry.state.delegateStartMarker || entry.state.startMarker)) continue;
      else {
        const sources = revalidateItemSources(loaded.workspace, entry.skill, entry.privateItem);
        if (!sources.ok) generated.push({ ...entry, mode: 'blocked', reason: sources.reason });
        else selected.push({ ...entry, mode: 'delegate' });
      }
    } else if (entry.state.state === 'GENERATED') generated.push({ ...entry, mode: 'reconcile' });
  }
  const limit = options.limit === undefined ? selected.length : Math.min(options.limit, selected.length);
  return { selected: selected.slice(0, limit), generated };
}

async function runWorkspace(options = {}) {
  const loaded = loadedWorkspace(options.workspace);
  const selection = selectRunItems(loaded, options);
  const results = [];
  for (const entry of selection.generated) {
    assertWorkspaceSafe(loaded.workspace);
    if (entry.mode === 'blocked') {
      const state = transitionItem(loaded.workspace, entry.skill, 'BLOCKED', { reason: entry.reason, pid: null, delegatePid: null });
      results.push({ name: entry.skill.name, state: state.state, claimed: false, reason: state.reason });
    } else if (validCandidateReceipt(loaded.workspace, entry.skill, entry.privateItem, options)) {
      let state;
      if (entry.state.state === 'RUNNING') {
        state = transitionItem(loaded.workspace, entry.skill, 'GENERATED', { reason: '', pid: null, delegatePid: null });
        state = transitionItem(loaded.workspace, entry.skill, 'VALIDATED', { reason: '', pid: null, delegatePid: null });
      } else if (entry.state.state === 'GENERATED') {
        state = transitionItem(loaded.workspace, entry.skill, 'VALIDATED', { reason: '', pid: null, delegatePid: null });
      } else {
        state = recoverableState(loaded.workspace, entry.skill, { ...entry.state, state: 'VALIDATED' }, { pid: null, delegatePid: null });
      }
      results.push({ name: entry.skill.name, state: state.state, claimed: false, reason: '' });
    } else if (entry.state.state === 'GENERATED') {
      let validation;
      try {
        validation = validateStagedCandidate(candidatePathFor(loaded.workspace, entry.skill), entry.skill.name, (entry.privateItem?.sources || []).map((source) => source.entrypointHash), {
          requireChanged: true,
          validatorPath: options.validatorPath,
          allowTestValidator: options.allowTestValidator === true,
        });
        validation.coveragePresent = coverageValid(loaded.workspace, entry.skill, entry.privateItem);
        if (!validation.coveragePresent) validation.reasons.push('coverage-receipt-missing');
        validation.valid = validation.valid && validation.coveragePresent;
        writeValidationReceipt(loaded.workspace, entry.skill, entry.privateItem, validation);
      } catch (error) {
        const state = transitionItem(loaded.workspace, entry.skill, 'FAILED', { reason: error.code || 'candidate-invalid', pid: null, delegatePid: null });
        results.push({ name: entry.skill.name, state: state.state, claimed: false, reason: state.reason });
        continue;
      }
      if (validation.valid) {
        const state = transitionItem(loaded.workspace, entry.skill, 'VALIDATED', { reason: '', pid: null, delegatePid: null, candidateHash: validation.candidateHash });
        results.push({ name: entry.skill.name, state: state.state, claimed: false, reason: '' });
      } else {
        const state = transitionItem(loaded.workspace, entry.skill, 'FAILED', { reason: 'candidate-invalid', pid: null, delegatePid: null });
        results.push({ name: entry.skill.name, state: state.state, claimed: false, reason: state.reason });
      }
    }
  }
  const requestedWorkers = Number.isSafeInteger(options.workers) ? options.workers : 2;
  const workers = Math.max(1, Math.min(requestedWorkers, MAX_WORKERS));
  let cursor = 0;
  async function worker() {
    while (cursor < selection.selected.length) {
      const index = cursor;
      cursor += 1;
      const entry = selection.selected[index];
      assertWorkspaceSafe(loaded.workspace);
      const current = loadItemState(loaded.workspace, entry.skill);
      const result = await processItem(loaded.workspace, entry.skill, current, entry.privateItem, options);
      results.push(result);
    }
  }
  await Promise.all(Array.from({ length: Math.min(workers, selection.selected.length) }, () => worker()));
  results.sort((a, b) => a.name.localeCompare(b.name));
  assertWorkspaceSafe(loaded.workspace);
  const claimed = results.filter((result) => result.claimed);
  const unsuccessful = results.filter((result) => ['FAILED', 'BLOCKED'].includes(result.state));
  return {
    schemaVersion: SCHEMA_VERSION,
    tool: TOOL,
    status: unsuccessful.length ? 'PARTIAL' : 'READY',
    workers,
    limit: options.limit === undefined ? null : options.limit,
    resume: options.resume === true,
    claimed: claimed.length,
    results,
    counts: {
      selected: selection.selected.length,
      reconciled: selection.generated.length,
      failedOrBlocked: unsuccessful.length,
    },
    exitCode: unsuccessful.length ? 2 : 0,
  };
}

function queueWorkspace(workspace) {
  const loaded = loadedWorkspace(workspace);
  const classificationCounts = Object.fromEntries(CLASSIFICATIONS.map((state) => [state, 0]));
  const jobStateCounts = Object.fromEntries([...JOB_STATES, 'NOT_APPLICABLE'].map((state) => [state, 0]));
  const items = [];
  for (const entry of loaded.entries) {
    classificationCounts[entry.skill.classification] = (classificationCounts[entry.skill.classification] || 0) + 1;
    jobStateCounts[entry.state.state] = (jobStateCounts[entry.state.state] || 0) + 1;
    items.push({ name: entry.skill.name, classification: entry.skill.classification, state: entry.state.state, reasons: entry.skill.reasons, workItemId: entry.skill.workItemId });
  }
  items.sort((a, b) => a.name.localeCompare(b.name));
  assertWorkspaceSafe(loaded.workspace);
  return {
    schemaVersion: SCHEMA_VERSION,
    tool: TOOL,
    status: 'READY',
    scanFingerprint: loaded.manifest.scanFingerprint,
    counts: { classifications: classificationCounts, jobStates: jobStateCounts, total: items.length },
    items: items.slice(0, MAX_QUEUE_ITEMS),
    truncated: items.length > MAX_QUEUE_ITEMS,
  };
}

function previewWorkspace(workspace, name) {
  const loaded = loadedWorkspace(workspace);
  const normalized = normalizeName(name);
  const entry = loaded.entries.find((item) => item.skill.name === normalized);
  if (!entry) throw new RefactorError('skill-not-found', 'logical skill was not found');
  const itemDirectoryPath = entry.skill.workItemId ? itemDirectory(loaded.workspace, entry.skill.name) : '';
  const privateItem = entry.privateItem;
  const candidate = entry.skill.workItemId ? candidatePathFor(loaded.workspace, entry.skill) : '';
  let candidateInfo = { present: false, hash: '', lineCount: 0, fileCount: 0, totalBytes: 0 };
  if (candidate && fs.existsSync(candidate)) {
    const validation = validateCandidate(candidate, entry.skill.name, (privateItem?.sources || []).map((source) => source.entrypointHash), { requireChanged: true });
    candidateInfo = {
      present: true,
      hash: validation.candidateHash,
      hashPrefix: hashPrefix(validation.candidateHash),
      lineCount: validation.lineCount,
      fileCount: validation.fileCount,
      totalBytes: validation.totalBytes,
      valid: validation.valid,
      reasons: validation.reasons,
    };
  }
  const receipt = readValidationReceipt(loaded.workspace, entry.skill);
  const nextCommand = entry.skill.classification !== 'REFACTOR'
    ? 'no staging action required'
    : entry.state.state === 'PENDING'
      ? 'canuto-skill-refactor --json run --workspace <workspace>'
      : entry.state.state === 'RUNNING'
        ? 'canuto-skill-refactor --json run --workspace <workspace> --resume'
        : entry.state.state === 'GENERATED'
          ? 'canuto-skill-refactor --json validate --workspace <workspace>'
          : entry.state.state === 'FAILED'
            ? 'create a new isolated workspace and rerun scan'
            : entry.state.state === 'BLOCKED'
              ? 'inspect the blocked reason and create a new isolated workspace if needed'
              : 'no further staging action required';
  assertWorkspaceSafe(loaded.workspace);
  return {
    schemaVersion: SCHEMA_VERSION,
    tool: TOOL,
    status: 'READY',
    name: entry.skill.name,
    classification: entry.skill.classification,
    reasons: entry.skill.reasons,
    state: entry.state.state,
    sourceHashPrefixes: (privateItem?.sources || []).map((source) => ({ variantId: source.variantId, hashPrefix: hashPrefix(source.contentHash) })),
    candidate: candidateInfo,
    validation: {
      state: receipt?.valid ? 'VALID' : receipt ? 'INVALID' : 'NOT_RUN',
      receiptPresent: Boolean(receipt),
      reasons: receipt?.reasons || [],
    },
    coverageReceipt: {
      present: Boolean(entry.skill.workItemId && coverageValid(loaded.workspace, entry.skill, privateItem)),
      variantCount: privateItem?.sources?.length || 0,
    },
    nextCommand,
  };
}

function validateWorkspace(options = {}) {
  const loaded = loadedWorkspace(options.workspace);
  const currentEstate = analyzeEstate(loaded.config, loaded.inventory, { home: loaded.home, frameworkRoot: loaded.frameworkRoot });
  if (currentEstate.scanFingerprint !== loaded.manifest.scanFingerprint) {
    return {
      schemaVersion: SCHEMA_VERSION,
      tool: TOOL,
      status: 'PARTIAL',
      liveSources: { status: 'UNVERIFIED', unchanged: false },
      checked: 1,
      valid: 0,
      invalid: 1,
      results: [{ name: '__estate__', classification: 'ESTATE', state: 'BLOCKED', valid: false, reason: 'estate-drift' }],
      exitCode: 2,
    };
  }
  const results = [];
  let liveUnchanged = true;
  for (const entry of loaded.entries) {
    assertWorkspaceSafe(loaded.workspace);
    if (entry.skill.classification === 'BLOCKED_PROVENANCE') {
      liveUnchanged = false;
      results.push({ name: entry.skill.name, classification: entry.skill.classification, state: 'BLOCKED', valid: false, reason: entry.skill.reasons?.[0] || 'blocked-provenance' });
      continue;
    }
    if (entry.skill.classification !== 'REFACTOR') {
      const blocked = entry.state.state === 'BLOCKED';
      if (blocked) liveUnchanged = false;
      results.push({
        name: entry.skill.name,
        classification: entry.skill.classification,
        state: entry.state.state,
        valid: !blocked,
        reason: blocked ? entry.skill.reasons.find((reason) => reason !== 'managed-installation') || 'source-uninspectable' : '',
      });
      continue;
    }
    const sources = revalidateItemSources(loaded.workspace, entry.skill, entry.privateItem);
    if (!sources.ok) {
      liveUnchanged = false;
      let state = entry.state;
      if (!['BLOCKED', 'FAILED'].includes(state.state)) state = transitionItem(loaded.workspace, entry.skill, 'BLOCKED', { reason: sources.reason, pid: null, delegatePid: null });
      results.push({ name: entry.skill.name, classification: entry.skill.classification, state: state.state, valid: false, reason: sources.reason });
      continue;
    }
    const snapshots = revalidateItemSnapshots(loaded.workspace, entry.skill, entry.privateItem);
    if (!snapshots.ok) {
      let state = entry.state;
      if (!['BLOCKED', 'FAILED'].includes(state.state)) state = transitionItem(loaded.workspace, entry.skill, 'BLOCKED', { reason: snapshots.reason, pid: null, delegatePid: null });
      results.push({ name: entry.skill.name, classification: entry.skill.classification, state: state.state, valid: false, reason: snapshots.reason });
      continue;
    }
    const candidate = candidatePathFor(loaded.workspace, entry.skill);
    if (fs.existsSync(candidate)) {
      const validation = validateStagedCandidate(candidate, entry.skill.name, (entry.privateItem?.sources || []).map((source) => source.entrypointHash), {
        requireChanged: true,
        validatorPath: options.validatorPath,
        allowTestValidator: options.allowTestValidator === true,
      });
      validation.coveragePresent = coverageValid(loaded.workspace, entry.skill, entry.privateItem);
      if (!validation.coveragePresent) validation.reasons.push('coverage-receipt-missing');
      validation.valid = validation.valid && validation.coveragePresent;
      writeValidationReceipt(loaded.workspace, entry.skill, entry.privateItem, validation);
      let state = entry.state;
      if (validation.valid && state.state === 'GENERATED') state = transitionItem(loaded.workspace, entry.skill, 'VALIDATED', { reason: '', pid: null, delegatePid: null, candidateHash: validation.candidateHash });
      else if (validation.valid && state.state === 'FAILED') state = recoverableState(loaded.workspace, entry.skill, { ...state, state: 'VALIDATED' }, { reason: '', pid: null, delegatePid: null, candidateHash: validation.candidateHash });
      else if (!validation.valid && ['GENERATED', 'VALIDATED'].includes(state.state)) state = transitionItem(loaded.workspace, entry.skill, 'FAILED', { reason: 'candidate-invalid', pid: null, delegatePid: null });
      results.push({ name: entry.skill.name, classification: entry.skill.classification, state: state.state, valid: validation.valid, reason: validation.valid ? '' : 'candidate-invalid' });
    } else {
      results.push({ name: entry.skill.name, classification: entry.skill.classification, state: entry.state.state, valid: false, reason: entry.state.state === 'PENDING' ? 'pending' : 'candidate-missing' });
    }
  }
  assertWorkspaceSafe(loaded.workspace);
  const invalid = results.filter((item) => !item.valid);
  return {
    schemaVersion: SCHEMA_VERSION,
    tool: TOOL,
    status: invalid.length ? 'PARTIAL' : 'READY',
    liveSources: { status: liveUnchanged ? 'VERIFIED' : 'UNVERIFIED', unchanged: liveUnchanged },
    checked: results.length,
    valid: results.filter((item) => item.valid).length,
    invalid: invalid.length,
    results,
    exitCode: invalid.length ? 2 : 0,
  };
}

function doctor() {
  const checks = {};
  const nodeMajor = Number(process.versions.node.split('.')[0]);
  checks.node = { status: nodeMajor >= 18 ? 'READY' : 'BLOCKED', major: nodeMajor };
  checks.gardener = {
    status: gardener && ['loadConfig', 'collectInventory', 'normalizeName', 'parseFrontmatter', 'sha256'].every((key) => typeof gardener[key] === 'function') ? 'READY' : 'BLOCKED',
  };
  const productionDelegate = path.join(os.homedir(), '.codex', 'bin', 'codex-delegate.sh');
  const selectedDelegate = defaultDelegatePath();
  const isExecutable = (filePath) => {
    try {
      const stat = fs.statSync(filePath);
      return stat.isFile() && (process.platform === 'win32' || (stat.mode & 0o111) !== 0);
    } catch { return false; }
  };
  const productionReady = isExecutable(productionDelegate);
  const selectedReady = isExecutable(selectedDelegate);
  const selectedTrusted = trustedDelegatePath(selectedDelegate);
  checks.delegate = { status: productionReady ? 'READY' : 'BLOCKED', overridden: false, selectedStatus: selectedReady && selectedTrusted ? 'READY' : 'BLOCKED' };
  checks.validator = { status: fs.existsSync(defaultValidatorPath()) ? 'READY' : 'BLOCKED' };
  const configPath = defaultConfigPath();
  try { gardener.loadConfig(configPath); checks.config = { status: 'READY' }; } catch (error) { checks.config = { status: 'BLOCKED', reason: error.message || 'config-invalid' }; }
  const offline = process.env.CANUTO_SKILL_REFACTOR_OFFLINE === '1';
  const requiredKeys = ['node', 'gardener', 'validator', 'config'];
  const requiredReady = requiredKeys.every((key) => checks[key]?.status === 'READY');
  const delegateReady = offline || productionReady;
  const status = requiredReady && delegateReady ? 'READY' : 'BLOCKED';
  return {
    schemaVersion: SCHEMA_VERSION,
    tool: TOOL,
    status,
    mode: offline ? 'offline' : 'production',
    checks,
    exitCode: status === 'READY' ? 0 : 2,
  };
}

module.exports = {
  TOOL,
  SCHEMA_VERSION,
  CLASSIFICATIONS,
  JOB_STATES,
  MAX_ENTRYPOINT_LINES,
  MAX_FILE_BYTES,
  MAX_BUNDLE_FILES,
  MAX_BUNDLE_BYTES,
  MAX_RESULT_BYTES,
  MAX_STDERR_BYTES,
  MAX_WORKSPACE_FILE_BYTES,
  MAX_QUEUE_ITEMS,
  MAX_WORKERS,
  MAX_DELEGATE_ATTEMPTS,
  DEFAULT_DELEGATE_TIMEOUT_MS,
  HASH_PREFIX_LENGTH,
  RefactorError,
  stableJson,
  sha256,
  normalizeName,
  parseFrontmatter,
  isWithin,
  isInactiveSourcePath,
  isSecretLookingPath,
  frontmatterContract,
  inspectSourceBundle,
  sourceBundleMatches,
  classifyLogicalName,
  validateCandidate,
  coverageValid,
  defaultConfigPath,
  defaultFrameworkRoot,
  defaultContractPath,
  defaultValidatorPath,
  defaultDelegatePath,
  acquireLock,
  inventoryForConfig,
  analyzeEstate,
  scanWorkspace,
  loadedWorkspace,
  queueWorkspace,
  runWorkspace,
  validateWorkspace,
  previewWorkspace,
  readFileBounded,
  runOfficialValidator,
  trustedDelegatePath,
  doctor,
};
