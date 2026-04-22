const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync, spawnSync } = require('node:child_process');

const DEFAULT_SESSION_LIMIT = 200;
const DEFAULT_PARALLELISM = 4;
const DEFAULT_ANALYSIS_MODE = 'deterministic';
const DEFAULT_CLAUDE_PROJECTS_ROOT = '~/.claude/projects';
const DEFAULT_CLAUDE_TELEMETRY_ROOT = '~/.claude/telemetry';
const DEFAULT_PRICING_PATH = '~/.cache/codeburn/litellm-pricing.json';
const DEFAULT_CANUTO_OTLP_HTTP_ENDPOINT = 'http://localhost:4318/v1/metrics';
const DEFAULT_CANUTO_OTLP_FALLBACK = '.agents/vault/metrics/canuto-otlp.jsonl';

const EXCLUDED_WORKSPACE_ROOTS = new Set(['.claude', 'CODEX-GERAL']);
const EXCLUDED_PATH_MARKERS = ['backup-before', '.backup-'];

const SOURCE_PRIORITY = {
  codex_log: 5,
  claude_project_log: 5,
  global_vault: 4,
  local_vault: 4,
  audit: 2,
  metrics: 1,
};

const SECTION_ALIASES = {
  summary: ['summary', 'resumo'],
  whatWasDone: ['what was done', 'o que foi feito'],
  validation: ['validation', 'validacao', 'validação'],
  learnings: ['learnings', 'learning', 'aprendizados'],
  pending: ['pending', 'pendente', 'pending (acumulado)'],
};

const STATUS_PRIORITY = {
  unknown: 0,
  healthy: 1,
  partial: 2,
  failing: 3,
};

// Keep bucket counts in lifecycle order so report diffs stay readable.
const BUCKET_TAXONOMY_ORDER = ['never-installed', 'dormant', 'pre-v1.8', 'v1.8-failing', 'healthy'];
// Surface broken v1.8 projects first where operators need triage.
const BUCKET_TRIAGE_ORDER = {
  'v1.8-failing': 0,
  'pre-v1.8': 1,
  dormant: 2,
  'never-installed': 3,
  healthy: 4,
};

const GENERIC_SKILL_PHRASES = new Set([
  'skill',
  'skills',
  'context',
  'review',
  'reviews',
  'code',
  'debug',
  'test',
  'tests',
  'plan',
  'planning',
  'research',
]);

