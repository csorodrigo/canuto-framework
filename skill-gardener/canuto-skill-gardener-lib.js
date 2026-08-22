'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync, spawn } = require('node:child_process');

let sharedAudit = {};
try {
  sharedAudit = require(path.join(__dirname, '..', '.agents', 'tools', 'framework-session-audit-lib.js'));
} catch {
  sharedAudit = {};
}

const parseFrontmatter = sharedAudit.parseFrontmatter || function parseFrontmatterFallback(markdown) {
  const text = String(markdown || '');
  if (!/^---\r?\n/.test(text)) return { data: {}, body: text };
  const lines = text.split(/\r?\n/);
  const data = {};
  let end = -1;
  for (let index = 1; index < lines.length; index += 1) {
    if (lines[index] === '---') {
      end = index;
      break;
    }
    const match = lines[index].match(/^([^:#][^:]*):\s*(.*)$/);
    if (!match) continue;
    let value = match[2].trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    } else if (value === 'true' || value === 'false') {
      value = value === 'true';
    }
    data[match[1].trim()] = value;
  }
  return { data, body: end < 0 ? text : lines.slice(end + 1).join('\n') };
};

const SCHEMA_VERSION = 1;
const MARKER = '# canuto-skill-gardener:v1';
const CRON_SCHEDULE = '0 3 * * 0';
const MAX_LINE_BYTES = 64 * 1024 * 1024;
const MAX_REMOTE_STDOUT_BYTES = 128 * 1024 * 1024;
const MAX_REMOTE_STDERR_BYTES = 1 * 1024 * 1024;
const REMOTE_CONNECT_TIMEOUT_MS = 10 * 1000;
const REMOTE_EXECUTION_TIMEOUT_MS = 20 * 60 * 1000;
const DETAIL_RETENTION_DAYS = 180;
const NEGATIVE_WINDOW_DAYS = 120;
const HMAC_KEY_RE = /^[a-f0-9]{64}$/i;
const PROVIDERS = ['codex', 'claude', 'hermes', 'opencode'];
const VALID_KINDS = new Set(['verified_usage', 'candidate_signal']);
const RUN_ID_RE = /^\d{14}-[a-f0-9]{10}$/;
const CANARY_STATUS = 'COMPLETE';
const SAFE_RESULTS = new Set(['success', 'failure', 'error', 'timeout', 'partial', 'unknown']);
const DEFAULT_FINGERPRINT_FAMILIES = Object.freeze({
  tools: ['read', 'search', 'edit', 'test', 'git', 'shell', 'delegate'],
  executables: ['node', 'npm', 'pnpm', 'yarn', 'bun', 'git', 'rg', 'grep', 'sed', 'awk', 'jq', 'bash', 'python3'],
  results: [...SAFE_RESULTS],
});
const CLOSED_REMOTE_KEYS = new Set([
  'schemaVersion',
  'kind',
  'eventKey',
  'skillKey',
  'signalKey',
  'timestamp',
  'provider',
  'surfaceAlias',
  'logicalProjectId',
  'verification',
  'fingerprint',
  'count',
]);

function expandHome(value, home = os.homedir()) {
  if (!value) return value;
  const text = String(value);
  if (text === '~') return home;
  if (text.startsWith('~/')) return path.join(home, text.slice(2));
  return text.replace(/^\$HOME(?=\/|$)/, home);
}

function resolvePath(value, cwd = process.cwd(), home = os.homedir()) {
  return path.resolve(cwd, expandHome(value, home));
}

function isPlainObject(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return false;
  const prototype = Object.getPrototypeOf(value);
  return prototype === Object.prototype || prototype === null;
}

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function hmac(value, key = 'canuto-skill-gardener-unconfigured') {
  return crypto.createHmac('sha256', key).update(String(value)).digest('hex');
}

function stableJson(value) {
  if (Array.isArray(value)) return `[${value.map(stableJson).join(',')}]`;
  if (value && typeof value === 'object') {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stableJson(value[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}

function normalizeName(value) {
  return String(value || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 120);
}

function normalizeProvider(value) {
  const provider = normalizeName(value);
  return PROVIDERS.includes(provider) ? provider : '';
}

function iso(value, fallback = new Date().toISOString()) {
  const parsed = Date.parse(String(value || ''));
  return Number.isFinite(parsed) ? new Date(parsed).toISOString() : fallback;
}

function parseNumber(value, fallback = 0) {
  const number = Number(value);
  return Number.isFinite(number) ? number : fallback;
}

function ensureDir(directory) {
  fs.mkdirSync(directory, { recursive: true });
}

function readJson(filePath, fallback = null) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    return fallback;
  }
}

function atomicWrite(filePath, content) {
  ensureDir(path.dirname(filePath));
  const temporary = `${filePath}.tmp-${process.pid}-${crypto.randomBytes(6).toString('hex')}`;
  fs.writeFileSync(temporary, content, { mode: 0o600 });
  fs.renameSync(temporary, filePath);
}

function atomicWriteJson(filePath, value) {
  atomicWrite(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

function fileExists(filePath) {
  try {
    fs.accessSync(filePath, fs.constants.F_OK);
    return true;
  } catch {
    return false;
  }
}

function isWithin(child, parent) {
  const relative = path.relative(parent, child);
  return relative === '' || (relative !== '..' && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative));
}

function isCanonicalRunId(value) {
  return typeof value === 'string' && RUN_ID_RE.test(value);
}

function canonicalArtifactPath(root, runId, suffix = '.json') {
  if (!isCanonicalRunId(runId)) return '';
  const directory = path.resolve(root);
  const target = path.resolve(directory, `${runId}${suffix}`);
  return isWithin(target, directory) ? target : '';
}

function normalizeArray(value) {
  if (Array.isArray(value)) return value;
  if (value === undefined || value === null || value === '') return [];
  return [value];
}

function makeSkillIdentity({ name, content, provider = '', installationKind = 'project', hmacKey, sourcePath }) {
  const normalizedName = normalizeName(name);
  const contentText = String(content || '');
  const contentHash = sha256(contentText);
  const key = hmacKey || process.env.CANUTO_SKILL_GARDENER_HMAC_KEY || 'canuto-skill-gardener-unconfigured';
  const identity = {
    name: normalizedName,
    contentHash,
    skillKey: hmac(`variant:${normalizedName}:${contentHash}`, key),
    provider: normalizeProvider(provider) || 'unknown',
    installationKind,
  };
  return identity;
}

function publicSkillIdentity(identity) {
  const output = { ...identity };
  delete output._sourcePath;
  return output;
}

function defaultConfig() {
  return {
    schemaVersion: SCHEMA_VERSION,
    projects: {},
    providers: {
      codex: {
        roots: ['~/.codex/skills'],
        pluginRoots: ['~/.codex/plugins'],
        systemRoots: ['~/.codex/system/skills'],
        historyRoots: ['~/.codex/sessions', '~/.codex/archived_sessions'],
      },
      claude: {
        roots: ['~/.claude/skills'],
        pluginRoots: ['~/.claude/plugins'],
        systemRoots: ['~/.claude/system/skills'],
        historyRoots: ['~/.claude/projects', '~/.claude/telemetry'],
      },
      hermes: {
        roots: ['~/.hermes/skills'],
        pluginRoots: ['~/.hermes/plugins'],
        systemRoots: ['~/.hermes/system/skills'],
        historyRoots: ['~/.hermes/sessions'],
      },
      opencode: {
        roots: [],
        pluginRoots: [],
        systemRoots: [],
        historyRoots: [],
      },
    },
    policy: {
      detailRetentionDays: DETAIL_RETENTION_DAYS,
      fingerprintFamilies: DEFAULT_FINGERPRINT_FAMILIES,
      evalAdapter: { enabled: false, command: 'agent-skill-eval', version: 'v1' },
    },
  };
}

function normalizeRootEntry(entry) {
  if (typeof entry === 'string') return { path: entry, id: '' };
  if (!entry || typeof entry !== 'object') return { path: '', id: '' };
  return {
    path: typeof entry.path === 'string' ? entry.path : typeof entry.root === 'string' ? entry.root : '',
    id: typeof entry.id === 'string' ? normalizeName(entry.id) : '',
    alias: typeof entry.alias === 'string' ? entry.alias.trim() : '',
    readOnly: entry.readOnly !== false,
  };
}

function normalizeSurface(surface) {
  const value = surface && typeof surface === 'object' ? surface : {};
  return {
    roots: normalizeArray(value.roots).map(normalizeRootEntry).filter((root) => root.path),
    aliases: normalizeArray(value.aliases).filter((alias) => typeof alias === 'string').map((alias) => alias.trim()).filter(Boolean),
    historyRoots: normalizeArray(value.historyRoots).map(normalizeRootEntry).filter((root) => root.path),
    provider: normalizeProvider(value.provider) || '',
    remote: value.remote === true,
  };
}

function normalizeConfig(raw) {
  const source = raw && typeof raw === 'object' ? raw : {};
  const base = defaultConfig();
  const projects = {};
  const rawProjects = source.projects && typeof source.projects === 'object'
    ? source.projects
    : source.logicalProjects && typeof source.logicalProjects === 'object'
      ? source.logicalProjects
      : Object.fromEntries(Object.entries(source).filter(([key]) => !['schemaVersion', 'providers', 'policy'].includes(key)));
  for (const [logicalProjectId, project] of Object.entries(rawProjects)) {
    if (!/^[a-z0-9][a-z0-9._-]*$/i.test(logicalProjectId)) continue;
    const surfaces = {};
    const rawSurfaces = project && typeof project === 'object' && project.surfaces && typeof project.surfaces === 'object'
      ? project.surfaces
      : {};
    for (const [surfaceId, surface] of Object.entries(rawSurfaces)) {
      surfaces[String(surfaceId)] = normalizeSurface(surface);
    }
    projects[logicalProjectId] = { surfaces };
  }
  const providers = { ...base.providers };
  const rawProviders = source.providers && typeof source.providers === 'object' ? source.providers : {};
  for (const provider of PROVIDERS) {
    if (!rawProviders[provider]) continue;
    const value = rawProviders[provider];
    providers[provider] = {
      roots: normalizeArray(value.roots).map(normalizeRootEntry).filter((root) => root.path),
      pluginRoots: normalizeArray(value.pluginRoots).map(normalizeRootEntry).filter((root) => root.path),
      systemRoots: normalizeArray(value.systemRoots).map(normalizeRootEntry).filter((root) => root.path),
      historyRoots: normalizeArray(value.historyRoots).map(normalizeRootEntry).filter((root) => root.path),
    };
  }
  const policy = source.policy && typeof source.policy === 'object' ? source.policy : {};
  const families = policy.fingerprintFamilies && typeof policy.fingerprintFamilies === 'object'
    ? policy.fingerprintFamilies
    : base.policy.fingerprintFamilies;
  return {
    schemaVersion: SCHEMA_VERSION,
    projects,
    providers,
    policy: {
      detailRetentionDays: Math.max(1, Math.min(3650, parseNumber(policy.detailRetentionDays, DETAIL_RETENTION_DAYS))),
      fingerprintFamilies: {
        tools: normalizeArray(families.tools).filter((item) => typeof item === 'string').map(normalizeName),
        executables: normalizeArray(families.executables).filter((item) => typeof item === 'string').map(normalizeName),
        results: normalizeArray(families.results).filter((item) => typeof item === 'string').map(normalizeName),
      },
      evalAdapter: {
        enabled: policy.evalAdapter?.enabled === true,
        command: typeof policy.evalAdapter?.command === 'string' ? policy.evalAdapter.command : 'agent-skill-eval',
        version: typeof policy.evalAdapter?.version === 'string' ? policy.evalAdapter.version : 'v1',
      },
    },
  };
}

const CONFIG_TOP_LEVEL_KEYS = new Set(['schemaVersion', 'projects', 'providers', 'policy']);
const CONFIG_ROOT_KEYS = new Set(['path', 'root', 'id', 'alias', 'readOnly']);
const CONFIG_SURFACE_KEYS = new Set(['provider', 'remote', 'roots', 'aliases', 'historyRoots']);
const CONFIG_POLICY_KEYS = new Set(['detailRetentionDays', 'fingerprintFamilies', 'evalAdapter']);
const CONFIG_FINGERPRINT_KEYS = new Set(['tools', 'executables', 'results']);
const CONFIG_EVAL_KEYS = new Set(['enabled', 'command', 'version']);

function hasExactKeys(value, keys) {
  const actual = Object.keys(value);
  return actual.length === keys.size && actual.every((key) => keys.has(key));
}

function validateStoredRootEntry(entry) {
  if (typeof entry === 'string') {
    if (!entry) throw new Error('config-invalid');
    return;
  }
  if (!isPlainObject(entry) || Object.keys(entry).some((key) => !CONFIG_ROOT_KEYS.has(key))) throw new Error('config-invalid');
  if (typeof entry.path !== 'string' && typeof entry.root !== 'string') throw new Error('config-invalid');
  if (entry.path !== undefined && typeof entry.path !== 'string') throw new Error('config-invalid');
  if (entry.root !== undefined && typeof entry.root !== 'string') throw new Error('config-invalid');
  if (entry.id !== undefined && typeof entry.id !== 'string') throw new Error('config-invalid');
  if (entry.alias !== undefined && typeof entry.alias !== 'string') throw new Error('config-invalid');
  if (entry.readOnly !== undefined && typeof entry.readOnly !== 'boolean') throw new Error('config-invalid');
}

function validateStoredRootArray(value) {
  if (!Array.isArray(value)) throw new Error('config-invalid');
  for (const entry of value) validateStoredRootEntry(entry);
}

function validateStoredConfig(raw) {
  if (!isPlainObject(raw) || raw.schemaVersion !== SCHEMA_VERSION || !hasExactKeys(raw, CONFIG_TOP_LEVEL_KEYS)) throw new Error('config-invalid');
  if (!isPlainObject(raw.projects) || !isPlainObject(raw.providers) || !isPlainObject(raw.policy)) throw new Error('config-invalid');

  for (const [logicalProjectId, project] of Object.entries(raw.projects)) {
    if (!/^[a-z0-9][a-z0-9._-]*$/i.test(logicalProjectId) || !isPlainObject(project) || !hasExactKeys(project, new Set(['surfaces'])) || !isPlainObject(project.surfaces)) throw new Error('config-invalid');
    for (const [surfaceId, surface] of Object.entries(project.surfaces)) {
      if (!/^[a-z0-9][a-z0-9._-]*$/i.test(surfaceId) || !isPlainObject(surface) || Object.keys(surface).some((key) => !CONFIG_SURFACE_KEYS.has(key))) throw new Error('config-invalid');
      if (typeof surface.provider !== 'string' || !PROVIDERS.includes(surface.provider)) throw new Error('config-invalid');
      if (surface.remote !== undefined && typeof surface.remote !== 'boolean') throw new Error('config-invalid');
      validateStoredRootArray(surface.roots);
      validateStoredRootArray(surface.historyRoots);
      if (!Array.isArray(surface.aliases) || surface.aliases.some((alias) => typeof alias !== 'string')) throw new Error('config-invalid');
    }
  }

  if (!hasExactKeys(raw.providers, new Set(PROVIDERS))) throw new Error('config-invalid');
  for (const provider of PROVIDERS) {
    const settings = raw.providers[provider];
    if (!isPlainObject(settings) || !hasExactKeys(settings, new Set(['roots', 'pluginRoots', 'systemRoots', 'historyRoots']))) throw new Error('config-invalid');
    validateStoredRootArray(settings.roots);
    validateStoredRootArray(settings.pluginRoots);
    validateStoredRootArray(settings.systemRoots);
    validateStoredRootArray(settings.historyRoots);
  }

  if (!hasExactKeys(raw.policy, CONFIG_POLICY_KEYS)
    || typeof raw.policy.detailRetentionDays !== 'number'
    || !Number.isFinite(raw.policy.detailRetentionDays)
    || raw.policy.detailRetentionDays < 1
    || raw.policy.detailRetentionDays > 3650
    || !isPlainObject(raw.policy.fingerprintFamilies)
    || !hasExactKeys(raw.policy.fingerprintFamilies, CONFIG_FINGERPRINT_KEYS)
    || !isPlainObject(raw.policy.evalAdapter)
    || !hasExactKeys(raw.policy.evalAdapter, CONFIG_EVAL_KEYS)) throw new Error('config-invalid');
  for (const family of Object.values(raw.policy.fingerprintFamilies)) {
    if (!Array.isArray(family) || family.some((item) => typeof item !== 'string')) throw new Error('config-invalid');
  }
  if (typeof raw.policy.evalAdapter.enabled !== 'boolean'
    || typeof raw.policy.evalAdapter.command !== 'string'
    || typeof raw.policy.evalAdapter.version !== 'string') throw new Error('config-invalid');
  return raw;
}

function loadConfig(configPath, sourceConfig) {
  if (sourceConfig !== undefined) {
    if (!isPlainObject(sourceConfig)) throw new Error('config-invalid');
    return normalizeConfig(sourceConfig);
  }
  let raw;
  try {
    raw = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  } catch (error) {
    if (error?.code === 'ENOENT') throw new Error('config-missing');
    if (error instanceof SyntaxError) throw new Error('config-invalid');
    throw new Error('config-read-failed');
  }
  validateStoredConfig(raw);
  return normalizeConfig(raw);
}

function gitCommonDir(root) {
  try {
    const output = execFileSync('git', ['-C', root, 'rev-parse', '--git-common-dir'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
    return path.resolve(root, output);
  } catch {
    return '';
  }
}

function expandRootGlob(rootPath) {
  const expanded = rootPath.replace(/\\/g, '/');
  if (!expanded.includes('*')) return [rootPath];
  const star = expanded.indexOf('*');
  const parent = expanded.slice(0, star).replace(/\/$/, '') || path.parse(expanded).root;
  const suffix = expanded.slice(star + 1).replace(/^\//, '');
  if (!fileExists(parent)) return [];
  let entries = [];
  try {
    entries = fs.readdirSync(parent, { withFileTypes: true });
  } catch {
    return [];
  }
  return entries
    .filter((entry) => entry.isDirectory())
    .map((entry) => path.join(parent, entry.name, suffix))
    .filter((candidate) => fileExists(candidate));
}

function configuredRootCandidates(root, home = os.homedir()) {
  const resolved = resolvePath(root.path, process.cwd(), home);
  const candidates = expandRootGlob(resolved);
  if (candidates.length === 0 && fileExists(resolved)) candidates.push(resolved);
  if (candidates.length === 0) return [];
  const configuredCommon = gitCommonDir(resolved) || gitCommonDir(candidates[0]);
  const result = [];
  for (const candidate of candidates) {
    const common = gitCommonDir(candidate);
    if (configuredCommon && common && configuredCommon !== common) continue;
    result.push({ ...root, path: candidate, gitCommonDir: common || configuredCommon });
  }
  return result;
}

function buildProjectMappings(config, home = os.homedir()) {
  const mappings = [];
  for (const [logicalProjectId, project] of Object.entries(config.projects || {})) {
    for (const [surfaceId, surface] of Object.entries(project.surfaces || {})) {
      const aliases = new Set((surface.aliases || []).map((alias) => normalizeName(alias)).filter(Boolean));
      for (const root of surface.roots || []) {
        for (const candidate of configuredRootCandidates(root, home)) {
          let rootPath = candidate.path;
          let realRoot = rootPath;
          try { realRoot = fs.realpathSync(rootPath); } catch { /* path may disappear after config load */ }
          mappings.push({
            logicalProjectId,
            surfaceId,
            provider: surface.provider || '',
            surfaceAlias: root.alias || surface.aliases?.[0] || 'UNMAPPED',
            aliases: new Set([...aliases, normalizeName(root.alias || '')].filter(Boolean)),
            rootPath: path.resolve(rootPath),
            realRoot: path.resolve(realRoot),
            gitCommonDir: candidate.gitCommonDir || gitCommonDir(rootPath),
          });
        }
      }
    }
  }
  return mappings;
}

function sessionHints(record) {
  const payload = nestedPayload(record);
  return {
    cwd: extractRecordValue(payload, ['cwd', 'workingDirectory', 'working_directory'])
      || extractRecordValue(record, ['cwd', 'workingDirectory', 'working_directory']) || '',
    gitCommonDir: extractRecordValue(payload, ['gitCommonDir', 'git_common_dir', 'commonDir', 'common_dir'])
      || extractRecordValue(record, ['gitCommonDir', 'git_common_dir', 'commonDir', 'common_dir']) || '',
    alias: extractRecordValue(payload, ['surfaceAlias', 'surface_alias', 'alias', 'surface'])
      || extractRecordValue(record, ['surfaceAlias', 'surface_alias', 'alias', 'surface']) || '',
  };
}

function mapSessionToProject(record, mappings = [], home = os.homedir()) {
  const hints = sessionHints(record);
  const normalizedAlias = normalizeName(hints.alias);
  const cwd = typeof hints.cwd === 'string' && hints.cwd ? path.resolve(expandHome(hints.cwd, home)) : '';
  let common = typeof hints.gitCommonDir === 'string' && hints.gitCommonDir ? path.resolve(expandHome(hints.gitCommonDir, home)) : '';
  if (!common && cwd) common = gitCommonDir(cwd);

  let candidates = mappings;
  if (normalizedAlias) {
    candidates = candidates.filter((item) => item.aliases.has(normalizedAlias));
    if (candidates.length === 0) return null;
  }
  let matchedLocation = false;
  if (cwd) {
    const byRoot = candidates.filter((item) => isWithin(cwd, item.realRoot) || isWithin(cwd, item.rootPath));
    if (byRoot.length === 0 && !common) return null;
    if (byRoot.length > 0) {
      candidates = byRoot;
      matchedLocation = true;
    }
  }
  if (common) {
    const byCommon = candidates.filter((item) => item.gitCommonDir && path.resolve(item.gitCommonDir) === common);
    if (byCommon.length === 0) return null;
    candidates = byCommon;
    matchedLocation = true;
  }
  if (candidates.length === 0) return null;
  if (!matchedLocation) {
    const identities = new Set(candidates.map((item) => `${item.logicalProjectId}\u0000${item.surfaceId}`));
    if (identities.size !== 1) return null;
  }
  const maxRootLength = Math.max(...candidates.map((item) => item.realRoot.length));
  const best = matchedLocation ? candidates.filter((item) => item.realRoot.length === maxRootLength) : candidates;
  const identities = new Set(best.map((item) => `${item.logicalProjectId}\u0000${item.surfaceId}`));
  if (identities.size !== 1) return null;
  const match = best[0];
  return {
    logicalProjectId: match.logicalProjectId,
    surfaceId: match.surfaceId,
    surfaceAlias: match.surfaceAlias || 'UNMAPPED',
  };
}

function makeSourceId(value, hmacKey) {
  return hmac(`source:${value}`, hmacKey);
}

function makeRootDescriptor({ logicalProjectId = '', surfaceId, root, kind, provider = '', home, hmacKey }) {
  const candidates = configuredRootCandidates(root, home);
  const sourceAlias = root.alias || normalizeArray((root.aliases || []))[0] || 'UNMAPPED';
  return candidates.map((candidate, index) => ({
    sourceId: makeSourceId(`${kind}|${provider}|${logicalProjectId}|${surfaceId}|${candidate.path}`, hmacKey),
    logicalProjectId,
    surfaceId,
    sourceAlias,
    provider: normalizeProvider(provider) || '',
    kind,
    rootIndex: index,
    path: candidate.path,
    gitCommonDir: candidate.gitCommonDir || '',
    readOnly: root.readOnly !== false,
  }));
}

function listEntries(directory) {
  try {
    return fs.readdirSync(directory, { withFileTypes: true });
  } catch {
    return [];
  }
}

function scanSkillFiles(rootPath) {
  if (!rootPath || !fileExists(rootPath)) return [];
  let allowlistedRoot = '';
  try {
    allowlistedRoot = fs.realpathSync(rootPath);
  } catch {
    return [];
  }
  const visited = new Set();
  const files = [];
  function walk(current, depth) {
    if (depth > 10) return;
    let real;
    try {
      real = fs.realpathSync(current);
    } catch {
      return;
    }
    if (!isWithin(real, allowlistedRoot) || visited.has(real)) return;
    visited.add(real);
    for (const entry of listEntries(real)) {
      const candidate = path.join(real, entry.name);
      let stat;
      try {
        stat = fs.lstatSync(candidate);
      } catch {
        continue;
      }
      if (stat.isSymbolicLink()) {
        let target;
        try { target = fs.realpathSync(candidate); } catch { target = ''; }
        if (!target || !isWithin(target, allowlistedRoot) || visited.has(target)) continue;
      }
      if (stat.isDirectory() || stat.isSymbolicLink()) {
        let targetStat;
        try { targetStat = fs.statSync(candidate); } catch { targetStat = null; }
        if (targetStat?.isDirectory()) walk(candidate, depth + 1);
        continue;
      }
      if (!stat.isFile() || !entry.name.endsWith('.md')) continue;
      const relative = path.relative(allowlistedRoot, candidate);
      const parts = relative.split(path.sep);
      const isSkillFile = entry.name === 'SKILL.md' || parts.length === 1 || parts.includes('skills');
      if (isSkillFile) files.push({ path: candidate, relative, stat });
    }
  }
  walk(allowlistedRoot, 0);
  return files.sort((left, right) => left.relative.localeCompare(right.relative));
}

function countFiles(rootPath) {
  if (!rootPath || !fileExists(rootPath)) return 0;
  let allowlistedRoot = '';
  try { allowlistedRoot = fs.realpathSync(rootPath); } catch { return 0; }
  const visited = new Set();
  let count = 0;
  function walk(current, depth) {
    if (depth > 12) return;
    let real;
    try { real = fs.realpathSync(current); } catch { return; }
    if (!isWithin(real, allowlistedRoot) || visited.has(real)) return;
    visited.add(real);
    for (const entry of listEntries(real)) {
      const candidate = path.join(real, entry.name);
      let stat;
      try { stat = fs.lstatSync(candidate); } catch { continue; }
      if (stat.isSymbolicLink()) {
        let target;
        try { target = fs.realpathSync(candidate); } catch { target = ''; }
        if (!target || !isWithin(target, allowlistedRoot) || visited.has(target)) continue;
      }
      let actual;
      try { actual = fs.statSync(candidate); } catch { continue; }
      if (actual.isDirectory()) walk(candidate, depth + 1);
      else if (actual.isFile()) count += 1;
    }
  }
  walk(allowlistedRoot, 0);
  return count;
}

function inferSkillName(filePath, content) {
  const { data } = parseFrontmatter(content);
  const metadataName = data.skill || data.name;
  if (metadataName) return String(metadataName);
  const base = path.basename(filePath);
  if (base === 'SKILL.md') return path.basename(path.dirname(filePath));
  return base.replace(/\.md$/i, '');
}

function inferInstallationKind(rootDescriptor) {
  return rootDescriptor.kind === 'plugin' ? 'plugin' : rootDescriptor.kind;
}

function extractCapabilityTokens(name, content, fingerprintFamilies = DEFAULT_FINGERPRINT_FAMILIES) {
  const corpus = `${name || ''}\n${content || ''}`
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9]+/g, '-');
  const padded = `-${corpus.replace(/-+/g, '-')}-`;
  const allowed = [...new Set(Object.values(fingerprintFamilies || {}).flat().map(normalizeName).filter(Boolean))];
  return allowed.filter((token) => padded.includes(`-${token}-`));
}

function collectInventory(config, options = {}) {
  const home = options.home || os.homedir();
  const hmacKey = options.hmacKey || 'canuto-skill-gardener-unconfigured';
  const descriptors = [];
  for (const [logicalProjectId, project] of Object.entries(config.projects)) {
    for (const [surfaceId, surface] of Object.entries(project.surfaces)) {
      for (const root of surface.roots) {
        descriptors.push(...makeRootDescriptor({ logicalProjectId, surfaceId, root: { ...root, alias: root.alias || surface.aliases[0] || '' }, kind: 'project', provider: surface.provider, home, hmacKey }));
      }
    }
  }
  for (const provider of PROVIDERS) {
    const settings = config.providers[provider] || {};
    for (const root of settings.roots || []) {
      descriptors.push(...makeRootDescriptor({ surfaceId: 'global', root, kind: 'global', provider, home, hmacKey }));
    }
    for (const root of settings.pluginRoots || []) {
      descriptors.push(...makeRootDescriptor({ surfaceId: 'plugin', root, kind: 'plugin', provider, home, hmacKey }));
    }
    for (const root of settings.systemRoots || []) {
      descriptors.push(...makeRootDescriptor({ surfaceId: 'system', root, kind: 'system', provider, home, hmacKey }));
    }
  }
  const frameworkRoot = options.frameworkRoot || process.env.CANUTO_SKILL_GARDENER_FRAMEWORK_ROOT || path.join(__dirname, '..');
  descriptors.push(...makeRootDescriptor({
    surfaceId: 'system',
    root: { path: path.join(frameworkRoot, '.agents', 'skills'), id: 'canuto-framework' },
    kind: 'system',
    provider: 'codex',
    home,
    hmacKey,
  }));

  const installations = [];
  const byPath = new Map();
  for (const descriptor of descriptors) {
    for (const file of scanSkillFiles(descriptor.path)) {
      let content;
      try { content = fs.readFileSync(file.path, 'utf8'); } catch { continue; }
      const identity = makeSkillIdentity({
        name: inferSkillName(file.path, content),
        content,
        provider: descriptor.provider,
        installationKind: inferInstallationKind(descriptor),
        hmacKey,
      });
      let installedAt = '';
      try { installedAt = new Date(file.stat.mtimeMs).toISOString(); } catch { installedAt = ''; }
      const installation = {
        ...identity,
        logicalProjectId: descriptor.logicalProjectId || 'UNMAPPED',
        surfaceId: descriptor.surfaceId,
        sourceAlias: descriptor.sourceAlias,
        installedAt,
        metadataClass: 'CODE_METADATA',
        metadataId: hmac(`metadata:${descriptor.provider || 'framework'}:${descriptor.surfaceId}:${file.relative}`, hmacKey),
        _sourcePath: file.path,
        _capabilityTokens: extractCapabilityTokens(identity.name, content, config.policy.fingerprintFamilies),
      };
      installations.push(installation);
      byPath.set(path.resolve(file.path), installation);
      try { byPath.set(path.resolve(fs.realpathSync(file.path)), installation); } catch { /* file may rotate after scan */ }
    }
  }
  const variants = new Map();
  const byName = new Map();
  for (const installation of installations) {
    const variant = variants.get(installation.skillKey) || {
      skillKey: installation.skillKey,
      name: installation.name,
      contentHash: installation.contentHash,
      installations: [],
    };
    variant.installations.push(publicInstallation(installation));
    variants.set(installation.skillKey, variant);
    const names = byName.get(installation.name) || new Set();
    names.add(installation.skillKey);
    byName.set(installation.name, names);
  }
  const divergence = [];
  for (const [name, skillKeys] of byName) {
    if (skillKeys.size > 1) divergence.push({ name, variants: [...skillKeys].sort(), status: 'DIVERGED' });
  }
  const dedupCandidates = [];
  const byContent = new Map();
  for (const variant of variants.values()) {
    const items = byContent.get(variant.contentHash) || [];
    items.push(variant);
    byContent.set(variant.contentHash, items);
  }
  for (const items of byContent.values()) {
    const names = [...new Set(items.map((item) => item.name))].sort();
    if (names.length > 1) dedupCandidates.push({ contentHash: items[0].contentHash, names, skillKeys: items.map((item) => item.skillKey).sort() });
  }
  return {
    installations: installations.map(publicInstallation),
    variants: [...variants.values()].sort((left, right) => left.name.localeCompare(right.name)),
    divergence: divergence.sort((left, right) => left.name.localeCompare(right.name)),
    dedupCandidates: dedupCandidates.sort((left, right) => left.contentHash.localeCompare(right.contentHash)),
    _installations: installations,
    _byPath: byPath,
    _byName: byName,
  };
}

function publicInstallation(installation) {
  const output = { ...installation };
  delete output._sourcePath;
  delete output._capabilityTokens;
  return output;
}

function findSkillByPath(catalog, candidatePath, home = os.homedir(), baseDir = '') {
  if (!candidatePath || !catalog?._byPath) return null;
  const expanded = expandHome(candidatePath, home);
  const resolved = path.resolve(baseDir ? expandHome(baseDir, home) : process.cwd(), expanded);
  const direct = catalog._byPath.get(resolved);
  if (direct) return direct;
  try { return catalog._byPath.get(path.resolve(fs.realpathSync(resolved))) || null; } catch { return null; }
}

function safeText(value, max = 180) {
  if (typeof value !== 'string' && typeof value !== 'number') return '';
  return String(value).slice(0, max);
}

function extractRecordValue(record, keys) {
  for (const key of keys) {
    if (record && Object.prototype.hasOwnProperty.call(record, key)) return record[key];
  }
  return undefined;
}

function nestedPayload(record) {
  if (record && record.payload && typeof record.payload === 'object') return record.payload;
  if (record && record.data && typeof record.data === 'object') return record.data;
  return record || {};
}

function getSessionId(record, context) {
  const payload = nestedPayload(record);
  return safeText(extractRecordValue(payload, ['sessionId', 'session_id', 'session']), 160)
    || safeText(extractRecordValue(record, ['sessionId', 'session_id', 'session']), 160)
    || context.sessionId
    || '';
}

function getTimestamp(record, context) {
  const payload = nestedPayload(record);
  return iso(extractRecordValue(payload, ['timestamp', 'ts', 'date', 'time']) || extractRecordValue(record, ['timestamp', 'ts', 'date']), context.fallbackTimestamp);
}

function getNativeId(record) {
  const payload = nestedPayload(record);
  return safeText(extractRecordValue(payload, ['eventId', 'event_id', 'id', 'call_id', 'callId']), 180)
    || safeText(extractRecordValue(record, ['eventId', 'event_id', 'id']), 180);
}

function extractSkillNameFromRecord(record) {
  const payload = nestedPayload(record);
  let skill = extractRecordValue(payload, ['skill', 'skillName', 'skill_name']);
  if (!skill && payload.input && typeof payload.input === 'object') {
    skill = extractRecordValue(payload.input, ['skill', 'skillName', 'skill_name', 'name']);
  }
  if (!skill && (payload.type === 'function_call' || payload.type === 'tool_use') && typeof payload.arguments === 'string') {
    try {
      const args = JSON.parse(payload.arguments);
      skill = extractRecordValue(args, ['skill', 'skillName', 'skill_name', 'name']);
    } catch {
      skill = '';
    }
  }
  if (!skill && record && typeof record.skill === 'string') skill = record.skill;
  return normalizeName(skill);
}

function isNativeSkillRecord(record) {
  const payload = nestedPayload(record);
  const type = normalizeName(payload.type || record.type || '');
  const name = normalizeName(payload.name || record.name || '');
  return type === 'skill' || type === 'skill-usage' || type === 'skill-used' || type === 'skill-read'
    || (type === 'tool-use' && name === 'skill')
    || name === 'skill' || record.event === 'Skill' || record.event === 'skill_usage';
}

function isMissingSkillRecord(record) {
  const payload = nestedPayload(record);
  const type = normalizeName(payload.type || record.type || '');
  const event = normalizeName(payload.event || record.event || '');
  const input = payload.input && typeof payload.input === 'object' ? payload.input : {};
  return type === 'skill-missing' || type === 'skill-not-found' || event === 'skill-missing' || event === 'skill_not_found'
    || input.missing === true || input.notFound === true || input.not_found === true;
}

function resolveSkillKey(skillName, catalog, hmacKey) {
  const normalized = normalizeName(skillName);
  if (!normalized) return { skillKey: '', known: false };
  const variants = catalog?._byName?.get(normalized);
  if (variants && variants.size === 1) return { skillKey: [...variants][0], known: true };
  return { skillKey: hmac(`name:${normalized}`, hmacKey), known: false };
}

function makeEventKey({ provider, nativeId, sessionId, position, sanitizedEvent, hmacKey }) {
  if (nativeId) return hmac(`native:${provider}:${nativeId}`, hmacKey);
  return hmac(`fallback:${provider}:${sessionId || 'session-unknown'}:${position}:${sha256(stableJson(sanitizedEvent))}`, hmacKey);
}

function makeUsageEvent({ provider, context, skillKey, known, record, position, nativeId, sessionId, verification = 'native_skill_event' }) {
  const sanitized = {
    schemaVersion: SCHEMA_VERSION,
    kind: 'verified_usage',
    skillKey,
    timestamp: getTimestamp(record, context),
    provider,
    surfaceAlias: context.surfaceAlias || 'UNMAPPED',
    logicalProjectId: context.logicalProjectId || 'UNMAPPED',
    verification,
    knownSkill: known,
  };
  sanitized.eventKey = makeEventKey({
    provider,
    nativeId,
    sessionId,
    position,
    sanitizedEvent: sanitized,
    hmacKey: context.hmacKey,
  });
  return sanitized;
}

function makeMissingSignal({ provider, context, record, position, sessionId, nativeId }) {
  const skillName = extractSkillNameFromRecord(record);
  if (!skillName) return null;
  const signalKey = hmac(`missing:${skillName}`, context.hmacKey);
  const sanitized = {
    schemaVersion: SCHEMA_VERSION,
    kind: 'candidate_signal',
    signalKey,
    timestamp: getTimestamp(record, context),
    provider,
    surfaceAlias: context.surfaceAlias || 'UNMAPPED',
    logicalProjectId: context.logicalProjectId || 'UNMAPPED',
    fingerprint: 'skill-missing',
    count: 1,
  };
  sanitized.eventKey = makeEventKey({ provider, nativeId, sessionId, position, sanitizedEvent: sanitized, hmacKey: context.hmacKey });
  return sanitized;
}

function extractStructuredReadRequest(record) {
  const payload = nestedPayload(record);
  const type = normalizeName(payload.type || record.type || '');
  const name = normalizeName(payload.name || record.name || '');
  const structuredRead = ['read', 'read-file', 'file-read'].includes(name)
    && ['tool-use', 'function-call', 'read'].includes(type);
  if (!structuredRead) return null;
  let input = payload.input && typeof payload.input === 'object' ? payload.input : {};
  if (Object.keys(input).length === 0 && typeof payload.arguments === 'string') {
    try { input = JSON.parse(payload.arguments); } catch { input = {}; }
  }
  const direct = extractRecordValue(payload, ['filePath', 'file_path', 'path', 'filename'])
    || input.file_path || input.filePath || input.path;
  const readPath = safeText(direct, 1000);
  const callId = safeText(extractRecordValue(payload, ['call_id', 'callId', 'id', 'tool_use_id', 'toolUseId']), 180);
  return readPath && callId ? { readPath, callId } : null;
}

function correlatedToolResult(record) {
  const payload = nestedPayload(record);
  const type = normalizeName(payload.type || record.type || '');
  const shellCommandEnd = type === 'exec-command-end';
  if (!['function-call-output', 'tool-result', 'read-result'].includes(type) && !shellCommandEnd && record.toolUseResult === undefined) return null;
  const callId = safeText(
    extractRecordValue(payload, ['call_id', 'callId', 'tool_use_id', 'toolUseId'])
      || extractRecordValue(record, ['call_id', 'callId', 'tool_use_id', 'toolUseId']),
    180,
  );
  if (!callId) return null;
  const status = normalizeName(extractRecordValue(payload, ['status', 'result', 'result_family']) || '');
  const exitCode = extractRecordValue(payload, ['exitCode', 'exit_code']);
  const failed = payload.is_error === true || record.is_error === true
    || ['error', 'failure', 'failed', 'timeout'].includes(status)
    || (exitCode !== undefined && parseNumber(exitCode, 1) !== 0);
  const hasResult = Object.hasOwn(payload, 'output') || Object.hasOwn(payload, 'content')
    || Object.hasOwn(payload, 'result') || record.toolUseResult !== undefined
    || (shellCommandEnd && (Object.hasOwn(payload, 'exit_code') || Object.hasOwn(payload, 'exitCode') || Object.hasOwn(payload, 'status') || Object.hasOwn(payload, 'aggregated_output')));
  return { callId, success: hasResult && !failed };
}

function commandFromRecord(record) {
  const payload = nestedPayload(record);
  if (payload.input && typeof payload.input.command === 'string') return payload.input.command;
  if (payload.input && typeof payload.input.cmd === 'string') return payload.input.cmd;
  if (typeof payload.arguments === 'string') {
    try {
      const args = JSON.parse(payload.arguments);
      return typeof args.cmd === 'string' ? args.cmd : typeof args.command === 'string' ? args.command : '';
    } catch { return ''; }
  }
  return '';
}

const SHELL_TOOL_NAMES = new Set(['bash', 'exec', 'exec-command', 'run-shell-command', 'shell', 'terminal', 'zsh', 'sh']);
const SHELL_READ_COMMANDS = new Set(['awk', 'bat', 'cat', 'cut', 'diff', 'file', 'grep', 'head', 'jq', 'less', 'more', 'nl', 'rg', 'sed', 'sort', 'tail', 'tr', 'wc']);

function shellTokens(command) {
  return String(command || '').match(/(?:\\.|[^\s"'`|;&()<>])+/g) || [];
}

function cleanShellToken(token) {
  return String(token || '').replace(/^[`'"(\[]+/, '').replace(/[`'",;|&)>\]]+$/, '');
}

function shellCommandName(token) {
  return normalizeName(path.basename(String(token || '')));
}

function shellReadExecutable(command) {
  const tokens = shellTokens(command).map(cleanShellToken).filter(Boolean);
  let index = 0;
  while (index < tokens.length) {
    const token = tokens[index];
    const commandName = shellCommandName(token);
    if (commandName === 'env' || commandName === 'command' || commandName === 'sudo' || /^[A-Za-z_][A-Za-z0-9_]*=/.test(token)) {
      index += 1;
      continue;
    }
    if (commandName === 'bash' || commandName === 'sh' || commandName === 'zsh') {
      index += 1;
      while (index < tokens.length && tokens[index].startsWith('-')) index += 1;
      continue;
    }
    if (commandName === 'rtk') {
      index += 1;
      while (index < tokens.length && tokens[index].startsWith('-')) index += 1;
      continue;
    }
    return commandName;
  }
  return '';
}

function candidatePathsFromCommand(command) {
  const candidates = [];
  for (const rawToken of shellTokens(command)) {
    const token = cleanShellToken(rawToken);
    if (!/\.md$/i.test(token)) continue;
    if (!/(?:^|\/)\.(?:agents|codex|claude|hermes)\//i.test(token)) continue;
    candidates.push(token);
  }
  return [...new Set(candidates)];
}

function extractShellSkillReadRequests(record, context) {
  const payload = nestedPayload(record);
  const type = normalizeName(payload.type || record.type || '');
  const name = normalizeName(payload.name || record.name || '');
  if (!['tool-use', 'function-call', 'read', 'shell'].includes(type) && !SHELL_TOOL_NAMES.has(name)) return [];
  if (!SHELL_TOOL_NAMES.has(name) && type !== 'shell') return [];
  const command = commandFromRecord(record);
  if (!SHELL_READ_COMMANDS.has(shellReadExecutable(command))) return [];
  const callId = getNativeId(record);
  if (!callId) return [];
  const baseDir = sessionHints(record).cwd || context.cwd || '';
  return candidatePathsFromCommand(command)
    .map((candidatePath) => findSkillByPath(context.catalog, candidatePath, context.home || os.homedir(), baseDir))
    .filter(Boolean)
    .map((installation) => ({ callId, skillKey: installation.skillKey }));
}

function fingerprintSignal(record, context) {
  const payload = nestedPayload(record);
  const families = context.fingerprintFamilies || DEFAULT_FINGERPRINT_FAMILIES;
  const command = commandFromRecord(record);
  const toolName = normalizeName(extractRecordValue(payload, ['toolFamily', 'tool_family', 'tool']))
    || (payload.type === 'tool_use' || payload.type === 'function_call' ? normalizeName(payload.name) : '');
  const tool = ['bash', 'exec-command', 'exec-command', 'shell', 'exec'].includes(toolName) ? 'shell' : toolName;
  const executable = normalizeName(extractRecordValue(payload, ['executableFamily', 'executable_family', 'executable']))
    || normalizeName((command.match(/^\s*(?:env\s+)?(?:command\s+)?([A-Za-z0-9._-]+)/) || [])[1]);
  const result = normalizeName(extractRecordValue(payload, ['resultFamily', 'result_family', 'result']));
  const parts = [tool, executable, result].filter(Boolean);
  const allowed = (value, list) => value && list.includes(value);
  if (!allowed(tool, families.tools || []) && !allowed(executable, families.executables || []) && !allowed(result, families.results || [])) return null;
  const allowedParts = [
    allowed(tool, families.tools || []) ? `tool:${tool}` : '',
    allowed(executable, families.executables || []) ? `exe:${executable}` : '',
    allowed(result, families.results || []) ? `result:${result}` : '',
  ].filter(Boolean);
  if (allowedParts.length < 2 || parts.length < 2) return null;
  const count = Math.max(1, Math.min(100000, Math.floor(parseNumber(extractRecordValue(payload, ['count', 'occurrences']), 1))));
  const fingerprint = allowedParts.join('|');
  return {
    fingerprint,
    count,
    signalKey: hmac(`fingerprint:${fingerprint}`, context.hmacKey),
  };
}

function updateSessionContext(record, context) {
  const hints = sessionHints(record);
  const hasHints = Boolean(hints.cwd || hints.gitCommonDir || hints.alias);
  if (hints.cwd) context.cwd = safeText(hints.cwd, 2000);
  if (!hasHints || context.mapSessions !== true) return;
  const mapped = mapSessionToProject(record, context.projectMappings || [], context.home || os.homedir());
  if (mapped) {
    context.logicalProjectId = mapped.logicalProjectId;
    context.surfaceAlias = mapped.surfaceAlias;
    context.surfaceId = mapped.surfaceId;
    return;
  }
  context.logicalProjectId = 'UNMAPPED';
  context.surfaceAlias = 'UNMAPPED';
  context.surfaceId = 'UNMAPPED';
}

function expandRealProviderRecords(provider, record) {
  if (provider === 'codex' && record.type === 'response_item') {
    const payload = record.payload || {};
    if (!['function_call', 'function_call_output'].includes(payload.type)) return [];
    return [{
      ...payload,
      sessionId: record.sessionId || record.session_id || '',
      timestamp: record.timestamp || payload.timestamp || '',
      cwd: record.cwd || payload.cwd || '',
      __normalizedProviderRecord: true,
    }];
  }
  if (provider === 'claude' && record.type === 'assistant' && record.message) {
    const content = Array.isArray(record.message.content) ? record.message.content : [];
    return content
      .filter((chunk) => chunk && chunk.type === 'tool_use')
      .map((chunk) => ({
        ...chunk,
        type: 'tool_use',
        sessionId: record.sessionId || record.session_id || '',
        timestamp: record.timestamp || '',
        cwd: record.cwd || '',
        __normalizedProviderRecord: true,
      }));
  }
  if (provider === 'claude' && record.type === 'user' && record.message) {
    const content = Array.isArray(record.message.content) ? record.message.content : [];
    return content
      .filter((chunk) => chunk && chunk.type === 'tool_result')
      .map((chunk) => ({
        ...chunk,
        type: 'tool_result',
        sessionId: record.sessionId || record.session_id || '',
        timestamp: record.timestamp || '',
        cwd: record.cwd || '',
        __normalizedProviderRecord: true,
      }));
  }
  if (provider === 'hermes' && Array.isArray(record.content)) {
    return record.content
      .filter((chunk) => chunk && ['tool-use', 'tool-result'].includes(normalizeName(chunk.type)))
      .map((chunk) => ({
        ...chunk,
        type: normalizeName(chunk.type) === 'tool-use' ? 'tool_use' : 'tool_result',
        sessionId: record.sessionId || record.session_id || '',
        timestamp: record.timestamp || '',
        cwd: record.cwd || '',
        __normalizedProviderRecord: true,
      }));
  }
  return [];
}

function parseProviderRecord(provider, record, context, position) {
  if (!record || typeof record !== 'object' || Array.isArray(record)) return { error: 'schema-invalid' };
  updateSessionContext(record, context);
  if (!record.__normalizedProviderRecord) {
    const realRecords = expandRealProviderRecords(provider, record);
    if (realRecords.length > 0) {
      const events = [];
      for (const realRecord of realRecords) {
        const result = parseProviderRecord(provider, realRecord, context, position);
        if (result.error) return result;
        events.push(...(result.events || []));
      }
      return { events };
    }
  }
  const payload = nestedPayload(record);
  if (record.type === 'session_meta' || payload.type === 'session_meta') {
    context.sessionId = safeText(record.payload?.id || payload.id || record.sessionId, 160) || context.sessionId;
    context.fallbackTimestamp = iso(record.payload?.timestamp || payload.timestamp, context.fallbackTimestamp);
    return { events: [] };
  }
  const sessionId = getSessionId(record, context);
  const nativeId = getNativeId(record);
  const events = [];
  const toolResult = correlatedToolResult(record);
  if (toolResult) {
    const pending = context.pendingSkillReads?.get(toolResult.callId);
    if (pending) {
      context.pendingSkillReads.delete(toolResult.callId);
      if (toolResult.success) {
        for (const skillKey of pending.skillKeys || [pending.skillKey]) {
          events.push(makeUsageEvent({
            provider,
            context,
            skillKey,
            known: true,
            record,
            position,
            nativeId: `${toolResult.callId}:confirmed-read:${skillKey}`,
            sessionId,
            verification: 'confirmed_skill_file_read',
          }));
        }
      }
    }
    return { events };
  }
  if (isMissingSkillRecord(record)) {
    const signal = makeMissingSignal({ provider, context, record, position, sessionId, nativeId });
    if (signal) events.push(signal);
  } else if (isNativeSkillRecord(record)) {
    const skillName = extractSkillNameFromRecord(record);
    if (skillName) {
      const resolved = resolveSkillKey(skillName, context.catalog, context.hmacKey);
      events.push(makeUsageEvent({ provider, context, skillKey: resolved.skillKey, known: resolved.known, record, position, nativeId, sessionId }));
    }
  } else {
    const readRequest = extractStructuredReadRequest(record);
    const shellRequests = extractShellSkillReadRequests(record, context);
    const installations = [];
    if (readRequest) {
      const installation = findSkillByPath(context.catalog, readRequest.readPath, context.home || os.homedir(), context.cwd || '');
      if (installation) installations.push({ callId: readRequest.callId, skillKey: installation.skillKey });
    }
    installations.push(...shellRequests);
    if (installations.length > 0) {
      if (!context.pendingSkillReads) context.pendingSkillReads = new Map();
      const byCallId = new Map();
      for (const request of installations) {
        const skillKeys = byCallId.get(request.callId) || [];
        if (!skillKeys.includes(request.skillKey)) skillKeys.push(request.skillKey);
        byCallId.set(request.callId, skillKeys);
      }
      for (const [callId, skillKeys] of byCallId) context.pendingSkillReads.set(callId, { skillKeys });
    }
    const fingerprint = fingerprintSignal(record, context);
    if (fingerprint) {
      events.push({
        schemaVersion: SCHEMA_VERSION,
        kind: 'candidate_signal',
        signalKey: fingerprint.signalKey,
        timestamp: getTimestamp(record, context),
        provider,
        surfaceAlias: context.surfaceAlias || 'UNMAPPED',
        logicalProjectId: context.logicalProjectId || 'UNMAPPED',
        fingerprint: fingerprint.fingerprint,
        count: fingerprint.count,
        eventKey: makeEventKey({ provider, nativeId: nativeId ? `${nativeId}:fingerprint` : '', sessionId, position, sanitizedEvent: fingerprint, hmacKey: context.hmacKey }),
      });
    }
  }
  return { events };
}

function validateClosedEvent(event) {
  if (!event || typeof event !== 'object' || Array.isArray(event)) return false;
  if (!VALID_KINDS.has(event.kind) || event.schemaVersion !== SCHEMA_VERSION) return false;
  if (Object.keys(event).some((key) => !CLOSED_REMOTE_KEYS.has(key) && key !== 'knownSkill')) return false;
  if (!/^[a-f0-9]{64}$/i.test(event.eventKey || '')) return false;
  if (typeof event.timestamp !== 'string' || !Number.isFinite(Date.parse(event.timestamp))) return false;
  for (const key of ['provider', 'surfaceAlias', 'logicalProjectId', 'verification', 'fingerprint']) {
    if (event[key] !== undefined && typeof event[key] !== 'string') return false;
  }
  if (event.provider !== undefined && normalizeProvider(event.provider) !== event.provider) return false;
  if (event.count !== undefined && (typeof event.count !== 'number' || !Number.isFinite(event.count) || event.count < 0)) return false;
  if (event.knownSkill !== undefined && typeof event.knownSkill !== 'boolean') return false;
  if (event.kind === 'verified_usage' && (!/^[a-f0-9]{64}$/i.test(event.skillKey || '') || typeof event.verification !== 'string' || !event.verification)) return false;
  if (event.kind === 'candidate_signal' && (!/^[a-f0-9]{64}$/i.test(event.signalKey || '') || typeof event.fingerprint !== 'string' || !event.fingerprint)) return false;
  return true;
}

function validateRemoteEvent(event) {
  if (!validateClosedEvent(event)) return false;
  return Object.keys(event).every((key) => CLOSED_REMOTE_KEYS.has(key) || key === 'knownSkill');
}

function parseHermesSessionDocument(text) {
  const trimmed = String(text || '').trim();
  if (!trimmed.startsWith('{')) return null;
  let document;
  try { document = JSON.parse(trimmed); } catch { return null; }
  if (!document || typeof document !== 'object' || Array.isArray(document) || !Object.hasOwn(document, 'messages')) return null;
  if (!Array.isArray(document.messages)) return { error: 'schema-invalid' };
  const sessionId = safeText(document.session_id || document.sessionId || document.id, 160);
  const timestamp = safeText(document.session_start || document.sessionStart || document.started_at || document.timestamp || document.created_at || document.createdAt || document.last_updated || document.lastUpdated, 80);
  const cwd = safeText(document.cwd || document.working_directory || document.workingDirectory, 2000);
  const records = [];
  for (const message of document.messages) {
    if (!message || typeof message !== 'object' || Array.isArray(message)) return { error: 'schema-invalid' };
    records.push({
      ...message,
      session_id: message.session_id || message.sessionId || sessionId,
      sessionId: message.sessionId || message.session_id || sessionId,
      timestamp: message.timestamp || message.created_at || message.createdAt || timestamp,
      cwd: message.cwd || message.working_directory || message.workingDirectory || cwd,
    });
  }
  return { records };
}

function parseProviderNdjson({ provider, text, context = {}, lineLimit = MAX_LINE_BYTES, ...input }) {
  const normalizedProvider = normalizeProvider(provider);
  if (!normalizedProvider || typeof text !== 'string') return { ok: false, reason: 'schema-invalid', events: [] };
  const runtimeContext = {
    ...input,
    ...context,
    provider: normalizedProvider,
    hmacKey: input.hmacKey || context.hmacKey || 'canuto-skill-gardener-unconfigured',
    catalog: input.catalog || context.catalog || { _byPath: new Map(), _byName: new Map() },
    fallbackTimestamp: input.fallbackTimestamp || context.fallbackTimestamp || new Date(0).toISOString(),
    sessionId: input.sessionId || context.sessionId || '',
    logicalProjectId: input.logicalProjectId || context.logicalProjectId || 'UNMAPPED',
    surfaceAlias: input.surfaceAlias || context.surfaceAlias || 'UNMAPPED',
    mapSessions: input.mapSessions === true || context.mapSessions === true,
  };
  const events = [];
  const effectiveLineLimit = Math.min(MAX_LINE_BYTES, Math.max(1, parseNumber(lineLimit, MAX_LINE_BYTES)));
  const hermesDocument = normalizedProvider === 'hermes' ? parseHermesSessionDocument(text) : null;
  if (hermesDocument?.error) return { ok: false, reason: hermesDocument.error, events: [] };
  const items = hermesDocument
    ? hermesDocument.records.map((record, position) => ({ position, line: '', record }))
    : iterateJsonlRecords(text, effectiveLineLimit);
  for (const item of items) {
    const { position, line } = item;
    if (line && Buffer.byteLength(line) > effectiveLineLimit) return { ok: false, reason: 'line-overflow', events: [] };
    if (item.error || !item.record) return { ok: false, reason: item.error || 'schema-invalid', events: [] };
    const record = item.record;
    const result = parseProviderRecord(normalizedProvider, record, runtimeContext, position);
    if (result.error) return { ok: false, reason: result.error, events: [] };
    for (const event of result.events || []) {
      if (!validateClosedEvent(event)) return { ok: false, reason: 'schema-invalid', events: [] };
      events.push(event);
    }
  }
  return { ok: true, events };
}

function* iterateJsonlRecords(text, lineLimit = MAX_LINE_BYTES) {
  const lines = String(text || '').split(/\r?\n/);
  for (let position = 0; position < lines.length; position += 1) {
    const line = lines[position];
    if (!line.trim()) continue;
    if (Buffer.byteLength(line) > lineLimit) {
      yield { position, line, record: null, error: 'line-overflow' };
      continue;
    }
    try {
      yield { position, line, record: JSON.parse(line) };
    } catch {
      yield { position, line, record: null, error: 'schema-invalid' };
    }
  }
}

function parseCodexEvents(input) { return parseProviderNdjson({ ...input, provider: 'codex' }); }
function parseClaudeEvents(input) { return parseProviderNdjson({ ...input, provider: 'claude' }); }
function parseHermesEvents(input) { return parseProviderNdjson({ ...input, provider: 'hermes' }); }

function sanitizeStructuredEvent(raw, options = {}) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const allowed = new Set(['schemaVersion', 'kind', 'eventKey', 'skillKey', 'signalKey', 'timestamp', 'provider', 'surfaceAlias', 'logicalProjectId', 'verification', 'fingerprint', 'count', 'knownSkill']);
  if (Object.keys(raw).some((key) => !allowed.has(key))) return null;
  const event = { ...raw, schemaVersion: SCHEMA_VERSION };
  if (event.provider && normalizeProvider(event.provider) !== event.provider) return null;
  if (options.expectedProvider && event.provider !== options.expectedProvider) return null;
  return validateClosedEvent(event) ? event : null;
}

function parseRemoteNdjson(text, options = {}) {
  if (typeof text !== 'string' || Buffer.byteLength(text) > MAX_REMOTE_STDOUT_BYTES) return { ok: false, reason: 'stdout-overflow', events: [] };
  const events = [];
  for (const line of text.split(/\r?\n/)) {
    if (!line.trim()) continue;
    if (Buffer.byteLength(line) > MAX_LINE_BYTES) return { ok: false, reason: 'line-overflow', events: [] };
    let raw;
    try { raw = JSON.parse(line); } catch { return { ok: false, reason: 'schema-invalid', events: [] }; }
    const event = sanitizeStructuredEvent(raw, options);
    if (!event) return { ok: false, reason: 'schema-invalid', events: [] };
    events.push(event);
  }
  return { ok: true, events };
}

function buildRemoteCollectorScript({ provider, historyRoots = [], skillKeys = {}, skillVariants = {}, hmacKey = '', surfaceAlias = 'UNMAPPED', logicalProjectId = '', projectMappings = [] }) {
  const variantLookup = Object.keys(skillVariants).length > 0 ? skillVariants : skillKeys;
  const flatSkillKeys = {};
  for (const [name, variants] of Object.entries(variantLookup)) {
    if (typeof variants === 'string') {
      flatSkillKeys[name] = variants;
      continue;
    }
    if (!variants || typeof variants !== 'object' || Array.isArray(variants)) continue;
    const keys = [...new Set(Object.values(variants).filter((value) => typeof value === 'string'))];
    if (keys.length === 1) flatSkillKeys[name] = keys[0];
  }
  const payload = JSON.stringify({ provider, historyRoots, skillKeys: flatSkillKeys, skillVariants: variantLookup, hmacKey, surfaceAlias, logicalProjectId, projectMappings });
  return `#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const cfg = ${payload};
const rawSkillKeys = cfg.skillKeys || {};
cfg.skillKeys = new Proxy(rawSkillKeys, { get: (target, property) => target[property] || (/^[a-f0-9]{64}$/i.test(String(property)) ? String(property) : undefined) });
const key = cfg.hmacKey || 'canuto-skill-gardener-unconfigured';
const h = (value) => crypto.createHmac('sha256', key).update(String(value)).digest('hex');
const iso = (value) => { const parsed = Date.parse(String(value || '')); return Number.isFinite(parsed) ? new Date(parsed).toISOString() : new Date(0).toISOString(); };
const MAX_LINE = ${MAX_LINE_BYTES};
const MAX_STDOUT = ${MAX_REMOTE_STDOUT_BYTES};
const normalize = (value) => String(value || '').toLowerCase().normalize('NFD').replace(/[\\u0300-\\u036f]/g, '').replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
const expandHome = (value) => { const text = String(value || ''); const home = os.homedir(); if (text === '~') return home; if (text.startsWith('~/')) return path.join(home, text.slice(2)); return text.replace(/^\\$HOME(?=\\/|$)/, home); };
const within = (child, parent) => { const relative = path.relative(parent, child); return relative === '' || (relative !== '..' && !relative.startsWith('..' + path.sep) && !path.isAbsolute(relative)); };
let stdoutBytes = 0;
const emit = (event) => { const line = JSON.stringify(event) + '\\n'; stdoutBytes += Buffer.byteLength(line); if (stdoutBytes > MAX_STDOUT) throw new Error('stdout-overflow'); process.stdout.write(line); };
const parsedInput = (payload) => { if (payload.input && typeof payload.input === 'object') return payload.input; if (typeof payload.arguments === 'string') { try { return JSON.parse(payload.arguments); } catch { return {}; } } return {}; };
const sessionHints = (record) => { const payload = record && record.payload && typeof record.payload === 'object' ? record.payload : record || {}; return { cwd: payload.cwd || payload.working_directory || payload.workingDirectory || record.cwd || record.working_directory || record.workingDirectory || '' }; };
const mapSession = (record) => { const cwdHint = sessionHints(record).cwd; if (!cwdHint || !Array.isArray(cfg.projectMappings) || cfg.projectMappings.length === 0) return null; const cwd = path.resolve(expandHome(cwdHint)); const candidates = []; for (const mapping of cfg.projectMappings) for (const root of mapping.roots || []) { const resolvedRoot = path.resolve(expandHome(root)); if (within(cwd, resolvedRoot)) candidates.push({ mapping, length: resolvedRoot.length }); } if (candidates.length === 0) return null; const maxLength = Math.max(...candidates.map((item) => item.length)); const best = candidates.filter((item) => item.length === maxLength); const identities = new Set(best.map((item) => item.mapping.logicalProjectId + '\\u0000' + item.mapping.surfaceId)); return identities.size === 1 ? best[0].mapping : null; };
const mappingValues = (state) => { if (Array.isArray(cfg.projectMappings) && cfg.projectMappings.length > 0) { if (!state.mapping) return null; return { logicalProjectId: state.mapping.logicalProjectId || 'UNMAPPED', surfaceAlias: state.mapping.surfaceAlias || 'UNMAPPED' }; } return { logicalProjectId: cfg.logicalProjectId || 'UNMAPPED', surfaceAlias: cfg.surfaceAlias || 'UNMAPPED' }; };
const skillVariants = cfg.skillVariants || {};
const maxSkillBytes = 4 * 1024 * 1024;
const sha256 = (value) => crypto.createHash('sha256').update(value).digest('hex');
const skillFromPath = (value) => { const parts = String(value || '').split('/'); const marker = parts.findIndex((part) => ['.agents', '.codex', '.claude', '.hermes'].includes(part.toLowerCase())); if (marker < 0) return ''; const skills = parts.findIndex((part, index) => index > marker && part.toLowerCase() === 'skills'); const name = skills >= 0 ? parts[skills + 1] : ''; const last = parts[parts.length - 1] || ''; return name && /\\.md$/i.test(last) ? normalize(name) : ''; };
const skillPathInfo = (value, record) => { const raw = String(value || ''); if (!raw) return null; const expanded = expandHome(raw); const cwd = sessionHints(record || {}).cwd || process.cwd(); const absolute = path.resolve(path.isAbsolute(expanded) ? expanded : path.join(expandHome(cwd), expanded)); const parts = absolute.split(path.sep); const markerIndex = parts.findIndex((part) => ['.agents', '.codex', '.claude', '.hermes'].includes(part.toLowerCase())); if (markerIndex < 0) return null; const marker = parts[markerIndex].toLowerCase(); const skillsIndex = parts.findIndex((part, index) => index > markerIndex && part.toLowerCase() === 'skills'); const name = skillsIndex >= 0 ? normalize(parts[skillsIndex + 1]) : ''; const last = parts[parts.length - 1] || ''; if (!name || !/\\.md$/i.test(last)) return null; const allowedRoots = []; if (['.codex', '.claude', '.hermes'].includes(marker)) allowedRoots.push(path.join(os.homedir(), marker)); if (marker === '.agents') for (const mapping of cfg.projectMappings || []) for (const root of mapping.roots || []) allowedRoots.push(path.join(path.resolve(expandHome(root)), '.agents')); for (const allowedRoot of allowedRoots) { if (!within(absolute, path.resolve(allowedRoot))) continue; try { const realRoot = fs.realpathSync(allowedRoot); const realFile = fs.realpathSync(absolute); const stat = fs.statSync(realFile); if (!stat.isFile() || !within(realFile, realRoot) || stat.size > maxSkillBytes) continue; return { name, file: realFile }; } catch {} } return null; };
const readSkillHash = (file) => { let fd; try { fd = fs.openSync(file, 'r'); const initial = fs.fstatSync(fd); if (!initial.isFile() || initial.size > maxSkillBytes) return ''; const buffer = Buffer.allocUnsafe(Math.min(maxSkillBytes + 1, Math.max(1, initial.size + 1))); const bytes = fs.readSync(fd, buffer, 0, buffer.length, 0); const final = fs.fstatSync(fd); if (!final.isFile() || final.size > maxSkillBytes || final.size !== bytes) return ''; return sha256(buffer.subarray(0, bytes)); } catch { return ''; } finally { if (fd !== undefined) try { fs.closeSync(fd); } catch {} } };
const keyForPath = (value, record) => { const info = skillPathInfo(value, record); if (!info) return ''; const contentHash = readSkillHash(info.file); if (!contentHash) return ''; const variants = skillVariants[info.name]; return variants && typeof variants === 'object' && typeof variants[contentHash] === 'string' ? variants[contentHash] : ''; };
const shellReadCommands = new Set(['awk', 'bat', 'cat', 'cut', 'diff', 'file', 'grep', 'head', 'jq', 'less', 'more', 'nl', 'rg', 'sed', 'sort', 'tail', 'tr', 'wc']);
const shellToolNames = new Set(['bash', 'exec', 'exec-command', 'run-shell-command', 'shell', 'terminal', 'zsh', 'sh']);
const commandText = (payload) => { const input = parsedInput(payload); return typeof input.command === 'string' ? input.command : typeof input.cmd === 'string' ? input.cmd : ''; };
const shellExecutable = (command) => { const tokens = String(command || '').trim().split(/\\s+/).map((token) => token.replace(/^['"(\\[]+/, '').replace(/['",;|&)>\\]]+$/, '')).filter(Boolean); let index = 0; while (index < tokens.length) { const token = tokens[index]; const commandName = normalize(path.basename(token)); if (commandName === 'env' || commandName === 'command' || commandName === 'sudo' || /^[A-Za-z_][A-Za-z0-9_]*=/.test(token)) { index += 1; continue; } if (commandName === 'bash' || commandName === 'sh' || commandName === 'zsh') { index += 1; while (index < tokens.length && tokens[index].startsWith('-')) index += 1; continue; } if (commandName === 'rtk') { index += 1; while (index < tokens.length && tokens[index].startsWith('-')) index += 1; continue; } return commandName; } return ''; };
const shellSkills = (payload) => { const command = commandText(payload); if (!shellReadCommands.has(shellExecutable(command))) return []; return String(command).trim().split(/\\s+/).map((token) => token.replace(/^['"(\\[]+/, '').replace(/['",;|&)>\\]]+$/, '')).map((token) => keyForPath(token, payload)).filter(Boolean); };
const skillName = (payload, record) => { const input = parsedInput(payload); const direct = payload.skill || payload.skillName || payload.skill_name || input.skill || input.skillName || record.skill; if (direct) return normalize(direct); const readPath = input.file_path || input.filePath || input.path; return readPath ? keyForPath(readPath, payload || record) : ''; };
const recordsFor = (record) => { if (cfg.provider === 'codex' && record.type === 'response_item') { const payload = record.payload || {}; return ['function_call', 'function_call_output'].includes(payload.type) ? [{ ...payload, cwd: record.cwd || payload.cwd || '', timestamp: record.timestamp || payload.timestamp || '', session_id: record.session_id || payload.session_id || '' }] : []; } if (cfg.provider === 'codex' && record.payload && typeof record.payload === 'object') return [{ ...record, ...record.payload, cwd: record.cwd || record.payload.cwd || '', timestamp: record.timestamp || record.payload.timestamp || '', session_id: record.session_id || record.payload.session_id || '' }]; if (cfg.provider === 'claude' && ['assistant', 'user'].includes(record.type)) return (Array.isArray(record.message?.content) ? record.message.content : []).filter((chunk) => ['tool_use', 'tool_result'].includes(chunk?.type)).map((chunk) => ({ ...chunk, timestamp: record.timestamp || chunk.timestamp || '', cwd: record.cwd || chunk.cwd || '', session_id: record.session_id || chunk.session_id || '' })); if (cfg.provider === 'hermes' && Array.isArray(record.content)) return record.content.filter((chunk) => chunk && ['tool_use', 'tool_result', 'tool-use', 'tool-result'].includes(chunk.type)).map((chunk) => ({ ...chunk, type: normalize(chunk.type) === 'tool-use' ? 'tool_use' : 'tool_result', timestamp: record.timestamp || chunk.timestamp || '', cwd: record.cwd || chunk.cwd || '', session_id: record.session_id || chunk.session_id || '' })); return [record]; };
const processRecord = (record, position, state) => { const hints = sessionHints(record); if (hints.cwd) state.mapping = mapSession(record); if (record.session_id || record.sessionId || record.payload?.session_id || record.payload?.sessionId) state.sessionId = String(record.session_id || record.sessionId || record.payload.session_id || record.payload.sessionId); for (const payload of recordsFor(record)) { const mapped = mappingValues(state); if (!mapped) continue; const input = parsedInput(payload); const type = normalize(payload.type || record.type); const name = normalize(payload.name || record.name); const skill = skillName(payload, record); const nativeId = String(payload.eventId || payload.event_id || payload.id || payload.call_id || record.eventId || record.event_id || ''); const resultId = String(payload.call_id || payload.tool_use_id || payload.toolUseId || record.call_id || record.tool_use_id || ''); const session = String(payload.sessionId || payload.session_id || record.sessionId || record.session_id || state.sessionId || 'remote'); const timestamp = iso(payload.timestamp || payload.ts || record.timestamp); const provider = cfg.provider; const keyFor = (nameValue) => cfg.skillKeys[nameValue] || h('name:' + nameValue); const isResult = ['function-call-output', 'tool-result', 'read-result', 'exec-command-end'].includes(type); if (isResult && resultId) { const pending = state.pendingReads.get(resultId); state.pendingReads.delete(resultId); const status = normalize(payload.status || payload.result_family || ''); const failed = payload.is_error === true || ['error', 'failure', 'failed', 'timeout'].includes(status) || (payload.exit_code !== undefined && Number(payload.exit_code) !== 0); const hasResult = Object.prototype.hasOwnProperty.call(payload, 'output') || Object.prototype.hasOwnProperty.call(payload, 'content') || Object.prototype.hasOwnProperty.call(payload, 'result') || (type === 'exec-command-end' && (Object.prototype.hasOwnProperty.call(payload, 'exit_code') || Object.prototype.hasOwnProperty.call(payload, 'exitCode') || Object.prototype.hasOwnProperty.call(payload, 'status') || Object.prototype.hasOwnProperty.call(payload, 'aggregated_output'))); if (pending && hasResult && !failed) for (const pendingKey of pending.skillKeys) emit({ schemaVersion: 1, kind: 'verified_usage', eventKey: h('native:' + provider + ':' + resultId + ':confirmed-read:' + pendingKey), skillKey: pendingKey, timestamp, provider, surfaceAlias: mapped.surfaceAlias, logicalProjectId: mapped.logicalProjectId, verification: 'confirmed_skill_file_read' }); continue; } const isSkill = type === 'skill' || type === 'skill-usage' || type === 'skill-used' || name === 'skill' || record.event === 'Skill'; if (isSkill && skill) { const key = keyFor(skill); emit({ schemaVersion: 1, kind: 'verified_usage', eventKey: nativeId ? h('native:' + provider + ':' + nativeId) : h('fallback:' + provider + ':' + session + ':' + position + ':' + key), skillKey: key, timestamp, provider, surfaceAlias: mapped.surfaceAlias, logicalProjectId: mapped.logicalProjectId, verification: 'native_skill_event' }); continue; } if ((type === 'skill-missing' || record.event === 'skill-missing' || input.missing === true) && skill) { emit({ schemaVersion: 1, kind: 'candidate_signal', eventKey: nativeId ? h('native:' + provider + ':' + nativeId) : h('fallback:' + provider + ':' + session + ':' + position + ':' + skill), signalKey: h('missing:' + skill), timestamp, provider, surfaceAlias: mapped.surfaceAlias, logicalProjectId: mapped.logicalProjectId, fingerprint: 'skill-missing', count: 1 }); continue; } const directRead = ['read', 'read-file', 'file-read'].includes(name) && ['tool-use', 'function-call', 'read'].includes(type) && skill && nativeId; const shellRead = shellToolNames.has(name) || type === 'shell'; const shellSkillNames = shellRead ? [...new Set(shellSkills(payload))] : []; const requestedSkills = directRead ? [skill] : shellSkillNames; if (requestedSkills.length > 0 && nativeId) state.pendingReads.set(nativeId, { skillKeys: [...new Set(requestedSkills.map(keyFor))] }); } };
const readLines = async function* (file) { const stream = fs.createReadStream(file, { encoding: 'utf8' }); let pending = ''; for await (const chunk of stream) { const lines = (pending + chunk).split(/\\r?\\n/); pending = lines.pop() || ''; if (Buffer.byteLength(pending) > MAX_LINE + 2) throw new Error('line-overflow'); for (const line of lines) { if (Buffer.byteLength(line) > MAX_LINE) throw new Error('line-overflow'); yield line; } } if (pending) { if (Buffer.byteLength(pending) > MAX_LINE) throw new Error('line-overflow'); yield pending; } };
const collectFiles = (root, depth, allowlistedRoot, files) => { if (depth > 8) return; const entries = fs.readdirSync(root, { withFileTypes: true }); for (const entry of entries) { const file = path.join(root, entry.name); const linkStat = fs.lstatSync(file); let real = file; if (linkStat.isSymbolicLink()) { real = fs.realpathSync(file); if (!within(real, allowlistedRoot)) continue; } if (linkStat.isDirectory() || (linkStat.isSymbolicLink() && fs.statSync(file).isDirectory())) collectFiles(file, depth + 1, allowlistedRoot, files); else if ((linkStat.isFile() || (linkStat.isSymbolicLink() && fs.statSync(file).isFile())) && (file.endsWith('.jsonl') || file.endsWith('.json'))) files.push(file); } };
const hermesDocumentRecords = (file) => { const text = fs.readFileSync(file, 'utf8'); if (Buffer.byteLength(text) > MAX_STDOUT) throw new Error('document-overflow'); let document; try { document = JSON.parse(text); } catch { throw new Error('schema-invalid'); } if (!document || typeof document !== 'object' || Array.isArray(document)) throw new Error('schema-invalid'); if (!Object.prototype.hasOwnProperty.call(document, 'messages')) return [document]; if (!Array.isArray(document.messages)) throw new Error('schema-invalid'); const sessionId = document.session_id || document.sessionId || document.id || ''; const timestamp = document.session_start || document.sessionStart || document.started_at || document.timestamp || document.created_at || document.createdAt || document.last_updated || document.lastUpdated || ''; const cwd = document.cwd || document.working_directory || document.workingDirectory || ''; return document.messages.map((message) => { if (!message || typeof message !== 'object' || Array.isArray(message)) throw new Error('schema-invalid'); return { ...message, session_id: message.session_id || message.sessionId || sessionId, sessionId: message.sessionId || message.session_id || sessionId, timestamp: message.timestamp || message.created_at || message.createdAt || timestamp, cwd: message.cwd || message.working_directory || message.workingDirectory || cwd }; }); };
const main = async () => { if (cfg.provider === 'opencode') throw new Error('not-implemented'); const files = []; for (const configuredRoot of (cfg.historyRoots || [])) { if (typeof configuredRoot !== 'string' || !configuredRoot) continue; const resolvedRoot = path.resolve(expandHome(configuredRoot)); const rootStat = fs.lstatSync(resolvedRoot); const allowlistedRoot = fs.realpathSync(resolvedRoot); if (!rootStat.isDirectory() && !fs.statSync(resolvedRoot).isDirectory()) throw new Error('root-invalid'); collectFiles(allowlistedRoot, 0, allowlistedRoot, files); } for (const file of [...new Set(files)].sort()) { const state = { mapping: null, sessionId: '', pendingReads: new Map() }; if (cfg.provider === 'hermes' && file.endsWith('.json')) { for (const [position, record] of hermesDocumentRecords(file).entries()) processRecord(record, position, state); continue; } let position = 0; for await (const line of readLines(file)) { if (!line.trim()) continue; let record; try { record = JSON.parse(line); } catch { throw new Error('schema-invalid'); } if (!record || typeof record !== 'object' || Array.isArray(record)) throw new Error('schema-invalid'); processRecord(record, position, state); position += 1; } } };
main().catch(() => { process.stderr.write('remote-collector-failed\\n'); process.exitCode = 1; });
`;
}

function collectRemoteSource({ alias, payload, spawnImpl = spawn, connectTimeoutMs = REMOTE_CONNECT_TIMEOUT_MS, executionTimeoutMs = REMOTE_EXECUTION_TIMEOUT_MS, stdoutLimit = MAX_REMOTE_STDOUT_BYTES, stderrLimit = MAX_REMOTE_STDERR_BYTES }) {
  return new Promise((resolve) => {
    let child;
    try {
      child = spawnImpl('ssh', ['-o', `ConnectTimeout=${Math.ceil(connectTimeoutMs / 1000)}`, '-T', '--', alias, 'node', '-'], { stdio: ['pipe', 'pipe', 'pipe'] });
    } catch (error) {
      resolve({ ok: false, partial: true, reason: `spawn:${error.code || 'error'}`, events: [] });
      return;
    }
    let stdoutPending = '';
    const remoteEvents = [];
    let stdoutReason = '';
    let stderr = '';
    let stdoutBytes = 0;
    let stderrBytes = 0;
    let settled = false;
    let connectionTimer;
    let executionTimer;
    const finish = (result) => {
      if (settled) return;
      settled = true;
      clearTimeout(connectionTimer);
      clearTimeout(executionTimer);
      resolve(result);
    };
    const stop = (reason) => {
      if (settled) return;
      stdoutReason = reason;
      try { child.kill('SIGKILL'); } catch { /* child may already be closed */ }
      finish({ ok: false, partial: true, reason, events: [] });
    };
    const consumeLine = (line) => {
      if (!line.trim()) return true;
      const parsed = parseRemoteNdjson(`${line}\n`, { expectedProvider: normalizeProvider(payload.provider) });
      if (!parsed.ok) {
        stop(parsed.reason);
        return false;
      }
      remoteEvents.push(...parsed.events);
      return true;
    };
    connectionTimer = setTimeout(() => stop('connection-timeout'), connectTimeoutMs);
    executionTimer = setTimeout(() => stop('execution-timeout'), executionTimeoutMs);
    child.on('spawn', () => clearTimeout(connectionTimer));
    child.stdout.on('data', (chunk) => {
      stdoutBytes += Buffer.byteLength(chunk);
      if (stdoutBytes > stdoutLimit) {
        stop('stdout-overflow');
        return;
      }
      if (settled) return;
      const lines = (stdoutPending + chunk.toString()).split(/\r?\n/);
      stdoutPending = lines.pop() || '';
      if (Buffer.byteLength(stdoutPending) > MAX_LINE_BYTES + 2) {
        stop('line-overflow');
        return;
      }
      for (const line of lines) {
        if (!consumeLine(line)) return;
      }
    });
    child.stderr.on('data', (chunk) => {
      stderrBytes += Buffer.byteLength(chunk);
      if (stderrBytes > stderrLimit) {
        stop('stderr-overflow');
        return;
      }
      stderr += chunk.toString();
    });
    child.on('error', (error) => finish({ ok: false, partial: true, reason: `ssh:${error.code || 'error'}`, stderr: stderr.slice(0, 256), events: [] }));
    child.on('close', (code, signal) => {
      if (settled) return;
      if (code !== 0 || signal) {
        finish({ ok: false, partial: true, reason: stdoutReason || `ssh-exit:${code ?? signal}`, stderr: stderr.slice(0, 256), events: [] });
        return;
      }
      if (stdoutPending && !consumeLine(stdoutPending)) return;
      if (stdoutReason) {
        finish({ ok: false, partial: true, reason: stdoutReason, events: [] });
        return;
      }
      finish({ ok: true, partial: false, reason: '', events: remoteEvents });
    });
    child.stdin.end(buildRemoteCollectorScript(payload));
  });
}

function sourceHistoryFiles(sourcePath) {
  if (!sourcePath || !fileExists(sourcePath)) return [];
  let allowlistedRoot = '';
  try { allowlistedRoot = fs.realpathSync(sourcePath); } catch { return []; }
  const files = [];
  const visited = new Set();
  function walk(directory, depth) {
    if (depth > 10) return;
    let realDirectory;
    try { realDirectory = fs.realpathSync(directory); } catch { return; }
    if (!isWithin(realDirectory, allowlistedRoot) || visited.has(realDirectory)) return;
    visited.add(realDirectory);
    for (const entry of listEntries(directory)) {
      const file = path.join(directory, entry.name);
      let linkStat;
      try { linkStat = fs.lstatSync(file); } catch { continue; }
      if (linkStat.isSymbolicLink()) {
        let target;
        try { target = fs.realpathSync(file); } catch { target = ''; }
        if (!target || !isWithin(target, allowlistedRoot) || visited.has(target)) continue;
      }
      let stat;
      try { stat = fs.statSync(file); } catch { continue; }
      if (stat.isDirectory()) walk(file, depth + 1);
      else if (stat.isFile() && (file.endsWith('.jsonl') || file.endsWith('.json'))) files.push(file);
    }
  }
  walk(allowlistedRoot, 0);
  return files.sort();
}

function prefixHash(filePath, bytes = 4096, content = null) {
  try {
    const length = Math.max(0, Math.min(Number(bytes) || 0, 4096));
    const buffer = Buffer.isBuffer(content) ? content : fs.readFileSync(filePath);
    return sha256(buffer.subarray(0, length));
  } catch { return ''; }
}

function* iterateBufferLines(buffer, start, end) {
  let lineStart = start;
  for (let index = start; index < end; index += 1) {
    if (buffer[index] !== 0x0a) continue;
    let lineEnd = index;
    if (lineEnd > lineStart && buffer[lineEnd - 1] === 0x0d) lineEnd -= 1;
    yield {
      line: buffer.subarray(lineStart, lineEnd).toString('utf8'),
      byteLength: lineEnd - lineStart,
    };
    lineStart = index + 1;
  }
}

function readLocalSource({ source, cursor = {}, context, full = false }) {
  const files = sourceHistoryFiles(source.path);
  if (files.length === 0 && fileExists(source.path)) return { ok: false, partial: true, reason: 'source-empty', events: [], cursors: {}, coverage: null };
  if (!fileExists(source.path)) return { ok: false, partial: true, reason: 'source-missing', events: [], cursors: {}, coverage: null };
  const events = [];
  const nextCursors = {};
  let partial = false;
  let reason = '';
  let firstTimestamp = '';
  let lastTimestamp = '';
  const currentFileTokens = new Set(files.map((file) => makeSourceId(file, context.hmacKey)));
  const previousFileTokens = new Set(Object.keys(cursor || {}));
  if (!full && [...previousFileTokens].some((token) => !currentFileTokens.has(token))) {
    partial = true;
    reason = 'source-files-changed';
  }
  for (const file of files) {
    let stat;
    try { stat = fs.statSync(file); } catch { partial = true; reason = 'source-stat'; continue; }
    const fileToken = makeSourceId(file, context.hmacKey);
    const previous = cursor[fileToken] || {};
    const previousPrefixLength = previous.prefixLength === undefined
      ? Math.min(Math.max(0, parseNumber(previous.size, 0)), 4096)
      : Math.min(Math.max(0, parseNumber(previous.prefixLength, 0)), 4096);
    let buffer;
    try { buffer = fs.readFileSync(file); } catch { partial = true; reason = 'source-read'; continue; }
    const prefixLengthToCompare = previous.size === undefined ? Math.min(stat.size, 4096) : previousPrefixLength;
    const prefix = prefixHash(file, prefixLengthToCompare, buffer);
    const rewritten = previous.size !== undefined && (
      stat.size < previous.size
      || previous.offset > stat.size
      || (previous.prefixHash && previous.prefixHash !== prefix)
    );
    if (rewritten) {
      partial = true;
      reason = 'source-truncated-or-rewritten';
    }
    const start = full || rewritten ? 0 : Math.min(Math.max(0, previous.offset || 0), buffer.length);
    const fileContext = {
      ...context,
      provider: source.provider,
      filePath: file,
      sessionId: '',
      logicalProjectId: source.logicalProjectId || 'UNMAPPED',
      surfaceAlias: source.sourceAlias || 'UNMAPPED',
      surfaceId: source.surfaceId || 'UNMAPPED',
      mapSessions: source.mapSessions === true,
    };

    if (source.provider === 'hermes' && file.toLowerCase().endsWith('.json')) {
      const result = parseHermesEvents({ text: buffer.toString('utf8'), context: fileContext });
      if (!result.ok) {
        partial = true;
        reason = result.reason || 'schema-invalid';
        continue;
      }
      for (const event of result.events || []) {
        if (!validateClosedEvent(event)) { partial = true; reason = 'schema-invalid'; break; }
        events.push(event);
        firstTimestamp = firstTimestamp || event.timestamp;
        lastTimestamp = event.timestamp;
      }
      if (partial) continue;
      nextCursors[fileToken] = {
        identity: fileToken,
        offset: buffer.length,
        size: stat.size,
        mtimeMs: stat.mtimeMs,
        prefixHash: prefixHash(file, Math.min(stat.size, 4096), buffer),
        prefixLength: Math.min(stat.size, 4096),
      };
      continue;
    }
    const unread = buffer.subarray(start);
    const lastLf = unread.lastIndexOf(0x0a);
    const completePrefixEnd = lastLf === -1 ? start : start + lastLf + 1;
    let linePosition = 0;
    for (const item of iterateBufferLines(buffer, start, completePrefixEnd)) {
      linePosition += 1;
      const line = item.line;
      if (!line.trim()) continue;
      if (item.byteLength > MAX_LINE_BYTES) {
        partial = true; reason = 'line-overflow'; break;
      }
      let record;
      try { record = JSON.parse(line); } catch { partial = true; reason = 'schema-invalid'; break; }
      const result = parseProviderRecord(source.provider, record, fileContext, start + linePosition);
      if (result.error) { partial = true; reason = result.error; break; }
      for (const event of result.events || []) {
        if (!validateClosedEvent(event)) { partial = true; reason = 'schema-invalid'; break; }
        events.push(event);
        firstTimestamp = firstTimestamp || event.timestamp;
        lastTimestamp = event.timestamp;
      }
      if (partial && reason === 'schema-invalid') break;
    }
    if (partial && ['line-overflow', 'schema-invalid'].includes(reason)) {
      continue;
    }
    nextCursors[fileToken] = {
      identity: fileToken,
      offset: completePrefixEnd,
      size: stat.size,
      mtimeMs: stat.mtimeMs,
      prefixHash: prefixHash(file, Math.min(stat.size, 4096), buffer),
      prefixLength: Math.min(stat.size, 4096),
    };
  }
  const previousComplete = Object.values(context.previousCoverage || {})
    .filter((interval) => interval && interval.status === 'COMPLETE' && Date.parse(interval.end) <= Date.parse(context.now))
    .sort((left, right) => Date.parse(right.end) - Date.parse(left.end))[0];
  const coverage = {
    sourceId: source.sourceId,
    provider: source.provider,
    surfaceId: source.surfaceId || 'UNMAPPED',
    surfaceAlias: source.sourceAlias,
    logicalProjectId: source.logicalProjectId || 'UNMAPPED',
    start: previousComplete?.end || context.now,
    end: context.now,
    status: partial ? 'PARTIAL' : 'COMPLETE',
    reason: reason || '',
  };
  return { ok: !partial, partial, reason, events: partial ? [] : events, cursors: nextCursors, coverage };
}

function mergeIntervals(intervals) {
  const sorted = intervals.filter(Boolean).sort((left, right) => Date.parse(left.start) - Date.parse(right.start));
  const merged = [];
  for (const interval of sorted) {
    const current = { ...interval };
    const previous = merged[merged.length - 1];
    if (previous && Date.parse(current.start) <= Date.parse(previous.end) && previous.status === current.status) {
      if (Date.parse(current.end) > Date.parse(previous.end)) previous.end = current.end;
    } else {
      merged.push(current);
    }
  }
  return merged;
}

function hasContinuousCoverage(intervals, start, end) {
  const from = Date.parse(start);
  const to = Date.parse(end);
  if (!Number.isFinite(from) || !Number.isFinite(to) || from > to) return false;
  let cursor = from;
  const sorted = (intervals || []).filter((item) => item && item.status === 'COMPLETE').sort((left, right) => Date.parse(left.start) - Date.parse(right.start));
  for (const interval of sorted) {
    const intervalStart = Date.parse(interval.start);
    const intervalEnd = Date.parse(interval.end);
    if (!Number.isFinite(intervalStart) || !Number.isFinite(intervalEnd)) continue;
    if (intervalEnd < cursor) continue;
    if (intervalStart > cursor) return false;
    cursor = Math.max(cursor, intervalEnd);
    if (cursor >= to) return true;
  }
  return cursor >= to;
}

function daysBetween(later, earlier) {
  return (Date.parse(later) - Date.parse(earlier)) / 86400000;
}

function classifySkill({ verifiedUsage = [], installedAt = '', now = new Date().toISOString(), coverageIntervals = [], coverageScopes = [], sourceComplete = true }) {
  const current = iso(now);
  const events = verifiedUsage.filter((event) => event && event.kind === 'verified_usage' && Number.isFinite(Date.parse(event.timestamp)));
  const countIn = (days) => events.filter((event) => daysBetween(current, event.timestamp) >= 0 && daysBetween(current, event.timestamp) <= days).length;
  const count30 = countIn(30);
  const count60 = countIn(60);
  const count90 = countIn(90);
  const latest = events.sort((left, right) => Date.parse(right.timestamp) - Date.parse(left.timestamp))[0];
  const lastAge = latest ? daysBetween(current, latest.timestamp) : Infinity;
  const scopes = coverageScopes.length > 0
    ? coverageScopes
    : [{ intervals: coverageIntervals, sourceComplete }];
  const negativeStart = new Date(Date.parse(current) - NEGATIVE_WINDOW_DAYS * 86400000).toISOString();
  const scopeHasCoverage = (start) => scopes.length > 0 && scopes.every((scope) => (
    scope.sourceComplete !== false && hasContinuousCoverage(scope.intervals || [], start, current)
  ));
  const coverage120 = scopeHasCoverage(negativeStart);
  const installedAge = installedAt ? daysBetween(current, installedAt) : Infinity;
  const coverageSinceInstall = installedAt ? scopeHasCoverage(installedAt) : false;
  const negativeBlocked = !sourceComplete || !coverage120;
  let classification = 'UNKNOWN';
  if (count30 >= 20) classification = 'HOT';
  else if (count30 >= 5) classification = 'ACTIVE';
  else if (count60 > 0 || count90 >= 3) classification = 'OCCASIONAL';
  else if (latest && lastAge >= 60 && lastAge < 120 && scopeHasCoverage(latest.timestamp) && sourceComplete) classification = 'DORMANT';
  else if (!latest && installedAge < 120 && sourceComplete && coverageSinceInstall) classification = 'NEW_UNOBSERVED';
  else if (!latest && installedAge >= 120 && !negativeBlocked) classification = 'DEAD';
  else if (latest && lastAge >= 120 && !negativeBlocked) classification = 'DEAD';
  return {
    classification,
    counts: { '30d': count30, '60d': count60, '90d': count90 },
    lastUsageAt: latest?.timestamp || null,
    lastUsageAgeDays: Number.isFinite(lastAge) ? lastAge : null,
    coverage: negativeBlocked ? 'PARTIAL' : 'COMPLETE',
    coverageContinuous120d: coverage120,
    installedAgeDays: Number.isFinite(installedAge) ? installedAge : null,
  };
}

function scoreCandidate(signal) {
  const recurrence = Math.min(40, Math.max(0, parseNumber(signal.occurrences, 0) * 8));
  const projects = Math.min(30, Math.max(0, (signal.logicalProjectIds || []).length * 15));
  const diversity = Math.min(20, Math.max(0, (signal.fingerprints || []).length * 10));
  const freshness = signal.coverage === 'COMPLETE' ? 10 : 0;
  return Math.min(100, Math.round(recurrence + projects + diversity + freshness));
}

function weekBucket(value) {
  const timestamp = Date.parse(String(value || ''));
  if (!Number.isFinite(timestamp)) return '';
  const date = new Date(timestamp);
  date.setUTCHours(0, 0, 0, 0);
  const daysSinceMonday = (date.getUTCDay() + 6) % 7;
  date.setUTCDate(date.getUTCDate() - daysSinceMonday);
  return date.toISOString().slice(0, 10);
}

function findCandidateClusters(signals = [], options = {}) {
  const groups = new Map();
  for (const signal of signals) {
    if (!signal || signal.kind !== 'candidate_signal' || !signal.signalKey) continue;
    const group = groups.get(signal.signalKey) || {
      signalKey: signal.signalKey,
      occurrences: 0,
      logicalProjectIds: new Set(),
      fingerprints: new Set(),
      weekBuckets: new Set(),
      coverage: 'COMPLETE',
    };
    group.occurrences += Math.max(1, parseNumber(signal.count, 1));
    if (signal.logicalProjectId && signal.logicalProjectId !== 'UNMAPPED') group.logicalProjectIds.add(signal.logicalProjectId);
    if (signal.fingerprint) group.fingerprints.add(signal.fingerprint);
    const observedWeek = weekBucket(signal.timestamp);
    if (observedWeek) group.weekBuckets.add(observedWeek);
    if (signal.coverage === 'PARTIAL') group.coverage = 'PARTIAL';
    groups.set(signal.signalKey, group);
  }
  return [...groups.values()].map((group) => {
    const value = {
      signalKey: group.signalKey,
      occurrences: group.occurrences,
      logicalProjectIds: [...group.logicalProjectIds].sort(),
      fingerprints: [...group.fingerprints].sort(),
      observedWeeks: [...group.weekBuckets].sort(),
      coverage: group.coverage,
    };
    value.score = scoreCandidate(value);
    const existingCoverage = parseNumber(options.existingCoverage?.[group.signalKey], 0);
    value.existingSkillCoverage = existingCoverage;
    value.eligible = value.occurrences >= 3
      && value.logicalProjectIds.length >= 2
      && value.observedWeeks.length >= 2
      && value.score >= 70
      && existingCoverage < 80;
    value.action = value.eligible
      ? 'INTERACTIVE_INCUBATING_VIA_SKILL_CREATOR'
      : 'NO_ACTION';
    return value;
  }).sort((left, right) => right.score - left.score || left.signalKey.localeCompare(right.signalKey));
}

function evalDecision({ kind = 'new', baseline, candidate, adapterResult }) {
  if (!adapterResult || adapterResult.status === 'NOT_CONFIGURED') return { status: 'NOT_CONFIGURED', eligible: false };
  const passRate = parseNumber(adapterResult.passRate, 0);
  const baselinePass = parseNumber(baseline?.passRate, 0);
  const candidatePass = parseNumber(candidate?.passRate, passRate);
  const gain = Math.round((candidatePass - baselinePass) * 10000) / 100;
  const failures = parseNumber(adapterResult.failures, 0);
  const timeRatio = baseline?.timeMs ? parseNumber(candidate?.timeMs, Infinity) / baseline.timeMs : 0;
  const tokenRatio = baseline?.tokens ? parseNumber(candidate?.tokens, Infinity) / baseline.tokens : 0;
  const eligible = kind === 'new'
    ? passRate >= 0.9 && gain >= 15 && failures === 0
    : failures === 0 && timeRatio <= 1.1 && tokenRatio <= 1.1;
  return { status: 'READY', passRate, gainPercentagePoints: gain, failures, timeRatio, tokenRatio, eligible };
}

function runEvalAdapter({ config, fixtureId = '', baseline = {}, candidate = {}, spawnImpl = require('node:child_process').spawnSync }) {
  const adapter = config?.policy?.evalAdapter;
  if (!adapter?.enabled) return { status: 'NOT_CONFIGURED', criticalPath: false, version: adapter?.version || 'v1' };
  const payload = JSON.stringify({
    schemaVersion: SCHEMA_VERSION,
    fixtureId: safeText(fixtureId, 120),
    baseline: { passRate: parseNumber(baseline.passRate, 0), timeMs: parseNumber(baseline.timeMs, 0), tokens: parseNumber(baseline.tokens, 0) },
    candidate: { passRate: parseNumber(candidate.passRate, 0), timeMs: parseNumber(candidate.timeMs, 0), tokens: parseNumber(candidate.tokens, 0) },
  });
  let result;
  try {
    result = spawnImpl(adapter.command, ['--version', adapter.version, '--json'], {
      input: payload,
      encoding: 'utf8',
      maxBuffer: 1024 * 1024,
      stdio: ['pipe', 'pipe', 'ignore'],
    });
  } catch {
    return { status: 'UNAVAILABLE', criticalPath: false, version: adapter.version };
  }
  if (result.status !== 0 || typeof result.stdout !== 'string') return { status: 'UNAVAILABLE', criticalPath: false, version: adapter.version };
  let parsed;
  try { parsed = JSON.parse(result.stdout); } catch { return { status: 'INVALID', criticalPath: false, version: adapter.version }; }
  const allowed = new Set(['passRate', 'failures', 'timeMs', 'tokens']);
  if (Object.keys(parsed).some((key) => !allowed.has(key))) return { status: 'INVALID', criticalPath: false, version: adapter.version };
  return { status: 'READY', criticalPath: false, version: adapter.version, ...parsed };
}

function sourceStatus(provider, configuredRoots, historyRoots) {
  if (configuredRoots.length === 0 && historyRoots.length === 0) return 'NOT_CONFIGURED';
  if (provider === 'opencode') return 'NOT_IMPLEMENTED';
  return 'CONFIGURED';
}

function canonicalConfiguredPath(value) {
  const resolved = path.resolve(value);
  try { return fs.realpathSync(resolved); } catch { return resolved; }
}

function configuredProviderHistoryPaths(config, home) {
  const paths = new Map(PROVIDERS.map((provider) => [provider, new Set()]));
  for (const provider of PROVIDERS) {
    for (const root of config.providers[provider]?.historyRoots || []) {
      const resolved = resolvePath(root.path, process.cwd(), home);
      paths.get(provider).add(canonicalConfiguredPath(resolved));
      for (const candidate of configuredRootCandidates(root, home)) paths.get(provider).add(canonicalConfiguredPath(candidate.path));
    }
  }
  return paths;
}

function collectSources(config, options = {}) {
  const home = options.home || os.homedir();
  const hmacKey = options.hmacKey || 'canuto-skill-gardener-unconfigured';
  const sources = [];
  const remoteGroups = new Map();
  const globalHistoryPaths = configuredProviderHistoryPaths(config, home);
  for (const [logicalProjectId, project] of Object.entries(config.projects)) {
    if (options.project && options.project !== logicalProjectId) continue;
    for (const [surfaceId, surface] of Object.entries(project.surfaces)) {
      if (surface.provider === 'opencode') {
        const status = sourceStatus('opencode', surface.roots || [], surface.historyRoots || []);
        const uniqueHistoryRoots = surface.remote ? surface.historyRoots || [] : (surface.historyRoots || []).filter((root) => !globalHistoryPaths.get(surface.provider)?.has(canonicalConfiguredPath(resolvePath(root.path, process.cwd(), home))));
        if (!surface.remote && (surface.historyRoots || []).length > 0 && uniqueHistoryRoots.length === 0) continue;
        if (uniqueHistoryRoots.length === 0) {
          sources.push({
            sourceId: makeSourceId(`provider|${logicalProjectId}|${surfaceId}|opencode`, hmacKey),
            logicalProjectId,
            surfaceId,
            sourceAlias: surface.aliases[0] || 'UNMAPPED',
            provider: 'opencode',
            kind: 'provider',
            status,
          });
        } else {
          for (const root of uniqueHistoryRoots) {
            sources.push({
              sourceId: makeSourceId(`opencode-history|${logicalProjectId}|${surfaceId}|${root.path}`, hmacKey),
              logicalProjectId,
              surfaceId,
              sourceAlias: root.alias || surface.aliases[0] || 'UNMAPPED',
              provider: 'opencode',
              kind: 'history',
              path: resolvePath(root.path, process.cwd(), home),
              status,
            });
          }
        }
        continue;
      }
      if (surface.remote) {
        for (const root of surface.historyRoots || []) {
          const remoteAlias = root.alias || surface.aliases[0] || 'UNMAPPED';
          const remoteProvider = surface.provider || 'codex';
          const groupKey = `${remoteAlias}\u0000${remoteProvider}\u0000${root.path}`;
          let group = remoteGroups.get(groupKey);
          if (!group) {
            group = {
              provider: remoteProvider,
              sourceAlias: remoteAlias,
              path: root.path,
              remoteAlias,
              remoteMappings: [],
              mappingKeys: new Set(),
            };
            remoteGroups.set(groupKey, group);
          }
          const mapping = {
            logicalProjectId,
            surfaceId,
            surfaceAlias: remoteAlias,
            roots: (surface.roots || []).map((entry) => entry.path).filter(Boolean),
          };
          const mappingKey = `${logicalProjectId}\u0000${surfaceId}`;
          if (!group.mappingKeys.has(mappingKey)) {
            group.mappingKeys.add(mappingKey);
            group.remoteMappings.push(mapping);
          }
        }
        continue;
      }
      for (const root of surface.historyRoots) {
        const configuredPath = canonicalConfiguredPath(resolvePath(root.path, process.cwd(), home));
        if (globalHistoryPaths.get(surface.provider)?.has(configuredPath)) continue;
        const candidates = configuredRootCandidates(root, home);
        if (candidates.length === 0) {
          sources.push({
            sourceId: makeSourceId(`missing-history|${logicalProjectId}|${surfaceId}|${root.path}`, hmacKey),
            logicalProjectId,
            surfaceId,
            sourceAlias: root.alias || surface.aliases[0] || 'UNMAPPED',
            provider: surface.provider || 'codex',
            kind: 'history',
            path: resolvePath(root.path, process.cwd(), home),
            missing: true,
            mapSessions: false,
          });
          continue;
        }
        for (const candidate of candidates) {
          if (globalHistoryPaths.get(surface.provider)?.has(canonicalConfiguredPath(candidate.path))) continue;
          sources.push({
            sourceId: makeSourceId(`history|${logicalProjectId}|${surfaceId}|${candidate.path}`, hmacKey),
            logicalProjectId,
            surfaceId,
            sourceAlias: root.alias || surface.aliases[0] || 'UNMAPPED',
            provider: surface.provider || 'codex',
            kind: 'history',
            path: candidate.path,
            remoteAlias: '',
            mapSessions: false,
          });
        }
      }
    }
  }
  for (const group of remoteGroups.values()) {
    sources.push({
      sourceId: makeSourceId(`remote-history|${group.provider}|${group.remoteAlias}|${group.path}`, hmacKey),
      logicalProjectId: '',
      surfaceId: 'remote',
      sourceAlias: group.sourceAlias,
      provider: group.provider,
      kind: 'history',
      path: group.path,
      remoteAlias: group.remoteAlias,
      mapSessions: false,
      remoteMappings: group.remoteMappings,
    });
  }
  for (const provider of PROVIDERS) {
    const settings = config.providers[provider] || {};
    const status = sourceStatus(provider, [...(settings.roots || []), ...(settings.pluginRoots || []), ...(settings.systemRoots || [])], settings.historyRoots || []);
    if (status === 'NOT_CONFIGURED' || status === 'NOT_IMPLEMENTED') {
      sources.push({ sourceId: makeSourceId(`provider:${provider}`, hmacKey), provider, kind: 'provider', sourceAlias: 'UNMAPPED', status });
      continue;
    }
    for (const root of settings.historyRoots || []) {
      const candidates = configuredRootCandidates(root, home);
      if (candidates.length === 0) {
        sources.push({
          sourceId: makeSourceId(`missing-history|${provider}|global|${root.path}`, hmacKey),
          logicalProjectId: '',
          surfaceId: 'global',
          sourceAlias: root.alias || 'UNMAPPED',
          provider,
          kind: 'history',
          path: resolvePath(root.path, process.cwd(), home),
          missing: true,
          mapSessions: true,
        });
        continue;
      }
      for (const candidate of candidates) {
        sources.push({
          sourceId: makeSourceId(`history|${provider}|global|${candidate.path}`, hmacKey),
          logicalProjectId: '',
          surfaceId: 'global',
          sourceAlias: root.alias || 'UNMAPPED',
          provider,
          kind: 'history',
          path: candidate.path,
          mapSessions: true,
        });
      }
    }
  }
  return sources;
}

function initializeHmacKey(hmacKeyPath) {
  ensureDir(path.dirname(hmacKeyPath));
  const generatedKey = crypto.randomBytes(32).toString('hex');
  const temporary = `${hmacKeyPath}.tmp-${process.pid}-${crypto.randomBytes(6).toString('hex')}`;
  try {
    fs.writeFileSync(temporary, `${generatedKey}\n`, { flag: 'wx', mode: 0o600 });
    fs.chmodSync(temporary, 0o600);
    try {
      fs.linkSync(temporary, hmacKeyPath);
    } catch (error) {
      if (error?.code !== 'EEXIST') throw error;
      let winner;
      try {
        winner = fs.readFileSync(hmacKeyPath, 'utf8').trim();
      } catch {
        throw new Error('hmac-key-persistence-failed');
      }
      if (!HMAC_KEY_RE.test(winner)) throw new Error('invalid-hmac-key');
      return winner;
    }
    const persistedKey = fs.readFileSync(hmacKeyPath, 'utf8').trim();
    if (!HMAC_KEY_RE.test(persistedKey) || persistedKey !== generatedKey) throw new Error('hmac-key-persistence-failed');
    return persistedKey;
  } finally {
    try { fs.unlinkSync(temporary); } catch (error) {
      if (error?.code !== 'ENOENT') throw error;
    }
  }
}

function getRuntimeOptions(options = {}) {
  const home = options.home || process.env.CANUTO_SKILL_GARDENER_HOME || os.homedir();
  const stateDir = options.stateDir || process.env.CANUTO_SKILL_GARDENER_STATE_DIR || path.join(home, '.canuto', 'cache', 'skill-gardener');
  const configPath = options.configPath || process.env.CANUTO_SKILL_GARDENER_CONFIG || path.join(home, '.canuto', 'config', 'skill-gardener.json');
  const vaultRoot = options.vaultRoot || process.env.CANUTO_SKILL_GARDENER_VAULT_ROOT || process.env.CANUTO_VAULT_DIR || path.join(home, '.canuto', 'vault');
  const artifactRoot = options.artifactRoot || process.env.CANUTO_SKILL_GARDENER_ARTIFACT_ROOT || path.join(vaultRoot, 'projects', 'canuto-framework-v1', 'skill-gardener');
  const frameworkRoot = options.frameworkRoot || process.env.CANUTO_SKILL_GARDENER_FRAMEWORK_ROOT || path.join(__dirname, '..');
  const eventLogCandidates = [
    options.eventLogPath,
    process.env.CANUTO_SKILL_GARDENER_EVENT_LOG,
    path.join(home, '.canuto', 'lib', 'event-log.sh'),
    path.join(frameworkRoot, '.agents', 'tools', 'event-log.sh'),
  ].filter(Boolean);
  const eventLogPath = eventLogCandidates.find(fileExists) || '';
  const hmacKeyPath = options.hmacKeyPath || path.join(stateDir, 'hmac.key');
  const readOnly = options.readOnly === true;
  let hmacKey = options.hmacKey || process.env.CANUTO_SKILL_GARDENER_HMAC_KEY || '';
  if (!hmacKey) {
    let keyFileMissing = false;
    let storedKey = '';
    try {
      storedKey = fs.readFileSync(hmacKeyPath, 'utf8').trim();
    } catch (error) {
      if (error?.code === 'ENOENT') keyFileMissing = true;
      else throw new Error('hmac-key-read-failed');
    }
    if (!keyFileMissing) {
      if (!HMAC_KEY_RE.test(storedKey)) throw new Error('invalid-hmac-key');
      hmacKey = storedKey;
    }
  }
  if (!hmacKey) {
    if (readOnly) {
      hmacKey = 'canuto-skill-gardener-readonly';
    } else {
      try {
        hmacKey = initializeHmacKey(hmacKeyPath);
      } catch (error) {
        if (error?.message === 'invalid-hmac-key') throw error;
        throw new Error('hmac-key-persistence-failed');
      }
    }
  }
  const now = iso(options.now || process.env.CANUTO_SKILL_GARDENER_NOW || new Date().toISOString());
  return { ...options, home, stateDir, configPath, vaultRoot, artifactRoot, frameworkRoot, eventLogPath, hmacKey, now };
}

function emptyState() {
  return { schemaVersion: SCHEMA_VERSION, cursors: {}, coverage: {}, eventKeys: {}, lifetimeUsage: {}, detailedEvents: [], runs: [] };
}

function stateInvalid() {
  throw new Error('state-invalid');
}

const FILE_CURSOR_KEYS = new Set(['identity', 'offset', 'size', 'mtimeMs', 'prefixHash', 'prefixLength']);

function normalizeCursorState(value) {
  if (value === undefined) return {};
  if (!isPlainObject(value)) stateInvalid();
  const output = {};
  for (const [sourceId, files] of Object.entries(value)) {
    if (!isPlainObject(files)) stateInvalid();
    output[sourceId] = {};
    for (const [fileId, cursor] of Object.entries(files)) {
      if (!isPlainObject(cursor) || !hasExactKeys(cursor, FILE_CURSOR_KEYS)) stateInvalid();
      if (typeof cursor.identity !== 'string' || !cursor.identity) stateInvalid();
      if (!Number.isSafeInteger(cursor.offset) || cursor.offset < 0) stateInvalid();
      if (!Number.isSafeInteger(cursor.size) || cursor.size < 0 || cursor.offset > cursor.size) stateInvalid();
      if (typeof cursor.mtimeMs !== 'number' || !Number.isFinite(cursor.mtimeMs) || cursor.mtimeMs < 0) stateInvalid();
      if (typeof cursor.prefixHash !== 'string' || !/^[a-f0-9]{64}$/i.test(cursor.prefixHash)) stateInvalid();
      if (!Number.isSafeInteger(cursor.prefixLength) || cursor.prefixLength < 0 || cursor.prefixLength > 4096 || cursor.prefixLength > cursor.size) stateInvalid();
      output[sourceId][fileId] = {
        identity: cursor.identity,
        offset: cursor.offset,
        size: cursor.size,
        mtimeMs: cursor.mtimeMs,
        prefixHash: cursor.prefixHash,
        prefixLength: cursor.prefixLength,
      };
    }
  }
  return output;
}

function normalizeCoverageMetadata(value) {
  if (!isPlainObject(value)) stateInvalid();
  const output = {};
  for (const [key, item] of Object.entries(value)) {
    if (item !== null && !['string', 'number', 'boolean'].includes(typeof item)) stateInvalid();
    if (typeof item === 'number' && !Number.isFinite(item)) stateInvalid();
    output[key] = item;
  }
  return output;
}

function normalizeCoverageState(value) {
  if (value === undefined) return {};
  if (!isPlainObject(value)) stateInvalid();
  const output = {};
  const allowed = new Set(['sourceId', 'provider', 'surfaceId', 'surfaceAlias', 'logicalProjectId', 'start', 'end', 'status', 'reason', 'metadata']);
  const stringFields = ['sourceId', 'provider', 'surfaceId', 'surfaceAlias', 'logicalProjectId', 'reason'];
  for (const [sourceId, intervals] of Object.entries(value)) {
    if (!Array.isArray(intervals)) stateInvalid();
    output[sourceId] = intervals.map((interval) => {
      if (!isPlainObject(interval) || Object.keys(interval).some((key) => !allowed.has(key))) stateInvalid();
      if (typeof interval.start !== 'string' || typeof interval.end !== 'string') stateInvalid();
      const start = Date.parse(interval.start);
      const end = Date.parse(interval.end);
      if (!Number.isFinite(start) || !Number.isFinite(end) || start > end) stateInvalid();
      if (interval.status !== 'COMPLETE' && interval.status !== 'PARTIAL') stateInvalid();
      const normalized = { start: interval.start, end: interval.end, status: interval.status };
      for (const field of stringFields) {
        if (interval[field] !== undefined && typeof interval[field] !== 'string') stateInvalid();
        if (interval[field] !== undefined) normalized[field] = interval[field];
      }
      if (interval.metadata !== undefined) normalized.metadata = normalizeCoverageMetadata(interval.metadata);
      return normalized;
    });
  }
  return output;
}

function normalizeHexLedger(value, countLedger = false) {
  if (!isPlainObject(value)) stateInvalid();
  const byLower = new Map();
  for (const [key, item] of Object.entries(value)) {
    if (!/^[a-f0-9]{64}$/i.test(key)) stateInvalid();
    const lower = key.toLowerCase();
    if (byLower.has(lower) && byLower.get(lower).key !== key) stateInvalid();
    if (countLedger && (typeof item !== 'number' || !Number.isFinite(item) || !Number.isInteger(item) || item < 0)) stateInvalid();
    byLower.set(lower, { key, value: countLedger ? item : 1 });
  }
  return Object.fromEntries([...byLower.values()].sort((left, right) => (left.key < right.key ? -1 : left.key > right.key ? 1 : 0)).map((entry) => [entry.key, entry.value]));
}

function normalizeDetailedEvents(value) {
  if (value === undefined) return [];
  if (!Array.isArray(value)) stateInvalid();
  return value.map((event) => {
    const sanitized = sanitizeStructuredEvent(event);
    if (!sanitized || !validateClosedEvent(sanitized)) stateInvalid();
    return sanitized;
  });
}

function normalizeRunIndex(value) {
  if (value === undefined) return [];
  if (!Array.isArray(value)) stateInvalid();
  return value.map((run) => {
    if (!isPlainObject(run) || Object.keys(run).length !== 2 || !Object.hasOwn(run, 'runId') || !Object.hasOwn(run, 'status')) stateInvalid();
    if (!isCanonicalRunId(run.runId) || !['complete', 'partial'].includes(run.status)) stateInvalid();
    return { runId: run.runId, status: run.status };
  });
}

function normalizeState(raw) {
  const stateKeys = new Set(['schemaVersion', 'cursors', 'coverage', 'eventKeys', 'lifetimeUsage', 'detailedEvents', 'runs']);
  if (!isPlainObject(raw) || raw.schemaVersion !== SCHEMA_VERSION || !hasExactKeys(raw, stateKeys)) stateInvalid();
  const detailedEvents = normalizeDetailedEvents(raw.detailedEvents);
  const eventKeys = normalizeHexLedger(raw.eventKeys);
  const derivedLedger = Object.fromEntries(detailedEvents.map((event) => [event.eventKey, 1]));
  return {
    schemaVersion: SCHEMA_VERSION,
    cursors: normalizeCursorState(raw.cursors),
    coverage: normalizeCoverageState(raw.coverage),
    eventKeys: mergeEventKeyLedger(eventKeys, Object.keys(derivedLedger)),
    lifetimeUsage: raw.lifetimeUsage === undefined ? {} : normalizeHexLedger(raw.lifetimeUsage, true),
    detailedEvents,
    runs: normalizeRunIndex(raw.runs),
  };
}

function loadState(statePath) {
  let raw;
  try {
    raw = JSON.parse(fs.readFileSync(statePath, 'utf8'));
  } catch (error) {
    if (error?.code === 'ENOENT') return emptyState();
    if (error instanceof SyntaxError) throw new Error('state-invalid');
    throw new Error('state-read-failed');
  }
  return normalizeState(raw);
}

function acquireLock(stateDir) {
  const lockPath = path.join(stateDir, 'run.lock');
  ensureDir(stateDir);
  try {
    fs.mkdirSync(lockPath);
  } catch (error) {
    if (error.code === 'EEXIST') return { acquired: false, lockPath };
    throw error;
  }
  try { atomicWrite(path.join(lockPath, 'owner.json'), JSON.stringify({ pid: process.pid, startedAt: new Date().toISOString() })); } catch { /* lock ownership is directory based */ }
  return { acquired: true, lockPath };
}

function releaseLock(lock) {
  if (!lock?.acquired) return;
  try { fs.rmSync(lock.lockPath, { recursive: true, force: true }); } catch { /* best effort cleanup of exact lock path */ }
}

function manifestFingerprint(rootDescriptor, hmacKey) {
  const root = rootDescriptor.path;
  const git = gitCommonDir(root);
  if (git) {
    let head = '';
    let manifest = '';
    try { head = execFileSync('git', ['-C', root, 'rev-parse', 'HEAD'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim(); } catch { head = ''; }
    try { manifest = execFileSync('git', ['-C', root, 'ls-files', '-s'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], maxBuffer: 32 * 1024 * 1024 }); } catch { manifest = ''; }
    return { type: 'GIT', commonDirKey: hmac(`git:${git}`, hmacKey), head, manifestHash: sha256(manifest) };
  }
  return { type: 'NON_GIT_MEMORY_ONLY', fileCount: countFiles(root) };
}

function compareFingerprints(before, after) {
  if (!before || !after || before.type !== after.type) return 'CHANGED_DURING_RUN';
  if (before.type === 'NON_GIT_MEMORY_ONLY') return before.fileCount === after.fileCount ? 'UNCHANGED' : 'CHANGED_DURING_RUN';
  return before.head === after.head && before.manifestHash === after.manifestHash ? 'UNCHANGED' : 'CHANGED_DURING_RUN';
}

function projectFingerprintDescriptors(config, home) {
  const descriptors = {};
  for (const [logicalProjectId, project] of Object.entries(config.projects)) {
    for (const surface of Object.values(project.surfaces)) {
      const root = (surface.roots || []).map((entry) => configuredRootCandidates(entry, home)[0]).find(Boolean);
      if (root) {
        descriptors[logicalProjectId] = { path: root.path };
        break;
      }
    }
  }
  return descriptors;
}

function publicSource(source, extra = {}) {
  return {
    sourceId: source.sourceId,
    provider: source.provider,
    kind: source.kind,
    surfaceId: source.surfaceId || 'unknown',
    surfaceAlias: source.sourceAlias || 'UNMAPPED',
    logicalProjectId: source.logicalProjectId || 'UNMAPPED',
    status: source.status || 'CONFIGURED',
    events: source.events || 0,
    reason: source.reason || '',
    ...extra,
  };
}

function installationScope(installation) {
  return [
    installation.provider || 'unknown',
    installation.sourceAlias || 'UNMAPPED',
    installation.surfaceId || 'UNMAPPED',
    installation.logicalProjectId || 'UNMAPPED',
  ].join('|');
}

function buildCoverageBySkill({ catalog, state, sources = [], now }) {
  const output = {};
  const allIntervals = Object.values(state.coverage || {}).flat().filter(Boolean);
  const negativeStart = new Date(Date.parse(now) - NEGATIVE_WINDOW_DAYS * 86400000).toISOString();
  for (const variant of catalog.variants) {
    const scopes = {};
    for (const installation of variant.installations || []) {
      const scopeKey = installationScope(installation);
      const intervals = allIntervals.filter((interval) => (
        interval.provider === installation.provider
        && (interval.surfaceAlias || 'UNMAPPED') === (installation.sourceAlias || 'UNMAPPED')
        && (interval.surfaceId || 'UNMAPPED') === (installation.surfaceId || 'UNMAPPED')
        && (interval.logicalProjectId || 'UNMAPPED') === (installation.logicalProjectId || 'UNMAPPED')
      ));
      scopes[scopeKey] = {
        provider: installation.provider,
        surfaceAlias: installation.sourceAlias || 'UNMAPPED',
        surfaceId: installation.surfaceId || 'UNMAPPED',
        logicalProjectId: installation.logicalProjectId || 'UNMAPPED',
        intervals: mergeIntervals(intervals),
        complete120d: hasContinuousCoverage(intervals, negativeStart, now),
      };
      const matchingSources = sources.filter((source) => {
        const directMatch = source.provider === installation.provider
          && (source.surfaceId || 'UNMAPPED') === (installation.surfaceId || 'UNMAPPED')
          && (source.logicalProjectId || 'UNMAPPED') === (installation.logicalProjectId || 'UNMAPPED')
          && (source.sourceAlias || 'UNMAPPED') === (installation.sourceAlias || 'UNMAPPED');
        const remoteMatch = source.provider === installation.provider
          && (source.remoteMappings || []).some((mapping) => (
            mapping.surfaceId === installation.surfaceId
            && mapping.logicalProjectId === installation.logicalProjectId
            && (mapping.surfaceAlias || 'UNMAPPED') === (installation.sourceAlias || 'UNMAPPED')
          ));
        return directMatch || remoteMatch;
      });
      if (matchingSources.some((source) => source.status && source.status !== 'COMPLETE')) scopes[scopeKey].complete120d = false;
    }
    const scopeValues = Object.values(scopes);
    output[variant.skillKey] = {
      intervals: scopeValues.flatMap((scope) => scope.intervals),
      scopes,
      sourceComplete: scopeValues.length > 0 && scopeValues.every((scope) => scope.complete120d),
    };
  }
  return output;
}

function buildExistingCoverage({ catalog, signals, hmacKey }) {
  const output = {};
  const knownNames = new Set(catalog.variants.map((variant) => variant.name));
  const knownSkillKeys = new Set(catalog.variants.map((variant) => variant.skillKey));
  const capabilitySets = (catalog._installations || []).map((installation) => new Set(installation._capabilityTokens || []));
  for (const signal of signals || []) {
    if (!signal?.signalKey) continue;
    if (knownSkillKeys.has(signal.signalKey)) {
      output[signal.signalKey] = 100;
      continue;
    }
    for (const name of knownNames) {
      if (hmac(`missing:${name}`, hmacKey) === signal.signalKey) {
        output[signal.signalKey] = 100;
        break;
      }
    }
    if (!Object.hasOwn(output, signal.signalKey)) {
      const fingerprintTokens = [...new Set(String(signal.fingerprint || '')
        .split('|')
        .map((part) => normalizeName(part.split(':').slice(1).join(':')))
        .filter(Boolean))];
      output[signal.signalKey] = fingerprintTokens.length === 0 ? 0 : capabilitySets.reduce((highest, capabilities) => {
        const matched = fingerprintTokens.filter((token) => capabilities.has(token)).length;
        return Math.max(highest, Math.round((matched / fingerprintTokens.length) * 100));
      }, 0);
    }
  }
  return output;
}

function buildMarkdown(report) {
  const lines = [
    `# Canuto Skill Gardener — ${report.runId}`,
    '',
    `- Status: **${report.status}**`,
    `- Mode: ${report.mode}`,
    `- Verified usage events: ${report.verifiedUsage.total}`,
    `- Candidate signals: ${report.candidateSignals.total}`,
    '',
    '## Sources',
    '',
  ];
  for (const source of report.sources) lines.push(`- ${source.provider} / ${source.surfaceAlias}: ${source.status || 'COMPLETE'} (${source.events || 0} events)`);
  lines.push('', '## Logical projects', '');
  for (const project of report.logicalProjects) lines.push(`- ${project.logicalProjectId}: ${project.installations} installations, ${project.verifiedUsage} verified uses`);
  lines.push('', '## Skills', '', '| Skill | Classification | 30d | 60d | 90d | Coverage |', '|---|---:|---:|---:|---:|---:|');
  for (const item of report.classifications) lines.push(`| ${item.name || item.skillKey} | ${item.classification} | ${item.counts['30d']} | ${item.counts['60d']} | ${item.counts['90d']} | ${item.coverage} |`);
  lines.push('', '## Candidate clusters', '');
  if (report.candidateSignals.clusters.length === 0) lines.push('- none');
  for (const cluster of report.candidateSignals.clusters) lines.push(`- ${cluster.signalKey}: ${cluster.occurrences} occurrences, ${cluster.logicalProjectIds.length} logical projects, score ${cluster.score}, action ${cluster.action}`);
  lines.push('', '## Gates and invariants', '', `- Post-gate: ${report.postGate.status}`, `- Event log: ${report.postGate.eventLog}`, `- Cursors promoted: ${report.cursorsPromoted.length}`, '- Read-only invariant: PASS', '- Cron installation: explicit command only');
  return `${lines.join('\n')}\n`;
}

function makeRunId(now = new Date().toISOString()) {
  return `${now.replace(/[^0-9]/g, '').slice(0, 14)}-${crypto.randomBytes(5).toString('hex')}`;
}

function appendRunIndex(state, runId, status) {
  const runs = Array.isArray(state.runs) ? state.runs.filter((run) => run && run.runId !== runId) : [];
  runs.push({ runId, status });
  return runs.slice(-1000);
}

function countBy(items, key) {
  const output = {};
  for (const item of items) output[item[key]] = (output[item[key]] || 0) + 1;
  return output;
}

function buildReport({ runId, mode, status, sources, catalog, retainedRunEvents = [], retainedDetailedEvents = [], coverageIntervals, config, fingerprints, postGate, cursorsPromoted, now, nonGitReceipts, hmacKey, lifetimeUsage = {} }) {
  const allDetailed = retainedDetailedEvents;
  const classifications = [];
  for (const variant of catalog.variants) {
    const uses = allDetailed.filter((event) => event.kind === 'verified_usage' && event.skillKey === variant.skillKey);
    const installedAt = variant.installations.map((item) => item.installedAt).filter(Boolean).sort()[0] || '';
    classifications.push({
      skillKey: variant.skillKey,
      name: variant.name,
      contentHash: variant.contentHash,
      ...classifySkill({
        verifiedUsage: uses,
        installedAt,
        now,
        coverageIntervals: coverageIntervals[variant.skillKey]?.intervals || [],
        coverageScopes: Object.values(coverageIntervals[variant.skillKey]?.scopes || {}).map((scope) => ({
          provider: scope.provider,
          surfaceAlias: scope.surfaceAlias,
          surfaceId: scope.surfaceId,
          logicalProjectId: scope.logicalProjectId,
          intervals: scope.intervals || [],
          sourceComplete: scope.complete120d === true,
        })),
        sourceComplete: coverageIntervals[variant.skillKey]?.sourceComplete === true,
      }),
    });
  }
  const projects = [...new Set([
    ...Object.keys(config.projects),
    ...retainedRunEvents.map((event) => event.logicalProjectId).filter(Boolean),
  ])].sort().map((logicalProjectId) => ({
    logicalProjectId,
    installations: catalog.installations.filter((item) => item.logicalProjectId === logicalProjectId).length,
    verifiedUsage: retainedRunEvents.filter((event) => event.kind === 'verified_usage' && event.logicalProjectId === logicalProjectId).length,
  }));
  const publicEvents = retainedRunEvents.map((event) => {
    const output = { ...event };
    delete output.knownSkill;
    return output;
  });
  const report = {
    schemaVersion: SCHEMA_VERSION,
    tool: 'canuto-skill-gardener',
    runId,
    mode,
    status,
    complete: status === 'complete',
    partial: status === 'partial',
    generatedAt: now,
    sources: sources.map((source) => publicSource(source)),
    coverageIntervals: Object.entries(coverageIntervals).flatMap(([skillKey, value]) => (value.intervals || []).map((interval) => ({ skillKey, ...interval }))),
    coverageScopes: Object.entries(coverageIntervals).flatMap(([skillKey, value]) => Object.values(value.scopes || {}).map((scope) => ({
      skillKey,
      provider: scope.provider,
      surfaceAlias: scope.surfaceAlias,
      surfaceId: scope.surfaceId,
      logicalProjectId: scope.logicalProjectId,
      intervals: scope.intervals || [],
      sourceComplete: scope.complete120d === true,
    }))),
    logicalProjects: projects,
    installations: catalog.installations,
    variants: catalog.variants,
    divergence: catalog.divergence,
    dedupCandidates: catalog.dedupCandidates,
    verifiedUsage: { total: publicEvents.filter((event) => event.kind === 'verified_usage').length, events: publicEvents.filter((event) => event.kind === 'verified_usage') },
    lifetimeSummary: { verifiedUsageBySkill: lifetimeUsage },
    classifications,
    candidateSignals: {
      total: allDetailed.filter((event) => event.kind === 'candidate_signal').length,
      events: allDetailed.filter((event) => event.kind === 'candidate_signal'),
      clusters: findCandidateClusters(allDetailed.filter((event) => event.kind === 'candidate_signal'), { existingCoverage: buildExistingCoverage({ catalog, signals: allDetailed.filter((event) => event.kind === 'candidate_signal'), hmacKey }) }),
    },
    incompleteSources: sources.filter((source) => source.status && source.status !== 'COMPLETE').map((source) => publicSource(source)),
    postGate,
    cursorsPromoted,
    fingerprints,
    nonGitReceipts,
    evalAdapter: {
      enabled: config.policy.evalAdapter.enabled,
      version: config.policy.evalAdapter.version,
      criticalPath: false,
      adapterId: 'agent-skill-eval',
      newSkillRequirement: { passRateAtLeast: 0.9, gainPercentagePointsAtLeast: 15 },
      updateRequirement: { failures: 0, maxTimeRatio: 1.1, maxTokenRatio: 1.1 },
      excludedFromCriticalPath: ['av/skilled', 'skill-managers'],
    },
    invariantsReadOnly: {
      noProductWrites: true,
      noRemoteWrites: true,
      noCronMutation: true,
      sensitivePayloadsAbsent: true,
      unknownFieldsRejected: true,
    },
  };
  report.markdown = buildMarkdown(report);
  return report;
}

function sanitizePersistedReport(report) {
  const forbidden = /prompt|response|command|argument|output|cwd|sourcePath|filePath|metadataRef|path/i;
  const looksLikePath = (value) => /^(?:~\/|\/|[A-Za-z]:[\\/])/.test(value)
    || /(?:\.agents\/|\.canuto\/|\/tmp\/|\/private\/|\/Users\/)/.test(value);
  function clean(value, key = '') {
    if (forbidden.test(key)) return undefined;
    if (typeof value === 'string' && looksLikePath(value)) return undefined;
    if (Array.isArray(value)) return value.map((item) => clean(item)).filter((item) => item !== undefined);
    if (value && typeof value === 'object') {
      const output = {};
      for (const [childKey, childValue] of Object.entries(value)) {
        const cleanValue = clean(childValue, childKey);
        if (cleanValue !== undefined) output[childKey] = cleanValue;
      }
      return output;
    }
    return value;
  }
  return clean(report);
}

function finalizeReport(report) {
  const clean = sanitizePersistedReport(report);
  clean.markdown = buildMarkdown(clean);
  return clean;
}

async function emitCanutoEvent(runtime, report) {
  const eventLog = runtime.eventLogPath || process.env.CANUTO_SKILL_GARDENER_EVENT_LOG || '';
  if (!eventLog || !fileExists(eventLog)) return { status: 'DEGRADED', reason: 'event-log-unavailable' };
  try {
    const eventProjectDir = path.join(runtime.vaultRoot, 'projects', 'canuto-framework-v1');
    const eventCwd = runtime.cwd && fs.existsSync(runtime.cwd)
      ? runtime.cwd
      : runtime.frameworkRoot && fs.existsSync(runtime.frameworkRoot)
        ? runtime.frameworkRoot
        : process.cwd();
    const result = require('node:child_process').spawnSync('bash', [eventLog, 'append', 'SKILL_GARDENER_RUN', `run_id=${report.runId}`, `status=${report.status}`], {
      cwd: eventCwd,
      encoding: 'utf8',
      stdio: ['ignore', 'ignore', 'ignore'],
      env: { ...process.env, CLAUDE_PROJECT_DIR: eventProjectDir, CANUTO_VAULT_DIR: runtime.vaultRoot },
    });
    return result.status === 0 ? { status: 'EMITTED', reason: '' } : { status: 'DEGRADED', reason: 'event-log-failed' };
  } catch {
    return { status: 'DEGRADED', reason: 'event-log-failed' };
  }
}

function postGate(stageDir, eventLogResult) {
  const reportPath = path.join(stageDir, 'report.json');
  const receiptPath = path.join(stageDir, 'receipt.json');
  const report = readJson(reportPath, null);
  const receipt = readJson(receiptPath, null);
  const artifacts = Boolean(report && receipt && report.runId === receipt.runId);
  return {
    status: artifacts && eventLogResult.status === 'EMITTED' ? 'PASS' : 'FAIL',
    eventLog: eventLogResult.status,
    checks: {
      reportPresent: fileExists(reportPath),
      receiptPresent: fileExists(receiptPath),
      atomicArtifacts: artifacts,
      eventLogEmitted: eventLogResult.status === 'EMITTED',
    },
    noRetry: true,
  };
}

function retentionCutoff(now, days) {
  return Date.parse(now) - days * 86400000;
}

function retainDetailedEvents(events, now, days) {
  const cutoff = retentionCutoff(now, days);
  const byKey = new Map();
  for (const event of events || []) {
    if (!event?.eventKey) continue;
    const timestamp = Date.parse(event.timestamp || '');
    if (!Number.isFinite(timestamp) || timestamp < cutoff || timestamp > Date.parse(now) + 86400000) continue;
    byKey.set(event.eventKey, event);
  }
  return [...byKey.values()].sort((left, right) => Date.parse(left.timestamp) - Date.parse(right.timestamp));
}

function retainCoverage(coverage, now, days) {
  const cutoff = retentionCutoff(now, days);
  const next = {};
  for (const [sourceId, intervals] of Object.entries(coverage || {})) {
    const retained = (intervals || []).filter((interval) => {
      const end = Date.parse(interval?.end || '');
      return Number.isFinite(end) && end >= cutoff && end <= Date.parse(now) + 86400000;
    });
    if (retained.length > 0) next[sourceId] = retained;
  }
  return next;
}

function mergeEventKeyLedger(existingLedger = {}, events = []) {
  if (!isPlainObject(existingLedger)) throw new Error('state-invalid');
  const byLower = new Map();
  for (const key of Object.keys(existingLedger)) {
    if (!/^[a-f0-9]{64}$/i.test(key)) throw new Error('state-invalid');
    byLower.set(key.toLowerCase(), key);
  }
  for (const item of events || []) {
    const key = typeof item === 'string' ? item : item?.eventKey;
    if (typeof key !== 'string' || !/^[a-f0-9]{64}$/i.test(key)) throw new Error('state-invalid');
    const lower = key.toLowerCase();
    if (!byLower.has(lower)) byLower.set(lower, key);
  }
  return Object.fromEntries([...byLower.values()].sort().map((key) => [key, 1]));
}

function readAuthenticatedPendingState(stageDir, commit) {
  let raw;
  try {
    raw = fs.readFileSync(path.join(stageDir, 'pending-state.json'));
  } catch {
    throw new Error('pending-state-read-failed');
  }
  if (typeof commit.pendingStateHash !== 'string' || !/^[a-f0-9]{64}$/i.test(commit.pendingStateHash) || sha256(raw) !== commit.pendingStateHash) {
    throw new Error('pending-state-hash-mismatch');
  }
  let parsed;
  try {
    parsed = JSON.parse(raw.toString('utf8'));
  } catch {
    throw new Error('state-invalid');
  }
  return normalizeState(parsed);
}

function sameRunEntry(left, right) {
  return left?.runId === right?.runId && left?.status === right?.status;
}

function pendingStateFollowsActive(activeRuns, pendingRuns, runId, status, activeRunIndex = -1) {
  const terminal = pendingRuns[pendingRuns.length - 1];
  if (!sameRunEntry(terminal, { runId, status })) return false;
  if (activeRunIndex >= 0) {
    const activeThroughRun = activeRuns.slice(0, activeRunIndex + 1);
    if (pendingRuns.length < activeThroughRun.length) return false;
    const pendingTail = pendingRuns.slice(-activeThroughRun.length);
    return activeThroughRun.every((entry, index) => sameRunEntry(entry, pendingTail[index]));
  }
  const ancestors = pendingRuns.slice(0, -1);
  if (ancestors.length !== Math.min(activeRuns.length, 999)) return false;
  const activeTail = activeRuns.slice(-ancestors.length);
  if (ancestors.length === 0 && activeTail.length === 0) return true;
  return ancestors.every((entry, index) => sameRunEntry(entry, activeTail[index]));
}

function recoverPendingRuns(runtime, initialState) {
  let state = initialState;
  const stagingRoot = path.join(runtime.stateDir, 'staging');
  if (!fileExists(stagingRoot)) return state;
  for (const entry of listEntries(stagingRoot)) {
    if (!entry.isDirectory() || !isCanonicalRunId(entry.name)) continue;
    const runId = entry.name;
    const stageDir = path.join(stagingRoot, runId);
    const commit = readJson(path.join(stageDir, 'commit.json'), null);
    const reportPath = canonicalArtifactPath(path.join(runtime.artifactRoot, 'reports'), runId);
    const receiptPath = canonicalArtifactPath(path.join(runtime.artifactRoot, 'receipts'), runId);
    const report = reportPath ? readJson(reportPath, null) : null;
    const receipt = receiptPath ? readJson(receiptPath, null) : null;
    if (!commit || commit.runId !== runId || !report || report.runId !== runId || !receipt || receipt.runId !== runId) continue;
    if (!validateFinalArtifacts(runtime, runId, report.status)) continue;
    if (commit.status !== report.status || commit.reportHash !== sha256(JSON.stringify(report))) continue;
    const readyReceipt = { ...receipt, cursorPromotion: 'READY' };
    if (commit.receiptHash !== sha256(JSON.stringify(readyReceipt))) continue;
    const pendingState = readAuthenticatedPendingState(stageDir, commit);
    const activeRuns = Array.isArray(state.runs) ? state.runs : [];
    const activeRunIndex = activeRuns.findIndex((run) => run.runId === runId);
    const activeRun = activeRunIndex >= 0 ? activeRuns[activeRunIndex] : null;
    if (activeRun && activeRun.status !== commit.status) continue;
    const followsActive = pendingStateFollowsActive(activeRuns, pendingState.runs, runId, commit.status, activeRunIndex);
    if (!followsActive) continue;

    if (receipt.cursorPromotion === 'PROMOTED') {
      try { fs.rmSync(stageDir, { recursive: true, force: true }); } catch { /* exact staging directory is safe to retain */ }
      continue;
    }

    if (activeRun) {
      atomicWriteJson(receiptPath, { ...receipt, cursorPromotion: 'PROMOTED', cursorsPromoted: report.cursorsPromoted || [] });
      try { fs.rmSync(stageDir, { recursive: true, force: true }); } catch { /* exact staging directory is safe to retain */ }
      continue;
    }

    const mergedState = normalizeState({
      ...pendingState,
      eventKeys: mergeEventKeyLedger(pendingState.eventKeys, Object.keys(state.eventKeys || {})),
    });
    atomicWriteJson(path.join(runtime.stateDir, 'state.json'), mergedState);
    state = mergedState;
    atomicWriteJson(receiptPath, { ...receipt, cursorPromotion: 'PROMOTED', cursorsPromoted: report.cursorsPromoted || [] });
    try { fs.rmSync(stageDir, { recursive: true, force: true }); } catch { /* exact staging directory is safe to retain */ }
  }
  return state;
}

function pruneArtifacts(runtime, now, days) {
  const cutoff = retentionCutoff(now, days);
  const reportsRoot = path.join(runtime.artifactRoot, 'reports');
  const receiptsRoot = path.join(runtime.artifactRoot, 'receipts');
  const stagingRoot = path.join(runtime.stateDir, 'staging');
  const runIds = new Set();
  for (const entry of listEntries(reportsRoot)) {
    if (entry.isFile() && entry.name.endsWith('.json')) runIds.add(entry.name.slice(0, -5));
  }
  for (const entry of listEntries(receiptsRoot)) {
    if (entry.isFile() && entry.name.endsWith('.json')) runIds.add(entry.name.slice(0, -5));
  }
  for (const entry of listEntries(stagingRoot)) {
    if (entry.isDirectory()) runIds.add(entry.name);
  }
  for (const runId of runIds) {
    if (!isCanonicalRunId(runId)) continue;
    const reportPath = canonicalArtifactPath(reportsRoot, runId);
    const receiptPath = canonicalArtifactPath(receiptsRoot, runId);
    const stageDir = path.join(stagingRoot, runId);
    const report = reportPath ? readJson(reportPath, null) : null;
    const receipt = receiptPath ? readJson(receiptPath, null) : null;
    const stageReport = readJson(path.join(stageDir, 'report.json'), null);
    const generatedAt = Date.parse(report?.generatedAt || stageReport?.generatedAt || receipt?.generatedAt || '');
    let observedAt = generatedAt;
    if (!Number.isFinite(observedAt)) {
      for (const target of [reportPath, receiptPath, stageDir]) {
        if (!target) continue;
        try {
          observedAt = fs.statSync(target).mtimeMs;
          break;
        } catch { /* exact retention target may already be gone */ }
      }
    }
    if (!Number.isFinite(observedAt) || observedAt >= cutoff) continue;
    for (const target of [
      reportPath,
      canonicalArtifactPath(reportsRoot, runId, '.md'),
      receiptPath,
      isCanonicalRunId(runId) ? stageDir : '',
    ]) {
      if (!target) continue;
      try { fs.rmSync(target, { recursive: true, force: true }); } catch { /* exact retention target */ }
    }
  }
}

function validateFinalArtifacts(runtime, runId, expectedStatus) {
  const reportPath = canonicalArtifactPath(path.join(runtime.artifactRoot, 'reports'), runId);
  const receiptPath = canonicalArtifactPath(path.join(runtime.artifactRoot, 'receipts'), runId);
  const report = reportPath ? readJson(reportPath, null) : null;
  const receipt = receiptPath ? readJson(receiptPath, null) : null;
  if (!report || !receipt || report.runId !== runId || receipt.runId !== runId || report.status !== expectedStatus) return false;
  if (report.markdown !== buildMarkdown(report)) return false;
  if (report.postGate?.status !== 'PASS' || report.postGate?.eventLog !== 'EMITTED') return false;
  if (receipt.postGate?.status !== 'PASS' || receipt.postGate?.eventLog !== 'EMITTED') return false;
  if (expectedStatus === 'complete' && !['READY', 'PROMOTED'].includes(receipt.cursorPromotion)) return false;
  if (expectedStatus !== 'complete' && (receipt.cursorPromotion !== 'BLOCKED' || (report.cursorsPromoted || []).length !== 0 || (receipt.cursorsPromoted || []).length !== 0)) return false;
  return true;
}

async function runGardener(mode, options = {}) {
  const runtime = getRuntimeOptions(options);
  let config;
  try {
    config = loadConfig(runtime.configPath, options.config);
  } catch (error) {
    return { exitCode: 1, status: 'fatal', runId: options.runId || null, error: error.message };
  }
  const lock = acquireLock(runtime.stateDir);
  if (!lock.acquired) return { exitCode: 75, status: 'locked', runId: null, report: null };
  const runId = options.runId || process.env.CANUTO_SKILL_GARDENER_RUN_ID || makeRunId(runtime.now);
  let stageDir = '';
  try {
    if (!isCanonicalRunId(runId)) return { exitCode: 1, status: 'fatal', runId: null, error: 'invalid-run-id' };
    stageDir = path.join(runtime.stateDir, 'staging', runId);
    let state = loadState(path.join(runtime.stateDir, 'state.json'));
    state = recoverPendingRuns(runtime, state);
    const existingRun = state.runs?.find((run) => run.runId === runId);
    if (existingRun) {
      const existingReport = reportForRun(runtime, runId);
      if (existingReport) return { exitCode: existingReport.status === 'complete' ? 0 : 2, status: existingReport.status, runId, report: existingReport };
    }
    const existingReceiptPath = canonicalArtifactPath(path.join(runtime.artifactRoot, 'receipts'), runId);
    const existingReceipt = existingReceiptPath ? readJson(existingReceiptPath, null) : null;
    if (existingReceipt?.cursorPromotion === 'PROMOTED') {
      const existingReport = reportForRun(runtime, runId);
      if (existingReport && validateFinalArtifacts(runtime, runId, existingReport.status)) {
        return { exitCode: existingReport.status === 'complete' ? 0 : 2, status: existingReport.status, runId, report: existingReport };
      }
    }
    const permanentLedger = mergeEventKeyLedger(state.eventKeys, state.detailedEvents.map((event) => event.eventKey));
    const retainedPriorDetails = retainDetailedEvents(state.detailedEvents, runtime.now, config.policy.detailRetentionDays);
    state = {
      ...state,
      eventKeys: permanentLedger,
      detailedEvents: retainedPriorDetails,
      coverage: retainCoverage(state.coverage, runtime.now, config.policy.detailRetentionDays),
    };
    const catalog = collectInventory(config, { home: runtime.home, hmacKey: runtime.hmacKey, frameworkRoot: runtime.frameworkRoot });
    const sources = collectSources(config, { home: runtime.home, hmacKey: runtime.hmacKey, project: options.project });
    const projectMappings = buildProjectMappings(config, runtime.home);
    const sourceReports = [];
    const newEventEntries = [];
    const promoted = [];
    const stagedCursors = {};
    const stagedCoverage = {};
    const full = mode === 'backfill' || mode === 'weekly' && Object.keys(state.cursors || {}).length === 0;
    const fingerprintDescriptors = projectFingerprintDescriptors(config, runtime.home);
    const fingerprintsBefore = {};
    const fingerprintsBeforeRaw = {};
    for (const [logicalProjectId, descriptor] of Object.entries(fingerprintDescriptors)) {
      const fingerprint = manifestFingerprint(descriptor, runtime.hmacKey);
      fingerprintsBeforeRaw[logicalProjectId] = fingerprint;
      fingerprintsBefore[logicalProjectId] = fingerprint.type === 'NON_GIT_MEMORY_ONLY' ? { type: fingerprint.type } : fingerprint;
    }
    for (const source of sources) {
      if (source.status === 'NOT_CONFIGURED' || source.status === 'NOT_IMPLEMENTED') {
        sourceReports.push({ ...source, status: source.status, events: 0 });
        continue;
      }
      const context = {
        catalog,
        hmacKey: runtime.hmacKey,
        now: runtime.now,
        home: runtime.home,
        surfaceAlias: source.sourceAlias || 'UNMAPPED',
        logicalProjectId: source.logicalProjectId || 'UNMAPPED',
        surfaceId: source.surfaceId || 'UNMAPPED',
        mapSessions: source.mapSessions === true,
        projectMappings,
        previousCoverage: state.coverage?.[source.sourceId] || [],
        fingerprintFamilies: config.policy.fingerprintFamilies,
        fallbackTimestamp: runtime.now,
      };
      let result;
      if (source.remoteAlias && source.remoteAlias !== 'UNMAPPED' && options.remote !== false) {
        const skillVariants = {};
        for (const variant of catalog.variants) {
          const variants = skillVariants[variant.name] || {};
          variants[variant.contentHash] = variant.skillKey;
          skillVariants[variant.name] = variants;
        }
        result = await collectRemoteSource({ alias: source.remoteAlias, payload: { provider: source.provider, historyRoots: [source.path], skillVariants, hmacKey: runtime.hmacKey, surfaceAlias: source.sourceAlias || 'UNMAPPED', logicalProjectId: source.logicalProjectId || 'UNMAPPED', projectMappings: source.remoteMappings || [] } });
        const previousCoverage = state.coverage?.[source.sourceId] || [];
        const previousComplete = previousCoverage.filter((interval) => interval.status === 'COMPLETE').sort((left, right) => Date.parse(right.end) - Date.parse(left.end))[0];
        const remoteCoverage = (source.remoteMappings || []).map((mapping) => ({
          sourceId: source.sourceId,
          provider: source.provider,
          surfaceId: mapping.surfaceId || 'UNMAPPED',
          surfaceAlias: mapping.surfaceAlias || source.sourceAlias || 'UNMAPPED',
          logicalProjectId: mapping.logicalProjectId || 'UNMAPPED',
          start: previousComplete?.end || runtime.now,
          end: runtime.now,
          status: result.ok ? 'COMPLETE' : 'PARTIAL',
          reason: result.reason || '',
        }));
        result.coverage = remoteCoverage.length > 0 ? remoteCoverage : {
          sourceId: source.sourceId,
          provider: source.provider,
          surfaceId: source.surfaceId || 'UNMAPPED',
          surfaceAlias: source.sourceAlias || 'UNMAPPED',
          logicalProjectId: source.logicalProjectId || 'UNMAPPED',
          start: previousComplete?.end || runtime.now,
          end: runtime.now,
          status: result.ok ? 'COMPLETE' : 'PARTIAL',
          reason: result.reason || '',
        };
      } else {
        result = readLocalSource({ source, cursor: state.cursors?.[source.sourceId] || {}, context, full });
      }
      sourceReports.push({ ...source, status: result.partial ? 'PARTIAL' : result.ok ? 'COMPLETE' : 'PARTIAL', events: (result.events || []).length, reason: result.reason || '' });
      if (result.ok) {
        for (const event of result.events || []) {
          const priority = source.mapSessions === true
            ? event.logicalProjectId && event.logicalProjectId !== 'UNMAPPED' ? 3 : 1
            : 2;
          newEventEntries.push({ event, priority });
        }
        stagedCursors[source.sourceId] = result.cursors || {};
        stagedCoverage[source.sourceId] = Array.isArray(result.coverage) ? result.coverage.map((coverage) => ({ ...coverage })) : [{ ...result.coverage }];
        promoted.push(source.sourceId);
      }
    }
    if (typeof options.beforeAfterFingerprint === 'function') await options.beforeAfterFingerprint();
    const fingerprintsAfter = {};
    const nonGitReceipts = {};
    for (const [logicalProjectId, descriptor] of Object.entries(fingerprintDescriptors)) {
      const after = manifestFingerprint(descriptor, runtime.hmacKey);
      fingerprintsAfter[logicalProjectId] = after.type === 'NON_GIT_MEMORY_ONLY' ? { type: after.type } : after;
      if (after.type === 'NON_GIT_MEMORY_ONLY') {
        nonGitReceipts[logicalProjectId] = { quantity: after.fileCount, status: compareFingerprints(fingerprintsBeforeRaw[logicalProjectId], after) };
      }
    }
    const uniqueNewEvents = [];
    const seen = new Set(Object.keys(permanentLedger));
    const byEventKey = new Map();
    for (const entry of newEventEntries) {
      const event = entry.event;
      if (seen.has(event.eventKey)) continue;
      const previous = byEventKey.get(event.eventKey);
      if (!previous || entry.priority > previous.priority) byEventKey.set(event.eventKey, entry);
    }
    for (const entry of byEventKey.values()) uniqueNewEvents.push(entry.event);
    const verified = uniqueNewEvents.filter((event) => event.kind === 'verified_usage');
    const retainedRunEvents = retainDetailedEvents(uniqueNewEvents, runtime.now, config.policy.detailRetentionDays);
    const retainedDetailedEvents = retainDetailedEvents([...(retainedPriorDetails || []), ...retainedRunEvents], runtime.now, config.policy.detailRetentionDays);
    let nextState = {
      ...state,
      schemaVersion: SCHEMA_VERSION,
      cursors: { ...(state.cursors || {}), ...stagedCursors },
      coverage: retainCoverage({ ...(state.coverage || {}) }, runtime.now, config.policy.detailRetentionDays),
      eventKeys: mergeEventKeyLedger(permanentLedger, uniqueNewEvents),
      lifetimeUsage: { ...(state.lifetimeUsage || {}) },
      detailedEvents: retainedDetailedEvents,
    };
    for (const event of verified) nextState.lifetimeUsage[event.skillKey] = (nextState.lifetimeUsage[event.skillKey] || 0) + 1;
    for (const [sourceId, intervals] of Object.entries(stagedCoverage)) nextState.coverage[sourceId] = mergeIntervals([...(state.coverage?.[sourceId] || []), ...intervals]);
    nextState.coverage = retainCoverage(nextState.coverage, runtime.now, config.policy.detailRetentionDays);
    const coverageBySkill = buildCoverageBySkill({ catalog, state: nextState, sources: sourceReports, now: runtime.now });
    const status = sourceReports.some((source) => ['PARTIAL', 'NOT_IMPLEMENTED'].includes(source.status)) ? 'partial' : 'complete';
    ensureDir(stageDir);
    const reportData = buildReport({
      runId,
      mode: full && mode === 'weekly' ? 'backfill' : mode,
      status,
      sources: sourceReports,
      catalog,
      state,
      retainedRunEvents,
      retainedDetailedEvents,
      coverageIntervals: coverageBySkill,
      config,
      fingerprints: { before: fingerprintsBefore, after: fingerprintsAfter },
      postGate: { status: 'PENDING', eventLog: 'PENDING', checks: {}, noRetry: true },
      cursorsPromoted: [],
      now: runtime.now,
      nonGitReceipts,
      hmacKey: runtime.hmacKey,
      lifetimeUsage: nextState.lifetimeUsage,
    });
    const cleanReport = finalizeReport(reportData);
    atomicWriteJson(path.join(stageDir, 'report.json'), cleanReport);
    atomicWriteJson(path.join(stageDir, 'receipt.json'), {
      schemaVersion: SCHEMA_VERSION,
      tool: 'canuto-skill-gardener',
      runId,
      status,
      eventCount: uniqueNewEvents.length,
      sourceCount: sourceReports.length,
      nonGitReceipts,
      cursorPromotion: 'PENDING',
    });
    if (options.failAfterStage || options.crashAt === 'stage') throw new Error('injected-crash-after-stage');
    const eventLogResult = await emitCanutoEvent(runtime, cleanReport);
    if (options.failAfterEventLog || options.crashAt === 'event-log') throw new Error('injected-crash-after-event-log');
    const gate = postGate(stageDir, eventLogResult);
    if (gate.status !== 'PASS') {
      const failedReport = finalizeReport({ ...cleanReport, status: 'partial', complete: false, partial: true, postGate: gate, cursorsPromoted: [] });
      atomicWriteJson(path.join(runtime.artifactRoot, 'reports', `${runId}.json`), failedReport);
      atomicWriteJson(path.join(runtime.artifactRoot, 'receipts', `${runId}.json`), { ...readJson(path.join(stageDir, 'receipt.json'), {}), status: 'partial', postGate: gate, cursorPromotion: 'BLOCKED', cursorsPromoted: [] });
      if (options.failAfterFinalArtifacts || options.crashAt === 'final-artifacts') throw new Error('injected-crash-after-final-artifacts');
      return { exitCode: 2, status: 'partial', runId, report: failedReport };
    }
    const promotionAllowed = status === 'complete';
    const finalReport = finalizeReport({ ...cleanReport, status, complete: promotionAllowed, partial: status === 'partial', postGate: gate, cursorsPromoted: promotionAllowed ? promoted : [] });
    const finalReceipt = {
      schemaVersion: SCHEMA_VERSION,
      tool: 'canuto-skill-gardener',
      runId,
      status: finalReport.status,
      eventCount: uniqueNewEvents.length,
      sourceCount: sourceReports.length,
      nonGitReceipts,
      postGate: gate,
      cursorPromotion: promotionAllowed ? 'READY' : 'BLOCKED',
      cursorsPromoted: promotionAllowed ? promoted : [],
    };
    atomicWriteJson(path.join(runtime.artifactRoot, 'reports', `${runId}.json`), finalReport);
    atomicWriteJson(path.join(runtime.artifactRoot, 'receipts', `${runId}.json`), finalReceipt);
    if (!validateFinalArtifacts(runtime, runId, status)) throw new Error('final-artifacts-invalid');
    if (options.failAfterFinalArtifacts || options.crashAt === 'final-artifacts') throw new Error('injected-crash-after-final-artifacts');
    if (!promotionAllowed) {
      try { fs.rmSync(stageDir, { recursive: true, force: true }); } catch { /* partial run never promotes cursor state */ }
      pruneArtifacts(runtime, runtime.now, config.policy.detailRetentionDays);
      return { exitCode: 2, status: 'partial', runId, report: finalReport };
    }
    nextState.runs = appendRunIndex(state, runId, finalReport.status);
    nextState = normalizeState(nextState);
    atomicWriteJson(path.join(stageDir, 'pending-state.json'), nextState);
    const pendingStateRaw = fs.readFileSync(path.join(stageDir, 'pending-state.json'));
    atomicWriteJson(path.join(stageDir, 'commit.json'), { schemaVersion: SCHEMA_VERSION, tool: 'canuto-skill-gardener', runId, status: finalReport.status, reportHash: sha256(JSON.stringify(finalReport)), receiptHash: sha256(JSON.stringify(finalReceipt)), pendingStateHash: sha256(pendingStateRaw) });
    if (options.failAfterCommit || options.crashAt === 'commit') throw new Error('injected-crash-after-commit');
    if (options.failBeforePromotion) throw new Error('injected-crash-before-cursor-promotion');
    atomicWriteJson(path.join(runtime.stateDir, 'state.json'), nextState);
    if (options.failAfterPromotion || options.crashAt === 'promotion') throw new Error('injected-crash-after-cursor-promotion');
    atomicWriteJson(path.join(runtime.artifactRoot, 'receipts', `${runId}.json`), { ...finalReceipt, cursorPromotion: 'PROMOTED' });
    try { fs.rmSync(stageDir, { recursive: true, force: true }); } catch { /* exact run stage can be recovered later */ }
    pruneArtifacts(runtime, runtime.now, config.policy.detailRetentionDays);
    return { exitCode: finalReport.status === 'complete' ? 0 : 2, status: finalReport.status, runId, report: finalReport };
  } catch (error) {
    return { exitCode: 1, status: 'fatal', runId, error: error.message };
  } finally {
    releaseLock(lock);
  }
}

function latestReport(runtime) {
  const state = loadState(path.join(runtime.stateDir, 'state.json'));
  const latest = state?.runs?.[state.runs.length - 1];
  if (!latest) return { schemaVersion: SCHEMA_VERSION, tool: 'canuto-skill-gardener', latestRunId: null, status: 'UNKNOWN', reports: 0 };
  const reportPath = canonicalArtifactPath(path.join(runtime.artifactRoot, 'reports'), latest.runId);
  const report = reportPath ? readJson(reportPath, null) : null;
  return report || { schemaVersion: SCHEMA_VERSION, tool: 'canuto-skill-gardener', latestRunId: latest.runId, status: latest.status, reports: state.runs.length };
}

function reportForRun(runtime, runId) {
  const reportPath = canonicalArtifactPath(path.join(runtime.artifactRoot, 'reports'), runId);
  return reportPath ? readJson(reportPath, null) : null;
}

function canonicalCronLine(home = os.homedir()) {
  const binary = path.join(home, '.canuto', 'bin', 'canuto-skill-gardener');
  const log = path.join(home, '.canuto', 'logs', 'skill-gardener-weekly.log');
  return `${CRON_SCHEDULE} ${binary} weekly >> ${log} 2>&1 ${MARKER}`;
}

function readCrontabText(options = {}) {
  if (typeof options.read === 'function') {
    try {
      return { ok: true, text: String(options.read() || ''), reason: '' };
    } catch (error) {
      const message = [error?.message, error?.stderr].map((value) => String(value || '')).join('\n');
      if (/no crontab for/i.test(message)) return { ok: true, text: '', reason: '' };
      return { ok: false, text: '', reason: 'crontab-read-failed' };
    }
  }
  const file = options.file || process.env.CANUTO_SKILL_GARDENER_CRONTAB_FILE;
  if (file) {
    try {
      return { ok: true, text: fs.readFileSync(file, 'utf8'), reason: '' };
    } catch (error) {
      if (error?.code === 'ENOENT') return { ok: true, text: '', reason: '' };
      return { ok: false, text: '', reason: 'crontab-read-failed' };
    }
  }
  try {
    return { ok: true, text: execFileSync('crontab', ['-l'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }), reason: '' };
  } catch (error) {
    const stderr = Buffer.isBuffer(error?.stderr) ? error.stderr.toString('utf8') : String(error?.stderr || '');
    if (/no crontab for/i.test(stderr)) return { ok: true, text: '', reason: '' };
    return { ok: false, text: '', reason: 'crontab-read-failed' };
  }
}

function renderCronInstall(current, line) {
  const lines = String(current || '').split(/\r?\n/).filter((value) => value && !value.includes(MARKER));
  if (!lines.includes(line)) lines.push(line);
  return `${lines.join('\n')}\n`;
}

function renderCronRemove(current) {
  const lines = String(current || '').split(/\r?\n/).filter((value) => value && !value.includes(MARKER));
  return lines.length ? `${lines.join('\n')}\n` : '';
}

function canaryReceiptPath(options = {}) {
  if (options.canaryPath) return path.resolve(options.canaryPath);
  const home = options.home || os.homedir();
  const artifactRoot = options.artifactRoot || path.join(home, '.canuto', 'vault', 'projects', 'canuto-framework-v1', 'skill-gardener');
  return path.resolve(artifactRoot, 'canary.json');
}

function promotedCanaryEvidence(runtime, runId) {
  const report = reportForRun(runtime, runId);
  const runReceiptPath = canonicalArtifactPath(path.join(runtime.artifactRoot, 'receipts'), runId);
  const runReceipt = runReceiptPath ? readJson(runReceiptPath, null) : null;
  let state;
  try {
    state = loadState(path.join(runtime.stateDir, 'state.json'));
  } catch {
    return { ok: false, reason: 'state-unavailable' };
  }
  const stageDir = path.join(runtime.stateDir, 'staging', runId);
  const reportCursors = [...(report?.cursorsPromoted || [])].sort();
  const receiptCursors = [...(runReceipt?.cursorsPromoted || [])].sort();
  const valid = report?.status === 'complete'
    && report.complete === true
    && report.postGate?.status === 'PASS'
    && report.postGate?.eventLog === 'EMITTED'
    && runReceipt?.status === 'complete'
    && runReceipt?.postGate?.status === 'PASS'
    && runReceipt?.postGate?.eventLog === 'EMITTED'
    && runReceipt?.cursorPromotion === 'PROMOTED'
    && stableJson(reportCursors) === stableJson(receiptCursors)
    && state?.runs?.some((run) => run?.runId === runId && run.status === 'complete')
    && !fileExists(stageDir);
  if (!valid) return { ok: false, reason: 'canary-run-not-promoted' };
  return {
    ok: true,
    reportHash: sha256(stableJson(report)),
    receiptHash: sha256(stableJson(runReceipt)),
  };
}

function canaryStatus(options = {}) {
  const runtime = getRuntimeOptions({ ...options, readOnly: true });
  const receipt = readJson(canaryReceiptPath(runtime), null);
  if (!receipt || receipt.schemaVersion !== SCHEMA_VERSION || receipt.status !== CANARY_STATUS || receipt.postMerge !== true || !isCanonicalRunId(receipt.runId)) {
    return { ok: false, status: 'BLOCKED', reason: 'canary-incomplete' };
  }
  const evidence = promotedCanaryEvidence(runtime, receipt.runId);
  if (!evidence.ok || receipt.reportHash !== evidence.reportHash || receipt.receiptHash !== evidence.receiptHash) {
    return { ok: false, status: 'BLOCKED', reason: evidence.reason || 'canary-evidence-mismatch' };
  }
  return { ok: true, status: CANARY_STATUS, reason: '', runId: receipt.runId };
}

function recordCanaryReceipt(options = {}) {
  const runtime = getRuntimeOptions(options);
  const runId = options.runId;
  if (options.postMerge !== true || !isCanonicalRunId(runId)) return { ok: false, reason: 'canary-requires-post-merge-canonical-run' };
  const evidence = promotedCanaryEvidence(runtime, runId);
  if (!evidence.ok) return evidence;
  const target = canaryReceiptPath(runtime);
  atomicWriteJson(target, { schemaVersion: SCHEMA_VERSION, tool: 'canuto-skill-gardener', kind: 'post-merge-canary', runId, status: CANARY_STATUS, postMerge: true, reportHash: evidence.reportHash, receiptHash: evidence.receiptHash, validatedAt: runtime.now });
  return { ok: true, status: CANARY_STATUS, runId };
}

function cronAction(action, options = {}) {
  const readResult = readCrontabText(options);
  if (!readResult.ok) {
    return {
      ok: false,
      changed: false,
      line: '',
      current: '',
      next: '',
      installed: null,
      status: 'UNAVAILABLE',
      reason: readResult.reason || 'crontab-read-failed',
    };
  }
  const line = canonicalCronLine(options.home || os.homedir());
  const current = readResult.text;
  if (action === 'status') return { ok: true, changed: false, line, current, next: current, installed: current.split(/\r?\n/).some((value) => value.includes(MARKER)), status: 'READY' };
  if (!['install', 'remove'].includes(action)) return { ok: false, changed: false, line, current, next: current, installed: current.includes(MARKER), status: 'UNAVAILABLE', reason: 'invalid-cron-action' };
  if (action === 'install') {
    const canary = canaryStatus(options);
    if (!canary.ok) return { ok: false, changed: false, line, current, next: current, installed: current.includes(MARKER), status: 'BLOCKED', reason: canary.reason, canaryStatus: canary.status };
  }
  const next = action === 'install' ? renderCronInstall(current, line) : renderCronRemove(current);
  const changed = next !== current;
  if (action === 'install' && !options.dryRun) ensureDir(path.join(options.home || os.homedir(), '.canuto', 'logs'));
  if (!options.dryRun && changed) {
    if (typeof options.write === 'function') options.write(next);
    else if (options.file || process.env.CANUTO_SKILL_GARDENER_CRONTAB_FILE) atomicWrite(options.file || process.env.CANUTO_SKILL_GARDENER_CRONTAB_FILE, next);
    else {
      const result = require('node:child_process').spawnSync('crontab', ['-'], { input: next, encoding: 'utf8', stdio: ['pipe', 'ignore', 'ignore'] });
      if (result.status !== 0) return { ok: false, changed: false, line, current, next, installed: current.includes(MARKER), status: 'UNAVAILABLE', reason: 'crontab-write-failed' };
    }
  }
  return { ok: true, changed, line, current, next, installed: next.includes(MARKER), status: 'READY' };
}

function statusJson(runtime) {
  let state = null;
  let stateError = '';
  try {
    state = loadState(path.join(runtime.stateDir, 'state.json'));
  } catch (error) {
    stateError = error.message || 'state-unavailable';
  }
  const latest = state?.runs?.[state.runs.length - 1];
  const reportPath = latest ? canonicalArtifactPath(path.join(runtime.artifactRoot, 'reports'), latest.runId) : '';
  const report = reportPath ? readJson(reportPath, null) : null;
  let config = null;
  let configError = '';
  try {
    config = loadConfig(runtime.configPath);
  } catch (error) {
    configError = error.message || 'config-unavailable';
  }
  const providerStatuses = Object.fromEntries(PROVIDERS.map((provider) => {
    if (configError || !config) return [provider, 'UNAVAILABLE'];
    const settings = config.providers[provider] || {};
    return [provider, sourceStatus(provider, [...(settings.roots || []), ...(settings.pluginRoots || []), ...(settings.systemRoots || [])], settings.historyRoots || [])];
  }));
  const cronStatus = cronAction('status', { ...runtime, dryRun: true });
  const unavailable = Boolean(configError || stateError || !cronStatus.ok);
  return sanitizePersistedReport({
    schemaVersion: SCHEMA_VERSION,
    tool: 'canuto-skill-gardener',
    latestRunId: report?.runId || latest?.runId || null,
    status: unavailable ? 'UNAVAILABLE' : report?.status || 'UNKNOWN',
    complete: unavailable ? false : report?.complete === true,
    partial: report?.partial === true || report?.status === 'partial',
    sources: report?.sources || [],
    classifications: report?.classifications || [],
    cursorsPromoted: report?.cursorsPromoted || [],
    postGate: report?.postGate || null,
    providerStatuses,
    configuration: configError ? 'UNAVAILABLE' : 'READY',
    configurationReason: configError,
    state: stateError ? 'UNAVAILABLE' : 'READY',
    stateReason: stateError,
    cron: {
      configured: cronStatus.ok ? cronStatus.installed === true : null,
      status: cronStatus.ok ? 'READY' : 'UNAVAILABLE',
      reason: cronStatus.ok ? '' : cronStatus.reason || 'crontab-read-failed',
      explicitInstallOnly: true,
    },
  });
}

module.exports = {
  CLOSED_REMOTE_KEYS,
  CRON_SCHEDULE,
  DETAIL_RETENTION_DAYS,
  MAX_LINE_BYTES,
  MAX_REMOTE_STDERR_BYTES,
  MAX_REMOTE_STDOUT_BYTES,
  NEGATIVE_WINDOW_DAYS,
  REMOTE_CONNECT_TIMEOUT_MS,
  REMOTE_EXECUTION_TIMEOUT_MS,
  buildRemoteCollectorScript,
  buildProjectMappings,
  buildExistingCoverage,
  canonicalCronLine,
  canaryStatus,
  classifySkill,
  collectInventory,
  collectRemoteSource,
  collectSources,
  compareFingerprints,
  cronAction,
  defaultConfig,
  evalDecision,
  findCandidateClusters,
  getRuntimeOptions,
  hasContinuousCoverage,
  hmac,
  latestReport,
  loadConfig,
  loadState,
  makeSkillIdentity,
  manifestFingerprint,
  mapSessionToProject,
  normalizeConfig,
  normalizeName,
  parseClaudeEvents,
  parseCodexEvents,
  parseHermesEvents,
  parseProviderNdjson,
  parseRemoteNdjson,
  parseFrontmatter,
  recordCanaryReceipt,
  readCrontabText,
  readJson,
  reportForRun,
  runEvalAdapter,
  runGardener,
  sanitizePersistedReport,
  sanitizeStructuredEvent,
  scanSkillFiles,
  sha256,
  statusJson,
  sourceStatus,
  isCanonicalRunId,
};