const PENDING_SYNC_CONTEXT_RE =
  /(?:(?:pending-sync|pending_sync)[\s:_—–\-#]*(?:queue|error|failed|backlog|items|count|fired|triggered)|(?:queue|error|failed|backlog|items|count|fired|triggered)[\s:_—–\-#]*(?:pending-sync|pending_sync))/i;
const PENDING_SYNC_MARKER_RE = /(?:pending-sync|pending_sync)/i;
const OFFLINE_SYNC_CONTEXT_RE =
  /(?:(?:OFFLINE[-_]SYNC|offline[-_]sync)[\s:_—–\-#]*(?:event|marker|triggered|detected|queued|fired|flag|required|fallback)|(?:event|marker|triggered|detected|queued|fired|flag|required|fallback)[\s:_—–\-#]*(?:OFFLINE[-_]SYNC|offline[-_]sync))/i;
const OFFLINE_SYNC_MARKER_RE = /(?:OFFLINE[-_]SYNC|offline[-_]sync)/i;
const OFFLINE_SYNC_HEADING_RE = /^\s*#+\s*(?:OFFLINE[-_]SYNC|offline[-_]sync)[\s:_—–\-#]+[^\s].*/i;
const SYNC_MARKDOWN_FILE_RE = /[^\s`'"]*(?:pending-sync|pending_sync|OFFLINE[-_]SYNC|offline[-_]sync)[^\s`'"]*\.md\b/gi;
const SYNC_TEST_REFERENCE_RE = /\b(?:test|tests|testing|fixture|fixtures|spec|specs)\b/i;

const OBSIDIAN_PRIORITY = {
  compliant: 0,
  non_compliant_local: 1,
  non_compliant_missing: 2,
};

const CANUTO_SESSION_METRIC_DEFS = [
  { name: 'canuto.session.validation_skip_rate', kind: 'gauge', unit: '1' },
  { name: 'canuto.session.rework_loop_rate', kind: 'gauge', unit: '1' },
  { name: 'canuto.session.same_file_reopened_rate', kind: 'gauge', unit: '1' },
  { name: 'canuto.session.context_reset_need_rate', kind: 'gauge', unit: '1' },
  { name: 'canuto.session.memory_miss_rate', kind: 'gauge', unit: '1' },
  { name: 'canuto.session.retry_exhaustion_count', kind: 'counter', unit: '{count}' },
  { name: 'canuto.session.rule_gap_count', kind: 'counter', unit: '{count}' },
];

const EMPTY_TOKEN_USAGE = Object.freeze({
  input_tokens: 0,
  uncached_input_tokens: 0,
  cached_input_tokens: 0,
  cache_creation_input_tokens: 0,
  cache_read_input_tokens: 0,
  output_tokens: 0,
  reasoning_output_tokens: 0,
  total_tokens: 0,
});

function expandHome(inputPath) {
  if (!inputPath) return inputPath;
  if (inputPath === '~') return os.homedir();
  if (inputPath.startsWith('~/')) {
    return path.join(os.homedir(), inputPath.slice(2));
  }
  return inputPath;
}

function resolvePath(inputPath, cwd = process.cwd()) {
  return path.resolve(cwd, expandHome(inputPath));
}

function readTextIfExists(filePath) {
  if (!filePath || !fs.existsSync(filePath)) return '';
  return fs.readFileSync(filePath, 'utf8');
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function writeJson(filePath, value) {
  ensureDir(path.dirname(filePath));
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`);
}

function writeText(filePath, value) {
  ensureDir(path.dirname(filePath));
  fs.writeFileSync(filePath, value);
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function normalizeText(value) {
  return String(value || '')
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-z0-9/._ -]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function normalizeTokens(value) {
  return normalizeText(value)
    .split(/\s+/)
    .map((token) => token.trim())
    .filter((token) => token.length >= 3);
}

function unique(items) {
  return [...new Set((items || []).filter(Boolean))];
}

function cleanBullet(line) {
  return String(line || '')
    .replace(/^\s*[-*]\s*/, '')
    .replace(/^\s*\d+\.\s*/, '')
    .replace(/^\s*\[[ xX]\]\s*/, '')
    .trim();
}

function parseScalar(rawValue) {
  const trimmed = String(rawValue || '').trim();
  if (!trimmed) return '';

  if ((trimmed.startsWith('"') && trimmed.endsWith('"')) || (trimmed.startsWith("'") && trimmed.endsWith("'"))) {
    return trimmed.slice(1, -1).replace(/\\"/g, '"');
  }

  if (trimmed === 'true') return true;
  if (trimmed === 'false') return false;
  if (trimmed === 'null') return null;

  if (/^-?\d+(?:\.\d+)?$/.test(trimmed)) {
    return Number(trimmed);
  }

  if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
    const inner = trimmed.slice(1, -1).trim();
    if (!inner) return [];
    return inner
      .split(',')
      .map((item) => parseScalar(item))
      .filter((item) => item !== '');
  }

  return trimmed;
}

function parseFrontmatter(markdown) {
  const text = String(markdown || '');
  if (!text.startsWith('---\n') && !text.startsWith('---\r\n')) {
    return { data: {}, body: text };
  }

  const lines = text.split(/\r?\n/);
  if (lines[0] !== '---') {
    return { data: {}, body: text };
  }

  const data = {};
  let key = null;
  let index = 1;
  for (; index < lines.length; index += 1) {
    const line = lines[index];
    if (line === '---') {
      index += 1;
      break;
    }

    const keyMatch = line.match(/^([A-Za-z0-9_.-]+):(?:\s*(.*))?$/);
    if (keyMatch) {
      key = keyMatch[1];
      const rawValue = keyMatch[2] || '';
      if (!rawValue) {
        data[key] = [];
      } else {
        data[key] = parseScalar(rawValue);
      }
      continue;
    }

    const arrayMatch = line.match(/^\s*-\s+(.*)$/);
    if (arrayMatch && key) {
      if (!Array.isArray(data[key])) {
        data[key] = [data[key]].filter((value) => value !== undefined && value !== null && value !== '');
      }
      data[key].push(parseScalar(arrayMatch[1]));
    }
  }

  return {
    data,
    body: lines.slice(index).join('\n'),
  };
}

function extractSectionLines(markdown, headings) {
  const lines = String(markdown || '').split(/\r?\n/);
  const normalizedHeadings = headings.map((heading) => normalizeText(heading));
  let currentHeading = null;
  const collected = [];

  for (const line of lines) {
    const headingMatch = line.match(/^##\s+(.+)$/);
    if (headingMatch) {
      const heading = normalizeText(headingMatch[1]);
      currentHeading = normalizedHeadings.includes(heading) ? heading : null;
      continue;
    }

    if (!currentHeading) continue;
    if (!line.trim()) continue;

    if (/^\s*[-*]\s+/.test(line) || /^\s*\d+\.\s+/.test(line) || /^\s*\[[ xX]\]\s+/.test(line)) {
      collected.push(cleanBullet(line));
      continue;
    }

    collected.push(line.trim());
  }

  return unique(collected);
}

function parseSessionSections(markdown) {
  return {
    summary: extractSectionLines(markdown, SECTION_ALIASES.summary),
    whatWasDone: extractSectionLines(markdown, SECTION_ALIASES.whatWasDone),
    validation: extractSectionLines(markdown, SECTION_ALIASES.validation),
    learnings: extractSectionLines(markdown, SECTION_ALIASES.learnings),
    pending: extractSectionLines(markdown, SECTION_ALIASES.pending),
  };
}

function extractChecklistItems(markdown) {
  return unique(
    String(markdown || '')
      .split(/\r?\n/)
      .filter((line) => /^\s*[-*]\s+\[\s\]\s+/.test(line))
      .map((line) => cleanBullet(line)),
  );
}

function firstNonEmpty(...values) {
  for (const value of values) {
    if (value === undefined || value === null) continue;
    if (typeof value === 'string' && !value.trim()) continue;
    if (Array.isArray(value) && value.length === 0) continue;
    return value;
  }
  return undefined;
}

function toBoolean(value, fallback = false) {
  if (typeof value === 'boolean') return value;
  if (typeof value === 'number') return value !== 0;
  const normalized = normalizeText(value);
  if (!normalized) return fallback;
  if (['true', 'yes', 'sim'].includes(normalized)) return true;
  if (['false', 'no', 'nao'].includes(normalized)) return false;
  return fallback;
}

function toNumber(value, fallback = 0) {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  const parsed = Number(String(value || '').trim());
  return Number.isFinite(parsed) ? parsed : fallback;
}

function roundCost(value) {
  return typeof value === 'number' && Number.isFinite(value) ? Number(value.toFixed(6)) : null;
}

function normalizeModelKey(value) {
  return normalizeText(value).replace(/[^a-z0-9]+/g, '');
}

function incrementCounter(counter, key, amount = 1) {
  const cleanKey = String(key || '').trim();
  if (!cleanKey) return;
  counter[cleanKey] = (counter[cleanKey] || 0) + amount;
}

function counterToRankedList(counter, limit = 20) {
  return Object.entries(counter || {})
    .sort((left, right) => right[1] - left[1] || left[0].localeCompare(right[0]))
    .slice(0, limit)
    .map(([name, count]) => ({ name, count }));
}

function rankedListToCounter(items) {
  const counter = {};
  for (const item of items || []) {
    incrementCounter(counter, item.name || item.key || item.label, toNumber(item.count, 0));
  }
  return counter;
}

function mergeCounters(...counters) {
  const merged = {};
  for (const counter of counters) {
    for (const [key, count] of Object.entries(counter || {})) {
      incrementCounter(merged, key, toNumber(count, 0));
    }
  }
  return merged;
}

function mergeRankedLists(...lists) {
  return counterToRankedList(mergeCounters(...lists.map(rankedListToCounter)));
}

function normalizeTokenUsage(rawUsage = {}, kind = 'generic') {
  const inputTokens = toNumber(rawUsage.input_tokens ?? rawUsage.inputTokens, 0);
  const cachedInputTokens = toNumber(rawUsage.cached_input_tokens ?? rawUsage.cachedInputTokens, 0);
  const cacheCreationTokens = toNumber(rawUsage.cache_creation_input_tokens ?? rawUsage.cacheCreationInputTokens, 0);
  const cacheReadTokens = toNumber(rawUsage.cache_read_input_tokens ?? rawUsage.cacheReadInputTokens, 0);
  const outputTokens = toNumber(rawUsage.output_tokens ?? rawUsage.outputTokens, 0);
  const reasoningTokens = toNumber(rawUsage.reasoning_output_tokens ?? rawUsage.reasoningOutputTokens, 0);
  const uncachedInputTokens =
    rawUsage.uncached_input_tokens !== undefined || rawUsage.uncachedInputTokens !== undefined
      ? toNumber(rawUsage.uncached_input_tokens ?? rawUsage.uncachedInputTokens, 0)
      : kind === 'codex'
        ? Math.max(0, inputTokens - cachedInputTokens)
        : inputTokens;
  const computedTotal =
    uncachedInputTokens +
    cachedInputTokens +
    cacheCreationTokens +
    cacheReadTokens +
    outputTokens +
    reasoningTokens;
  const totalTokens = toNumber(rawUsage.total_tokens ?? rawUsage.totalTokens, computedTotal);

  return {
    input_tokens: inputTokens,
    uncached_input_tokens: uncachedInputTokens,
    cached_input_tokens: cachedInputTokens,
    cache_creation_input_tokens: cacheCreationTokens,
    cache_read_input_tokens: cacheReadTokens,
    output_tokens: outputTokens,
    reasoning_output_tokens: reasoningTokens,
    total_tokens: totalTokens || computedTotal,
  };
}

function addTokenUsage(left = EMPTY_TOKEN_USAGE, right = EMPTY_TOKEN_USAGE) {
  const result = {};
  for (const key of Object.keys(EMPTY_TOKEN_USAGE)) {
    result[key] = toNumber(left?.[key], 0) + toNumber(right?.[key], 0);
  }
  return result;
}

function tokenUsageHasValues(tokenUsage) {
  return Object.values(tokenUsage || {}).some((value) => toNumber(value, 0) > 0);
}

function loadPricingIndex(pricingPath) {
  const info = {
    path: pricingPath || '',
    available: false,
    model_count: 0,
    error: '',
  };
  const byKey = new Map();
  const entries = [];

  if (!pricingPath || !fs.existsSync(pricingPath)) {
    info.error = pricingPath ? 'not-found' : 'not-configured';
    return { byKey, entries, info };
  }

  try {
    const parsed = JSON.parse(readTextIfExists(pricingPath));
    const data = parsed.data && typeof parsed.data === 'object' ? parsed.data : parsed;
    for (const [modelKey, pricing] of Object.entries(data || {})) {
      if (!pricing || typeof pricing !== 'object') continue;
      const entry = {
        model_key: modelKey,
        normalized_key: normalizeModelKey(modelKey),
        pricing,
      };
      entries.push(entry);
      byKey.set(entry.normalized_key, entry);
    }
    info.available = entries.length > 0;
    info.model_count = entries.length;
  } catch (error) {
    info.error = error && error.message ? error.message : String(error);
  }

  return { byKey, entries, info };
}

function findPricingEntry(model, pricingIndex) {
  if (!model || !pricingIndex || pricingIndex.entries.length === 0) return null;
  const normalized = normalizeModelKey(model);
  if (!normalized) return null;

  const direct = pricingIndex.byKey.get(normalized);
  if (direct) return direct;

  const candidates = [
    `openai${normalized}`,
    `anthropic${normalized}`,
    `globalanthropic${normalized}`,
    `usanthropic${normalized}`,
  ];
  for (const candidate of candidates) {
    const match = pricingIndex.byKey.get(candidate);
    if (match) return match;
  }

  return pricingIndex.entries.find((entry) =>
    entry.normalized_key.includes(normalized) || normalized.includes(entry.normalized_key),
  ) || null;
}

function estimateTokenCost({ model, tokenUsage, pricingIndex, overrideCost = null, overrideSource = '' }) {
  if (typeof overrideCost === 'number' && Number.isFinite(overrideCost)) {
    return {
      estimated_cost_usd: roundCost(overrideCost),
      cost_source: overrideSource || 'telemetry',
      missing_pricing: [],
    };
  }

  if (!tokenUsageHasValues(tokenUsage)) {
    return {
      estimated_cost_usd: null,
      cost_source: 'none',
      missing_pricing: [],
    };
  }

  const pricingEntry = findPricingEntry(model, pricingIndex);
  if (!pricingEntry) {
    return {
      estimated_cost_usd: null,
      cost_source: 'missing-pricing',
      missing_pricing: model ? [model] : [],
    };
  }

  const pricing = pricingEntry.pricing;
  const inputCost = toNumber(pricing.inputCostPerToken, 0);
  const outputCost = toNumber(pricing.outputCostPerToken, 0);
  const cacheWriteCost = toNumber(pricing.cacheWriteCostPerToken, inputCost);
  const cacheReadCost = toNumber(pricing.cacheReadCostPerToken, inputCost);
  const cost =
    toNumber(tokenUsage.uncached_input_tokens, 0) * inputCost +
    toNumber(tokenUsage.cache_creation_input_tokens, 0) * cacheWriteCost +
    (toNumber(tokenUsage.cache_read_input_tokens, 0) + toNumber(tokenUsage.cached_input_tokens, 0)) * cacheReadCost +
    toNumber(tokenUsage.output_tokens, 0) * outputCost;

  return {
    estimated_cost_usd: roundCost(cost),
    cost_source: `pricing:${pricingEntry.model_key}`,
    missing_pricing: [],
  };
}

function extractFieldFromBody(body, fieldName) {
  const pattern = new RegExp(`^-\\s*${escapeRegExp(fieldName)}:\\s*(.+)$`, 'im');
  const match = String(body || '').match(pattern);
  return match ? match[1].trim().replace(/^`|`$/g, '') : '';
}

function normalizeToolName(toolName) {
  const name = String(toolName || '').trim();
  if (!name) return '';
  if (name === 'exec_command') return 'bash';
  if (name === 'apply_patch') return 'Edit';
  if (name.startsWith('mcp__')) {
    const parts = name.split('__');
    return parts[2] || parts[1] || name;
  }
  return name;
}

function extractMcpServerName(toolName) {
  const name = String(toolName || '').trim();
  if (!name.startsWith('mcp__')) return '';
  return name.split('__')[1] || '';
}

function stripShellWrapper(command) {
  const text = String(command || '').trim();
  const shellMatch = text.match(/^(?:\/bin\/)?(?:bash|zsh|sh)\s+-lc\s+(.+)$/);
  if (!shellMatch) return text;
  return shellMatch[1].replace(/^['"]|['"]$/g, '').trim();
}

function shellCommandName(command) {
  let text = stripShellWrapper(command)
    .replace(/^\s*(?:sudo\s+)?(?:env\s+)?/, '')
    .replace(/^\w+=\S+\s+/, '')
    .trim();
  if (!text) return '';
  if (text.startsWith('python ')) return 'python';
  if (text.startsWith('python3 ')) return 'python3';
  if (text.startsWith('node ')) return 'node';
  if (text.startsWith('npm run ')) return 'npm';
  if (text.startsWith('pnpm ')) return 'pnpm';
  if (text.startsWith('yarn ')) return 'yarn';
  if (text.startsWith('command -v ')) return 'command';
  const match = text.match(/^([A-Za-z0-9_./-]+)/);
  if (!match) return '';
  return path.basename(match[1]);
}

function classifyActivity({ tools = [], shellCommands = [], failedCommandCount = 0, userMessages = [] }) {
  const text = normalizeText([
    ...tools,
    ...shellCommands,
    ...userMessages,
  ].join(' '));
  const commandNames = shellCommands.map(shellCommandName).map((item) => normalizeText(item));
  const toolNames = tools.map((item) => normalizeText(item));

  if (commandNames.includes('git')) return 'Git Ops';
  if (/\b(test|vitest|jest|pytest|node --test|playwright test)\b/.test(text)) return 'Testing';
  if (/\b(build|tsc|typecheck|type-check|lint|deploy|vercel|netlify)\b/.test(text)) return 'Build/Deploy';
  if (
    toolNames.some((item) => ['edit', 'write', 'apply_patch'].includes(item)) ||
    /\b(apply_patch|tee|mv|cp|rm|mkdir)\b/.test(text) ||
    />\s*\S+/.test(text)
  ) {
    return 'Coding';
  }
  if (
    failedCommandCount > 0 ||
    /\b(error|stack|trace|console|debug|logs?|exception|failed)\b/.test(text) ||
    toolNames.some((item) => item.includes('console'))
  ) {
    return 'Debugging';
  }
  if (toolNames.includes('update_plan') || /\b(plan-review|architect|planning)\b/.test(text)) return 'Planning';
  if (
    toolNames.some((item) => ['read', 'grep', 'glob', 'find'].includes(item)) ||
    commandNames.some((item) => ['rg', 'grep', 'find', 'sed', 'head', 'tail', 'cat', 'ls'].includes(item))
  ) {
    return 'Exploration';
  }
  return 'Conversation';
}

function buildActivityBreakdown(activity, callCount, estimatedCost) {
  const calls = Math.max(1, toNumber(callCount, 0));
  return {
    [activity || 'Conversation']: {
      calls,
      estimated_cost_usd: estimatedCost,
      cost_estimated: estimatedCost !== null,
    },
  };
}

function oneShotEstimate({ userMessages = [], failedCommandCount = 0, reviewFixCycles = 0, toolCount = 0 }) {
  const turns = Math.max(1, userMessages.length || 1);
  const oneShot = turns <= 1 && failedCommandCount === 0 && reviewFixCycles === 0;
  return {
    value: oneShot ? 1 : 0,
    eligible: toolCount > 0 || userMessages.length > 0,
    heuristic: 'single-user-turn-no-failed-command-no-review-fix',
  };
}

function mergeActivityBreakdowns(...breakdowns) {
  const merged = {};
  for (const breakdown of breakdowns) {
    for (const [activity, value] of Object.entries(breakdown || {})) {
      const current = merged[activity] || {
        calls: 0,
        estimated_cost_usd: 0,
        cost_estimated: false,
      };
      current.calls += toNumber(value.calls, 0);
      if (typeof value.estimated_cost_usd === 'number') {
        current.estimated_cost_usd = roundCost(toNumber(current.estimated_cost_usd, 0) + value.estimated_cost_usd);
        current.cost_estimated = true;
      }
      merged[activity] = current;
    }
  }
  for (const value of Object.values(merged)) {
    if (!value.cost_estimated) value.estimated_cost_usd = null;
  }
  return merged;
}

function mergeEfficiency(...entries) {
  const merged = {};
  for (const entry of entries) {
    for (const [key, value] of Object.entries(entry || {})) {
      merged[key] = toNumber(merged[key], 0) + toNumber(value, 0);
    }
  }
  return merged;
}

function extractIsoLikeTimestamp(input, fallback = '') {
  const text = String(input || '');
  const match = text.match(/20\d{2}-\d{2}-\d{2}(?:[T_]\d{2}(?::?\d{2})?(?::?\d{2})?(?:\.\d+)?Z?)?/);
  if (!match) return fallback;
  const raw = match[0].replace('_', 'T');
  if (/^\d{4}-\d{2}-\d{2}$/.test(raw)) {
    return `${raw}T00:00:00.000Z`;
  }

  const normalized = raw
    .replace(/^(\d{4}-\d{2}-\d{2})T(\d{2})(\d{2})(\d{2})Z$/, '$1T$2:$3:$4Z')
    .replace(/^(\d{4}-\d{2}-\d{2})T(\d{2})(\d{2})Z$/, '$1T$2:$3:00Z');
  const parsed = Date.parse(normalized);
  return Number.isFinite(parsed) ? new Date(parsed).toISOString() : fallback;
}

function detectRuntime(frontmatter, body, fallback = 'claude') {
  const direct = normalizeText(frontmatter.runtime || frontmatter.provider || frontmatter.actor || '');
  if (direct.includes('codex')) return 'codex';
  if (direct.includes('claude')) return 'claude';

  const actor = normalizeText(extractFieldFromBody(body, 'runtime') || extractFieldFromBody(body, 'actor'));
  if (actor.includes('codex')) return 'codex';
  if (actor.includes('claude')) return 'claude';
  return fallback;
}

function buildCommandValidationList(commandCalls = [], validationLines = []) {
  const results = new Set();
  const matcher =
    /\b(?:npm\s+run\s+(?:test(?::\w+)?|type-check|build)|npm\s+test|pnpm\s+test|yarn\s+test|node\s+--test|bash\s+.+codex-health-check\.sh|bash\s+.+session-save\.sh|bash\s+.+vault-sync\.sh)\b/i;

  for (const command of commandCalls) {
    if (matcher.test(command)) {
      results.add(command.trim());
    }
  }

  for (const validationLine of validationLines) {
    if (validationLine) {
      results.add(validationLine.trim());
    }
  }

  return [...results];
}

function countReviewFixCycles(userMessages = []) {
  return userMessages.reduce((count, message) => {
    const normalized = normalizeText(message);
    if (
      normalized.includes('review the code changes against the base branch') ||
      normalized.includes('review output from reviewer model') ||
      normalized.includes('code review request') ||
      normalized.includes('<user_action>')
    ) {
      return count + 1;
    }
    return count;
  }, 0);
}

function isExcludedWorkspaceRoot(name) {
  if (EXCLUDED_WORKSPACE_ROOTS.has(name)) return true;
  return EXCLUDED_PATH_MARKERS.some((marker) => name.includes(marker));
}

function findReposWithAgents(workspacesRoot, maxDepth = 3) {
  const repos = [];

  function walk(currentPath, depth, workspaceRootName) {
    if (depth > maxDepth) return;
    if (!fs.existsSync(currentPath) || !fs.statSync(currentPath).isDirectory()) return;

    const baseName = path.basename(currentPath);
    if (depth === 0 && isExcludedWorkspaceRoot(baseName)) return;
    if (depth > 0 && EXCLUDED_PATH_MARKERS.some((marker) => baseName.includes(marker))) return;

    const agentsDir = path.join(currentPath, '.agents');
    if (fs.existsSync(agentsDir) && fs.statSync(agentsDir).isDirectory()) {
      repos.push({
        workspace_path: currentPath,
        workspace_root: workspaceRootName || path.basename(currentPath),
      });
      return;
    }

    if (depth === maxDepth) return;

    for (const entry of fs.readdirSync(currentPath, { withFileTypes: true })) {
      if (!entry.isDirectory()) continue;
      if (entry.name.startsWith('.git')) continue;
      walk(
        path.join(currentPath, entry.name),
        depth + 1,
        workspaceRootName || path.basename(currentPath),
      );
    }
  }

  if (!fs.existsSync(workspacesRoot)) return repos;

  for (const entry of fs.readdirSync(workspacesRoot, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    walk(path.join(workspacesRoot, entry.name), 0, entry.name);
  }

  return repos.sort((left, right) => left.workspace_path.localeCompare(right.workspace_path));
}

function listVaultProjectDirs(vaultRoot) {
  if (!vaultRoot || !fs.existsSync(vaultRoot)) return [];
  return fs
    .readdirSync(vaultRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .filter((entry) => !entry.name.startsWith('.'))
    .filter((entry) => entry.name !== '.snapshots')
    .map((entry) => ({
      project_slug: entry.name,
      vault_path: path.join(vaultRoot, entry.name),
    }))
    .sort((left, right) => left.project_slug.localeCompare(right.project_slug));
}

function runCanutoMemoryCommand(scriptPath, projectPath, functionName) {
  if (!scriptPath || !fs.existsSync(scriptPath)) return '';
  try {
    return execFileSync(
      'bash',
      ['-lc', `source "$1" && ${functionName} "$2"`, '_', scriptPath, projectPath],
      {
        encoding: 'utf8',
        stdio: ['ignore', 'pipe', 'ignore'],
      },
    ).trim();
  } catch {
    return '';
  }
}

function parseProjectSlugFromContext(projectPath) {
  const contextPath = path.join(projectPath, '.context.md');
  if (!fs.existsSync(contextPath)) return '';
  const content = readTextIfExists(contextPath);
  const match = content.match(/^[ \t]*-[ \t]*project:[ \t]*([^\n]+)/m);
  return match ? match[1].trim() : '';
}

function parseProjectSlugFromClaude(projectPath) {
  const claudePath = path.join(projectPath, 'CLAUDE.md');
  if (!fs.existsSync(claudePath)) return '';
  const content = readTextIfExists(claudePath);
  const match = content.match(/project-slug:[ \t]*([^\s]+)/);
  return match ? match[1].trim() : '';
}

function chooseWorkspaceSlug(repo, vaultSlugSet) {
  const repoName = path.basename(repo.workspace_path);
  const explicitSlug = repo.canuto_slug || repo.claude_slug || repo.context_slug;

  if (explicitSlug) {
    return {
      project_slug: explicitSlug,
      slug_source: repo.canuto_slug
        ? 'canuto_project_slug'
        : repo.claude_slug
          ? 'claude_project_slug'
          : 'context_project',
    };
  }

  if (vaultSlugSet.has(repoName)) {
    return { project_slug: repoName, slug_source: 'repo_dir' };
  }

  if (vaultSlugSet.has(repo.workspace_root)) {
    return { project_slug: repo.workspace_root, slug_source: 'workspace_root_match' };
  }

  return { project_slug: repoName, slug_source: 'repo_dir' };
}

function buildSkillCatalog(workspacePath) {
  const skillsDir = path.join(workspacePath, '.agents', 'skills');
  if (!fs.existsSync(skillsDir)) return [];

  const skillFiles = [];
  for (const entry of fs.readdirSync(skillsDir, { withFileTypes: true })) {
    if (entry.isFile() && entry.name.endsWith('.md')) {
      skillFiles.push(path.join(skillsDir, entry.name));
      continue;
    }

    if (entry.isDirectory()) {
      const skillPath = path.join(skillsDir, entry.name, 'SKILL.md');
      if (fs.existsSync(skillPath)) {
        skillFiles.push(skillPath);
      }
    }
  }

  return skillFiles
    .map((filePath) => {
      const content = readTextIfExists(filePath);
      const { data } = parseFrontmatter(content);
      const id =
        normalizeText(data.skill || data.name || path.basename(path.dirname(filePath)) || path.basename(filePath, '.md'))
          .replace(/\s+/g, '-')
          .replace(/^-+|-+$/g, '') ||
        path.basename(filePath, '.md');
      const rawTriggers = Array.isArray(data.trigger) ? data.trigger : String(data.trigger || '').split(',');
      const triggerPhrases = unique([
        data.name,
        data.skill,
        path.basename(filePath, '.md'),
        path.basename(path.dirname(filePath)),
        ...rawTriggers,
      ])
        .map((phrase) => String(phrase || '').trim())
        .filter(Boolean)
        .filter((phrase) => {
          const normalizedPhrase = normalizeText(phrase);
          return !GENERIC_SKILL_PHRASES.has(normalizedPhrase);
        });
      return {
        id,
        name: String(data.name || data.skill || path.basename(filePath, '.md')),
        path: filePath,
        trigger_phrases: triggerPhrases,
      };
    })
    .filter((skill) => skill.id !== 'skills')
    .sort((left, right) => left.id.localeCompare(right.id));
}

function scoreSkillMatch(skill, corpusText, corpusTokens) {
  let bestScore = 0;
  let matchedPhrase = '';

  for (const phrase of skill.trigger_phrases) {
    const normalizedPhrase = normalizeText(phrase);
    if (!normalizedPhrase) continue;
    const phraseTokens = normalizeTokens(phrase);
    if (phraseTokens.length === 0) continue;

    if (corpusText.includes(normalizedPhrase)) {
      const score = phraseTokens.length + 4;
      if (score > bestScore) {
        bestScore = score;
        matchedPhrase = phrase;
      }
      continue;
    }

    const overlap = phraseTokens.filter((token) => corpusTokens.has(token)).length;
    if (overlap >= Math.min(2, phraseTokens.length)) {
      const score = overlap;
      if (score > bestScore) {
        bestScore = score;
        matchedPhrase = phrase;
      }
    }
  }

  return { score: bestScore, matched_phrase: matchedPhrase };
}

function detectProbableSkillMatches(skillCatalog, corpusParts) {
  const corpusText = normalizeText(corpusParts.join(' '));
  if (!corpusText) return [];
  const corpusTokens = new Set(normalizeTokens(corpusText));

  return skillCatalog
    .map((skill) => ({
      skill_id: skill.id,
      ...scoreSkillMatch(skill, corpusText, corpusTokens),
    }))
    .filter((match) => match.score >= 4)
    .sort((left, right) => right.score - left.score || left.skill_id.localeCompare(right.skill_id))
    .slice(0, 5);
}

function extractSkillReadsFromCommand(command, catalogByPath) {
  const reads = [];
  const matches = String(command || '').match(/([/~A-Za-z0-9._-]+\/\.agents\/skills\/[A-Za-z0-9._/-]+(?:\/SKILL\.md|\.md))/g) || [];

  for (const rawPath of matches) {
    const expandedPath = rawPath.startsWith('~/') ? path.join(os.homedir(), rawPath.slice(2)) : rawPath;
    const normalizedPath = path.resolve(expandedPath);
    const skill = catalogByPath.get(normalizedPath);
    if (skill) {
      reads.push(skill.id);
      continue;
    }

    const fallback = normalizedPath.match(/\/\.agents\/skills\/([^/]+)(?:\/SKILL\.md|\.md)$/);
    if (fallback) {
      reads.push(fallback[1]);
    }
  }

  return unique(reads);
}

function detectSkillBreakages(text) {
  const breakages = new Set();
  const patterns = [
    {
      type: 'skill-file-missing',
      regex:
        /(?:\.agents\/skills\/[\w-]+(?:\/(?:SKILL\.md|[\w-]+\.md)|\.md).*(?:ENOENT|No such file or directory)|(?:ENOENT|No such file or directory).*\.agents\/skills\/[\w-]+(?:\/(?:SKILL\.md|[\w-]+\.md)|\.md))/i,
    },
    {
      type: 'skill-parse-failure',
      regex:
        /(?:(?:Failed to parse|YAMLException|Unexpected token|SyntaxError).*\.agents\/skills\/|\.agents\/skills\/.*(?:YAMLException|SyntaxError|Unexpected token|Failed to parse))/i,
    },
    {
      type: 'skill-not-found',
      regex:
        /(?:Skill not found:\s*['"]?[\w-]+|Unknown skill:?\s*['"]?[\w-]+|Could not resolve skill:?\s*['"]?[\w-]+|Skill ['"]?[\w-]+['"]? does not exist)/i,
    },
    {
      type: 'skill-read-failure',
      regex:
        /(?:(?:cannot read|unable to read|permission denied).*\.agents\/skills\/[\w-]+|\.agents\/skills\/[\w-]+.*(?:cannot read|unable to read|permission denied))/i,
    },
  ];

  for (const line of String(text || '').split(/\r?\n/)) {
    for (const pattern of patterns) {
      if (pattern.regex.test(line)) {
        breakages.add(pattern.type);
      }
    }
  }

  return [...breakages];
}

function lineHasSyncSignal(line, markerRe, contextRe) {
  const text = String(line || '').replace(SYNC_MARKDOWN_FILE_RE, '');
  if (!markerRe.test(text)) return false;
  if (SYNC_TEST_REFERENCE_RE.test(text)) return false;
  return contextRe.test(text);
}

function textHasPendingSyncSignal(text) {
  return String(text || '')
    .split(/\r?\n/)
    .some((line) => lineHasSyncSignal(line, PENDING_SYNC_MARKER_RE, PENDING_SYNC_CONTEXT_RE));
}

function textHasOfflineSyncSignal(text) {
  return String(text || '')
    .split(/\r?\n/)
    .some((line) => {
      const text = String(line || '').replace(SYNC_MARKDOWN_FILE_RE, '');
      if (SYNC_TEST_REFERENCE_RE.test(text)) return false;
      return OFFLINE_SYNC_HEADING_RE.test(text) || lineHasSyncSignal(text, OFFLINE_SYNC_MARKER_RE, OFFLINE_SYNC_CONTEXT_RE);
    });
}

function frontmatterHasOfflineSyncSignal(data) {
  const frontmatterEvent = String(data.event || data.type || '').toUpperCase();
  const frontmatterTags = Array.isArray(data.tags) ? data.tags : data.tags ? [data.tags] : [];

  return (
    frontmatterEvent === 'OFFLINE_SYNC' ||
    frontmatterEvent === 'OFFLINE-SYNC' ||
    frontmatterTags.some((tag) => {
      const normalizedTag = String(tag || '').toLowerCase();
      return normalizedTag === 'offline-sync' || normalizedTag === 'offline_sync';
    })
  );
}

function auditFilenameHasOfflineSyncSignal(filePath, data) {
  if (String(data.type || '').toLowerCase() !== 'audit-event') return false;
  return /offline[-_]sync/i.test(path.basename(filePath));
}

function auditFileHasOfflineSyncSignal(filePath, data, body) {
  return (
    frontmatterHasOfflineSyncSignal(data) ||
    auditFilenameHasOfflineSyncSignal(filePath, data) ||
    textHasOfflineSyncSignal(body)
  );
}

function cleanUserMessage(text) {
  const raw = String(text || '');
  if (
    raw.includes('AGENTS.md instructions for') ||
    raw.includes('<INSTRUCTIONS>') ||
    raw.includes('<environment_context>') ||
    raw.includes('<system_instruction>') ||
    raw.includes('## MCP Tools Available')
  ) {
    return '';
  }

  const sanitized = String(text || '')
    .replace(/^# AGENTS\.md instructions.*$/m, '')
    .replace(/<environment_context>[\s\S]*?<\/environment_context>/g, '')
    .replace(/<system_instruction>[\s\S]*?<\/system_instruction>/g, '')
    .replace(/## Skills[\s\S]*?## /g, '## ')
    .replace(/\s+/g, ' ')
    .trim();

  if (!sanitized) return '';
  if (sanitized.includes('AGENTS.md instructions')) return '';
  return sanitized;
}

function loadSessionIndexThreadName(sessionId) {
  if (!sessionId) return '';
  const indexPath = path.join(os.homedir(), '.codex', 'session_index.jsonl');
  if (!fs.existsSync(indexPath)) return '';

  const lines = readTextIfExists(indexPath).split(/\r?\n/);
  for (const line of lines) {
    if (!line.trim()) continue;
    try {
      const record = JSON.parse(line);
      if (record.id === sessionId) {
        return String(record.thread_name || '').trim();
      }
    } catch {
      // ignore malformed records
    }
  }

  return '';
}

function parseCodexLogMeta(filePath) {
  const firstLine = readTextIfExists(filePath).split(/\r?\n/, 1)[0];
  if (!firstLine) return null;
  try {
    const record = JSON.parse(firstLine);
    if (record.type !== 'session_meta') return null;
    return {
      file_path: filePath,
      session_id: record.payload?.id || '',
      timestamp: extractIsoLikeTimestamp(record.payload?.timestamp || '') || '',
      cwd: record.payload?.cwd || '',
    };
  } catch {
    return null;
  }
}

function parseCodexLogRecord(meta, projectKey, skillCatalog, pricingIndex = null) {
  const catalogByPath = new Map(skillCatalog.map((skill) => [path.resolve(skill.path), skill]));
  const raw = readTextIfExists(meta.file_path);
  const lines = raw.split(/\r?\n/);
  const userMessages = [];
  const commandCalls = [];
  const commandOutputs = [];
  const toolCounts = {};
  const shellCounts = {};
  const mcpCounts = {};
  const shellCommands = [];
  const tools = [];
  const seenExecCallIds = new Set();
  const skillReads = new Set();
  const skillBreakages = new Set();
  let model = '';
  let tokenUsage = normalizeTokenUsage({}, 'codex');
  let failedCommandCount = 0;
  let taskStartedCount = 0;
  let pendingSync = false;
  let offlineSync = false;

  for (const line of lines) {
    if (!line.trim()) continue;
    let record;
    try {
      record = JSON.parse(line);
    } catch {
      continue;
    }

    if (record.type === 'response_item') {
      const payload = record.payload || {};
      if (payload.type === 'message' && payload.role === 'user') {
        const chunks = (payload.content || [])
          .map((chunk) => chunk.text || chunk.input_text || '')
          .map(cleanUserMessage)
          .filter(Boolean);
        if (chunks.length > 0) {
          userMessages.push(chunks.join(' '));
        }
      }

      if (payload.type === 'function_call') {
        const normalizedTool = normalizeToolName(payload.name);
        if (normalizedTool) {
          incrementCounter(toolCounts, normalizedTool);
          tools.push(normalizedTool);
        }
        const mcpServer = extractMcpServerName(payload.name);
        if (mcpServer) incrementCounter(mcpCounts, mcpServer);
      }

      if (payload.type === 'function_call' && payload.name === 'exec_command') {
        try {
          const args = JSON.parse(payload.arguments || '{}');
          const command = String(args.cmd || '').trim();
          if (command) {
            commandCalls.push(command);
            shellCommands.push(command);
            incrementCounter(shellCounts, shellCommandName(command));
            if (payload.call_id) seenExecCallIds.add(payload.call_id);
            for (const skillId of extractSkillReadsFromCommand(command, catalogByPath)) {
              skillReads.add(skillId);
            }
          }
        } catch {
          // ignore malformed args
        }
      }

      if (payload.type === 'function_call_output') {
        const output = String(payload.output || '');
        if (output) {
          commandOutputs.push(output);
          for (const message of detectSkillBreakages(output)) {
            skillBreakages.add(message);
          }
          if (textHasPendingSyncSignal(output)) pendingSync = true;
          if (textHasOfflineSyncSignal(output)) offlineSync = true;
        }
      }
    }

    if (record.type === 'turn_context') {
      model = firstNonEmpty(record.payload?.model, record.payload?.collaboration_mode?.settings?.model, model, '');
    }

    if (record.type === 'event_msg' && record.payload?.type === 'task_started') {
      taskStartedCount += 1;
    }

    if (record.type === 'event_msg' && record.payload?.type === 'token_count' && record.payload?.info?.total_token_usage) {
      tokenUsage = normalizeTokenUsage(record.payload.info.total_token_usage, 'codex');
    }

    if (record.type === 'event_msg' && record.payload?.type === 'exec_command_end') {
      const payload = record.payload || {};
      const command = Array.isArray(payload.command) ? payload.command.join(' ') : '';
      if (command) {
        commandCalls.push(command);
        if (!payload.call_id || !seenExecCallIds.has(payload.call_id)) {
          shellCommands.push(command);
          incrementCounter(shellCounts, shellCommandName(command));
        }
        for (const skillId of extractSkillReadsFromCommand(command, catalogByPath)) {
          skillReads.add(skillId);
        }
      }
      for (const parsed of payload.parsed_cmd || []) {
        const parsedCommand = String(parsed.cmd || parsed.name || '').trim();
        if (parsedCommand && (!payload.call_id || !seenExecCallIds.has(payload.call_id))) {
          shellCommands.push(parsedCommand);
          incrementCounter(shellCounts, parsed.name || shellCommandName(parsedCommand));
        }
      }
      if (toNumber(payload.exit_code, 0) !== 0 || payload.status === 'failed') {
        failedCommandCount += 1;
      }

      const aggregatedOutput = String(payload.aggregated_output || '');
      if (aggregatedOutput) {
        commandOutputs.push(aggregatedOutput);
        for (const message of detectSkillBreakages(aggregatedOutput)) {
          skillBreakages.add(message);
        }
        if (textHasPendingSyncSignal(aggregatedOutput)) pendingSync = true;
        if (textHasOfflineSyncSignal(aggregatedOutput)) offlineSync = true;
      }
    }
  }

  const threadName = loadSessionIndexThreadName(meta.session_id);
  const validation = buildCommandValidationList(commandCalls, []);
  const summary = unique([threadName, userMessages[0]].filter(Boolean));
  const probableSkillMatches = detectProbableSkillMatches(skillCatalog, [
    threadName,
    ...userMessages,
  ]);
  const tokenCost = estimateTokenCost({ model, tokenUsage, pricingIndex });
  const toolCallCount = Object.values(toolCounts).reduce((sum, count) => sum + count, 0);
  const activity = classifyActivity({
    tools,
    shellCommands,
    failedCommandCount,
    userMessages,
  });
  const reviewFixCycles = countReviewFixCycles(userMessages);

  return {
    project_key: projectKey,
    session_id: meta.session_id || `codex-${path.basename(meta.file_path, '.jsonl')}`,
    runtime: 'codex',
    timestamp: meta.timestamp || new Date(0).toISOString(),
    source_kind: 'codex_log',
    source_path: meta.file_path,
    source_log_path: meta.file_path,
    vault_scope: 'none',
    captured_to_vault: false,
    fallback_used: false,
    health_reason: 'unknown',
    offline_sync: offlineSync,
    pending_sync: pendingSync,
    review_fix_cycles: reviewFixCycles,
    tasks_completed: 0,
    tests_run: validation.length,
    pending_count: 0,
    summary,
    what_was_done: [],
    validation,
    learnings: [],
    skill_reads: [...skillReads],
    skill_breakages: [...skillBreakages],
    probable_skill_matches: probableSkillMatches,
    evidence_refs: unique([meta.file_path]),
    provider: 'openai',
    model,
    token_usage: tokenUsage,
    estimated_cost_usd: tokenCost.estimated_cost_usd,
    cost_source: tokenCost.cost_source,
    missing_pricing: tokenCost.missing_pricing,
    tool_calls: counterToRankedList(toolCounts),
    shell_commands: counterToRankedList(shellCounts),
    mcp_calls: counterToRankedList(mcpCounts),
    activity_breakdown: buildActivityBreakdown(activity, toolCallCount + shellCommands.length, tokenCost.estimated_cost_usd),
    one_shot_estimate: oneShotEstimate({
      userMessages,
      failedCommandCount,
      reviewFixCycles,
      toolCount: toolCallCount,
    }),
    efficiency: {
      failed_command_count: failedCommandCount,
      total_shell_command_count: shellCommands.length,
      task_started_count: taskStartedCount,
    },
    _user_messages: userMessages,
  };
}

function parseVaultSessionFile(filePath, projectKey, vaultScope) {
  const markdown = readTextIfExists(filePath);
  if (!markdown) return null;
  const { data, body } = parseFrontmatter(markdown);
  const sections = parseSessionSections(body);
  const pending = unique([...sections.pending, ...extractChecklistItems(body)]);
  const timestamp =
    extractIsoLikeTimestamp(data.date || data.generated_by || '') ||
    extractIsoLikeTimestamp(path.basename(filePath)) ||
    new Date(0).toISOString();
  const sourceLog = String(data.source_log || extractFieldFromBody(body, 'source_log') || '').trim();

  return {
    project_key: projectKey,
    session_id:
      String(data.session_id || data.session || '').trim() ||
      `${vaultScope}-session-${path.basename(filePath, '.md')}`,
    runtime: detectRuntime(data, body),
    timestamp,
    source_kind: vaultScope === 'global' ? 'global_vault' : 'local_vault',
    source_path: filePath,
    source_log_path: sourceLog || '',
    vault_scope: vaultScope,
    captured_to_vault: true,
    fallback_used: toBoolean(data.fallback_used, toBoolean(extractFieldFromBody(body, 'fallback_used'), false)),
    health_reason: String(data.health_reason || extractFieldFromBody(body, 'health_reason') || 'healthy'),
    offline_sync: textHasOfflineSyncSignal(body),
    pending_sync: pending.length > 0,
    review_fix_cycles: toNumber(data.review_fix_cycles, toNumber(extractFieldFromBody(body, 'review_fix_cycles'), 0)),
    tasks_completed: sections.whatWasDone.length,
    tests_run: sections.validation.length,
    pending_count: pending.length,
    summary: sections.summary,
    what_was_done: sections.whatWasDone,
    validation: sections.validation,
    learnings: sections.learnings,
    skill_reads: [],
    skill_breakages: detectSkillBreakages(body),
    probable_skill_matches: [],
    evidence_refs: [filePath],
  };
}

function parseVaultMetricsFile(filePath, projectKey, vaultScope) {
  const markdown = readTextIfExists(filePath);
  if (!markdown) return null;
  const { data, body } = parseFrontmatter(markdown);
  const pendingCount = toNumber(data.pending_count, toNumber(extractFieldFromBody(body, 'pending_count'), 0));
  const timestamp =
    extractIsoLikeTimestamp(data.date || '') ||
    extractIsoLikeTimestamp(path.basename(filePath)) ||
    new Date(0).toISOString();

  return {
    project_key: projectKey,
    session_id:
      String(data.session_id || '').trim() ||
      `${vaultScope}-metrics-${path.basename(filePath, '.md')}`,
    runtime: detectRuntime(data, body, 'claude'),
    timestamp,
    source_kind: 'metrics',
    source_path: filePath,
    source_log_path: '',
    vault_scope: vaultScope,
    captured_to_vault: true,
    fallback_used: toBoolean(data.fallback_used, false),
    health_reason: String(data.health_reason || 'healthy'),
    offline_sync: textHasOfflineSyncSignal(body),
    pending_sync: pendingCount > 0,
    review_fix_cycles: toNumber(data.reviews_count, 0),
    tasks_completed: toNumber(data.tasks_completed, toNumber(extractFieldFromBody(body, 'tasks_completed'), 0)),
    tests_run: toNumber(data.tests_run, toNumber(extractFieldFromBody(body, 'tests_run'), 0)),
    pending_count: pendingCount,
    summary: [],
    what_was_done: [],
    validation: [],
    learnings: [],
    skill_reads: [],
    skill_breakages: [],
    probable_skill_matches: [],
    evidence_refs: [filePath],
  };
}

function parseVaultAuditFile(filePath, projectKey, vaultScope) {
  const markdown = readTextIfExists(filePath);
  if (!markdown) return null;
  const { data, body } = parseFrontmatter(markdown);
  const timestamp =
    extractIsoLikeTimestamp(data.date || '') ||
    extractIsoLikeTimestamp(path.basename(filePath)) ||
    new Date(0).toISOString();
  const sourceLog = String(extractFieldFromBody(body, 'source_log') || '').trim();
  const healthReason = String(extractFieldFromBody(body, 'health_reason') || data.health_reason || 'healthy');

  return {
    project_key: projectKey,
    session_id:
      String(data.session || data.session_id || '').trim() ||
      `${vaultScope}-audit-${path.basename(filePath, '.md')}`,
    runtime: detectRuntime(data, body),
    timestamp,
    source_kind: 'audit',
    source_path: filePath,
    source_log_path: sourceLog || '',
    vault_scope: vaultScope,
    captured_to_vault: true,
    fallback_used: toBoolean(extractFieldFromBody(body, 'fallback_used'), false),
    health_reason: healthReason || 'healthy',
    offline_sync: auditFileHasOfflineSyncSignal(filePath, data, body),
    pending_sync: false,
    review_fix_cycles: toNumber(extractFieldFromBody(body, 'review_fix_cycles'), 0),
    tasks_completed: 0,
    tests_run: 0,
    pending_count: 0,
    summary: [],
    what_was_done: [],
    validation: [],
    learnings: [],
    skill_reads: [],
    skill_breakages: detectSkillBreakages(body),
    probable_skill_matches: [],
    evidence_refs: [filePath],
  };
}

function listMarkdownFiles(dirPath) {
  if (!dirPath || !fs.existsSync(dirPath)) return [];
  return fs
    .readdirSync(dirPath, { withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.endsWith('.md'))
    .map((entry) => path.join(dirPath, entry.name))
    .sort();
}

function sessionMergeKey(record) {
  if (record.session_id) return `session:${record.session_id}`;
  if (record.source_log_path) return `source:${record.source_log_path}`;
  return `stamp:${record.project_key}:${record.runtime}:${record.timestamp}`;
}

function richnessScore(record) {
  return (
    (record.summary || []).length +
    (record.what_was_done || []).length +
    (record.validation || []).length +
    (record.learnings || []).length +
    (record.skill_reads || []).length +
    (record.skill_breakages || []).length
  );
}

function choosePrimaryRecord(left, right) {
  const leftPriority = SOURCE_PRIORITY[left.source_kind] || 0;
  const rightPriority = SOURCE_PRIORITY[right.source_kind] || 0;
  if (leftPriority !== rightPriority) {
    return leftPriority > rightPriority ? left : right;
  }

  const leftRichness = richnessScore(left);
  const rightRichness = richnessScore(right);
  if (leftRichness !== rightRichness) {
    return leftRichness > rightRichness ? left : right;
  }

  return left;
}

function mergeRecords(left, right) {
  const primary = choosePrimaryRecord(left, right);
  const secondary = primary === left ? right : left;
  const merged = { ...primary };

  merged.source_path = primary.source_path;
  merged.source_kind = primary.source_kind;
  merged.source_log_path = firstNonEmpty(primary.source_log_path, secondary.source_log_path, '');
  merged.vault_scope = primary.vault_scope !== 'none' ? primary.vault_scope : secondary.vault_scope;
  merged.captured_to_vault = Boolean(left.captured_to_vault || right.captured_to_vault);
  merged.fallback_used = Boolean(left.fallback_used || right.fallback_used);
  merged.health_reason = firstNonEmpty(
    primary.health_reason && primary.health_reason !== 'unknown' ? primary.health_reason : '',
    secondary.health_reason && secondary.health_reason !== 'unknown' ? secondary.health_reason : '',
    primary.health_reason,
    secondary.health_reason,
    'unknown',
  );
  merged.offline_sync = Boolean(left.offline_sync || right.offline_sync);
  merged.pending_sync = Boolean(left.pending_sync || right.pending_sync);
  merged.review_fix_cycles = Math.max(left.review_fix_cycles || 0, right.review_fix_cycles || 0);
  merged.tasks_completed = Math.max(left.tasks_completed || 0, right.tasks_completed || 0);
  merged.tests_run = Math.max(left.tests_run || 0, right.tests_run || 0);
  merged.pending_count = Math.max(left.pending_count || 0, right.pending_count || 0);
  merged.summary = unique([...(left.summary || []), ...(right.summary || [])]);
  merged.what_was_done = unique([...(left.what_was_done || []), ...(right.what_was_done || [])]);
  merged.validation = unique([...(left.validation || []), ...(right.validation || [])]);
  merged.learnings = unique([...(left.learnings || []), ...(right.learnings || [])]);
  merged.skill_reads = unique([...(left.skill_reads || []), ...(right.skill_reads || [])]);
  merged.skill_breakages = unique([...(left.skill_breakages || []), ...(right.skill_breakages || [])]);
  merged.probable_skill_matches = uniqueProbableMatches([
    ...(left.probable_skill_matches || []),
    ...(right.probable_skill_matches || []),
  ]);
  merged.evidence_refs = unique([...(left.evidence_refs || []), ...(right.evidence_refs || [])]);
  merged.provider = firstNonEmpty(primary.provider, secondary.provider, '');
  merged.model = firstNonEmpty(primary.model, secondary.model, '');
  merged.token_usage = addTokenUsage(left.token_usage, right.token_usage);
  const leftCost = typeof left.estimated_cost_usd === 'number' ? left.estimated_cost_usd : null;
  const rightCost = typeof right.estimated_cost_usd === 'number' ? right.estimated_cost_usd : null;
  merged.estimated_cost_usd =
    leftCost !== null && rightCost !== null
      ? roundCost(leftCost + rightCost)
      : leftCost !== null
        ? leftCost
        : rightCost;
  merged.cost_source = unique([left.cost_source, right.cost_source]).join(', ');
  merged.missing_pricing = unique([...(left.missing_pricing || []), ...(right.missing_pricing || [])]);
  merged.tool_calls = mergeRankedLists(left.tool_calls, right.tool_calls);
  merged.shell_commands = mergeRankedLists(left.shell_commands, right.shell_commands);
  merged.mcp_calls = mergeRankedLists(left.mcp_calls, right.mcp_calls);
  merged.activity_breakdown = mergeActivityBreakdowns(left.activity_breakdown, right.activity_breakdown);
  merged.one_shot_estimate = primary.one_shot_estimate || secondary.one_shot_estimate;
  merged.efficiency = mergeEfficiency(left.efficiency, right.efficiency);

  return merged;
}

function uniqueProbableMatches(items) {
  const bestBySkill = new Map();
  for (const item of items) {
    if (!item || !item.skill_id) continue;
    const existing = bestBySkill.get(item.skill_id);
    if (!existing || item.score > existing.score) {
      bestBySkill.set(item.skill_id, item);
    }
  }
  return [...bestBySkill.values()].sort((left, right) => right.score - left.score || left.skill_id.localeCompare(right.skill_id));
}

function sortSessionsByTimestampDesc(items) {
  return [...items].sort((left, right) => {
    const leftTs = Date.parse(left.timestamp || '');
    const rightTs = Date.parse(right.timestamp || '');
    if (Number.isFinite(leftTs) && Number.isFinite(rightTs) && leftTs !== rightTs) {
      return rightTs - leftTs;
    }
    return String(right.source_path).localeCompare(String(left.source_path));
  });
}

function matchesWorkspacePath(cwd, workspacePath) {
  if (!cwd || !workspacePath) return false;
  const resolvedCwd = path.resolve(cwd);
  const resolvedWorkspace = path.resolve(workspacePath);
  return resolvedCwd === resolvedWorkspace || resolvedCwd.startsWith(`${resolvedWorkspace}${path.sep}`);
}

function mapCodexLogToProject(meta, workspaceProjects) {
  const candidates = workspaceProjects
    .filter((project) => project.workspace_path && matchesWorkspacePath(meta.cwd, project.workspace_path))
    .sort((left, right) => right.workspace_path.length - left.workspace_path.length);
  return candidates[0] || null;
}

function collectCodexLogMetas(codexLogRoots) {
  const results = [];

  function walk(currentPath) {
    if (!fs.existsSync(currentPath)) return;
    const stat = fs.statSync(currentPath);
    if (stat.isFile()) {
      if (currentPath.endsWith('.jsonl')) {
        const meta = parseCodexLogMeta(currentPath);
        if (meta) results.push(meta);
      }
      return;
    }

    for (const entry of fs.readdirSync(currentPath, { withFileTypes: true })) {
      const nextPath = path.join(currentPath, entry.name);
      if (entry.isDirectory()) {
        walk(nextPath);
      } else if (entry.isFile() && entry.name.endsWith('.jsonl')) {
        const meta = parseCodexLogMeta(nextPath);
        if (meta) results.push(meta);
      }
    }
  }

  for (const root of codexLogRoots) {
    walk(root);
  }

  return sortSessionsByTimestampDesc(results);
}

function parseClaudeMessageContent(content) {
  if (!Array.isArray(content)) return [];
  return content;
}

function parseClaudeProjectLogRecord(filePath, projectKey, pricingIndex, telemetryBySession = new Map()) {
  const lines = readTextIfExists(filePath).split(/\r?\n/);
  const userMessages = [];
  const toolCounts = {};
  const shellCounts = {};
  const mcpCounts = {};
  const shellCommands = [];
  const tools = [];
  let sessionId = '';
  let timestamp = '';
  let cwd = '';
  let model = '';
  let tokenUsage = normalizeTokenUsage({}, 'claude');
  let failedCommandCount = 0;

  for (const line of lines) {
    if (!line.trim()) continue;
    let record;
    try {
      record = JSON.parse(line);
    } catch {
      continue;
    }

    sessionId = firstNonEmpty(sessionId, record.sessionId, record.session_id, '');
    timestamp = firstNonEmpty(timestamp, record.timestamp, '');
    cwd = firstNonEmpty(cwd, record.cwd, '');

    if (record.type === 'user' && record.message?.content) {
      const rawContent = record.message.content;
      const text = Array.isArray(rawContent)
        ? rawContent.map((chunk) => chunk.text || '').filter(Boolean).join(' ')
        : String(record.message.content || '');
      if (text) userMessages.push(cleanUserMessage(text));
    }

    if (record.type === 'assistant' && record.message) {
      model = firstNonEmpty(record.message.model, model, '');
      if (record.message.usage) {
        tokenUsage = addTokenUsage(tokenUsage, normalizeTokenUsage(record.message.usage, 'claude'));
      }

      for (const chunk of parseClaudeMessageContent(record.message.content)) {
        if (chunk.type !== 'tool_use') continue;
        const normalizedTool = normalizeToolName(chunk.name);
        if (normalizedTool) {
          incrementCounter(toolCounts, normalizedTool);
          tools.push(normalizedTool);
        }
        const mcpServer = extractMcpServerName(chunk.name);
        if (mcpServer) incrementCounter(mcpCounts, mcpServer);
        const command = String(chunk.input?.command || chunk.input?.cmd || '').trim();
        if (command) {
          shellCommands.push(command);
          incrementCounter(shellCounts, shellCommandName(command));
        }
      }
    }

    if (record.toolUseResult && record.toolUseResult.exitCode && toNumber(record.toolUseResult.exitCode, 0) !== 0) {
      failedCommandCount += 1;
    }
  }

  if (!sessionId) sessionId = `claude-${path.basename(filePath, '.jsonl')}`;
  const telemetry = telemetryBySession.get(sessionId) || null;
  const tokenCost = estimateTokenCost({
    model,
    tokenUsage,
    pricingIndex,
    overrideCost: telemetry?.cost_usd,
    overrideSource: telemetry?.cost_usd !== undefined ? 'claude-telemetry' : '',
  });
  const toolCallCount = Object.values(toolCounts).reduce((sum, count) => sum + count, 0);
  const reviewFixCycles = countReviewFixCycles(userMessages);
  const activity = classifyActivity({
    tools,
    shellCommands,
    failedCommandCount,
    userMessages,
  });

  return {
    project_key: projectKey,
    session_id: sessionId,
    runtime: 'claude',
    timestamp: extractIsoLikeTimestamp(timestamp) || new Date(0).toISOString(),
    source_kind: 'claude_project_log',
    source_path: filePath,
    source_log_path: filePath,
    vault_scope: 'none',
    captured_to_vault: false,
    fallback_used: false,
    health_reason: 'unknown',
    offline_sync: false,
    pending_sync: false,
    review_fix_cycles: reviewFixCycles,
    tasks_completed: 0,
    tests_run: 0,
    pending_count: 0,
    summary: userMessages.slice(0, 1),
    what_was_done: [],
    validation: [],
    learnings: [],
    skill_reads: [],
    skill_breakages: [],
    probable_skill_matches: [],
    evidence_refs: unique([filePath, ...(telemetry?.evidence_refs || [])]),
    provider: 'anthropic',
    model,
    token_usage: tokenUsage,
    estimated_cost_usd: tokenCost.estimated_cost_usd,
    cost_source: tokenCost.cost_source,
    missing_pricing: tokenCost.missing_pricing,
    tool_calls: counterToRankedList(toolCounts),
    shell_commands: counterToRankedList(shellCounts),
    mcp_calls: counterToRankedList(mcpCounts),
    activity_breakdown: buildActivityBreakdown(activity, toolCallCount + shellCommands.length, tokenCost.estimated_cost_usd),
    one_shot_estimate: oneShotEstimate({
      userMessages,
      failedCommandCount,
      reviewFixCycles,
      toolCount: toolCallCount,
    }),
    efficiency: {
      failed_command_count: failedCommandCount,
      total_shell_command_count: shellCommands.length,
      api_errors: telemetry?.api_errors || 0,
      prompt_too_long_errors: telemetry?.prompt_too_long_errors || 0,
      compact_failures: telemetry?.compact_failures || 0,
      deferred_tool_tokens: telemetry?.deferred_tool_tokens || 0,
    },
    _user_messages: userMessages,
    _cwd: cwd,
  };
}

function collectClaudeProjectRecords(claudeProjectsRoot, workspaceProjects, pricingIndex, telemetryBySession) {
  const health = {
    path: claudeProjectsRoot || '',
    available: false,
    files_seen: 0,
    sessions_mapped: 0,
    skipped_unmapped: 0,
    error: '',
  };
  const records = [];

  if (!claudeProjectsRoot || !fs.existsSync(claudeProjectsRoot)) {
    health.error = claudeProjectsRoot ? 'not-found' : 'not-configured';
    return { records, health };
  }

  function walk(currentPath) {
    const stat = fs.statSync(currentPath);
    if (stat.isFile()) {
      if (!currentPath.endsWith('.jsonl')) return;
      health.files_seen += 1;
      const record = parseClaudeProjectLogRecord(currentPath, '', pricingIndex, telemetryBySession);
      const project = mapCodexLogToProject({ cwd: record._cwd || '' }, workspaceProjects);
      if (!project) {
        health.skipped_unmapped += 1;
        return;
      }
      records.push({ ...record, project_key: project.project_key });
      health.sessions_mapped += 1;
      return;
    }

    for (const entry of fs.readdirSync(currentPath, { withFileTypes: true })) {
      const nextPath = path.join(currentPath, entry.name);
      if (entry.isDirectory()) {
        walk(nextPath);
      } else if (entry.isFile() && entry.name.endsWith('.jsonl')) {
        walk(nextPath);
      }
    }
  }

  try {
    walk(claudeProjectsRoot);
    health.available = true;
  } catch (error) {
    health.error = error && error.message ? error.message : String(error);
  }

  return { records: sortSessionsByTimestampDesc(records), health };
}

function parseMetadataJson(value) {
  if (!value) return {};
  if (typeof value === 'object') return value;
  try {
    return JSON.parse(String(value));
  } catch {
    return {};
  }
}

function collectClaudeTelemetry(claudeTelemetryRoot) {
  const bySession = new Map();
  const health = {
    path: claudeTelemetryRoot || '',
    available: false,
    files_seen: 0,
    events_seen: 0,
    sessions_seen: 0,
    error: '',
  };

  if (!claudeTelemetryRoot || !fs.existsSync(claudeTelemetryRoot)) {
    health.error = claudeTelemetryRoot ? 'not-found' : 'not-configured';
    return { bySession, health };
  }

  try {
    for (const fileName of fs.readdirSync(claudeTelemetryRoot)) {
      if (!fileName.endsWith('.json')) continue;
      const filePath = path.join(claudeTelemetryRoot, fileName);
      if (!fs.statSync(filePath).isFile()) continue;
      health.files_seen += 1;

      for (const line of readTextIfExists(filePath).split(/\r?\n/)) {
        if (!line.trim()) continue;
        let record;
        try {
          record = JSON.parse(line);
        } catch {
          continue;
        }
        const data = record.event_data || {};
        const eventName = String(data.event_name || '');
        const sessionId = String(data.session_id || '').trim();
        if (!sessionId) continue;
        const metadata = parseMetadataJson(data.additional_metadata);
        const current = bySession.get(sessionId) || {
          session_id: sessionId,
          cost_usd: 0,
          api_successes: 0,
          api_errors: 0,
          prompt_too_long_errors: 0,
          compact_failures: 0,
          deferred_tool_tokens: 0,
          tool_counts: {},
          evidence_refs: [],
        };

        health.events_seen += 1;
        current.evidence_refs.push(filePath);

        if (eventName === 'tengu_api_success') {
          current.api_successes += 1;
          current.cost_usd += toNumber(metadata.costUSD, 0);
        } else if (eventName === 'tengu_api_error') {
          current.api_errors += 1;
          if (metadata.errorType === 'prompt_too_long' || normalizeText(metadata.error).includes('prompt too long')) {
            current.prompt_too_long_errors += 1;
          }
        } else if (eventName === 'tengu_compact_failed') {
          current.compact_failures += 1;
          if (metadata.reason === 'prompt_too_long') current.prompt_too_long_errors += 1;
        } else if (eventName === 'tengu_tool_use_success' || eventName === 'tengu_tool_use_progress') {
          incrementCounter(current.tool_counts, metadata.toolName);
        } else if (eventName === 'tengu_tool_search_mode_decision') {
          current.deferred_tool_tokens += toNumber(metadata.deferredToolTokens, 0);
        }

        current.cost_usd = roundCost(current.cost_usd) || 0;
        current.evidence_refs = unique(current.evidence_refs);
        bySession.set(sessionId, current);
      }
    }
    health.available = true;
    health.sessions_seen = bySession.size;
  } catch (error) {
    health.error = error && error.message ? error.message : String(error);
  }

  return { bySession, health };
}

function buildInventory({ workspacesRoot, vaultRoot }) {
  const workspaceRepos = findReposWithAgents(workspacesRoot);
  const vaultProjects = listVaultProjectDirs(vaultRoot);
  const vaultSlugSet = new Set(vaultProjects.map((project) => project.project_slug));
  const excluded = [];

  const workspaceEntries = workspaceRepos.map((repo) => {
    const memoryScriptPath = path.join(repo.workspace_path, '.agents', 'tools', 'canuto-memory.sh');
    const canutoSlug = runCanutoMemoryCommand(memoryScriptPath, repo.workspace_path, 'canuto_project_slug');
    const canutoBackendRaw = runCanutoMemoryCommand(memoryScriptPath, repo.workspace_path, 'canuto_resolve_memory_backend');
    const localVaultPath = fs.existsSync(path.join(repo.workspace_path, '.agents', 'vault'))
      ? path.join(repo.workspace_path, '.agents', 'vault')
      : '';

    const resolved = chooseWorkspaceSlug(
      {
        ...repo,
        canuto_slug: canutoSlug,
        claude_slug: parseProjectSlugFromClaude(repo.workspace_path),
        context_slug: parseProjectSlugFromContext(repo.workspace_path),
      },
      vaultSlugSet,
    );

    const globalVaultPathCandidate = vaultSlugSet.has(resolved.project_slug)
      ? path.join(vaultRoot, resolved.project_slug)
      : '';

    let backendKind = 'missing';
    let backendPath = '';
    if (canutoBackendRaw) {
      const [rawKind, rawPath] = canutoBackendRaw.split('\t');
      if (rawKind === 'global' || rawKind === 'local') {
        backendKind = rawKind;
        backendPath = rawPath || '';
      }
    }

    if (backendKind === 'missing') {
      if (localVaultPath) {
        backendKind = 'local';
        backendPath = localVaultPath;
      } else if (globalVaultPathCandidate) {
        backendKind = 'global';
        backendPath = globalVaultPathCandidate;
      }
    }

    const hasSessionSave = fs.existsSync(path.join(repo.workspace_path, '.agents', 'hooks', 'session-save.sh'));
    const hasHealthCheck = fs.existsSync(path.join(repo.workspace_path, '.agents', 'tools', 'codex-health-check.sh'));

    return {
      project_slug: resolved.project_slug,
      slug_source: resolved.slug_source,
      workspace_path: repo.workspace_path,
      workspace_root: repo.workspace_root,
      repo_name: path.basename(repo.workspace_path),
      memory_script_present: fs.existsSync(memoryScriptPath),
      session_save_hook_present: hasSessionSave,
      health_check_tool_present: hasHealthCheck,
      // Deprecated aliases retained for one release; remove in the next major version.
      session_capture_present: hasSessionSave,
      obsidian_healthcheck_present: hasHealthCheck,
      backend_kind: backendKind,
      backend_path: backendPath,
      global_vault_path: globalVaultPathCandidate,
      local_vault_path: localVaultPath,
      framework_version_signals: {
        slug_source: resolved.slug_source,
        context_present: fs.existsSync(path.join(repo.workspace_path, '.context.md')),
        feature_map_present: fs.existsSync(path.join(repo.workspace_path, 'docs', 'FEATURE-MAP.md')),
        trace_analysis_present: fs.existsSync(path.join(repo.workspace_path, '.agents', 'skills', 'trace-analysis', 'SKILL.md')),
      },
    };
  });

  const workspacesBySlug = new Map();
  for (const entry of workspaceEntries) {
    if (!workspacesBySlug.has(entry.project_slug)) {
      workspacesBySlug.set(entry.project_slug, []);
    }
    workspacesBySlug.get(entry.project_slug).push(entry);
  }

  const attachedVaultSlugs = new Set();
  const projects = [];

  for (const entry of workspaceEntries) {
    const collisions = workspacesBySlug.get(entry.project_slug) || [];
    const hasCollision = collisions.length > 1;
    const canAttachGlobalVault =
      Boolean(entry.global_vault_path) &&
      (!hasCollision || entry.workspace_root === entry.project_slug || entry.repo_name === entry.project_slug || entry.slug_source !== 'repo_dir');

    if (canAttachGlobalVault) {
      attachedVaultSlugs.add(entry.project_slug);
    }

    projects.push({
      project_key: entry.project_slug,
      project_slug: entry.project_slug,
      workspace_path: entry.workspace_path,
      workspace_root: entry.workspace_root,
      backend_kind: entry.backend_kind,
      global_vault_path: canAttachGlobalVault ? entry.global_vault_path : '',
      local_vault_path: entry.local_vault_path,
      memory_script_present: entry.memory_script_present,
      session_save_hook_present: entry.session_save_hook_present,
      health_check_tool_present: entry.health_check_tool_present,
      // Deprecated aliases retained for one release; remove in the next major version.
      session_capture_present: entry.session_capture_present,
      obsidian_healthcheck_present: entry.obsidian_healthcheck_present,
      framework_version_signals: entry.framework_version_signals,
      excluded_reason: '',
      slug_collision: hasCollision,
      collision_group: collisions.map((item) => item.workspace_path),
      skill_catalog: entry.workspace_path ? buildSkillCatalog(entry.workspace_path) : [],
    });
  }

  for (const vaultProject of vaultProjects) {
    if (attachedVaultSlugs.has(vaultProject.project_slug)) continue;
    projects.push({
      project_key: vaultProject.project_slug,
      project_slug: vaultProject.project_slug,
      workspace_path: '',
      workspace_root: '',
      backend_kind: 'global',
      global_vault_path: vaultProject.vault_path,
      local_vault_path: '',
      memory_script_present: false,
      session_save_hook_present: false,
      health_check_tool_present: false,
      // Deprecated aliases retained for one release; remove in the next major version.
      session_capture_present: false,
      obsidian_healthcheck_present: false,
      framework_version_signals: {
        slug_source: 'vault_dir',
        context_present: false,
        feature_map_present: false,
        trace_analysis_present: false,
      },
      excluded_reason: '',
      slug_collision: Boolean(workspacesBySlug.get(vaultProject.project_slug)?.length > 1),
      collision_group: (workspacesBySlug.get(vaultProject.project_slug) || []).map((item) => item.workspace_path),
      skill_catalog: [],
    });
  }

  const projectGroups = new Map();
  for (const project of projects) {
    if (!projectGroups.has(project.project_slug)) {
      projectGroups.set(project.project_slug, []);
    }
    projectGroups.get(project.project_slug).push(project);
  }

  for (const project of projects) {
    const siblings = projectGroups.get(project.project_slug) || [];
    if (siblings.length > 1) {
      const suffix = project.workspace_root || path.basename(project.global_vault_path || '') || 'vault';
      project.project_key = `${project.project_slug}::${suffix}`;
      project.slug_collision = true;
      project.collision_group = siblings.map((item) => item.workspace_path || item.global_vault_path).filter(Boolean);
    }
  }

  return {
    projects: projects.sort((left, right) => left.project_key.localeCompare(right.project_key)),
    excluded,
  };
}

function collectVaultSessionsForProject(project) {
  const records = [];
  const vaultSources = unique(
    [
      project.global_vault_path ? { scope: 'global', path: project.global_vault_path } : null,
      project.local_vault_path ? { scope: 'local', path: project.local_vault_path } : null,
    ].filter(Boolean),
  );

  for (const vaultSource of vaultSources) {
    const sessionsDir = path.join(vaultSource.path, 'sessions');
    const metricsDir = path.join(vaultSource.path, 'metrics');
    const auditDir = path.join(vaultSource.path, 'audit');

    for (const filePath of listMarkdownFiles(sessionsDir)) {
      const record = parseVaultSessionFile(filePath, project.project_key, vaultSource.scope);
      if (record) {
        record.probable_skill_matches = detectProbableSkillMatches(project.skill_catalog || [], [
          ...record.summary,
          ...record.what_was_done,
          ...record.learnings,
        ]);
        records.push(record);
      }
    }

    for (const filePath of listMarkdownFiles(metricsDir)) {
      const record = parseVaultMetricsFile(filePath, project.project_key, vaultSource.scope);
      if (record) records.push(record);
    }

    for (const filePath of listMarkdownFiles(auditDir)) {
      const record = parseVaultAuditFile(filePath, project.project_key, vaultSource.scope);
      if (record) records.push(record);
    }
  }

  return sortSessionsByTimestampDesc(records);
}

function collectProjectSessions(project, codexLogMetas, sessionLimit, costInputs = {}) {
  const vaultRecords = collectVaultSessionsForProject(project);
  const codexRecords = codexLogMetas
    .filter((meta) => meta.project_key === project.project_key)
    .slice(0, sessionLimit * 2)
    .map((meta) => parseCodexLogRecord(meta, project.project_key, project.skill_catalog || [], costInputs.pricingIndex));
  const claudeRecords = (costInputs.claudeRecords || [])
    .filter((record) => record.project_key === project.project_key)
    .slice(0, sessionLimit * 2);

  const merged = new Map();
  for (const record of [...vaultRecords, ...codexRecords, ...claudeRecords]) {
    const key = sessionMergeKey(record);
    if (!merged.has(key)) {
      merged.set(key, record);
      continue;
    }
    merged.set(key, mergeRecords(merged.get(key), record));
  }

  return sortSessionsByTimestampDesc([...merged.values()]);
}

function summarizeCountsBy(items, keyFn) {
  const counts = new Map();
  for (const item of items) {
    const key = keyFn(item);
    if (!key) continue;
    counts.set(key, (counts.get(key) || 0) + 1);
  }
  return [...counts.entries()]
    .sort((left, right) => right[1] - left[1] || left[0].localeCompare(right[0]))
    .map(([key, count]) => ({ key, count }));
}

function severityFromStatus(status) {
  if (status === 'failing' || status === 'non_compliant_missing') return 'high';
  if (status === 'partial' || status === 'non_compliant_local') return 'medium';
  return 'low';
}

function pushFinding(target, finding) {
  target.push({
    id: finding.id,
    category: finding.category,
    severity: finding.severity,
    message: finding.message,
    evidence_refs: unique(finding.evidence_refs || []),
  });
}

function aggregateRankedField(sessions, fieldName) {
  const counter = {};
  for (const session of sessions) {
    for (const item of session[fieldName] || []) {
      incrementCounter(counter, item.name, item.count);
    }
  }
  return counterToRankedList(counter);
}

function aggregateActivityBreakdown(sessions) {
  return mergeActivityBreakdowns(...sessions.map((session) => session.activity_breakdown));
}

function summarizeProjectCost(sessions) {
  const tokenTotals = sessions.reduce((total, session) => addTokenUsage(total, session.token_usage), normalizeTokenUsage({}));
  const knownCostSessions = sessions.filter((session) => typeof session.estimated_cost_usd === 'number');
  const estimatedCost = roundCost(
    knownCostSessions.reduce((sum, session) => sum + session.estimated_cost_usd, 0),
  );
  const providerCounts = summarizeCountsBy(
    sessions.filter((session) => session.provider),
    (session) => session.provider,
  );
  const missingPricing = unique(sessions.flatMap((session) => session.missing_pricing || []));

  return {
    cost_summary: {
      estimated_cost_usd: estimatedCost,
      sessions_with_cost: knownCostSessions.length,
      sessions_missing_cost: sessions.length - knownCostSessions.length,
      avg_cost_per_session_usd: knownCostSessions.length > 0 ? roundCost(estimatedCost / knownCostSessions.length) : null,
      top_provider: providerCounts[0]?.key || '',
      missing_pricing_count: missingPricing.length,
    },
    token_totals: tokenTotals,
    missing_pricing: missingPricing,
    top_tools: aggregateRankedField(sessions, 'tool_calls'),
    top_shell_commands: aggregateRankedField(sessions, 'shell_commands'),
    top_mcp_servers: aggregateRankedField(sessions, 'mcp_calls'),
    activity_breakdown: aggregateActivityBreakdown(sessions),
  };
}

function roundedMetric(value, digits = 4) {
  return typeof value === 'number' && Number.isFinite(value) ? Number(value.toFixed(digits)) : null;
}

function computeLastSessionAgeDays(sessions, generatedAt) {
  const runTime = Date.parse(generatedAt || '');
  if (!Number.isFinite(runTime)) return null;

  const timestamps = sessions
    .map((session) => Date.parse(session.timestamp || ''))
    .filter((timestamp) => Number.isFinite(timestamp));
  if (timestamps.length === 0) return null;

  const latest = Math.max(...timestamps);
  return roundedMetric(Math.max(0, runTime - latest) / (24 * 60 * 60 * 1000));
}

function hasWorkspaceMemoryDir(project) {
  if (!project.workspace_path) return false;
  const memoryDir = path.join(project.workspace_path, '.agents', 'memory');
  return fs.existsSync(memoryDir) && fs.statSync(memoryDir).isDirectory();
}

function hasWorkspaceClaudeFile(project) {
  return Boolean(project.workspace_path && fs.existsSync(path.join(project.workspace_path, 'CLAUDE.md')));
}

function resolveProjectToolFlags(project) {
  const sessionSaveHookPresent =
    project.session_save_hook_present === undefined ? Boolean(project.session_capture_present) : Boolean(project.session_save_hook_present);
  const healthCheckToolPresent =
    project.health_check_tool_present === undefined ? Boolean(project.obsidian_healthcheck_present) : Boolean(project.health_check_tool_present);
  return { sessionSaveHookPresent, healthCheckToolPresent };
}

function classifyProjectBucket({ project, sessionsAvailable, lastSessionAgeDays, captureRatio, pendingSyncOrphanRatio }) {
  const hasWorkspace = Boolean(project.workspace_path);
  const hasRecentSession = lastSessionAgeDays !== null && lastSessionAgeDays <= 30;
  const workspaceMissingCanFallThrough = !hasWorkspace && hasRecentSession && Boolean(project.global_vault_path);
  const memoryInstallSignal = project.memory_script_present || workspaceMissingCanFallThrough;
  const { sessionSaveHookPresent, healthCheckToolPresent } = resolveProjectToolFlags(project);

  if (
    !workspaceMissingCanFallThrough &&
    (!hasWorkspace || !hasWorkspaceMemoryDir(project) || !hasWorkspaceClaudeFile(project) || sessionsAvailable === 0)
  ) {
    return 'never-installed';
  }

  if (lastSessionAgeDays !== null && lastSessionAgeDays > 30) {
    return 'dormant';
  }

  if (memoryInstallSignal && (!sessionSaveHookPresent || !healthCheckToolPresent)) {
    return 'pre-v1.8';
  }

  if (
    memoryInstallSignal &&
    sessionSaveHookPresent &&
    healthCheckToolPresent &&
    (captureRatio < 0.4 || pendingSyncOrphanRatio > 0.2)
  ) {
    return 'v1.8-failing';
  }

  if (
    memoryInstallSignal &&
    sessionSaveHookPresent &&
    healthCheckToolPresent &&
    captureRatio >= 0.4 &&
    pendingSyncOrphanRatio <= 0.2
  ) {
    return 'healthy';
  }

  return 'never-installed';
}

function buildProjectSummary(project, allSessions, sessionLimit, generatedAt = new Date().toISOString()) {
  const skillCatalog = project.skill_catalog || [];
  const { sessionSaveHookPresent, healthCheckToolPresent } = resolveProjectToolFlags(project);
  const sessionsAvailable = allSessions.length;
  const analyzedSessions = sortSessionsByTimestampDesc(allSessions).slice(0, sessionLimit);
  const runtimeMix = analyzedSessions.reduce((accumulator, session) => {
    accumulator[session.runtime] = (accumulator[session.runtime] || 0) + 1;
    return accumulator;
  }, {});

  const captureEvidenceCount = analyzedSessions.filter((session) => session.captured_to_vault).length;
  const pendingSyncOrphanCount = analyzedSessions.filter((session) => session.pending_sync).length;
  const healthcheckEvidenceCount = analyzedSessions.filter((session) =>
    session.validation.some((line) => normalizeText(line).includes('codex-health-check')),
  ).length;
  const captureRatio = analyzedSessions.length === 0 ? 0 : captureEvidenceCount / analyzedSessions.length;
  const pendingSyncOrphanRatio = analyzedSessions.length === 0 ? 0 : roundedMetric(pendingSyncOrphanCount / analyzedSessions.length);
  const lastSessionAgeDays = sessionsAvailable === 0 ? null : computeLastSessionAgeDays(analyzedSessions, generatedAt);
  const bucket = classifyProjectBucket({
    project,
    sessionsAvailable,
    lastSessionAgeDays,
    captureRatio,
    pendingSyncOrphanRatio,
  });
  const missEntries = [];
  const projectSkillReadSet = new Set(analyzedSessions.flatMap((session) => session.skill_reads || []));

  analyzedSessions.forEach((session) => {
    for (const match of session.probable_skill_matches || []) {
      if (match.score >= 4 && !projectSkillReadSet.has(match.skill_id)) {
        missEntries.push({
          skill_id: match.skill_id,
          score: match.score,
          evidence_ref: session.source_path,
        });
      }
    }
  });

  const skillBreakageEntries = analyzedSessions.flatMap((session) =>
    (session.skill_breakages || []).map((breakage) => ({
      breakage,
      evidence_ref: session.source_path,
    })),
  );

  let obsidianStatus = 'non_compliant_missing';
  if (
    project.backend_kind === 'global' &&
    project.memory_script_present &&
    (captureEvidenceCount > 0 || healthcheckEvidenceCount > 0)
  ) {
    obsidianStatus = 'compliant';
  } else if (project.backend_kind === 'local') {
    obsidianStatus = 'non_compliant_local';
  }

  let captureHealth = 'unknown';
  if (analyzedSessions.length > 0) {
    if (captureRatio >= 0.8) captureHealth = 'healthy';
    else if (captureRatio >= 0.2) captureHealth = 'partial';
    else captureHealth = 'failing';
  }

  let skillStatus = 'unknown';
  if (skillCatalog.length > 0 || analyzedSessions.some((session) => (session.probable_skill_matches || []).length > 0)) {
    const missRatio = analyzedSessions.length === 0 ? 0 : missEntries.length / analyzedSessions.length;
    if (skillBreakageEntries.length > 0 || missRatio >= 0.5) skillStatus = 'failing';
    else if (missEntries.length > 0) skillStatus = 'partial';
    else skillStatus = 'healthy';
  }

  let frameworkHealth = 'unknown';
  if (project.workspace_path) {
    const missingCoreScripts = [];
    if (!project.memory_script_present) missingCoreScripts.push('canuto-memory.sh');
    if (!sessionSaveHookPresent) missingCoreScripts.push('session-save.sh');
    if (!healthCheckToolPresent) missingCoreScripts.push('codex-health-check.sh');

    if (project.slug_collision || missingCoreScripts.length >= 2) {
      frameworkHealth = 'failing';
    } else if (missingCoreScripts.length === 1 || obsidianStatus !== 'compliant') {
      frameworkHealth = 'partial';
    } else {
      frameworkHealth = 'healthy';
    }
  }

  const topFindings = [];
  const recommendedActions = [];

  if (project.slug_collision) {
    pushFinding(topFindings, {
      id: 'slug-collision',
      category: 'slug-collision',
      severity: 'high',
      message: `Slug "${project.project_slug}" collides with another project and risks binding the wrong vault.`,
      evidence_refs: project.collision_group,
    });
    recommendedActions.push({
      priority: 'P0',
      message: `Assign a unique project slug to ${project.project_key} and rebind its vault path.`,
      evidence_refs: project.collision_group,
    });
  }

  if (obsidianStatus !== 'compliant') {
    const severity = severityFromStatus(obsidianStatus);
    pushFinding(topFindings, {
      id: 'obsidian-noncompliance',
      category: 'obsidian-noncompliance',
      severity,
      message:
        obsidianStatus === 'non_compliant_local'
          ? 'Project is using a local `.agents/vault`, which violates the mandatory global Obsidian policy.'
          : 'Project lacks a compliant global Obsidian workflow or missing runtime pieces required to enforce it.',
      evidence_refs: unique([
        project.workspace_path,
        project.global_vault_path,
        project.local_vault_path,
      ]),
    });
    recommendedActions.push({
      priority: severity === 'high' ? 'P0' : 'P1',
      message:
        obsidianStatus === 'non_compliant_local'
          ? 'Migrate storage from local `.agents/vault` to `~/.canuto/vault/projects/<slug>` and reinstall the memory backend.'
          : 'Restore the global vault binding and required memory scripts before new sessions run.',
      evidence_refs: unique([
        project.workspace_path,
        project.global_vault_path,
        project.local_vault_path,
      ]),
    });
  }

  if (captureHealth === 'partial' || captureHealth === 'failing') {
    pushFinding(topFindings, {
      id: 'capture-gap',
      category: 'playbook-gap',
      severity: severityFromStatus(captureHealth),
      message: `Only ${captureEvidenceCount}/${analyzedSessions.length || 0} analyzed sessions show vault capture evidence.`,
      evidence_refs: unique(analyzedSessions.slice(0, 5).map((session) => session.source_path)),
    });
    recommendedActions.push({
      priority: captureHealth === 'failing' ? 'P0' : 'P1',
      message: 'Reinstate the session-save hook flow and verify capture artifacts land in the vault every run.',
      evidence_refs: unique(analyzedSessions.slice(0, 5).map((session) => session.source_path)),
    });
  }

  if (skillStatus === 'partial' || skillStatus === 'failing') {
    pushFinding(topFindings, {
      id: 'skill-gap',
      category: 'skill-gap',
      severity: severityFromStatus(skillStatus),
      message:
        skillBreakageEntries.length > 0
          ? `Detected ${skillBreakageEntries.length} skill breakage signal(s) across analyzed sessions.`
          : `Detected ${missEntries.length} probable skill miss(es) where a local skill matched but was not read.`,
      evidence_refs: unique([
        ...missEntries.slice(0, 5).map((entry) => entry.evidence_ref),
        ...skillBreakageEntries.slice(0, 5).map((entry) => entry.evidence_ref),
      ]),
    });
    recommendedActions.push({
      priority: skillStatus === 'failing' ? 'P0' : 'P1',
      message: 'Tighten mandatory-skill-check enforcement and remove or repair broken skill entrypoints.',
      evidence_refs: unique([
        ...missEntries.slice(0, 5).map((entry) => entry.evidence_ref),
        ...skillBreakageEntries.slice(0, 5).map((entry) => entry.evidence_ref),
      ]),
    });
  }

  if (frameworkHealth === 'partial' || frameworkHealth === 'failing') {
    const missingTools = [
      !project.memory_script_present ? 'canuto-memory.sh' : null,
      project.workspace_path && !sessionSaveHookPresent ? 'session-save.sh' : null,
      project.workspace_path && !healthCheckToolPresent ? 'codex-health-check.sh' : null,
    ].filter(Boolean);

    if (missingTools.length > 0) {
      pushFinding(topFindings, {
        id: 'framework-version-skew',
        category: 'framework-version-skew',
        severity: severityFromStatus(frameworkHealth),
        message: `Workspace is missing framework runtime tools: ${missingTools.join(', ')}.`,
        evidence_refs: [project.workspace_path],
      });
      recommendedActions.push({
        priority: frameworkHealth === 'failing' ? 'P0' : 'P1',
        message: 'Run a framework repair/update path to resync runtime tools distributed to consumer projects.',
        evidence_refs: [project.workspace_path],
      });
    }
  }

  const healthReasonCounts = summarizeCountsBy(
    analyzedSessions.filter((session) => session.health_reason && session.health_reason !== 'healthy' && session.health_reason !== 'unknown'),
    (session) => session.health_reason,
  );
  const topBreakages = [
    ...(healthReasonCounts.map((item) => ({
      kind: 'health_reason',
      label: item.key,
      count: item.count,
      evidence_refs: unique(
        analyzedSessions
          .filter((session) => session.health_reason === item.key)
          .slice(0, 5)
          .map((session) => session.source_path),
      ),
    })) || []),
    ...(analyzedSessions.some((session) => session.offline_sync)
      ? [
          {
            kind: 'offline_sync',
            label: 'OFFLINE-SYNC',
            count: analyzedSessions.filter((session) => session.offline_sync).length,
            evidence_refs: unique(
              analyzedSessions
                .filter((session) => session.offline_sync)
                .slice(0, 5)
                .map((session) => session.source_path),
            ),
          },
        ]
      : []),
    ...(analyzedSessions.some((session) => session.pending_sync)
      ? [
          {
            kind: 'pending_sync',
            label: 'pending-sync',
            count: analyzedSessions.filter((session) => session.pending_sync).length,
            evidence_refs: unique(
              analyzedSessions
                .filter((session) => session.pending_sync)
                .slice(0, 5)
                .map((session) => session.source_path),
            ),
          },
        ]
      : []),
    ...(analyzedSessions.some((session) => session.fallback_used)
      ? [
          {
            kind: 'fallback_used',
            label: 'fallback_used=true',
            count: analyzedSessions.filter((session) => session.fallback_used).length,
            evidence_refs: unique(
              analyzedSessions
                .filter((session) => session.fallback_used)
                .slice(0, 5)
                .map((session) => session.source_path),
            ),
          },
        ]
      : []),
  ].sort((left, right) => right.count - left.count || left.label.localeCompare(right.label));

  const topSkillsMissed = summarizeCountsBy(missEntries, (entry) => entry.skill_id).map((item) => ({
    skill_id: item.key,
    count: item.count,
    evidence_refs: unique(
      missEntries
        .filter((entry) => entry.skill_id === item.key)
        .slice(0, 5)
        .map((entry) => entry.evidence_ref),
    ),
  }));

  const evidenceRefs = unique([
    project.workspace_path,
    project.global_vault_path,
    project.local_vault_path,
    ...analyzedSessions.slice(0, 10).map((session) => session.source_path),
  ]).filter(Boolean);
  const costSummary = summarizeProjectCost(analyzedSessions);

  return {
    project_key: project.project_key,
    project_slug: project.project_slug,
    sessions_available: sessionsAvailable,
    sessions_analyzed: analyzedSessions.length,
    session_save_hook_present: sessionSaveHookPresent,
    health_check_tool_present: healthCheckToolPresent,
    // Deprecated aliases retained for one release; remove in the next major version.
    session_capture_present: sessionSaveHookPresent,
    obsidian_healthcheck_present: healthCheckToolPresent,
    bucket,
    last_session_age_days: lastSessionAgeDays,
    pending_sync_orphan_ratio: pendingSyncOrphanRatio,
    runtime_mix: runtimeMix,
    obsidian_status: obsidianStatus,
    capture_health: captureHealth,
    skill_status: skillStatus,
    framework_health: frameworkHealth,
    top_findings: topFindings,
    top_skills_missed: topSkillsMissed,
    top_breakages: topBreakages,
    recommended_actions: recommendedActions,
    evidence_refs: evidenceRefs,
    skill_catalog_count: skillCatalog.length,
    cost_summary: costSummary.cost_summary,
    token_totals: costSummary.token_totals,
    top_tools: costSummary.top_tools,
    top_shell_commands: costSummary.top_shell_commands,
    top_mcp_servers: costSummary.top_mcp_servers,
    activity_breakdown: costSummary.activity_breakdown,
    missing_pricing: costSummary.missing_pricing,
    sessions: analyzedSessions,
  };
}

function clampRate(value) {
  if (!Number.isFinite(value)) return 0;
  return roundedMetric(Math.max(0, Math.min(1, value)));
}

function safeDivide(numerator, denominator) {
  return denominator > 0 ? numerator / denominator : 0;
}

function hasImplementationSignal(session) {
  const toolNames = (session.tool_calls || []).map((item) => normalizeText(item.name));
  return (
    toNumber(session.tasks_completed, 0) > 0 ||
    Boolean(session.activity_breakdown?.Coding) ||
    toolNames.some((name) => ['edit', 'write', 'apply_patch'].includes(name))
  );
}

function hasValidationSignal(session) {
  return toNumber(session.tests_run, 0) > 0 || (session.validation || []).length > 0;
}

function hasReworkSignal(session) {
  return (
    toNumber(session.review_fix_cycles, 0) > 0 ||
    toNumber(session.efficiency?.failed_command_count, 0) >= 2
  );
}

function hasContextResetSignal(session) {
  return (
    toNumber(session.efficiency?.prompt_too_long_errors, 0) > 0 ||
    toNumber(session.efficiency?.compact_failures, 0) > 0
  );
}

function extractMentionedFilePaths(session) {
  const corpus = [
    ...(session.summary || []),
    ...(session.what_was_done || []),
    ...(session.validation || []),
    ...(session.learnings || []),
    ...(session._user_messages || []),
  ].join('\n');
  const paths = new Set();
  const matcher =
    /(?:^|[\s`'"])((?:[./~]?(?:[A-Za-z0-9_.-]+\/)+[A-Za-z0-9_.-]+\.[A-Za-z0-9]{1,8})|(?:[A-Za-z0-9_.-]+\.(?:js|ts|tsx|jsx|mjs|cjs|json|md|sh|py|go|rs|toml|ya?ml|css|html)))(?=$|[\s`'",:;)])/g;
  let match;
  while ((match = matcher.exec(corpus)) !== null) {
    const candidate = match[1].replace(/^\.?\//, '');
    if (!candidate || candidate.endsWith('.jsonl')) continue;
    paths.add(candidate);
  }
  return [...paths];
}

function computeSameFileReopenedRate(sessions) {
  const seen = new Set();
  let reopened = 0;
  const chronologicalSessions = [...sessions].sort((left, right) => {
    const leftTs = Date.parse(left.timestamp || '');
    const rightTs = Date.parse(right.timestamp || '');
    return toNumber(leftTs, 0) - toNumber(rightTs, 0);
  });

  for (const session of chronologicalSessions) {
    const mentionedPaths = extractMentionedFilePaths(session);
    if (mentionedPaths.some((filePath) => seen.has(filePath))) {
      reopened += 1;
    }
    for (const filePath of mentionedPaths) {
      seen.add(filePath);
    }
  }

  return clampRate(safeDivide(reopened, sessions.length));
}

function sumRankedCounts(items) {
  return (items || []).reduce((sum, item) => sum + toNumber(item.count, 0), 0);
}

function buildCanutoSessionMetricValues(summary) {
  const sessions = summary.sessions || [];
  const sessionCount = toNumber(summary.sessions_analyzed, sessions.length);
  const implementationSessions = sessions.filter(hasImplementationSignal);
  const validationDenominator = implementationSessions.length > 0 ? implementationSessions.length : sessionCount;
  const validationSkipped = implementationSessions.length > 0
    ? implementationSessions.filter((session) => !hasValidationSignal(session)).length
    : sessions.filter((session) => !hasValidationSignal(session)).length;
  const retryExhaustionCount = sessions.filter((session) => toNumber(session.efficiency?.failed_command_count, 0) >= 3).length;
  const ruleGapCategories = new Set(['playbook-gap', 'skill-gap', 'framework-version-skew']);
  const ruleGapCount = (summary.top_findings || []).filter((finding) => ruleGapCategories.has(finding.category)).length;
  const skillMissCount = sumRankedCounts(summary.top_skills_missed);

  return {
    'canuto.session.validation_skip_rate': clampRate(safeDivide(validationSkipped, validationDenominator)),
    'canuto.session.rework_loop_rate': clampRate(safeDivide(sessions.filter(hasReworkSignal).length, sessionCount)),
    // TODO: replace this approximation with explicit edit-path history once hooks persist per-session file reopen events.
    'canuto.session.same_file_reopened_rate': computeSameFileReopenedRate(sessions),
    'canuto.session.context_reset_need_rate': clampRate(safeDivide(sessions.filter(hasContextResetSignal).length, sessionCount)),
    // TODO: replace this skill-miss proxy with explicit memory-worthy-rule persistence signals when available.
    'canuto.session.memory_miss_rate': clampRate(safeDivide(skillMissCount, sessionCount)),
    'canuto.session.retry_exhaustion_count': retryExhaustionCount,
    'canuto.session.rule_gap_count': ruleGapCount,
  };
}

function otlpAttribute(key, value) {
  if (typeof value === 'number' && Number.isInteger(value)) {
    return { key, value: { intValue: String(value) } };
  }
  if (typeof value === 'number' && Number.isFinite(value)) {
    return { key, value: { doubleValue: value } };
  }
  return { key, value: { stringValue: String(value || '') } };
}

function otlpTimeUnixNano(generatedAt) {
  const millis = Date.parse(generatedAt || '');
  const safeMillis = Number.isFinite(millis) ? millis : Date.now();
  return String(BigInt(safeMillis) * 1000000n);
}

function buildCanutoOtlpPayload(auditResult) {
  const generatedAt = auditResult?.generated_at || new Date().toISOString();
  const timeUnixNano = otlpTimeUnixNano(generatedAt);
  const projectSummaries = auditResult?.project_summaries || [];
  const metrics = CANUTO_SESSION_METRIC_DEFS.map((definition) => {
    const dataPoints = projectSummaries.map((summary) => {
      const values = buildCanutoSessionMetricValues(summary);
      const value = values[definition.name] || 0;
      const point = {
        attributes: [
          otlpAttribute('project.key', summary.project_key || ''),
          otlpAttribute('project.slug', summary.project_slug || summary.project_key || ''),
          otlpAttribute('sessions.analyzed', toNumber(summary.sessions_analyzed, 0)),
        ],
        timeUnixNano,
      };
      if (definition.kind === 'counter') {
        point.asInt = String(Math.max(0, Math.round(toNumber(value, 0))));
      } else {
        point.asDouble = toNumber(value, 0);
      }
      return point;
    });

    const metric = {
      name: definition.name,
      unit: definition.unit,
    };
    if (definition.kind === 'counter') {
      metric.sum = {
        aggregationTemporality: 'AGGREGATION_TEMPORALITY_DELTA',
        isMonotonic: true,
        dataPoints,
      };
    } else {
      metric.gauge = { dataPoints };
    }
    return metric;
  });

  return {
    resourceMetrics: [
      {
        resource: {
          attributes: [
            otlpAttribute('service.name', 'canuto-framework-audit'),
            otlpAttribute('deployment.environment', 'local-dev'),
          ],
        },
        scopeMetrics: [
          {
            scope: { name: 'canuto' },
            metrics,
          },
        ],
      },
    ],
  };
}

function isCanutoOtlpEnabled(opts = {}) {
  if (typeof opts.enabled === 'boolean') return opts.enabled;
  const explicit = process.env.CANUTO_OTLP_ENABLED;
  if (explicit === '0' || normalizeText(explicit) === 'false') return false;
  const master = process.env.CLAUDE_CODE_ENABLE_TELEMETRY;
  const masterOn = master === '1' || normalizeText(master) === 'true';
  if (!masterOn) return false;
  if (explicit === '1' || normalizeText(explicit) === 'true') return true;
  return Boolean(process.env.OTEL_EXPORTER_OTLP_ENDPOINT);
}

function fallbackCanutoOtlpPayload(fallbackPath, payload) {
  try {
    ensureDir(path.dirname(fallbackPath));
    fs.appendFileSync(fallbackPath, `${JSON.stringify(payload)}\n`);
    return true;
  } catch {
    return false;
  }
}

async function emitCanutoOtlpMetrics(auditResult, opts = {}) {
  const endpoint = opts.endpoint || process.env.CANUTO_OTLP_HTTP_ENDPOINT || DEFAULT_CANUTO_OTLP_HTTP_ENDPOINT;
  const fallbackPath = resolvePath(
    opts.fallbackNdjson || process.env.CANUTO_OTLP_FALLBACK || DEFAULT_CANUTO_OTLP_FALLBACK,
    opts.cwd || process.cwd(),
  );

  if (!isCanutoOtlpEnabled(opts)) {
    return { status: 'skipped', endpoint, fallback_path: fallbackPath };
  }

  const payload = buildCanutoOtlpPayload(auditResult);
  const fetchImpl = opts.fetch || globalThis.fetch;
  const timeoutMs = toNumber(opts.timeoutMs, 3000);

  if (typeof fetchImpl === 'function') {
    const controller = typeof AbortController === 'function' ? new AbortController() : null;
    const timeout = controller ? setTimeout(() => controller.abort(), timeoutMs) : null;
    try {
      const response = await fetchImpl(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
        signal: controller?.signal,
      });
      if (!response || response.status < 200 || response.status >= 300) {
        throw new Error(`OTLP HTTP status ${response?.status || 'unknown'}`);
      }
      return { status: 'otlp', endpoint, fallback_path: fallbackPath };
    } catch {
      // Fall through to NDJSON so local audits remain useful when SigNoz is down.
    } finally {
      if (timeout) clearTimeout(timeout);
    }
  }

  if (fallbackCanutoOtlpPayload(fallbackPath, payload)) {
    return { status: 'ndjson', endpoint, fallback_path: fallbackPath };
  }
  return { status: 'skipped', endpoint, fallback_path: fallbackPath };
}

function sortProjectSummariesByBucket(projectSummaries) {
  return [...projectSummaries].sort((left, right) => {
    const bucketDiff = (BUCKET_TRIAGE_ORDER[left.bucket] ?? 99) - (BUCKET_TRIAGE_ORDER[right.bucket] ?? 99);
    if (bucketDiff !== 0) return bucketDiff;
    return left.project_key.localeCompare(right.project_key);
  });
}

function groupProjectsByBucket(projectSummaries) {
  return BUCKET_TAXONOMY_ORDER.map((bucket) => ({
    bucket,
    count: projectSummaries.filter((summary) => summary.bucket === bucket).length,
    projects: projectSummaries
      .filter((summary) => summary.bucket === bucket)
      .map((summary) => summary.project_key)
      .sort((left, right) => left.localeCompare(right)),
  }));
}

function rankProjects(projectSummaries) {
  return {
    projects_by_bucket: sortProjectSummariesByBucket(projectSummaries).map((summary) => ({
      project_key: summary.project_key,
      bucket: summary.bucket,
      last_session_age_days: summary.last_session_age_days,
      pending_sync_orphan_ratio: summary.pending_sync_orphan_ratio,
      capture_health: summary.capture_health,
      framework_health: summary.framework_health,
    })),
    bucket_counts: groupProjectsByBucket(projectSummaries),
    obsidian_noncompliance: [...projectSummaries]
      .filter((summary) => summary.obsidian_status !== 'compliant')
      .sort((left, right) => {
        const severityDiff = (OBSIDIAN_PRIORITY[left.obsidian_status] || 0) - (OBSIDIAN_PRIORITY[right.obsidian_status] || 0);
        if (severityDiff !== 0) return severityDiff;
        return right.sessions_analyzed - left.sessions_analyzed;
      })
      .map((summary) => ({
        project_key: summary.project_key,
        obsidian_status: summary.obsidian_status,
        evidence_refs: summary.evidence_refs.slice(0, 5),
      })),
    low_skill_adoption: [...projectSummaries]
      .filter((summary) => summary.skill_status === 'partial' || summary.skill_status === 'failing')
      .sort((left, right) => {
        const statusDiff = (STATUS_PRIORITY[right.skill_status] || 0) - (STATUS_PRIORITY[left.skill_status] || 0);
        if (statusDiff !== 0) return statusDiff;
        return right.top_skills_missed.length - left.top_skills_missed.length;
      })
      .map((summary) => ({
        project_key: summary.project_key,
        skill_status: summary.skill_status,
        top_skills_missed: summary.top_skills_missed.slice(0, 3),
      })),
    operational_breakage: [...projectSummaries]
      .filter((summary) => summary.framework_health === 'partial' || summary.framework_health === 'failing' || summary.capture_health === 'failing')
      .sort((left, right) => {
        const frameworkDiff = (STATUS_PRIORITY[right.framework_health] || 0) - (STATUS_PRIORITY[left.framework_health] || 0);
        if (frameworkDiff !== 0) return frameworkDiff;
        return (right.top_breakages[0]?.count || 0) - (left.top_breakages[0]?.count || 0);
      })
      .map((summary) => ({
        project_key: summary.project_key,
        framework_health: summary.framework_health,
        capture_health: summary.capture_health,
        top_breakages: summary.top_breakages.slice(0, 3),
      })),
    candidate_skills_to_reinforce: summarizeCountsBy(
      projectSummaries.flatMap((summary) => summary.top_skills_missed.map((item) => ({ project_key: summary.project_key, skill_id: item.skill_id }))),
      (item) => item.skill_id,
    ).slice(0, 10),
    candidate_skills_to_simplify: summarizeCountsBy(
      projectSummaries.flatMap((summary) =>
        summary.skill_catalog_count > 0 && summary.top_skills_missed.length === 0 && summary.skill_status === 'healthy'
          ? []
          : [],
      ),
      (item) => item,
    ),
  };
}

function loadCodeburnExport(filePath) {
  const health = {
    path: filePath || '',
    available: false,
    error: '',
  };
  const empty = {
    by_activity: [],
    core_tools: [],
    shell_commands: [],
    mcp_servers: [],
    by_project: [],
  };

  if (!filePath) {
    health.error = 'not-configured';
    return { observations: empty, health };
  }
  if (!fs.existsSync(filePath)) {
    health.error = 'not-found';
    return { observations: empty, health };
  }

  try {
    const parsed = JSON.parse(readTextIfExists(filePath));
    const observations = { ...empty };
    for (const key of Object.keys(empty)) {
      observations[key] = Array.isArray(parsed[key]) ? parsed[key] : [];
    }
    health.available = true;
    return { observations, health };
  } catch (error) {
    health.error = error && error.message ? error.message : String(error);
    return { observations: empty, health };
  }
}

function allocateCostByRankedField(sessions, fieldName) {
  const entries = {};
  for (const session of sessions) {
    const items = session[fieldName] || [];
    const totalCount = items.reduce((sum, item) => sum + toNumber(item.count, 0), 0);
    const shareCost = typeof session.estimated_cost_usd === 'number' && totalCount > 0
      ? session.estimated_cost_usd / totalCount
      : null;

    for (const item of items) {
      const key = item.name;
      if (!key) continue;
      const current = entries[key] || {
        name: key,
        count: 0,
        estimated_cost_usd: 0,
        cost_estimated: false,
      };
      current.count += toNumber(item.count, 0);
      if (shareCost !== null) {
        current.estimated_cost_usd += shareCost * toNumber(item.count, 0);
        current.cost_estimated = true;
      }
      entries[key] = current;
    }
  }

  return Object.values(entries)
    .map((entry) => ({
      ...entry,
      estimated_cost_usd: entry.cost_estimated ? roundCost(entry.estimated_cost_usd) : null,
    }))
    .sort((left, right) =>
      toNumber(right.estimated_cost_usd, -1) - toNumber(left.estimated_cost_usd, -1) ||
      right.count - left.count ||
      left.name.localeCompare(right.name),
    )
    .slice(0, 20);
}

function aggregateProviderModels(sessions) {
  const entries = {};
  for (const session of sessions) {
    const provider = session.provider || session.runtime || 'unknown';
    const model = session.model || 'unknown';
    const key = `${provider}/${model}`;
    const current = entries[key] || {
      provider,
      model,
      sessions: 0,
      calls: 0,
      estimated_cost_usd: 0,
      cost_known: false,
      token_usage: normalizeTokenUsage({}),
    };
    current.sessions += 1;
    current.calls += Object.values(rankedListToCounter(session.tool_calls)).reduce((sum, count) => sum + count, 0);
    current.token_usage = addTokenUsage(current.token_usage, session.token_usage);
    if (typeof session.estimated_cost_usd === 'number') {
      current.estimated_cost_usd += session.estimated_cost_usd;
      current.cost_known = true;
    }
    entries[key] = current;
  }

  return Object.values(entries)
    .map((entry) => {
      const cached =
        toNumber(entry.token_usage.cached_input_tokens, 0) +
        toNumber(entry.token_usage.cache_read_input_tokens, 0);
      const inputLike =
        toNumber(entry.token_usage.uncached_input_tokens, 0) +
        cached +
        toNumber(entry.token_usage.cache_creation_input_tokens, 0);
      return {
        ...entry,
        estimated_cost_usd: entry.cost_known ? roundCost(entry.estimated_cost_usd) : null,
        cache_hit_rate: inputLike > 0 ? Number((cached / inputLike).toFixed(4)) : 0,
      };
    })
    .sort((left, right) => toNumber(right.estimated_cost_usd, -1) - toNumber(left.estimated_cost_usd, -1));
}

function aggregateActivities(sessions) {
  const entries = {};
  for (const session of sessions) {
    for (const [activity, value] of Object.entries(session.activity_breakdown || {})) {
      const current = entries[activity] || {
        activity,
        calls: 0,
        estimated_cost_usd: 0,
        cost_estimated: false,
        one_shot_total: 0,
        one_shot_eligible: 0,
        tools: {},
      };
      current.calls += toNumber(value.calls, 0);
      if (typeof value.estimated_cost_usd === 'number') {
        current.estimated_cost_usd += value.estimated_cost_usd;
        current.cost_estimated = true;
      }
      if (session.one_shot_estimate?.eligible) {
        current.one_shot_eligible += 1;
        current.one_shot_total += toNumber(session.one_shot_estimate.value, 0);
      }
      for (const tool of session.tool_calls || []) {
        incrementCounter(current.tools, tool.name, tool.count);
      }
      entries[activity] = current;
    }
  }

  return Object.values(entries)
    .map((entry) => ({
      activity: entry.activity,
      calls: entry.calls,
      estimated_cost_usd: entry.cost_estimated ? roundCost(entry.estimated_cost_usd) : null,
      one_shot_rate: entry.one_shot_eligible > 0 ? Number((entry.one_shot_total / entry.one_shot_eligible).toFixed(4)) : null,
      dominant_tools: counterToRankedList(entry.tools, 5),
    }))
    .sort((left, right) => toNumber(right.estimated_cost_usd, -1) - toNumber(left.estimated_cost_usd, -1) || right.calls - left.calls);
}

function buildRecommendations(costDashboard) {
  const recommendations = [];
  const exploration = costDashboard.rankings.by_activity.find((item) => item.activity === 'Exploration');
  if (exploration && toNumber(exploration.estimated_cost_usd, 0) > 0) {
    recommendations.push('Report-only: exploration has measurable spend; check repeated reads/searches before changing routing.');
  }
  if (costDashboard.efficiency_signals.cache_hit_rate < 0.5 && costDashboard.totals.total_tokens > 0) {
    recommendations.push('Report-only: cache hit rate is below 50%; inspect prompt/cache ordering before adding gates.');
  }
  const heavyShell = costDashboard.rankings.shell_commands[0];
  if (heavyShell && heavyShell.count >= 10) {
    recommendations.push(`Report-only: shell command ${heavyShell.name} is frequent (${heavyShell.count} calls); consider a digest or narrower search workflow.`);
  }
  if (costDashboard.efficiency_signals.prompt_too_long_errors > 0) {
    recommendations.push('Report-only: prompt-too-long errors occurred; prioritize context compaction and source pruning.');
  }
  return recommendations.length > 0 ? recommendations : ['Report-only: no cost anomaly crossed the current reporting thresholds.'];
}

function buildCostDashboard({ generatedAt, projectSummaries, options, sourceHealth, codeburnObservations }) {
  const sessions = projectSummaries.flatMap((summary) => summary.sessions || []);
  const tokenTotals = sessions.reduce((total, session) => addTokenUsage(total, session.token_usage), normalizeTokenUsage({}));
  const knownCost = roundCost(
    sessions.reduce((sum, session) => sum + (typeof session.estimated_cost_usd === 'number' ? session.estimated_cost_usd : 0), 0),
  );
  const missingPricing = unique(sessions.flatMap((session) => session.missing_pricing || []));
  const cached =
    toNumber(tokenTotals.cached_input_tokens, 0) +
    toNumber(tokenTotals.cache_read_input_tokens, 0);
  const inputLike =
    toNumber(tokenTotals.uncached_input_tokens, 0) +
    cached +
    toNumber(tokenTotals.cache_creation_input_tokens, 0);
  const failedCommandCount = sessions.reduce((sum, session) => sum + toNumber(session.efficiency?.failed_command_count, 0), 0);
  const totalShellCommandCount = sessions.reduce((sum, session) => sum + toNumber(session.efficiency?.total_shell_command_count, 0), 0);

  const missingSources = [];
  for (const [name, health] of Object.entries(sourceHealth || {})) {
    if (!health || health.available) continue;
    missingSources.push(`${name}:${health.error || 'unavailable'}`);
  }

  const dashboard = {
    generated_at: generatedAt,
    totals: {
      estimated_cost_usd: knownCost,
      total_tokens: toNumber(tokenTotals.total_tokens, 0),
      sessions: sessions.length,
      sessions_with_cost: sessions.filter((session) => typeof session.estimated_cost_usd === 'number').length,
      providers: unique(sessions.map((session) => session.provider || session.runtime).filter(Boolean)),
      models: unique(sessions.map((session) => session.model).filter(Boolean)),
    },
    token_totals: tokenTotals,
    source_health: sourceHealth,
    sources_used: unique(sessions.map((session) => session.source_kind).filter(Boolean)),
    missing_sources: missingSources,
    missing_pricing: missingPricing,
    rankings: {
      by_project: projectSummaries
        .map((summary) => ({
          project_key: summary.project_key,
          estimated_cost_usd: summary.cost_summary?.estimated_cost_usd ?? null,
          sessions: summary.sessions_analyzed,
          total_tokens: toNumber(summary.token_totals?.total_tokens, 0),
          avg_cost_per_session_usd: summary.cost_summary?.avg_cost_per_session_usd ?? null,
          top_provider: summary.cost_summary?.top_provider || '',
          evidence_refs: summary.evidence_refs,
        }))
        .sort((left, right) => toNumber(right.estimated_cost_usd, -1) - toNumber(left.estimated_cost_usd, -1)),
      by_provider_model: aggregateProviderModels(sessions),
      by_activity: aggregateActivities(sessions),
      core_tools: allocateCostByRankedField(sessions, 'tool_calls'),
      shell_commands: allocateCostByRankedField(sessions, 'shell_commands'),
      mcp_servers: allocateCostByRankedField(sessions, 'mcp_calls'),
    },
    efficiency_signals: {
      cache_hit_rate: inputLike > 0 ? Number((cached / inputLike).toFixed(4)) : 0,
      prompt_too_long_errors: sessions.reduce((sum, session) => sum + toNumber(session.efficiency?.prompt_too_long_errors, 0), 0),
      compact_failures: sessions.reduce((sum, session) => sum + toNumber(session.efficiency?.compact_failures, 0), 0),
      failed_command_rate: totalShellCommandCount > 0 ? Number((failedCommandCount / totalShellCommandCount).toFixed(4)) : 0,
      deferred_tool_tokens: sessions.reduce((sum, session) => sum + toNumber(session.efficiency?.deferred_tool_tokens, 0), 0),
    },
    external_observations: {
      codeburn_export: codeburnObservations || {
        by_activity: [],
        core_tools: [],
        shell_commands: [],
        mcp_servers: [],
        by_project: [],
      },
    },
  };
  dashboard.recommendations = buildRecommendations(dashboard);
  return dashboard;
}

function formatCost(value) {
  return typeof value === 'number' && Number.isFinite(value) ? `$${value.toFixed(2)}` : 'n/a';
}

function formatInt(value) {
  return String(Math.round(toNumber(value, 0)));
}

function generateCostDashboardReport(dashboard) {
  const lines = [
    '# Canuto Cost Dashboard',
    '',
    `- Generated at: ${dashboard.generated_at}`,
    `- Estimated cost: ${formatCost(dashboard.totals.estimated_cost_usd)}`,
    `- Total tokens: ${formatInt(dashboard.totals.total_tokens)}`,
    `- Sessions: ${dashboard.totals.sessions}`,
    `- Providers: ${dashboard.totals.providers.join(', ') || 'n/a'}`,
    `- Sources used: ${dashboard.sources_used.join(', ') || 'n/a'}`,
    `- Missing sources: ${dashboard.missing_sources.join(', ') || 'none'}`,
    '',
    '## By Project',
    '',
    '| Project | Cost | Sessions | Tokens | Avg/session | Top provider |',
    '| --- | ---: | ---: | ---: | ---: | --- |',
  ];

  for (const item of dashboard.rankings.by_project.slice(0, 20)) {
    lines.push(`| \`${item.project_key}\` | ${formatCost(item.estimated_cost_usd)} | ${item.sessions} | ${formatInt(item.total_tokens)} | ${formatCost(item.avg_cost_per_session_usd)} | ${item.top_provider || 'n/a'} |`);
  }

  lines.push('', '## By Provider/Model', '', '| Provider | Model | Cost | Tokens | Calls | Cache hit |', '| --- | --- | ---: | ---: | ---: | ---: |');
  for (const item of dashboard.rankings.by_provider_model.slice(0, 20)) {
    lines.push(`| ${item.provider} | \`${item.model}\` | ${formatCost(item.estimated_cost_usd)} | ${formatInt(item.token_usage.total_tokens)} | ${item.calls} | ${(item.cache_hit_rate * 100).toFixed(1)}% |`);
  }

  lines.push('', '## By Activity', '', '| Activity | Cost | Calls | One-shot estimate | Dominant tools |', '| --- | ---: | ---: | ---: | --- |');
  for (const item of dashboard.rankings.by_activity) {
    const tools = item.dominant_tools.map((tool) => `${tool.name} (${tool.count})`).join(', ');
    lines.push(`| ${item.activity} | ${formatCost(item.estimated_cost_usd)} | ${item.calls} | ${item.one_shot_rate === null ? 'n/a' : `${(item.one_shot_rate * 100).toFixed(0)}%`} | ${tools || 'n/a'} |`);
  }

  lines.push('', '## Core Tools', '', '| Tool | Calls | Cost share |', '| --- | ---: | ---: |');
  for (const item of dashboard.rankings.core_tools.slice(0, 20)) {
    lines.push(`| \`${item.name}\` | ${item.count} | ${formatCost(item.estimated_cost_usd)} |`);
  }

  lines.push('', '## Shell Commands', '', '| Command | Calls | Cost share |', '| --- | ---: | ---: |');
  for (const item of dashboard.rankings.shell_commands.slice(0, 20)) {
    lines.push(`| \`${item.name}\` | ${item.count} | ${formatCost(item.estimated_cost_usd)} |`);
  }

  lines.push('', '## MCP Servers', '', '| Server | Calls | Cost share |', '| --- | ---: | ---: |');
  for (const item of dashboard.rankings.mcp_servers.slice(0, 20)) {
    lines.push(`| \`${item.name}\` | ${item.count} | ${formatCost(item.estimated_cost_usd)} |`);
  }

  lines.push(
    '',
    '## Efficiency Signals',
    '',
    `- Cache hit rate: ${(dashboard.efficiency_signals.cache_hit_rate * 100).toFixed(1)}%`,
    `- Prompt-too-long errors: ${dashboard.efficiency_signals.prompt_too_long_errors}`,
    `- Compact failures: ${dashboard.efficiency_signals.compact_failures}`,
    `- Failed command rate: ${(dashboard.efficiency_signals.failed_command_rate * 100).toFixed(1)}%`,
    `- Deferred tool tokens: ${formatInt(dashboard.efficiency_signals.deferred_tool_tokens)}`,
    '',
    '## Recommendations',
    '',
  );
  for (const recommendation of dashboard.recommendations) {
    lines.push(`- ${recommendation}`);
  }

  if (dashboard.missing_pricing.length > 0) {
    lines.push('', '## Missing Pricing', '');
    for (const model of dashboard.missing_pricing) {
      lines.push(`- \`${model}\``);
    }
  }

  return `${lines.join('\n')}\n`;
}

function generateReport({ generatedAt, inventory, projectSummaries, rankings, options }) {
  const totalSessions = projectSummaries.reduce((sum, summary) => sum + summary.sessions_analyzed, 0);
  const compliantCount = projectSummaries.filter((summary) => summary.obsidian_status === 'compliant').length;
  const localCount = projectSummaries.filter((summary) => summary.obsidian_status === 'non_compliant_local').length;
  const missingCount = projectSummaries.filter((summary) => summary.obsidian_status === 'non_compliant_missing').length;
  const bucketCounts = rankings.bucket_counts || groupProjectsByBucket(projectSummaries);
  const bucketSortedSummaries = sortProjectSummariesByBucket(projectSummaries);

  const lines = [
    '# Canuto Cross-Project Session Audit',
    '',
    `- Generated at: ${generatedAt}`,
    `- Workspaces root: \`${options.workspacesRoot}\``,
    `- Vault root: \`${options.vaultRoot}\``,
    `- Codex log roots: ${options.codexLogRoots.map((root) => `\`${root}\``).join(', ')}`,
    `- Session limit per project: ${options.sessionLimit}`,
    `- Analysis mode: ${options.analysisMode}`,
    '- Note: Breakage and probable-match signals are heuristic; verify specific counts against source logs before acting.',
    '',
    '## Project buckets',
    '',
    '| Bucket | Count | Projects |',
    '|---|---:|---|',
  ];

  for (const item of bucketCounts) {
    lines.push(`| ${item.bucket} | ${item.count} | ${item.projects.join(', ') || 'n/a'} |`);
  }

  lines.push(
    '',
    '## Overview',
    '',
    `- Projects included: ${projectSummaries.length}`,
    `- Total sessions analyzed: ${totalSessions}`,
    `- Obsidian compliant: ${compliantCount}`,
    `- Obsidian non-compliant (local vault): ${localCount}`,
    `- Obsidian non-compliant (missing/global gap): ${missingCount}`,
    '',
    '## Rankings',
    '',
    '### Obsidian noncompliance',
    '',
  );

  if (rankings.obsidian_noncompliance.length === 0) {
    lines.push('- No non-compliant projects detected.');
  } else {
    for (const item of rankings.obsidian_noncompliance) {
      lines.push(`- \`${item.project_key}\` — ${item.obsidian_status}`);
    }
  }

  lines.push('', '### Low skill adoption', '');
  if (rankings.low_skill_adoption.length === 0) {
    lines.push('- No project crossed the skill-gap threshold.');
  } else {
    for (const item of rankings.low_skill_adoption) {
      const skills = item.top_skills_missed.map((skill) => `${skill.skill_id} (${skill.count})`).join(', ');
      lines.push(`- \`${item.project_key}\` — ${item.skill_status}${skills ? ` — ${skills}` : ''}`);
    }
  }

  lines.push('', '### Operational breakage', '');
  if (rankings.operational_breakage.length === 0) {
    lines.push('- No major operational breakage detected.');
  } else {
    for (const item of rankings.operational_breakage) {
      lines.push(`- \`${item.project_key}\` — framework=${item.framework_health}, capture=${item.capture_health}`);
    }
  }

  lines.push('', '## Project Matrix', '', '| Project | Bucket | Sessions | Runtime | Obsidian | Capture | Skills | Framework |', '| --- | --- | ---: | --- | --- | --- | --- | --- |');
  for (const summary of bucketSortedSummaries) {
    const runtime = Object.entries(summary.runtime_mix)
      .map(([key, count]) => `${key}:${count}`)
      .join(', ');
    lines.push(
      `| \`${summary.project_key}\` | ${summary.bucket} | ${summary.sessions_analyzed}/${summary.sessions_available} | ${runtime || 'n/a'} | ${summary.obsidian_status} | ${summary.capture_health} | ${summary.skill_status} | ${summary.framework_health} |`,
    );
  }

  lines.push('', '## Project Details', '');

  for (const summary of bucketSortedSummaries) {
    lines.push(`### ${summary.project_key}`, '');
    lines.push(`- Bucket: ${summary.bucket}`);
    lines.push(`- Last session age days: ${summary.last_session_age_days === null ? 'n/a' : summary.last_session_age_days}`);
    lines.push(`- Pending-sync orphan ratio: ${summary.pending_sync_orphan_ratio}`);
    lines.push(`- Sessions available/analyzed: ${summary.sessions_available}/${summary.sessions_analyzed}`);
    lines.push(`- Runtime mix: ${Object.entries(summary.runtime_mix).map(([key, count]) => `${key}:${count}`).join(', ') || 'n/a'}`);
    lines.push(`- Obsidian: ${summary.obsidian_status}`);
    lines.push(`- Capture: ${summary.capture_health}`);
    lines.push(`- Skills: ${summary.skill_status}`);
    lines.push(`- Framework: ${summary.framework_health}`);
    lines.push('');
    lines.push('Top findings:');
    if (summary.top_findings.length === 0) {
      lines.push('- None');
    } else {
      for (const finding of summary.top_findings) {
        lines.push(`- [${finding.severity}] ${finding.category}: ${finding.message}`);
      }
    }
    lines.push('');
    lines.push('Top skills missed:');
    if (summary.top_skills_missed.length === 0) {
      lines.push('- None');
    } else {
      for (const item of summary.top_skills_missed.slice(0, 5)) {
        lines.push(`- ${item.skill_id} (${item.count})`);
      }
    }
    lines.push('');
    lines.push('Top breakages:');
    if (summary.top_breakages.length === 0) {
      lines.push('- None');
    } else {
      for (const item of summary.top_breakages.slice(0, 5)) {
        lines.push(`- ${item.label} (${item.count})`);
      }
    }
    lines.push('');
    lines.push('Recommended actions:');
    if (summary.recommended_actions.length === 0) {
      lines.push('- None');
    } else {
      for (const action of summary.recommended_actions) {
        lines.push(`- ${action.priority}: ${action.message}`);
      }
    }
    lines.push('');
    lines.push('Evidence:');
    if (summary.evidence_refs.length === 0) {
      lines.push('- None');
    } else {
      for (const ref of summary.evidence_refs.slice(0, 10)) {
        lines.push(`- \`${ref}\``);
      }
    }
    lines.push('');
  }

  return `${lines.join('\n')}\n`;
}

function validateProjectSummary(summary) {
  const requiredFields = [
    'project_key',
    'sessions_available',
    'sessions_analyzed',
    'bucket',
    'last_session_age_days',
    'pending_sync_orphan_ratio',
    'runtime_mix',
    'obsidian_status',
    'capture_health',
    'skill_status',
    'framework_health',
    'top_findings',
    'top_skills_missed',
    'top_breakages',
    'recommended_actions',
    'evidence_refs',
  ];
  return requiredFields.every((field) => Object.prototype.hasOwnProperty.call(summary, field));
}

function runCodexReviewerAnalysis(packet, options) {
  const codexPath = spawnSync('bash', ['-lc', 'command -v codex'], { encoding: 'utf8' }).stdout.trim();
  if (!codexPath) {
    return null;
  }

  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'framework-session-audit-'));
  const outputPath = path.join(tempDir, 'summary.json');
  const prompt = [
    'You are auditing one project in the Canuto framework.',
    'Return JSON only.',
    'Schema:',
    JSON.stringify({
      project_key: 'string',
      sessions_available: 0,
      sessions_analyzed: 0,
      bucket: 'never-installed|dormant|pre-v1.8|v1.8-failing|healthy',
      last_session_age_days: 0,
      pending_sync_orphan_ratio: 0,
      runtime_mix: {},
      obsidian_status: 'compliant|non_compliant_local|non_compliant_missing',
      capture_health: 'healthy|partial|failing|unknown',
      skill_status: 'healthy|partial|failing|unknown',
      framework_health: 'healthy|partial|failing|unknown',
      top_findings: [],
      top_skills_missed: [],
      top_breakages: [],
      recommended_actions: [],
      evidence_refs: [],
    }),
    '',
    JSON.stringify(packet, null, 2),
  ].join('\n');

  try {
    execFileSync(
      codexPath,
      [
        'exec',
        '--skip-git-repo-check',
        '--profile',
        'reviewer',
        '-s',
        'read-only',
        '--ephemeral',
        '--output-last-message',
        outputPath,
        '-',
      ],
      {
        input: prompt,
        encoding: 'utf8',
        maxBuffer: 16 * 1024 * 1024,
        stdio: ['pipe', 'ignore', 'ignore'],
      },
    );
    const raw = readTextIfExists(outputPath).trim();
    const parsed = JSON.parse(raw);
    return validateProjectSummary(parsed) ? parsed : null;
  } catch {
    return null;
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

async function mapWithConcurrency(items, concurrency, worker) {
  const results = new Array(items.length);
  let nextIndex = 0;

  async function runOne() {
    while (true) {
      const currentIndex = nextIndex;
      nextIndex += 1;
      if (currentIndex >= items.length) return;
      results[currentIndex] = await worker(items[currentIndex], currentIndex);
    }
  }

  const runners = Array.from({ length: Math.max(1, concurrency) }, () => runOne());
  await Promise.all(runners);
  return results;
}

async function runAudit(options) {
  const generatedAt = new Date().toISOString();
  const inventory = buildInventory({
    workspacesRoot: options.workspacesRoot,
    vaultRoot: options.vaultRoot,
  });

  const workspaceProjects = inventory.projects.filter((project) => project.workspace_path);
  const pricingIndex = loadPricingIndex(options.pricingPath);
  const claudeTelemetry = collectClaudeTelemetry(options.claudeTelemetryRoot);
  const claudeProjectLogs = collectClaudeProjectRecords(
    options.claudeProjectsRoot,
    workspaceProjects,
    pricingIndex,
    claudeTelemetry.bySession,
  );
  const codeburnExport = loadCodeburnExport(options.codeburnExport);
  const codexLogMetas = collectCodexLogMetas(options.codexLogRoots)
    .map((meta) => {
      const project = mapCodexLogToProject(meta, workspaceProjects);
      return project ? { ...meta, project_key: project.project_key } : null;
    })
    .filter(Boolean);

  const analyzedProjects = await mapWithConcurrency(inventory.projects, options.parallelism, async (project) => {
    const sessions = collectProjectSessions(project, codexLogMetas, options.sessionLimit, {
      pricingIndex,
      claudeRecords: claudeProjectLogs.records,
    });
    const summary = buildProjectSummary(project, sessions, options.sessionLimit, generatedAt);

    if (options.analysisMode === 'codex-reviewer') {
      const packet = {
        inventory: {
          project_key: project.project_key,
          project_slug: project.project_slug,
          workspace_path: project.workspace_path,
          workspace_root: project.workspace_root,
          backend_kind: project.backend_kind,
          global_vault_path: project.global_vault_path,
          local_vault_path: project.local_vault_path,
          memory_script_present: project.memory_script_present,
          session_save_hook_present: project.session_save_hook_present,
          session_capture_present: project.session_capture_present,
          health_check_tool_present: project.health_check_tool_present,
          obsidian_healthcheck_present: project.obsidian_healthcheck_present,
          framework_version_signals: project.framework_version_signals,
          slug_collision: project.slug_collision,
        },
        sessions: summary.sessions,
      };
      const reviewed = runCodexReviewerAnalysis(packet, options);
      if (reviewed && validateProjectSummary(reviewed)) {
        return {
          ...reviewed,
          bucket: summary.bucket,
          last_session_age_days: summary.last_session_age_days,
          pending_sync_orphan_ratio: summary.pending_sync_orphan_ratio,
          session_save_hook_present: summary.session_save_hook_present,
          session_capture_present: summary.session_capture_present,
          health_check_tool_present: summary.health_check_tool_present,
          obsidian_healthcheck_present: summary.obsidian_healthcheck_present,
          cost_summary: summary.cost_summary,
          token_totals: summary.token_totals,
          top_tools: summary.top_tools,
          top_shell_commands: summary.top_shell_commands,
          top_mcp_servers: summary.top_mcp_servers,
          activity_breakdown: summary.activity_breakdown,
          missing_pricing: summary.missing_pricing,
          sessions: summary.sessions,
        };
      }
    }

    return summary;
  });

  const projectSummaries = analyzedProjects
    .filter((summary) => validateProjectSummary(summary))
    .sort((left, right) => left.project_key.localeCompare(right.project_key));
  const rankings = rankProjects(projectSummaries);
  const report = generateReport({
    generatedAt,
    inventory,
    projectSummaries,
    rankings,
    options,
  });
  const costDashboard = buildCostDashboard({
    generatedAt,
    projectSummaries,
    options,
    sourceHealth: {
      codex_logs: {
        paths: options.codexLogRoots,
        available: codexLogMetas.length > 0,
        sessions_mapped: codexLogMetas.length,
        error: codexLogMetas.length > 0 ? '' : 'no-mapped-sessions',
      },
      claude_projects: claudeProjectLogs.health,
      claude_telemetry: claudeTelemetry.health,
      pricing: pricingIndex.info,
      codeburn_export: codeburnExport.health,
    },
    codeburnObservations: codeburnExport.observations,
  });

  return {
    generated_at: generatedAt,
    inventory,
    project_summaries: projectSummaries,
    rankings,
    report,
    cost_dashboard: costDashboard,
    cost_dashboard_report: generateCostDashboardReport(costDashboard),
  };
}

function defaultOutputDir(cwd = process.cwd()) {
  const stamp = new Date().toISOString().slice(0, 10).replace(/-/g, '');
  return path.join(cwd, '.context', 'audits', `canuto-session-audit-${stamp}`);
}

function parseArgs(argv, cwd = process.cwd()) {
  const args = {
    workspacesRoot: '/Users/rodrigooliveira/conductor/workspaces',
    vaultRoot: '~/.canuto/vault/projects',
    codexLogRoots: ['~/.codex/sessions', '~/.codex/archived_sessions'],
    claudeProjectsRoot: DEFAULT_CLAUDE_PROJECTS_ROOT,
    claudeTelemetryRoot: DEFAULT_CLAUDE_TELEMETRY_ROOT,
    pricingPath: DEFAULT_PRICING_PATH,
    codeburnExport: '',
    sessionLimit: DEFAULT_SESSION_LIMIT,
    parallelism: DEFAULT_PARALLELISM,
    analysisMode: DEFAULT_ANALYSIS_MODE,
    outputDir: defaultOutputDir(cwd),
  };

  for (let index = 0; index < argv.length; index += 1) {
    const key = argv[index];
    const next = argv[index + 1];
    if (!key.startsWith('--')) continue;

    switch (key) {
      case '--workspaces-root':
        args.workspacesRoot = next;
        index += 1;
        break;
      case '--vault-root':
        args.vaultRoot = next;
        index += 1;
        break;
      case '--codex-log-roots':
        args.codexLogRoots = [];
        while (argv[index + 1] && !argv[index + 1].startsWith('--')) {
          args.codexLogRoots.push(argv[index + 1]);
          index += 1;
        }
        break;
      case '--claude-projects-root':
        args.claudeProjectsRoot = next;
        index += 1;
        break;
      case '--claude-telemetry-root':
        args.claudeTelemetryRoot = next;
        index += 1;
        break;
      case '--pricing-path':
        args.pricingPath = next;
        index += 1;
        break;
      case '--codeburn-export':
        args.codeburnExport = next;
        index += 1;
        break;
      case '--session-limit':
        args.sessionLimit = Number(next);
        index += 1;
        break;
      case '--parallelism':
        args.parallelism = Number(next);
        index += 1;
        break;
      case '--output-dir':
        args.outputDir = next;
        index += 1;
        break;
      case '--analysis-mode':
        args.analysisMode = next;
        index += 1;
        break;
      default:
        break;
    }
  }

  return {
    workspacesRoot: resolvePath(args.workspacesRoot, cwd),
    vaultRoot: resolvePath(args.vaultRoot, cwd),
    codexLogRoots: args.codexLogRoots.map((item) => resolvePath(item, cwd)),
    claudeProjectsRoot: resolvePath(args.claudeProjectsRoot, cwd),
    claudeTelemetryRoot: resolvePath(args.claudeTelemetryRoot, cwd),
    pricingPath: resolvePath(args.pricingPath, cwd),
    codeburnExport: args.codeburnExport ? resolvePath(args.codeburnExport, cwd) : '',
    sessionLimit: Number.isFinite(args.sessionLimit) && args.sessionLimit > 0 ? args.sessionLimit : DEFAULT_SESSION_LIMIT,
    parallelism: Number.isFinite(args.parallelism) && args.parallelism > 0 ? args.parallelism : DEFAULT_PARALLELISM,
    analysisMode: ['deterministic', 'codex-reviewer'].includes(args.analysisMode) ? args.analysisMode : DEFAULT_ANALYSIS_MODE,
    outputDir: resolvePath(args.outputDir, cwd),
  };
}

function writeAuditOutputs(outputDir, result) {
  ensureDir(outputDir);

  writeJson(path.join(outputDir, '00-inventory.json'), {
    generated_at: result.generated_at,
    projects: result.inventory.projects.map((project) => ({
      project_key: project.project_key,
      project_slug: project.project_slug,
      workspace_path: project.workspace_path,
      workspace_root: project.workspace_root,
      backend_kind: project.backend_kind,
      global_vault_path: project.global_vault_path,
      local_vault_path: project.local_vault_path,
      memory_script_present: project.memory_script_present,
      session_save_hook_present: project.session_save_hook_present,
      session_capture_present: project.session_capture_present,
      health_check_tool_present: project.health_check_tool_present,
      obsidian_healthcheck_present: project.obsidian_healthcheck_present,
      framework_version_signals: project.framework_version_signals,
      excluded_reason: project.excluded_reason,
      slug_collision: project.slug_collision,
      collision_group: project.collision_group,
    })),
    excluded: result.inventory.excluded,
  });

  const ndjson = result.project_summaries
    .flatMap((summary) =>
      summary.sessions.map((session) =>
        JSON.stringify({
          project_key: session.project_key,
          bucket: summary.bucket,
          last_session_age_days: summary.last_session_age_days,
          pending_sync_orphan_ratio: summary.pending_sync_orphan_ratio,
          session_id: session.session_id,
          runtime: session.runtime,
          timestamp: session.timestamp,
          source_kind: session.source_kind,
          source_path: session.source_path,
          source_log_path: session.source_log_path,
          vault_scope: session.vault_scope,
          captured_to_vault: session.captured_to_vault,
          fallback_used: session.fallback_used,
          health_reason: session.health_reason,
          offline_sync: session.offline_sync,
          pending_sync: session.pending_sync,
          review_fix_cycles: session.review_fix_cycles,
          tasks_completed: session.tasks_completed,
          tests_run: session.tests_run,
          pending_count: session.pending_count,
          summary: session.summary,
          what_was_done: session.what_was_done,
          validation: session.validation,
          learnings: session.learnings,
          skill_reads: session.skill_reads,
          skill_breakages: session.skill_breakages,
          probable_skill_matches: session.probable_skill_matches,
          evidence_refs: session.evidence_refs,
          provider: session.provider,
          model: session.model,
          token_usage: session.token_usage,
          estimated_cost_usd: session.estimated_cost_usd,
          cost_source: session.cost_source,
          missing_pricing: session.missing_pricing,
          tool_calls: session.tool_calls,
          shell_commands: session.shell_commands,
          mcp_calls: session.mcp_calls,
          activity_breakdown: session.activity_breakdown,
          one_shot_estimate: session.one_shot_estimate,
        }),
      ),
    )
    .join('\n');
  writeText(path.join(outputDir, '01-sessions.ndjson'), ndjson ? `${ndjson}\n` : '');

  writeJson(path.join(outputDir, '02-project-summaries.json'), {
    generated_at: result.generated_at,
    rankings: result.rankings,
    projects: result.project_summaries.map((summary) => ({
      project_key: summary.project_key,
      project_slug: summary.project_slug,
      sessions_available: summary.sessions_available,
      sessions_analyzed: summary.sessions_analyzed,
      session_save_hook_present: summary.session_save_hook_present,
      session_capture_present: summary.session_capture_present,
      health_check_tool_present: summary.health_check_tool_present,
      obsidian_healthcheck_present: summary.obsidian_healthcheck_present,
      bucket: summary.bucket,
      last_session_age_days: summary.last_session_age_days,
      pending_sync_orphan_ratio: summary.pending_sync_orphan_ratio,
      runtime_mix: summary.runtime_mix,
      obsidian_status: summary.obsidian_status,
      capture_health: summary.capture_health,
      skill_status: summary.skill_status,
      framework_health: summary.framework_health,
      top_findings: summary.top_findings,
      top_skills_missed: summary.top_skills_missed,
      top_breakages: summary.top_breakages,
      recommended_actions: summary.recommended_actions,
      evidence_refs: summary.evidence_refs,
      skill_catalog_count: summary.skill_catalog_count,
      cost_summary: summary.cost_summary,
      token_totals: summary.token_totals,
      top_tools: summary.top_tools,
      top_shell_commands: summary.top_shell_commands,
      top_mcp_servers: summary.top_mcp_servers,
      activity_breakdown: summary.activity_breakdown,
    })),
  });

  writeText(path.join(outputDir, '03-report.md'), result.report);
  writeJson(path.join(outputDir, '04-cost-dashboard.json'), result.cost_dashboard || {});
  writeText(path.join(outputDir, '04-cost-dashboard.md'), result.cost_dashboard_report || '');
}

module.exports = {
  DEFAULT_CLAUDE_PROJECTS_ROOT,
  DEFAULT_CLAUDE_TELEMETRY_ROOT,
  DEFAULT_PRICING_PATH,
  DEFAULT_ANALYSIS_MODE,
  DEFAULT_PARALLELISM,
  DEFAULT_SESSION_LIMIT,
  buildCostDashboard,
  buildInventory,
  buildProjectSummary,
  cleanUserMessage,
  collectClaudeProjectRecords,
  collectClaudeTelemetry,
  collectCodexLogMetas,
  collectProjectSessions,
  detectSkillBreakages,
  detectProbableSkillMatches,
  emitCanutoOtlpMetrics,
  generateCostDashboardReport,
  generateReport,
  parseArgs,
  parseClaudeProjectLogRecord,
  parseCodexLogMeta,
  parseCodexLogRecord,
  parseFrontmatter,
  parseSessionSections,
  runAudit,
  sessionMergeKey,
  writeAuditOutputs,
};
