const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { EventEmitter } = require('node:events');
const { execFileSync, spawn, spawnSync } = require('node:child_process');
const test = require('node:test');

const gardener = require('./canuto-skill-gardener-lib');
const cli = require('./canuto-skill-gardener');

function tempDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'skill-gardener-test-'));
}

function writeFile(filePath, content, mode) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, content);
  if (mode) fs.chmodSync(filePath, mode);
}

function isolatedEnv(home, crontab) {
  const config = path.join(__dirname, '..', 'config', 'skill-gardener.json');
  return {
    ...process.env,
    HOME: home,
    CANUTO_INSTALL_TEST_ISOLATED_HOME: home,
    CANUTO_SKILL_GARDENER_SOURCE_DIR: __dirname,
    CANUTO_SKILL_GARDENER_CONFIG_SOURCE: config,
    CANUTO_SKILL_GARDENER_CONFIG: config,
    CANUTO_SKILL_GARDENER_CRONTAB_FILE: crontab,
  };
}

function emptyProviderConfig() {
  return {
    codex: { roots: [], pluginRoots: [], historyRoots: [] },
    claude: { roots: [], pluginRoots: [], historyRoots: [] },
    hermes: { roots: [], pluginRoots: [], historyRoots: [] },
    opencode: { roots: [], pluginRoots: [], historyRoots: [] },
  };
}

function completeCoverage(now) {
  return [{
    start: new Date(Date.parse(now) - 120 * 86400000).toISOString(),
    end: now,
    status: 'COMPLETE',
  }];
}

function usageEvent(skillKey, timestamp) {
  return { kind: 'verified_usage', schemaVersion: 1, eventKey: `${skillKey.slice(0, 63)}0`, skillKey, timestamp, verification: 'native_skill_event' };
}

test('normalizes a skill identity without retaining its source path', () => {
  const skill = gardener.makeSkillIdentity({
    name: 'Audit Trail',
    content: '# Audit Trail\n',
    provider: 'codex',
    installationKind: 'global',
    sourcePath: '/private/sensitive/session/path/SKILL.md',
  });

  assert.equal(skill.name, 'audit-trail');
  assert.match(skill.contentHash, /^[a-f0-9]{64}$/);
  assert.match(skill.skillKey, /^[a-f0-9]{64}$/);
  assert.equal(Object.hasOwn(skill, 'sourcePath'), false);
  assert.equal(Object.hasOwn(skill, '_sourcePath'), false);
});

test('generated HMAC keys are persisted with stable restricted permissions', () => {
  const root = tempDir();
  const stateDir = path.join(root, 'state');
  const hmacKeyPath = path.join(stateDir, 'hmac.key');
  const previousKey = process.env.CANUTO_SKILL_GARDENER_HMAC_KEY;
  delete process.env.CANUTO_SKILL_GARDENER_HMAC_KEY;
  try {
    const first = gardener.getRuntimeOptions({ home: root, stateDir, hmacKeyPath });
    const second = gardener.getRuntimeOptions({ home: root, stateDir, hmacKeyPath });
    assert.match(first.hmacKey, /^[a-f0-9]{64}$/);
    assert.equal(fs.readFileSync(hmacKeyPath, 'utf8').trim(), first.hmacKey);
    assert.equal(second.hmacKey, first.hmacKey);
    if (process.platform !== 'win32') assert.equal(fs.statSync(hmacKeyPath).mode & 0o777, 0o600);
  } finally {
    if (previousKey === undefined) delete process.env.CANUTO_SKILL_GARDENER_HMAC_KEY;
    else process.env.CANUTO_SKILL_GARDENER_HMAC_KEY = previousKey;
  }
});

test('competing HMAC initialization callers converge on one key without temporary targets', async () => {
  const root = tempDir();
  const home = path.join(root, 'home');
  const stateDir = path.join(root, 'state');
  const hmacKeyPath = path.join(stateDir, 'hmac.key');
  const readyDir = path.join(root, 'ready');
  const releasePath = path.join(root, 'release');
  const workerPath = path.join(root, 'hmac-worker.js');
  fs.mkdirSync(readyDir, { recursive: true });
  writeFile(workerPath, `
const fs = require('node:fs');
const path = require('node:path');
const keyPath = path.resolve(process.argv[2]);
const readyDir = process.argv[3];
const releasePath = process.argv[4];
const libraryPath = process.argv[5];
const home = process.argv[6];
const stateDir = process.argv[7];
const originalOpenSync = fs.openSync;
let gated = false;
fs.openSync = function openSync(file, ...args) {
  if (!gated && typeof file === 'string' && path.resolve(file) === keyPath) {
    gated = true;
    fs.writeFileSync(path.join(readyDir, 'ready-' + process.pid), 'ready', { flag: 'wx' });
    const cell = new Int32Array(new SharedArrayBuffer(4));
    while (!fs.existsSync(releasePath)) Atomics.wait(cell, 0, 0, 10);
  }
  return originalOpenSync.call(fs, file, ...args);
};
const gardener = require(libraryPath);
const runtime = gardener.getRuntimeOptions({ home, stateDir, hmacKeyPath: keyPath });
process.stdout.write(runtime.hmacKey);
`, 0o600);

  const startWorker = () => new Promise((resolve) => {
    const child = spawn(process.execPath, [workerPath, hmacKeyPath, readyDir, releasePath, path.join(__dirname, 'canuto-skill-gardener-lib.js'), home, stateDir], {
      env: Object.fromEntries(Object.entries(process.env).filter(([key]) => key !== 'CANUTO_SKILL_GARDENER_HMAC_KEY')),
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk) => { stdout += chunk; });
    child.stderr.on('data', (chunk) => { stderr += chunk; });
    child.on('close', (status) => resolve({ child, status, stdout, stderr }));
  });
  const workers = [startWorker(), startWorker()];
  const waitCell = new Int32Array(new SharedArrayBuffer(4));
  try {
    const deadline = Date.now() + 5000;
    while (fs.readdirSync(readyDir).filter((name) => name.startsWith('ready-')).length < 2) {
      if (Date.now() >= deadline) throw new Error('HMAC workers did not reach the initialization barrier');
      Atomics.wait(waitCell, 0, 0, 10);
    }
    writeFile(releasePath, 'go');
    const results = await Promise.all(workers);
    for (const result of results) assert.equal(result.status, 0, result.stderr);
    assert.equal(results[0].stdout, results[1].stdout);
    assert.equal(fs.readFileSync(hmacKeyPath, 'utf8').trim(), results[0].stdout);
    assert.deepEqual(fs.readdirSync(stateDir).filter((name) => name.startsWith('hmac.key.tmp-')), []);
  } finally {
    writeFile(releasePath, 'go');
  }
});

test('invalid and unreadable on-disk HMAC key targets fail closed', () => {
  const root = tempDir();
  const invalidKeyPath = path.join(root, 'invalid', 'hmac.key');
  writeFile(invalidKeyPath, 'not-a-key\n');
  assert.throws(() => gardener.getRuntimeOptions({ home: root, stateDir: path.join(root, 'invalid-state'), hmacKeyPath: invalidKeyPath }), { message: 'invalid-hmac-key' });

  const blockingFile = path.join(root, 'not-a-directory');
  writeFile(blockingFile, 'block');
  assert.throws(() => gardener.getRuntimeOptions({ home: root, hmacKeyPath: path.join(blockingFile, 'hmac.key') }), { message: 'hmac-key-read-failed' });
});

test('parses Codex, Claude and Hermes fixtures into verified usage and candidate signals', () => {
  const audit = gardener.makeSkillIdentity({ name: 'audit', content: '# audit\n', hmacKey: 'fixture-key' });
  const catalog = {
    _byPath: new Map([
      [path.resolve(os.homedir(), '.codex/skills/audit/SKILL.md'), audit],
      [path.resolve(os.homedir(), '.claude/skills/audit/SKILL.md'), audit],
      [path.resolve(os.homedir(), '.hermes/skills/audit/SKILL.md'), audit],
    ]),
    _byName: new Map([['audit', new Set([audit.skillKey])]]),
  };
  for (const provider of ['codex', 'claude', 'hermes']) {
    const text = fs.readFileSync(path.join(__dirname, 'fixtures', `${provider}.jsonl`), 'utf8');
    const result = gardener[`parse${provider[0].toUpperCase()}${provider.slice(1)}Events`]({
      text,
      catalog,
      hmacKey: 'fixture-key',
      surfaceAlias: 'fixture',
      fallbackTimestamp: '2026-08-01T00:00:00.000Z',
    });
    assert.equal(result.ok, true);
    assert.equal(result.events.some((event) => event.kind === 'verified_usage' && event.skillKey === audit.skillKey), true);
    assert.equal(result.events.some((event) => event.kind === 'candidate_signal'), true);
    assert.equal(JSON.stringify(result.events).includes('incubating-example'), false);
  }
});

test('accepts valid JSONL records above 64 KiB and rejects records above the bounded maximum', () => {
  const accepted = JSON.stringify({
    event: 'Skill',
    skill: 'audit',
    event_id: 'large-valid-line',
    timestamp: '2026-08-03T03:00:00.000Z',
    detail: 'x'.repeat(70 * 1024),
  });
  const acceptedResult = gardener.parseCodexEvents({ text: `${accepted}\n`, hmacKey: 'large-line-key' });
  assert.equal(acceptedResult.ok, true);
  assert.equal(acceptedResult.events.length, 1);

  const oversizedResult = gardener.parseCodexEvents({ text: `${'x'.repeat(gardener.MAX_LINE_BYTES + 1)}\n`, hmacKey: 'large-line-key' });
  assert.equal(oversizedResult.ok, false);
  assert.equal(oversizedResult.reason, 'line-overflow');
});

test('parses Hermes JSON session documents with inherited session context and accepts empty message histories', () => {
  const home = tempDir();
  const skillPath = path.join(home, '.hermes', 'skills', 'audit', 'SKILL.md');
  const audit = gardener.makeSkillIdentity({ name: 'audit', content: '# audit\n', hmacKey: 'hermes-document-key' });
  const catalog = {
    _byPath: new Map([[path.resolve(skillPath), audit]]),
    _byName: new Map([['audit', new Set([audit.skillKey])]]),
  };
  const document = JSON.stringify({
    session_id: 'hermes-document-session',
    cwd: home,
    created_at: '2026-08-03T03:00:00.000Z',
    messages: [
      { role: 'assistant', timestamp: '2026-08-03T03:01:00.000Z', content: [{ type: 'tool_use', id: 'hermes-read-1', name: 'Read', input: { file_path: skillPath } }] },
      { role: 'tool', timestamp: '2026-08-03T03:01:01.000Z', content: [{ type: 'tool_result', tool_use_id: 'hermes-read-1', content: '# audit', is_error: false }] },
    ],
  });
  const parsed = gardener.parseHermesEvents({ text: document, catalog, home, hmacKey: 'hermes-document-key' });
  assert.equal(parsed.ok, true);
  assert.equal(parsed.events.filter((event) => event.kind === 'verified_usage' && event.skillKey === audit.skillKey).length, 1);
  assert.equal(parsed.events[0].timestamp, '2026-08-03T03:01:01.000Z');

  const historical = gardener.parseHermesEvents({
    text: JSON.stringify({
      session_id: 'hermes-historical-session',
      session_start: '2026-07-01T03:00:00.000Z',
      last_updated: '2026-08-20T03:00:00.000Z',
      cwd: home,
      messages: [
        { role: 'assistant', content: [{ type: 'tool_use', id: 'hermes-historical-read', name: 'Read', input: { file_path: skillPath } }] },
        { role: 'tool', content: [{ type: 'tool_result', tool_use_id: 'hermes-historical-read', content: '# audit', is_error: false }] },
      ],
    }),
    catalog,
    home,
    hmacKey: 'hermes-document-key',
    fallbackTimestamp: '2026-08-22T00:00:00.000Z',
  });
  assert.equal(historical.events.filter((event) => event.kind === 'verified_usage' && event.skillKey === audit.skillKey).length, 1);
  assert.equal(historical.events[0].timestamp, '2026-07-01T03:00:00.000Z');

  const empty = gardener.parseHermesEvents({
    text: JSON.stringify({ session_id: 'hermes-empty-session', messages: [{ role: 'user', content: 'nothing to inspect' }] }),
    catalog,
    home,
    hmacKey: 'hermes-document-key',
  });
  assert.deepEqual(empty, { ok: true, events: [] });

  for (const [timestampField, timestamp] of [
    ['session_start', '2026-08-03T04:00:00.000Z'],
    ['last_updated', '2026-08-03T05:00:00.000Z'],
  ]) {
    const inherited = gardener.parseHermesEvents({
      text: JSON.stringify({
        session_id: `hermes-${timestampField}`,
        cwd: home,
        [timestampField]: timestamp,
        messages: [
          { role: 'assistant', content: [{ type: 'tool_use', id: `read-${timestampField}`, name: 'Read', input: { file_path: skillPath } }] },
          { role: 'tool', content: [{ type: 'tool_result', tool_use_id: `read-${timestampField}`, content: '# audit', is_error: false }] },
        ],
      }),
      catalog,
      home,
      hmacKey: 'hermes-document-key',
    });
    assert.equal(inherited.ok, true);
    assert.equal(inherited.events[0].timestamp, timestamp);
  }
});

test('maps global real sessions by cwd before deduplication and leaves unknown sessions UNMAPPED', async () => {
  const root = tempDir();
  const home = path.join(root, 'home');
  const projectA = path.join(root, 'projects', 'alpha');
  const projectB = path.join(root, 'projects', 'beta');
  const history = path.join(root, 'global-history');
  const skills = path.join(home, '.codex', 'skills');
  const eventLog = path.join(root, 'event-log.sh');
  writeFile(path.join(skills, 'audit', 'SKILL.md'), '# audit\n');
  const session = (id, cwd, eventId) => [
    JSON.stringify({ type: 'session_meta', payload: { id, timestamp: '2026-08-20T00:00:00.000Z', cwd } }),
    JSON.stringify({ type: 'event_msg', payload: { type: 'Skill', skill: 'audit', event_id: eventId, timestamp: '2026-08-20T00:01:00.000Z' } }),
  ].join('\n') + '\n';
  writeFile(path.join(history, 'alpha.jsonl'), session('alpha-session', projectA, 'alpha-read'));
  writeFile(path.join(history, 'beta.jsonl'), session('beta-session', projectB, 'beta-read'));
  writeFile(path.join(history, 'unknown.jsonl'), JSON.stringify({ event: 'Skill', skill: 'audit', event_id: 'unknown-read', timestamp: '2026-08-20T00:03:00.000Z' }) + '\n');
  writeFile(eventLog, '#!/bin/sh\nexit 0\n', 0o755);
  const config = {
    projects: {
      alpha: { surfaces: { mac: { roots: [projectA], aliases: ['Alpha'], historyRoots: [] } } },
      beta: { surfaces: { mac: { roots: [projectB], aliases: ['Beta'], historyRoots: [] } } },
    },
    providers: { ...emptyProviderConfig(), codex: { roots: [skills], pluginRoots: [], historyRoots: [history] } },
  };
  const result = await gardener.runGardener('backfill', { home, config, vaultRoot: path.join(root, 'vault'), eventLogPath: eventLog, frameworkRoot: path.join(root, 'missing-framework'), now: '2026-08-21T00:00:00.000Z', hmacKey: 'mapping-key', runId: '20260821060000-2222222222' });
  assert.equal(result.exitCode, 0);
  const projectIds = result.report.verifiedUsage.events.map((event) => event.logicalProjectId);
  assert.equal(projectIds.includes('alpha'), true);
  assert.equal(projectIds.includes('beta'), true);
  assert.equal(projectIds.includes('UNMAPPED'), true);
  assert.equal(projectIds.filter((id) => id === 'alpha').length, 1);
  assert.equal(projectIds.filter((id) => id === 'beta').length, 1);
});

test('overlapping project and global histories use one mapped provider source and fail closed for coverage', async () => {
  const root = tempDir();
  const home = path.join(root, 'home');
  const projectA = path.join(root, 'projects', 'alpha');
  const projectB = path.join(root, 'projects', 'beta');
  const history = path.join(home, '.codex', 'sessions');
  const skills = path.join(home, '.codex', 'skills');
  const eventLog = path.join(root, 'event-log.sh');
  writeFile(path.join(projectA, '.agents', 'skills', 'audit', 'SKILL.md'), '# audit\n');
  writeFile(path.join(projectB, '.agents', 'skills', 'audit', 'SKILL.md'), '# audit\n');
  writeFile(path.join(skills, 'audit', 'SKILL.md'), '# audit\n');
  const session = (id, cwd, eventId) => [
    JSON.stringify({ type: 'session_meta', payload: { id, timestamp: '2026-08-20T00:00:00.000Z', cwd } }),
    JSON.stringify({ type: 'event_msg', payload: { type: 'Skill', skill: 'audit', event_id: eventId, timestamp: '2026-08-20T00:01:00.000Z' } }),
  ].join('\n') + '\n';
  writeFile(path.join(history, 'alpha.jsonl'), session('alpha-session', projectA, 'overlap-alpha-read'));
  writeFile(path.join(history, 'unknown.jsonl'), JSON.stringify({ event: 'Skill', skill: 'audit', event_id: 'overlap-unknown-read', timestamp: '2026-08-20T00:03:00.000Z' }) + '\n');
  writeFile(eventLog, '#!/bin/sh\nexit 0\n', 0o755);
  const config = {
    projects: {
      alpha: { surfaces: { mac: { provider: 'codex', roots: [projectA], aliases: ['Alpha'], historyRoots: [history] } } },
      beta: { surfaces: { mac: { provider: 'codex', roots: [projectB], aliases: ['Beta'], historyRoots: [history] } } },
    },
    providers: { ...emptyProviderConfig(), codex: { roots: [skills], pluginRoots: [], historyRoots: [history] } },
  };
  const result = await gardener.runGardener('backfill', { home, config, vaultRoot: path.join(root, 'vault'), eventLogPath: eventLog, frameworkRoot: path.join(root, 'missing-framework'), now: '2026-08-21T00:00:00.000Z', hmacKey: 'overlap-key', runId: '20260821060002-4444444444' });
  assert.equal(result.exitCode, 0);
  const projectIds = result.report.verifiedUsage.events.map((event) => event.logicalProjectId);
  assert.equal(projectIds.filter((id) => id === 'alpha').length, 1);
  assert.equal(projectIds.filter((id) => id === 'UNMAPPED').length, 1);
  assert.equal(projectIds.includes('beta'), false);
  const historySources = result.report.sources.filter((source) => source.provider === 'codex' && source.kind === 'history');
  assert.equal(historySources.length, 1);
  const projectCoverage = result.report.coverageScopes.filter((scope) => ['alpha', 'beta'].includes(scope.logicalProjectId));
  assert.equal(projectCoverage.length > 0, true);
  assert.equal(projectCoverage.every((scope) => scope.sourceComplete === false), true);
});

test('each local history file is consumed once without the shared audit full-file pass', async () => {
  const root = tempDir();
  const home = path.join(root, 'home');
  const skills = path.join(home, '.codex', 'skills');
  const history = path.join(root, 'history');
  const historyFile = path.join(history, 'session.jsonl');
  const eventLog = path.join(root, 'event-log.sh');
  writeFile(path.join(skills, 'audit', 'SKILL.md'), '# audit\n');
  writeFile(historyFile, `${JSON.stringify({ event: 'Skill', skill: 'audit', event_id: 'single-read', timestamp: '2026-08-20T00:01:00.000Z' })}\n`);
  writeFile(eventLog, '#!/bin/sh\nexit 0\n', 0o755);
  const config = { projects: {}, providers: { ...emptyProviderConfig(), codex: { roots: [skills], pluginRoots: [], historyRoots: [history] } } };
  const originalOpenSync = fs.openSync;
  const realHistoryFile = fs.realpathSync(historyFile);
  let historyReads = 0;
  fs.openSync = function countedOpen(file, ...args) {
    if (path.resolve(String(file)) === realHistoryFile) historyReads += 1;
    return originalOpenSync.call(fs, file, ...args);
  };
  let result;
  try {
    result = await gardener.runGardener('backfill', { home, config, vaultRoot: path.join(root, 'vault'), eventLogPath: eventLog, frameworkRoot: path.join(root, 'missing-framework'), now: '2026-08-21T00:00:00.000Z', hmacKey: 'single-read-key', runId: '20260821060003-5555555555' });
  } finally {
    fs.openSync = originalOpenSync;
  }
  assert.equal(result.exitCode, 0);
  assert.equal(historyReads, 1);
});

test('remote sources deduplicate by alias/provider/history root and map only matched remote sessions', () => {
  const root = tempDir();
  const home = path.join(root, 'home');
  const alpha = path.join(root, 'worktrees', 'alpha', 'main');
  const beta = path.join(root, 'worktrees', 'beta', 'main');
  const config = gardener.normalizeConfig({
    projects: {
      alpha: { surfaces: { remote: { provider: 'codex', remote: true, roots: [alpha], aliases: ['Papiro'], historyRoots: ['~/.codex/sessions', '~/.codex/archived_sessions'] } } },
      beta: { surfaces: { remote: { provider: 'codex', remote: true, roots: [beta], aliases: ['Papiro'], historyRoots: ['~/.codex/sessions', '~/.codex/archived_sessions'] } } },
    },
    providers: emptyProviderConfig(),
  });
  const sources = gardener.collectSources(config, { home, hmacKey: 'remote-dedup-key' }).filter((source) => source.remoteAlias);
  assert.equal(sources.length, 2);
  assert.deepEqual(sources.map((source) => source.path).sort(), ['~/.codex/archived_sessions', '~/.codex/sessions']);
  assert.equal(sources.every((source) => source.remoteMappings.length === 2), true);

  const remoteHome = path.join(root, 'remote-home');
  const history = path.join(remoteHome, '.codex', 'sessions');
  const scriptPath = path.join(root, 'remote-collector.js');
  const session = (id, cwd, eventId, detail = '') => [
    JSON.stringify({ type: 'session_meta', payload: { id, timestamp: '2026-08-20T00:00:00.000Z', cwd } }),
    JSON.stringify({ event: 'Skill', skill: 'audit', event_id: eventId, timestamp: '2026-08-20T00:01:00.000Z', detail }),
  ].join('\n') + '\n';
  writeFile(path.join(history, 'alpha.jsonl'), session('alpha-session', alpha, 'remote-alpha', 'x'.repeat(70 * 1024)));
  writeFile(path.join(history, 'beta.jsonl'), [
    JSON.stringify({ type: 'session_meta', payload: { id: 'beta-session', timestamp: '2026-08-20T00:00:00.000Z', cwd: beta } }),
    JSON.stringify({ type: 'event_msg', payload: { type: 'Skill', skill: 'audit', event_id: 'remote-beta', timestamp: '2026-08-20T00:01:00.000Z' } }),
  ].join('\n') + '\n');
  writeFile(path.join(history, 'unmatched.jsonl'), session('unmatched-session', path.join(root, 'elsewhere'), 'remote-unmatched'));
  writeFile(scriptPath, gardener.buildRemoteCollectorScript({
    provider: 'codex',
    historyRoots: ['~/.codex/sessions'],
    skillKeys: { audit: 'c'.repeat(64) },
    hmacKey: 'remote-map-key',
    surfaceAlias: 'Papiro',
    projectMappings: [
      { logicalProjectId: 'alpha', surfaceId: 'remote', surfaceAlias: 'Alpha', roots: [alpha] },
      { logicalProjectId: 'beta', surfaceId: 'remote', surfaceAlias: 'Beta', roots: [beta] },
    ],
  }));
  const collected = execFileSync(process.execPath, [scriptPath], { encoding: 'utf8', env: { ...process.env, HOME: remoteHome } });
  const parsed = gardener.parseRemoteNdjson(collected, { expectedProvider: 'codex' });
  assert.equal(parsed.ok, true);
  assert.deepEqual(parsed.events.map((event) => event.logicalProjectId).sort(), ['alpha', 'beta']);
  assert.deepEqual(parsed.events.map((event) => event.surfaceAlias).sort(), ['Alpha', 'Beta']);
});

test('remote path-confirmed reads resolve divergent variants and ambiguous names fail closed', () => {
  const root = tempDir();
  const remoteHome = path.join(root, 'remote-home');
  const history = path.join(root, 'history');
  const firstPath = path.join(remoteHome, '.codex', 'skills', 'audit', 'SKILL.md');
  const secondPath = path.join(remoteHome, '.claude', 'skills', 'audit', 'SKILL.md');
  const firstContent = '# audit codex variant\n';
  const secondContent = '# audit claude variant\n';
  writeFile(firstPath, firstContent);
  writeFile(secondPath, secondContent);
  const first = gardener.makeSkillIdentity({ name: 'audit', content: firstContent, hmacKey: 'remote-variants-key' });
  const second = gardener.makeSkillIdentity({ name: 'audit', content: secondContent, hmacKey: 'remote-variants-key' });
  writeFile(path.join(history, 'session.jsonl'), [
    { type: 'response_item', payload: { type: 'function_call', name: 'exec_command', call_id: 'remote-rtk-first', arguments: JSON.stringify({ cmd: `/opt/homebrew/bin/rtk sed -n '1p' ${firstPath}` }) } },
    { type: 'response_item', payload: { type: 'function_call_output', call_id: 'remote-rtk-first', output: firstContent, exit_code: 0 } },
    { type: 'response_item', payload: { type: 'function_call', name: 'exec_command', call_id: 'remote-rtk-second', arguments: JSON.stringify({ cmd: `rtk sed -n '1p' ${secondPath}` }) } },
    { type: 'response_item', payload: { type: 'function_call_output', call_id: 'remote-rtk-second', output: secondContent, exit_code: 0 } },
    { type: 'response_item', payload: { type: 'function_call', name: 'exec_command', call_id: 'remote-rtk-failed', arguments: JSON.stringify({ cmd: `rtk sed -n '1p' ${firstPath}` }) } },
    { type: 'response_item', payload: { type: 'function_call_output', call_id: 'remote-rtk-failed', output: 'permission denied', exit_code: 1 } },
    { event: 'Skill', skill: 'audit', event_id: 'remote-ambiguous-name' },
  ].map(JSON.stringify).join('\n') + '\n');
  const scriptPath = path.join(root, 'collector.js');
  writeFile(scriptPath, gardener.buildRemoteCollectorScript({
    provider: 'codex',
    historyRoots: [history],
    skillVariants: { audit: { [first.contentHash]: first.skillKey, [second.contentHash]: second.skillKey } },
    hmacKey: 'remote-variants-key',
    surfaceAlias: 'Papiro',
    logicalProjectId: 'remote-project',
  }));
  const collected = execFileSync(process.execPath, [scriptPath], { encoding: 'utf8', env: { ...process.env, HOME: remoteHome } });
  const parsed = gardener.parseRemoteNdjson(collected, { expectedProvider: 'codex' });
  assert.equal(parsed.ok, true);
  const confirmed = parsed.events.filter((event) => event.verification === 'confirmed_skill_file_read');
  assert.deepEqual(confirmed.map((event) => event.skillKey).sort(), [first.skillKey, second.skillKey].sort());
  const native = parsed.events.find((event) => event.eventKey === gardener.hmac('native:codex:remote-ambiguous-name', 'remote-variants-key'));
  assert.equal(native.skillKey, gardener.hmac('name:audit', 'remote-variants-key'));
  assert.notEqual(native.skillKey, first.skillKey);
  assert.notEqual(native.skillKey, second.skillKey);
});

test('remote Hermes documents inherit session_start before last_updated', () => {
  const root = tempDir();
  const remoteHome = path.join(root, 'remote-home');
  const history = path.join(root, 'history');
  const skillPath = path.join(remoteHome, '.hermes', 'skills', 'audit', 'SKILL.md');
  const content = '# audit hermes\n';
  writeFile(skillPath, content);
  const audit = gardener.makeSkillIdentity({ name: 'audit', content, hmacKey: 'remote-hermes-time-key' });
  writeFile(path.join(history, 'session.json'), JSON.stringify({
    session_id: 'remote-hermes-historical',
    session_start: '2026-07-01T03:00:00.000Z',
    last_updated: '2026-08-20T03:00:00.000Z',
    messages: [
      { role: 'assistant', content: [{ type: 'tool_use', id: 'remote-hermes-read', name: 'Read', input: { file_path: skillPath } }] },
      { role: 'tool', content: [{ type: 'tool_result', tool_use_id: 'remote-hermes-read', content, is_error: false }] },
    ],
  }));
  const scriptPath = path.join(root, 'collector.js');
  writeFile(scriptPath, gardener.buildRemoteCollectorScript({
    provider: 'hermes',
    historyRoots: [history],
    skillVariants: { audit: { [audit.contentHash]: audit.skillKey } },
    hmacKey: 'remote-hermes-time-key',
    surfaceAlias: 'Papiro',
    logicalProjectId: 'remote-project',
  }));
  const collected = execFileSync(process.execPath, [scriptPath], { encoding: 'utf8', env: { ...process.env, HOME: remoteHome } });
  const parsed = gardener.parseRemoteNdjson(collected, { expectedProvider: 'hermes' });
  assert.equal(parsed.ok, true);
  assert.equal(parsed.events.length, 1);
  assert.equal(parsed.events[0].skillKey, audit.skillKey);
  assert.equal(parsed.events[0].timestamp, '2026-07-01T03:00:00.000Z');
});

test('remote collector ignores only proven non-event corruption and non-Hermes JSON documents', () => {
  const root = tempDir();
  const history = path.join(root, 'history');
  const scriptPath = path.join(root, 'collector.js');
  writeFile(path.join(history, 'sessions-index.json'), '{\n  "sessions": []\n}\n');
  writeFile(path.join(history, 'session.jsonl'), [
    JSON.stringify({ event: 'Skill', skill: 'audit', event_id: 'valid-skill' }),
    '{"type":"response_item","payload":{"type":"reasoning","summary":"truncated',
    '\0\0\0',
  ].join('\n') + '\n');
  writeFile(scriptPath, gardener.buildRemoteCollectorScript({
    provider: 'codex',
    historyRoots: [history],
    skillKeys: { audit: 'a'.repeat(64) },
    hmacKey: 'corruption-key',
    surfaceAlias: 'Remote',
    logicalProjectId: 'alpha',
  }));
  const parsed = gardener.parseRemoteNdjson(execFileSync(process.execPath, [scriptPath], { encoding: 'utf8' }));
  assert.equal(parsed.ok, true);
  assert.equal(parsed.events.length, 1);
  assert.equal(parsed.events[0].skillKey, 'a'.repeat(64));

  writeFile(path.join(history, 'unsafe.jsonl'), '{"type":"response_item","payload":{"type":"function_call"\n');
  assert.throws(
    () => execFileSync(process.execPath, [scriptPath], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }),
    (error) => error.status === 1,
  );
});

test('local Claude history scans JSONL while ignoring pretty JSON indexes and tool results', async () => {
  const root = tempDir();
  const history = path.join(root, 'history');
  const eventLog = path.join(root, 'event-log.sh');
  writeFile(path.join(history, 'sessions-index.json'), '{\n  "sessions": []\n}\n');
  writeFile(path.join(history, 'tool-results', 'tool.json'), '{\n  "result": "not history"\n}\n');
  writeFile(path.join(history, 'session.jsonl'), `${JSON.stringify({ event: 'Skill', skill: 'audit', event_id: 'claude-valid', timestamp: '2026-08-20T00:00:00.000Z' })}\n`);
  writeFile(eventLog, '#!/bin/sh\nexit 0\n', 0o755);
  const config = {
    projects: {},
    providers: { ...emptyProviderConfig(), claude: { roots: [], pluginRoots: [], historyRoots: [history] } },
  };
  const result = await gardener.runGardener('backfill', {
    home: path.join(root, 'home'),
    config,
    vaultRoot: path.join(root, 'vault'),
    eventLogPath: eventLog,
    frameworkRoot: path.join(root, 'missing-framework'),
    now: '2026-08-21T00:00:00.000Z',
    hmacKey: 'claude-jsonl-key',
    runId: '20260821060004-6666666666',
  });
  assert.equal(result.exitCode, 0);
  const source = result.report.sources.find((item) => item.provider === 'claude');
  assert.equal(source.status, 'COMPLETE');
  assert.equal(source.events, 1);
});

test('OpenCode is explicit: no roots is NOT_CONFIGURED and configured roots are NOT_IMPLEMENTED without coverage', async () => {
  assert.equal(gardener.sourceStatus('opencode', [], []), 'NOT_CONFIGURED');
  assert.equal(gardener.sourceStatus('opencode', ['/configured'], ['/history']), 'NOT_IMPLEMENTED');
  const root = tempDir();
  const home = path.join(root, 'home');
  const skills = path.join(home, 'opencode', 'skills');
  const history = path.join(home, 'opencode', 'history');
  const eventLog = path.join(root, 'event-log.sh');
  writeFile(path.join(skills, 'audit', 'SKILL.md'), '# audit\n');
  writeFile(path.join(history, 'session.jsonl'), JSON.stringify({ event: 'Skill', skill: 'audit', event_id: 'opencode-use', timestamp: '2026-08-20T00:00:00.000Z' }) + '\n');
  writeFile(eventLog, '#!/bin/sh\nexit 0\n', 0o755);
  const config = { projects: {}, providers: { ...emptyProviderConfig(), opencode: { roots: [skills], pluginRoots: [], systemRoots: [], historyRoots: [history] } } };
  const result = await gardener.runGardener('backfill', { home, config, vaultRoot: path.join(root, 'vault'), eventLogPath: eventLog, frameworkRoot: path.join(root, 'missing-framework'), now: '2026-08-21T00:00:00.000Z', hmacKey: 'opencode-key', runId: '20260821060001-3333333333' });
  assert.equal(result.exitCode, 2);
  assert.equal(result.status, 'partial');
  assert.equal(result.report.sources.some((source) => source.provider === 'opencode' && source.status === 'NOT_IMPLEMENTED'), true);
  assert.equal(result.report.classifications[0].classification, 'UNKNOWN');
  const notConfigured = gardener.normalizeConfig({ projects: {}, providers: emptyProviderConfig() });
  assert.equal(gardener.collectSources(notConfigured, { home, hmacKey: 'opencode-key' }).some((source) => source.provider === 'opencode' && source.status === 'NOT_CONFIGURED'), true);
  const projectConfig = gardener.normalizeConfig({
    projects: { opencodeProject: { surfaces: { local: { provider: 'opencode', roots: [skills], aliases: ['OpenCode'], historyRoots: [history] } } } },
    providers: emptyProviderConfig(),
  });
  assert.equal(gardener.collectSources(projectConfig, { home, hmacKey: 'opencode-key' }).some((source) => source.provider === 'opencode' && source.status === 'NOT_IMPLEMENTED'), true);
});

test('inventory accepts SKILL.md, legacy markdown, plugins and safe symlinks without loops', () => {
  const root = tempDir();
  const projectSkills = path.join(root, 'project', '.agents', 'skills');
  const globalSkills = path.join(root, 'codex', 'skills');
  const pluginSkills = path.join(root, 'codex', 'plugins', 'pkg', 'skills');
  writeFile(path.join(projectSkills, 'audit', 'SKILL.md'), '# Audit\nproject\n');
  writeFile(path.join(projectSkills, 'legacy.md'), '# Legacy\n');
  writeFile(path.join(globalSkills, 'audit', 'SKILL.md'), '# Audit\nproject\n');
  writeFile(path.join(pluginSkills, 'audit', 'SKILL.md'), '# Audit\nplugin\n');
  writeFile(path.join(pluginSkills, 'alias.md'), '# Audit\nproject\n');
  writeFile(path.join(pluginSkills, 'audit', 'references', 'provider.md'), '# Provider reference\n');
  writeFile(path.join(globalSkills, 'gstack', 'test', 'fixtures', 'synthetic', 'SKILL.md'), '# Synthetic fixture\n');
  writeFile(path.join(globalSkills, 'build', 'legit-build', 'SKILL.md'), '# Legit build skill\n');
  writeFile(path.join(globalSkills, 'dist', 'legit-dist', 'SKILL.md'), '# Legit dist skill\n');
  writeFile(path.join(globalSkills, 'coverage', 'legit-coverage', 'SKILL.md'), '# Legit coverage skill\n');
  writeFile(path.join(globalSkills, 'fixtures', 'legit-fixtures', 'SKILL.md'), '# Legit fixture-named skill\n');
  writeFile(path.join(projectSkills, 'audit', 'README.md'), '# Audit documentation\n');
  fs.symlinkSync(path.join(projectSkills, 'audit'), path.join(projectSkills, 'cycle'), 'dir');
  const config = gardener.normalizeConfig({
    projects: { demo: { surfaces: { mac: { roots: [path.join(root, 'project')], aliases: ['Mac'], historyRoots: [] } } } },
    providers: {
      ...emptyProviderConfig(),
      codex: { roots: [globalSkills], pluginRoots: [path.join(root, 'codex', 'plugins')], historyRoots: [] },
    },
  });
  const inventory = gardener.collectInventory(config, { home: root, hmacKey: 'inventory-key', frameworkRoot: path.join(root, 'missing-framework') });
  assert.equal(inventory.installations.length, 9);
  assert.equal(inventory.divergence.some((item) => item.name === 'audit'), true);
  assert.equal(inventory.dedupCandidates.length >= 1, true);
  assert.equal(inventory.installations.some((item) => item.name === 'legacy'), true);
  assert.equal(inventory.installations.some((item) => item.name === 'alias'), true);
  assert.equal(inventory.installations.some((item) => item.name === 'provider'), false);
  assert.equal(inventory.installations.some((item) => item.name === 'readme'), false);
  assert.equal(inventory.installations.some((item) => item.name === 'synthetic'), false);
  assert.equal(inventory.installations.some((item) => item.name === 'legit-build'), true);
  assert.equal(inventory.installations.some((item) => item.name === 'legit-dist'), true);
  assert.equal(inventory.installations.some((item) => item.name === 'legit-coverage'), true);
  assert.equal(inventory.installations.some((item) => item.name === 'legit-fixtures'), true);
  assert.equal(inventory.installations.some((item) => JSON.stringify(item).includes(root)), false);
});

test('oversized inventory files become partial blocked evidence without being read into memory', () => {
  const root = tempDir();
  const globalSkills = path.join(root, 'codex', 'skills');
  writeFile(path.join(globalSkills, 'build', 'legit', 'SKILL.md'), '# Legit\n');
  writeFile(path.join(globalSkills, 'oversized', 'SKILL.md'), Buffer.alloc(gardener.MAX_SKILL_BYTES + 1, 'x'));
  const config = gardener.normalizeConfig({
    projects: {},
    providers: { ...emptyProviderConfig(), codex: { roots: [globalSkills], pluginRoots: [], historyRoots: [] } },
  });
  const inventory = gardener.collectInventory(config, { home: root, hmacKey: 'inventory-size-key', frameworkRoot: path.join(root, 'missing-framework') });
  const blocked = inventory.installations.find((item) => item.name === 'oversized');
  assert.equal(inventory.inventoryStatus, 'PARTIAL');
  assert.ok(inventory.inventoryIssues.some((issue) => issue.name === 'oversized' && issue.reason === 'skill-file-too-large'));
  assert.equal(blocked.status, 'BLOCKED');
  assert.equal(blocked.reason, 'skill-file-too-large');
  assert.equal(inventory.installations.some((item) => item.name === 'legit'), true);
  assert.doesNotMatch(JSON.stringify(inventory.installations), new RegExp(root.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')));
});

test('Git worktrees are admitted only when they share the configured common dir and aliases do not merge projects', () => {
  const root = tempDir();
  const repo = path.join(root, 'repo');
  const worktreeParent = path.join(root, 'workspaces', 'demo');
  fs.mkdirSync(repo, { recursive: true });
  execFileSync('git', ['init', '-q', repo]);
  execFileSync('git', ['-C', repo, 'config', 'user.email', 'test@example.invalid']);
  execFileSync('git', ['-C', repo, 'config', 'user.name', 'Skill Gardener Test']);
  writeFile(path.join(repo, '.agents', 'skills', 'audit', 'SKILL.md'), '# audit\n');
  execFileSync('git', ['-C', repo, 'add', '.']);
  execFileSync('git', ['-C', repo, 'commit', '-qm', 'fixture']);
  fs.mkdirSync(worktreeParent, { recursive: true });
  const worktree = path.join(worktreeParent, 'main');
  execFileSync('git', ['-C', repo, 'worktree', 'add', '-q', worktree, 'HEAD']);
  const config = gardener.normalizeConfig({
    projects: {
      alpha: { surfaces: {
        mac: { roots: [repo], aliases: ['Mac'], historyRoots: [] },
        ssh: { roots: [path.join(worktreeParent, '*')], aliases: ['Papiro'], historyRoots: [] },
      } },
      beta: { surfaces: { sameRoot: { roots: [repo], aliases: ['Other'], historyRoots: [] } } },
    },
    providers: emptyProviderConfig(),
  });
  const inventory = gardener.collectInventory(config, { home: root, hmacKey: 'worktree-key', frameworkRoot: path.join(root, 'missing') });
  assert.equal(inventory.installations.length, 3);
  assert.equal(new Set(inventory.installations.map((item) => item.logicalProjectId)).has('alpha'), true);
  assert.equal(new Set(inventory.installations.map((item) => item.logicalProjectId)).has('beta'), true);
  assert.equal(inventory.installations.some((item) => item.logicalProjectId.includes('::')), false);
  assert.equal(inventory.installations.some((item) => item.sourceAlias === 'Papiro'), true);
});

test('ambiguous aliases without location evidence stay UNMAPPED instead of choosing a project', () => {
  const root = tempDir();
  const alpha = path.join(root, 'alpha');
  const beta = path.join(root, 'beta');
  fs.mkdirSync(alpha, { recursive: true });
  fs.mkdirSync(beta, { recursive: true });
  const config = gardener.normalizeConfig({
    projects: {
      alpha: { surfaces: { mac: { roots: [alpha], aliases: ['Mac'], historyRoots: [] } } },
      beta: { surfaces: { mac: { roots: [beta], aliases: ['Mac'], historyRoots: [] } } },
    },
    providers: emptyProviderConfig(),
  });
  const mappings = gardener.buildProjectMappings(config, root);
  assert.equal(gardener.mapSessionToProject({ alias: 'Mac' }, mappings, root), null);
  assert.equal(gardener.mapSessionToProject({ cwd: path.join(alpha, 'work') }, mappings, root).logicalProjectId, 'alpha');
});

test('native event identity deduplicates the same session event observed on two hosts', () => {
  const text = '{"event":"Skill","skill":"audit","event_id":"same-native-id","timestamp":"2026-08-20T00:00:00.000Z"}\n';
  const first = gardener.parseCodexEvents({ text, hmacKey: 'host-key', surfaceAlias: 'Mac' });
  const second = gardener.parseCodexEvents({ text, hmacKey: 'host-key', surfaceAlias: 'Papiro' });
  assert.equal(first.events[0].eventKey, second.events[0].eventKey);
  assert.notEqual(first.events[0].surfaceAlias, second.events[0].surfaceAlias);
});

test('classification follows thresholds and fails closed for negative coverage', () => {
  const now = '2026-08-21T00:00:00.000Z';
  const key = 'a'.repeat(64);
  const hot = gardener.classifySkill({ verifiedUsage: Array.from({ length: 20 }, (_, index) => usageEvent(key, new Date(Date.parse(now) - index * 86400000).toISOString())), now, coverageIntervals: completeCoverage(now) });
  const active = gardener.classifySkill({ verifiedUsage: Array.from({ length: 5 }, (_, index) => usageEvent(key, new Date(Date.parse(now) - index * 86400000).toISOString())), now, coverageIntervals: completeCoverage(now) });
  const occasional = gardener.classifySkill({ verifiedUsage: [usageEvent(key, '2026-08-01T00:00:00.000Z')], now, coverageIntervals: completeCoverage(now) });
  const dormant = gardener.classifySkill({ verifiedUsage: [usageEvent(key, '2026-06-20T00:00:00.000Z')], now, coverageIntervals: [{ start: '2026-06-20T00:00:00.000Z', end: now, status: 'COMPLETE' }] });
  const dead = gardener.classifySkill({ installedAt: '2026-02-01T00:00:00.000Z', now, coverageIntervals: completeCoverage(now) });
  const unknown = gardener.classifySkill({ installedAt: '2026-02-01T00:00:00.000Z', now, coverageIntervals: [{ start: '2026-02-01T00:00:00.000Z', end: now, status: 'PARTIAL' }] });
  assert.equal(hot.classification, 'HOT');
  assert.equal(active.classification, 'ACTIVE');
  assert.equal(occasional.classification, 'OCCASIONAL');
  assert.equal(dormant.classification, 'DORMANT');
  assert.equal(dead.classification, 'DEAD');
  assert.equal(unknown.classification, 'UNKNOWN');
  assert.notEqual(unknown.classification, 'DEAD');
});

test('negative coverage never combines separate provider or project scopes', () => {
  const now = '2026-08-21T00:00:00.000Z';
  const complete = completeCoverage(now);
  const split = gardener.classifySkill({
    installedAt: '2026-02-01T00:00:00.000Z',
    now,
    coverageScopes: [
      { provider: 'codex', surfaceAlias: 'Mac', logicalProjectId: 'alpha', sourceComplete: true, intervals: complete },
      { provider: 'claude', surfaceAlias: 'Mac', logicalProjectId: 'beta', sourceComplete: true, intervals: [{ start: complete[0].start, end: '2026-07-01T00:00:00.000Z', status: 'COMPLETE' }] },
    ],
    sourceComplete: true,
  });
  assert.equal(split.coverage, 'PARTIAL');
  assert.notEqual(split.classification, 'DEAD');
});

test('candidate cluster requires recurrence, two logical projects, score and low existing coverage', () => {
  const signalKey = 'b'.repeat(64);
  const signals = [
    { kind: 'candidate_signal', signalKey, logicalProjectId: 'a', fingerprint: 'tool:search|exe:rg', count: 1, timestamp: '2026-07-01T00:00:00.000Z' },
    { kind: 'candidate_signal', signalKey, logicalProjectId: 'b', fingerprint: 'tool:search|exe:rg', count: 1, timestamp: '2026-07-08T00:00:00.000Z' },
    { kind: 'candidate_signal', signalKey, logicalProjectId: 'a', fingerprint: 'tool:search|exe:rg', count: 1, timestamp: '2026-07-15T00:00:00.000Z' },
  ];
  const eligible = gardener.findCandidateClusters(signals, { existingCoverage: { [signalKey]: 20 } })[0];
  const covered = gardener.findCandidateClusters(signals, { existingCoverage: { [signalKey]: 80 } })[0];
  const burst = gardener.findCandidateClusters(signals.map((signal, index) => ({ ...signal, logicalProjectId: index === 1 ? 'UNMAPPED' : signal.logicalProjectId, timestamp: '2026-07-01T00:00:00.000Z' })), { existingCoverage: { [signalKey]: 0 } })[0];
  assert.equal(eligible.eligible, true);
  assert.equal(eligible.action, 'INTERACTIVE_INCUBATING_VIA_SKILL_CREATOR');
  assert.equal(covered.eligible, false);
  assert.equal(burst.eligible, false);
  const semanticCoverage = gardener.buildExistingCoverage({
    catalog: { variants: [], _installations: [{ _capabilityTokens: ['search', 'rg'] }] },
    signals,
    hmacKey: 'candidate-key',
  });
  assert.equal(semanticCoverage[signalKey], 100);
});

test('generic shell mentions never count as verified usage and structured reads require a correlated result', () => {
  const home = tempDir();
  const skillPath = path.join(home, '.codex', 'skills', 'audit', 'SKILL.md');
  const audit = gardener.makeSkillIdentity({ name: 'audit', content: '# audit\n', hmacKey: 'read-key' });
  const catalog = {
    _byPath: new Map([[path.resolve(skillPath), audit]]),
    _byName: new Map([['audit', new Set([audit.skillKey])]]),
  };
  const shellOnly = [
    { type: 'response_item', payload: { type: 'function_call', name: 'exec_command', call_id: 'shell-1', arguments: JSON.stringify({ cmd: `printf never-ran ${skillPath}` }) } },
    { type: 'response_item', payload: { type: 'function_call_output', call_id: 'shell-1', output: skillPath } },
  ].map(JSON.stringify).join('\n');
  const shellResult = gardener.parseCodexEvents({ text: shellOnly, catalog, home, hmacKey: 'read-key', fallbackTimestamp: '2026-08-21T00:00:00.000Z' });
  assert.equal(shellResult.events.some((event) => event.kind === 'verified_usage'), false);

  const successfulShellRead = [
    { type: 'response_item', payload: { type: 'function_call', name: 'exec_command', call_id: 'shell-read-1', arguments: JSON.stringify({ cmd: `rtk sed -n '1p' ${skillPath}` }) } },
    { type: 'response_item', payload: { type: 'function_call_output', call_id: 'shell-read-1', output: '# audit', exit_code: 0 } },
  ].map(JSON.stringify).join('\n');
  const successfulShellResult = gardener.parseCodexEvents({ text: successfulShellRead, catalog, home, hmacKey: 'read-key', fallbackTimestamp: '2026-08-21T00:00:00.000Z' });
  assert.equal(successfulShellResult.events.filter((event) => event.kind === 'verified_usage').length, 1);

  const absoluteWrapperRead = [
    { type: 'response_item', payload: { type: 'function_call', name: 'exec_command', call_id: 'shell-read-absolute-rtk', arguments: JSON.stringify({ cmd: `/opt/homebrew/bin/rtk sed -n '1p' ${skillPath}` }) } },
    { type: 'response_item', payload: { type: 'function_call_output', call_id: 'shell-read-absolute-rtk', output: '# audit', exit_code: 0 } },
  ].map(JSON.stringify).join('\n');
  const absoluteWrapperResult = gardener.parseCodexEvents({ text: absoluteWrapperRead, catalog, home, hmacKey: 'read-key', fallbackTimestamp: '2026-08-21T00:00:00.000Z' });
  assert.equal(absoluteWrapperResult.events.filter((event) => event.kind === 'verified_usage').length, 1);

  const failedShellRead = [
    { type: 'response_item', payload: { type: 'function_call', name: 'exec_command', call_id: 'shell-read-failed', arguments: JSON.stringify({ cmd: `rtk sed -n '1p' ${skillPath}` }) } },
    { type: 'response_item', payload: { type: 'function_call_output', call_id: 'shell-read-failed', output: 'permission denied', exit_code: 1 } },
  ].map(JSON.stringify).join('\n');
  const failedShellResult = gardener.parseCodexEvents({ text: failedShellRead, catalog, home, hmacKey: 'read-key', fallbackTimestamp: '2026-08-21T00:00:00.000Z' });
  assert.equal(failedShellResult.events.some((event) => event.kind === 'verified_usage'), false);

  const commandEndRead = [
    { type: 'response_item', payload: { type: 'function_call', name: 'exec_command', call_id: 'shell-end-1', arguments: JSON.stringify({ cmd: `cat ${skillPath}` }) } },
    { type: 'event_msg', payload: { type: 'exec_command_end', call_id: 'shell-end-1', command: ['cat', skillPath], exit_code: 0, aggregated_output: '# audit' } },
  ].map(JSON.stringify).join('\n');
  const commandEndResult = gardener.parseCodexEvents({ text: commandEndRead, catalog, home, hmacKey: 'read-key', fallbackTimestamp: '2026-08-21T00:00:00.000Z' });
  assert.equal(commandEndResult.events.filter((event) => event.kind === 'verified_usage').length, 1);

  const failedCommandEndRead = [
    { type: 'response_item', payload: { type: 'function_call', name: 'exec_command', call_id: 'shell-end-failed', arguments: JSON.stringify({ cmd: `cat ${skillPath}` }) } },
    { type: 'event_msg', payload: { type: 'exec_command_end', call_id: 'shell-end-failed', command: ['cat', skillPath], exit_code: 1, aggregated_output: 'permission denied' } },
  ].map(JSON.stringify).join('\n');
  const failedCommandEndResult = gardener.parseCodexEvents({ text: failedCommandEndRead, catalog, home, hmacKey: 'read-key', fallbackTimestamp: '2026-08-21T00:00:00.000Z' });
  assert.equal(failedCommandEndResult.events.some((event) => event.kind === 'verified_usage'), false);

  const structuredRead = [
    { type: 'response_item', payload: { type: 'function_call', name: 'Read', call_id: 'read-1', arguments: JSON.stringify({ file_path: skillPath }) } },
    { type: 'response_item', payload: { type: 'function_call_output', call_id: 'read-1', output: '# audit' } },
  ].map(JSON.stringify).join('\n');
  const readResult = gardener.parseCodexEvents({ text: structuredRead, catalog, home, hmacKey: 'read-key', fallbackTimestamp: '2026-08-21T00:00:00.000Z' });
  assert.equal(readResult.events.filter((event) => event.kind === 'verified_usage').length, 1);
});

test('shell reads resolve project, global, plugin and Hermes skill paths through the catalog index', () => {
  const home = tempDir();
  const entries = [
    ['project-audit', path.join(home, 'project', '.agents', 'skills', 'project-audit', 'SKILL.md')],
    ['codex-audit', path.join(home, '.codex', 'skills', 'codex-audit', 'SKILL.md')],
    ['claude-plugin', path.join(home, '.claude', 'plugins', 'pkg', 'skills', 'claude-plugin', 'SKILL.md')],
    ['hermes-audit', path.join(home, '.hermes', 'skills', 'hermes-audit', 'SKILL.md')],
  ];
  const installations = entries.map(([name, sourcePath]) => gardener.makeSkillIdentity({ name, content: `# ${name}\n`, hmacKey: 'path-index-key', sourcePath }));
  const catalog = {
    _byPath: new Map(entries.map(([name, sourcePath], index) => [path.resolve(sourcePath), installations[index]])),
    _byName: new Map(entries.map(([name], index) => [name, new Set([installations[index].skillKey])])),
  };
  const records = [];
  for (const [index, [, sourcePath]] of entries.entries()) {
    records.push({ type: 'response_item', payload: { type: 'function_call', name: 'exec_command', call_id: `path-read-${index}`, arguments: JSON.stringify({ cmd: `sed -n '1p' ${sourcePath}` }) } });
    records.push({ type: 'response_item', payload: { type: 'function_call_output', call_id: `path-read-${index}`, output: '# skill', exit_code: 0 } });
  }
  const parsed = gardener.parseCodexEvents({ text: records.map(JSON.stringify).join('\n'), catalog, home, hmacKey: 'path-index-key', fallbackTimestamp: '2026-08-21T00:00:00.000Z' });
  assert.equal(parsed.ok, true);
  assert.deepEqual(parsed.events.filter((event) => event.kind === 'verified_usage').map((event) => event.skillKey).sort(), installations.map((item) => item.skillKey).sort());
});

test('remote limits reject invalid schema, bounded streams and failed SSH without retaining raw data', async () => {
  const unknown = gardener.parseRemoteNdjson('{"schemaVersion":1,"kind":"verified_usage","eventKey":"' + 'a'.repeat(64) + '","skillKey":"' + 'b'.repeat(64) + '","prompt":"secret"}');
  assert.equal(unknown.ok, false);
  const child = new EventEmitter();
  child.stdout = new EventEmitter();
  child.stderr = new EventEmitter();
  child.stdin = { end() { process.nextTick(() => child.emit('close', 255, null)); } };
  child.kill = () => {};
  const failed = await gardener.collectRemoteSource({ alias: 'Papiro', payload: { provider: 'codex', historyRoots: [] }, spawnImpl: () => child, connectTimeoutMs: 1000, executionTimeoutMs: 1000 });
  assert.equal(failed.ok, false);
  assert.equal(failed.partial, true);

  const overflowChild = new EventEmitter();
  overflowChild.stdout = new EventEmitter();
  overflowChild.stderr = new EventEmitter();
  overflowChild.stdin = { end() { process.nextTick(() => overflowChild.stdout.emit('data', '1234567890')); } };
  overflowChild.kill = () => {};
  const stdoutOverflow = await gardener.collectRemoteSource({ alias: 'Papiro', payload: { provider: 'codex', historyRoots: [] }, spawnImpl: () => overflowChild, stdoutLimit: 4, connectTimeoutMs: 1000, executionTimeoutMs: 1000 });
  assert.equal(stdoutOverflow.reason, 'stdout-overflow');

  const stderrChild = new EventEmitter();
  stderrChild.stdout = new EventEmitter();
  stderrChild.stderr = new EventEmitter();
  stderrChild.stdin = { end() { process.nextTick(() => stderrChild.stderr.emit('data', '1234567890')); } };
  stderrChild.kill = () => {};
  const stderrOverflow = await gardener.collectRemoteSource({ alias: 'Papiro', payload: { provider: 'codex', historyRoots: [] }, spawnImpl: () => stderrChild, stderrLimit: 4, connectTimeoutMs: 1000, executionTimeoutMs: 1000 });
  assert.equal(stderrOverflow.reason, 'stderr-overflow');

  const timeoutChild = new EventEmitter();
  timeoutChild.stdout = new EventEmitter();
  timeoutChild.stderr = new EventEmitter();
  timeoutChild.stdin = { end() { process.nextTick(() => timeoutChild.emit('spawn')); } };
  timeoutChild.kill = () => {};
  const timeout = await gardener.collectRemoteSource({ alias: 'Papiro', payload: { provider: 'codex', historyRoots: [] }, spawnImpl: () => timeoutChild, connectTimeoutMs: 1000, executionTimeoutMs: 10 });
  assert.equal(timeout.reason, 'execution-timeout');

  const invalidChild = new EventEmitter();
  invalidChild.stdout = new EventEmitter();
  invalidChild.stderr = new EventEmitter();
  invalidChild.stdin = { end() { process.nextTick(() => { invalidChild.stdout.emit('data', '{"not":"an event"}\n'); invalidChild.emit('close', 0, null); }); } };
  invalidChild.kill = () => {};
  const invalidOutput = await gardener.collectRemoteSource({ alias: 'Papiro', payload: { provider: 'codex', historyRoots: [] }, spawnImpl: () => invalidChild, connectTimeoutMs: 1000, executionTimeoutMs: 1000 });
  assert.equal(invalidOutput.reason, 'schema-invalid');

  const remoteRoot = tempDir();
  const remoteHome = tempDir();
  const outsideRoot = tempDir();
  const remoteAudit = gardener.makeSkillIdentity({ name: 'audit', content: '# audit\n', hmacKey: 'remote-key' });
  writeFile(path.join(remoteHome, '.codex', 'skills', 'audit', 'SKILL.md'), '# audit\n');
  writeFile(path.join(outsideRoot, 'outside.jsonl'), JSON.stringify({ type: 'response_item', payload: { type: 'function_call', name: 'exec_command', call_id: 'outside', arguments: JSON.stringify({ cmd: 'sed -n 1p ~/.codex/skills/audit/SKILL.md' }) } }) + '\n');
  writeFile(path.join(remoteRoot, 'valid.jsonl'), [
    { type: 'response_item', payload: { type: 'function_call', name: 'exec_command', call_id: 'shell-mention', arguments: JSON.stringify({ cmd: 'printf ~/.codex/skills/audit/SKILL.md' }) } },
    { type: 'response_item', payload: { type: 'function_call_output', call_id: 'shell-mention', output: '~/.codex/skills/audit/SKILL.md' } },
    { type: 'response_item', payload: { type: 'function_call', name: 'Read', call_id: 'inside', arguments: JSON.stringify({ file_path: '~/.codex/skills/audit/SKILL.md' }) } },
    { type: 'response_item', payload: { type: 'function_call_output', call_id: 'inside', output: '# audit' } },
  ].map(JSON.stringify).join('\n') + '\n');
  fs.symlinkSync(path.join(outsideRoot, 'outside.jsonl'), path.join(remoteRoot, 'outside.jsonl'));
  const scriptPath = path.join(remoteRoot, 'collector.js');
  writeFile(scriptPath, gardener.buildRemoteCollectorScript({ provider: 'codex', historyRoots: [remoteRoot], skillVariants: { audit: { [remoteAudit.contentHash]: remoteAudit.skillKey } }, hmacKey: 'remote-key', surfaceAlias: 'Papiro', logicalProjectId: 'alpha' }));
  const collected = execFileSync(process.execPath, [scriptPath], { encoding: 'utf8', env: { ...process.env, HOME: remoteHome } });
  const collectedEvents = gardener.parseRemoteNdjson(collected, { expectedProvider: 'codex' });
  assert.equal(collectedEvents.ok, true);
  assert.equal(collectedEvents.events.length, 1);
  assert.equal(collectedEvents.events[0].logicalProjectId, 'alpha');
  writeFile(path.join(remoteRoot, 'valid.jsonl'), '{not-json}\n');
  assert.throws(() => execFileSync(process.execPath, [scriptPath], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }), (error) => error.status === 1);
});

test('cron preview is explicit, idempotent and preserves unrelated crontab lines', () => {
  const root = tempDir();
  const crontab = path.join(root, 'crontab');
  const artifactRoot = path.join(root, 'artifacts');
  const canaryPath = path.join(root, 'canary.json');
  const canaryRun = '20260821030000-aaaaaaaaaa';
  const blockedCrontab = path.join(root, 'blocked-crontab');
  const blockedCanary = path.join(root, 'blocked-canary.json');
  writeFile(blockedCrontab, '15 4 * * * keep-me\n');
  writeFile(blockedCanary, JSON.stringify({ schemaVersion: 1, status: 'PARTIAL', postMerge: true, runId: canaryRun }));
  const blocked = gardener.cronAction('install', { home: root, file: blockedCrontab, artifactRoot, canaryPath: blockedCanary });
  assert.equal(blocked.ok, false);
  assert.equal(blocked.reason, 'canary-incomplete');
  assert.equal(fs.readFileSync(blockedCrontab, 'utf8'), '15 4 * * * keep-me\n');
  const canaryReport = { runId: canaryRun, status: 'complete', complete: true, cursorsPromoted: ['source-1'], postGate: { status: 'PASS', eventLog: 'EMITTED' } };
  writeFile(path.join(artifactRoot, 'reports', `${canaryRun}.json`), JSON.stringify(canaryReport));
  assert.equal(gardener.recordCanaryReceipt({ home: root, artifactRoot, canaryPath, runId: canaryRun, postMerge: true, now: '2026-08-21T00:00:00.000Z', hmacKey: 'canary-key' }).ok, false);
  const canaryRunReceipt = { runId: canaryRun, status: 'complete', cursorPromotion: 'PROMOTED', cursorsPromoted: ['source-1'], postGate: { status: 'PASS', eventLog: 'EMITTED' } };
  writeFile(path.join(artifactRoot, 'receipts', `${canaryRun}.json`), JSON.stringify(canaryRunReceipt));
  writeFile(path.join(root, '.canuto', 'cache', 'skill-gardener', 'state.json'), JSON.stringify({ schemaVersion: 1, cursors: {}, coverage: {}, eventKeys: {}, lifetimeUsage: {}, detailedEvents: [], runs: [{ runId: canaryRun, status: 'complete' }] }));
  assert.equal(gardener.recordCanaryReceipt({ home: root, artifactRoot, canaryPath, runId: canaryRun, postMerge: true, now: '2026-08-21T00:00:00.000Z', hmacKey: 'canary-key' }).ok, true);
  fs.mkdirSync(path.join(root, '.canuto', 'cache', 'skill-gardener', 'staging', canaryRun), { recursive: true });
  assert.equal(gardener.canaryStatus({ home: root, artifactRoot, canaryPath }).ok, false);
  fs.rmSync(path.join(root, '.canuto', 'cache', 'skill-gardener', 'staging', canaryRun), { recursive: true });
  assert.equal(gardener.canaryStatus({ home: root, artifactRoot, canaryPath }).ok, true);
  writeFile(crontab, '15 4 * * * keep-me\n');
  const options = { home: root, file: crontab, artifactRoot, canaryPath };
  const preview = gardener.cronAction('install', { ...options, dryRun: true });
  assert.equal(preview.changed, true);
  assert.match(preview.next, /keep-me/);
  assert.match(preview.next, /canuto-skill-gardener:v1/);
  assert.equal(fs.readFileSync(crontab, 'utf8').includes('canuto-skill-gardener:v1'), false);
  assert.equal(fs.existsSync(path.join(root, '.canuto', 'logs')), false);
  const installed = gardener.cronAction('install', options);
  const second = gardener.cronAction('install', options);
  assert.equal(installed.changed, true);
  assert.equal(fs.existsSync(path.join(root, '.canuto', 'logs')), true);
  assert.equal(second.changed, false);
  const status = gardener.cronAction('status', options);
  assert.equal(status.changed, false);
  assert.equal(status.installed, true);
  const removed = gardener.cronAction('remove', options);
  assert.equal(removed.changed, true);
  assert.equal(fs.readFileSync(crontab, 'utf8'), '15 4 * * * keep-me\n');
});

test('cron install and remove fail closed after a real custom read error', () => {
  const root = tempDir();
  let writes = 0;
  const options = {
    home: root,
    read: () => { throw new Error('read failed at /private/sensitive/crontab'); },
    write: () => { writes += 1; },
  };
  for (const action of ['install', 'remove']) {
    const result = gardener.cronAction(action, options);
    assert.equal(result.ok, false);
    assert.equal(result.reason, 'crontab-read-failed');
    assert.equal(result.changed, false);
    assert.equal(result.line, '');
    assert.doesNotMatch(JSON.stringify(result), /sensitive/);
  }
  assert.equal(writes, 0);
  assert.equal(fs.existsSync(path.join(root, '.canuto')), false);
});

test('an explicit no-crontab reader condition is treated as an empty crontab', () => {
  const result = gardener.cronAction('status', {
    home: tempDir(),
    read: () => { throw new Error('no crontab for test-user'); },
  });
  assert.equal(result.ok, true);
  assert.equal(result.current, '');
  assert.equal(result.installed, false);
});

test('statusJson reports cron readiness without masking read failures', () => {
  const root = tempDir();
  const crontab = path.join(root, 'crontab');
  const key = 'a'.repeat(64);
  writeFile(crontab, `${gardener.canonicalCronLine(root)}\n`);
  const base = { home: root, hmacKey: key, configPath: path.join(root, 'missing-config.json'), file: crontab };

  const configured = gardener.statusJson(gardener.getRuntimeOptions(base));
  assert.equal(configured.cron.configured, true);
  assert.equal(configured.cron.status, 'READY');
  assert.equal(configured.cron.explicitInstallOnly, true);

  writeFile(crontab, '');
  const empty = gardener.statusJson(gardener.getRuntimeOptions(base));
  assert.equal(empty.cron.configured, false);
  assert.equal(empty.cron.status, 'READY');

  const unavailable = gardener.statusJson(gardener.getRuntimeOptions({
    home: root,
    hmacKey: key,
    configPath: path.join(root, 'missing-config.json'),
    read: () => { throw new Error('unexpected read failure'); },
  }));
  assert.equal(unavailable.cron.configured, null);
  assert.equal(unavailable.cron.status, 'UNAVAILABLE');
  assert.equal(unavailable.cron.reason, 'crontab-read-failed');
  assert.equal(unavailable.status, 'UNAVAILABLE');
});

test('cron CLI reports unavailable read failures truthfully in JSON and human output', () => {
  const root = tempDir();
  const home = path.join(root, 'home');
  const unreadableCrontab = path.join(root, 'crontab-directory');
  fs.mkdirSync(unreadableCrontab, { recursive: true });
  const env = isolatedEnv(home, unreadableCrontab);
  const jsonResult = spawnSync(process.execPath, [path.join(__dirname, 'canuto-skill-gardener.js'), 'cron', 'status', '--json', '--home', home], { encoding: 'utf8', env });
  assert.notEqual(jsonResult.status, 0);
  const json = JSON.parse(jsonResult.stdout);
  assert.equal(json.installed, null);
  assert.equal(json.status, 'UNAVAILABLE');
  assert.equal(json.reason, 'crontab-read-failed');

  const humanResult = spawnSync(process.execPath, [path.join(__dirname, 'canuto-skill-gardener.js'), 'cron', 'status', '--home', home], { encoding: 'utf8', env });
  assert.notEqual(humanResult.status, 0);
  assert.match(humanResult.stdout, /unavailable/);
  assert.doesNotMatch(humanResult.stdout, /not installed/);
});

test('CLI rejects --project before creating any .canuto state', () => {
  const home = tempDir();
  const crontab = path.join(home, 'crontab');
  const result = spawnSync(process.execPath, [
    path.join(__dirname, 'canuto-skill-gardener.js'),
    'backfill',
    '--project',
    'alpha',
    '--home',
    home,
  ], { encoding: 'utf8', env: isolatedEnv(home, crontab) });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /--project is not supported/);
  assert.equal(fs.existsSync(path.join(home, '.canuto')), false);
  assert.doesNotMatch(cli.help(), /--project/);
});

test('report lookup accepts only canonical run IDs and retention prunes detail without lifetime summary', async () => {
  const root = tempDir();
  const home = path.join(root, 'home');
  const artifactRoot = path.join(root, 'artifacts');
  const oldRun = '20260101000000-dddddddddd';
  const oldTimestamp = '2026-01-01T00:00:00.000Z';
  writeFile(path.join(artifactRoot, 'reports', `${oldRun}.json`), JSON.stringify({ runId: oldRun, generatedAt: oldTimestamp }));
  writeFile(path.join(artifactRoot, 'reports', `${oldRun}.md`), 'old\n');
  writeFile(path.join(artifactRoot, 'receipts', `${oldRun}.json`), JSON.stringify({ runId: oldRun, generatedAt: oldTimestamp }));
  writeFile(path.join(home, '.canuto', 'cache', 'skill-gardener', 'staging', oldRun, 'report.json'), JSON.stringify({ runId: oldRun, generatedAt: oldTimestamp }));
  const oldEvent = usageEvent('e'.repeat(64), oldTimestamp);
  writeFile(path.join(home, '.canuto', 'cache', 'skill-gardener', 'state.json'), JSON.stringify({
    schemaVersion: 1,
    cursors: {},
    coverage: { old: [{ start: oldTimestamp, end: oldTimestamp, status: 'COMPLETE' }] },
    eventKeys: { [oldEvent.eventKey]: { timestamp: oldTimestamp } },
    lifetimeUsage: { ['e'.repeat(64)]: 9 },
    detailedEvents: [oldEvent],
    runs: [],
  }));
  const eventLog = path.join(root, 'event-log.sh');
  writeFile(eventLog, '#!/bin/sh\nexit 0\n', 0o755);
  const currentRun = '20260821090000-eeeeeeeeee';
  const result = await gardener.runGardener('weekly', {
    home,
    artifactRoot,
    config: { projects: {}, providers: emptyProviderConfig() },
    vaultRoot: path.join(root, 'vault'),
    eventLogPath: eventLog,
    frameworkRoot: path.join(root, 'missing-framework'),
    now: '2026-08-21T00:00:00.000Z',
    hmacKey: 'retention-key',
    runId: currentRun,
  });
  assert.equal(result.exitCode, 0);
  assert.equal(gardener.reportForRun({ artifactRoot }, '../' + oldRun), null);
  const state = gardener.readJson(path.join(home, '.canuto', 'cache', 'skill-gardener', 'state.json'));
  assert.deepEqual(state.detailedEvents, []);
  assert.deepEqual(state.eventKeys, { [oldEvent.eventKey]: 1 });
  assert.deepEqual(state.coverage, {});
  assert.equal(state.lifetimeUsage['e'.repeat(64)], 9);
  assert.equal(fs.existsSync(path.join(artifactRoot, 'reports', `${oldRun}.json`)), false);
  assert.equal(fs.existsSync(path.join(artifactRoot, 'reports', `${oldRun}.md`)), false);
  assert.equal(fs.existsSync(path.join(artifactRoot, 'receipts', `${oldRun}.json`)), false);
  assert.equal(fs.existsSync(path.join(home, '.canuto', 'cache', 'skill-gardener', 'staging', oldRun)), false);
});

test('exclusive run lock returns 75 without entering a stage', async () => {
  const root = tempDir();
  const stateDir = path.join(root, 'state');
  fs.mkdirSync(path.join(stateDir, 'run.lock'), { recursive: true });
  const result = await gardener.runGardener('weekly', { stateDir, home: path.join(root, 'home'), config: { projects: {}, providers: emptyProviderConfig() }, runId: 'locked' });
  assert.equal(result.exitCode, 75);
  assert.equal(fs.existsSync(path.join(stateDir, 'staging', 'locked')), false);
});

test('run is transactional, idempotent and writes a MECESA non-Git receipt without a manifest', async () => {
  const root = tempDir();
  const home = path.join(root, 'home');
  const history = path.join(root, 'history');
  const skills = path.join(root, 'skills');
  const mecesa = path.join(root, 'mecesa');
  const eventLog = path.join(root, 'event-log.sh');
  writeFile(path.join(skills, 'audit', 'SKILL.md'), '# audit\n');
  writeFile(path.join(history, 'session.jsonl'), '{"type":"session_meta","payload":{"id":"s1","timestamp":"2026-08-20T00:00:00.000Z"}}\n{"event":"Skill","skill":"audit","event_id":"e1","timestamp":"2026-08-20T00:01:00.000Z"}\n');
  writeFile(path.join(mecesa, 'notes.txt'), 'non-git container\n');
  writeFile(eventLog, '#!/bin/sh\nexit 0\n', 0o755);
  const config = {
    projects: { 'mecesa-v1': { surfaces: { mac: { roots: [mecesa], aliases: ['Mac'], historyRoots: [] } } } },
    providers: { ...emptyProviderConfig(), codex: { roots: [skills], pluginRoots: [], historyRoots: [history] } },
  };
  const first = await gardener.runGardener('backfill', { home, config, vaultRoot: path.join(root, 'vault'), eventLogPath: eventLog, now: '2026-08-21T00:00:00.000Z', hmacKey: 'run-key', runId: '20260821000000-bbbbbbbbbb' });
  assert.equal(first.exitCode, 0);
  assert.match(first.report.markdown, /Post-gate: PASS/);
  assert.doesNotMatch(first.report.markdown, /PENDING/);
  assert.equal(gardener.readJson(path.join(root, 'vault', 'projects', 'canuto-framework-v1', 'skill-gardener', 'reports', '20260821000000-bbbbbbbbbb.json')).markdown, first.report.markdown);
  const second = await gardener.runGardener('weekly', { home, config, vaultRoot: path.join(root, 'vault'), eventLogPath: eventLog, now: '2026-08-21T00:00:00.000Z', hmacKey: 'run-key', runId: '20260821000001-cccccccccc' });
  assert.equal(second.exitCode, 0);
  assert.equal(second.report.verifiedUsage.total, 0);
  const receipt = gardener.readJson(path.join(root, 'vault', 'projects', 'canuto-framework-v1', 'skill-gardener', 'receipts', '20260821000000-bbbbbbbbbb.json'));
  assert.equal(receipt.nonGitReceipts['mecesa-v1'].status, 'UNCHANGED');
  assert.equal(JSON.stringify(receipt).includes('manifestHash'), false);
  const changed = await gardener.runGardener('weekly', {
    home,
    config,
    vaultRoot: path.join(root, 'vault'),
    eventLogPath: eventLog,
    now: '2026-08-21T00:00:00.000Z',
    hmacKey: 'run-key',
    runId: '20260821000002-dddddddddd',
    beforeAfterFingerprint: async () => writeFile(path.join(mecesa, 'changed.txt'), 'changed during run\n'),
  });
  assert.equal(changed.exitCode, 0);
  const changedReceipt = gardener.readJson(path.join(root, 'vault', 'projects', 'canuto-framework-v1', 'skill-gardener', 'receipts', '20260821000002-dddddddddd.json'));
  assert.equal(changedReceipt.nonGitReceipts['mecesa-v1'].status, 'CHANGED_DURING_RUN');
  const crash = await gardener.runGardener('weekly', { home, config, vaultRoot: path.join(root, 'vault'), eventLogPath: eventLog, now: '2026-08-21T00:00:00.000Z', hmacKey: 'run-key', runId: '20260821000003-eeeeeeeeee', failBeforePromotion: true });
  assert.equal(crash.exitCode, 1);
  const state = gardener.readJson(path.join(home, '.canuto', 'cache', 'skill-gardener', 'state.json'));
  assert.equal(state.runs.some((run) => run.runId === '20260821000003-eeeeeeeeee'), false);
});

test('cursor identity detects truncation or rewrite and refuses negative classification', async () => {
  const root = tempDir();
  const home = path.join(root, 'home');
  const skills = path.join(root, 'skills');
  const history = path.join(root, 'history');
  const eventLog = path.join(root, 'event-log.sh');
  writeFile(path.join(skills, 'dead', 'SKILL.md'), '# dead\n');
  writeFile(path.join(history, 'session.jsonl'), '{"type":"session_meta","payload":{"id":"rotation","timestamp":"2026-08-20T00:00:00.000Z"}}\n{"event":"Skill","skill":"dead","event_id":"rotation-1","timestamp":"2026-08-20T00:01:00.000Z"}\n');
  writeFile(eventLog, '#!/bin/sh\nexit 0\n', 0o755);
  const config = { projects: {}, providers: { ...emptyProviderConfig(), codex: { roots: [skills], pluginRoots: [], historyRoots: [history] } } };
  const first = await gardener.runGardener('backfill', { home, config, vaultRoot: path.join(root, 'vault'), eventLogPath: eventLog, now: '2026-08-21T00:00:00.000Z', hmacKey: 'rotation-key', runId: '20260821000004-fffffffff0' });
  assert.equal(first.exitCode, 0);
  writeFile(path.join(history, 'session.jsonl'), '{"event":"Skill","skill":"dead","event_id":"rotation-2","timestamp":"2026-08-20T00:02:00.000Z"}\n');
  const second = await gardener.runGardener('weekly', { home, config, vaultRoot: path.join(root, 'vault'), eventLogPath: eventLog, now: '2026-08-21T00:00:00.000Z', hmacKey: 'rotation-key', runId: '20260821000005-1111111111' });
  assert.equal(second.status, 'partial');
  assert.equal(second.report.incompleteSources.some((source) => source.reason === 'source-truncated-or-rewritten'), true);
  assert.notEqual(second.report.classifications[0].classification, 'DEAD');
  assert.notEqual(second.report.classifications[0].classification, 'DORMANT');
});

test('incremental append compares the exact observed prefix below and above 4096 bytes', async () => {
  const root = tempDir();
  const home = path.join(root, 'home');
  const skills = path.join(root, 'skills');
  const history = path.join(root, 'history');
  const eventLog = path.join(root, 'event-log.sh');
  writeFile(path.join(skills, 'audit', 'SKILL.md'), '# audit\n');
  writeFile(path.join(history, 'session.jsonl'), [
    JSON.stringify({ type: 'session_meta', payload: { id: 'append', timestamp: '2026-08-20T00:00:00.000Z' } }),
    JSON.stringify({ event: 'Skill', skill: 'audit', event_id: 'append-1', timestamp: '2026-08-20T00:01:00.000Z' }),
  ].join('\n') + '\n');
  writeFile(eventLog, '#!/bin/sh\nexit 0\n', 0o755);
  const config = { projects: {}, providers: { ...emptyProviderConfig(), codex: { roots: [skills], pluginRoots: [], historyRoots: [history] } } };
  const first = await gardener.runGardener('backfill', { home, config, vaultRoot: path.join(root, 'vault'), eventLogPath: eventLog, frameworkRoot: path.join(root, 'missing-framework'), now: '2026-08-21T00:00:00.000Z', hmacKey: 'append-key', runId: '20260821070000-4444444444' });
  assert.equal(first.exitCode, 0);
  const before = gardener.readJson(path.join(home, '.canuto', 'cache', 'skill-gardener', 'state.json'));
  const sourceCursor = Object.values(before.cursors).flatMap((cursor) => Object.values(cursor)).find((cursor) => cursor.prefixLength !== undefined);
  assert.equal(sourceCursor.prefixLength < 4096, true);
  writeFile(path.join(history, 'session.jsonl'), `${fs.readFileSync(path.join(history, 'session.jsonl'), 'utf8')}${JSON.stringify({ event: 'Skill', skill: 'audit', event_id: 'append-2', timestamp: '2026-08-20T00:02:00.000Z' })}\n`);
  const second = await gardener.runGardener('weekly', { home, config, vaultRoot: path.join(root, 'vault'), eventLogPath: eventLog, frameworkRoot: path.join(root, 'missing-framework'), now: '2026-08-21T00:00:00.000Z', hmacKey: 'append-key', runId: '20260821070001-5555555555' });
  assert.equal(second.exitCode, 0);
  assert.equal(second.report.status, 'complete');
  assert.equal(second.report.verifiedUsage.total, 1);
  const filler = Array.from({ length: 500 }, (_, index) => JSON.stringify({ type: 'event_msg', payload: { type: 'noop', index } })).join('\n') + '\n';
  writeFile(path.join(history, 'session.jsonl'), fs.readFileSync(path.join(history, 'session.jsonl'), 'utf8') + filler + JSON.stringify({ event: 'Skill', skill: 'audit', event_id: 'append-3', timestamp: '2026-08-20T00:03:00.000Z' }) + '\n');
  const third = await gardener.runGardener('weekly', { home, config, vaultRoot: path.join(root, 'vault'), eventLogPath: eventLog, frameworkRoot: path.join(root, 'missing-framework'), now: '2026-08-21T00:00:00.000Z', hmacKey: 'append-key', runId: '20260821070002-6666666666' });
  assert.equal(third.exitCode, 0);
  assert.equal(third.report.verifiedUsage.total, 1);
});

test('incremental cursor resumes at the beginning of an incomplete trailing JSON record', async () => {
  const root = tempDir();
  const home = path.join(root, 'home');
  const skills = path.join(root, 'skills');
  const history = path.join(root, 'history');
  const sessionFile = path.join(history, 'session.jsonl');
  const eventLog = path.join(root, 'event-log.sh');
  writeFile(path.join(skills, 'audit', 'SKILL.md'), '# audit\n');
  const sessionMeta = JSON.stringify({ type: 'session_meta', payload: { id: 'trailing', timestamp: '2026-08-20T00:00:00.000Z' } });
  const usage = JSON.stringify({ event: 'Skill', skill: 'audit', event_id: 'trailing-1', timestamp: '2026-08-20T00:01:00.000Z' });
  const splitAt = Math.floor(usage.length / 2);
  writeFile(sessionFile, `${sessionMeta}\n${usage.slice(0, splitAt)}`);
  writeFile(eventLog, '#!/bin/sh\nexit 0\n', 0o755);
  const config = { projects: {}, providers: { ...emptyProviderConfig(), codex: { roots: [skills], pluginRoots: [], historyRoots: [history] } } };
  const first = await gardener.runGardener('backfill', { home, config, vaultRoot: path.join(root, 'vault'), eventLogPath: eventLog, frameworkRoot: path.join(root, 'missing-framework'), now: '2026-08-21T00:00:00.000Z', hmacKey: 'trailing-key', runId: '20260821100000-1212121212' });
  assert.equal(first.exitCode, 0);
  const state = gardener.readJson(path.join(home, '.canuto', 'cache', 'skill-gardener', 'state.json'));
  const cursor = Object.values(state.cursors).flatMap((value) => Object.values(value))[0];
  assert.equal(cursor.offset, Buffer.byteLength(`${sessionMeta}\n`));
  fs.appendFileSync(sessionFile, `${usage.slice(splitAt)}\n`);
  const second = await gardener.runGardener('weekly', { home, config, vaultRoot: path.join(root, 'vault'), eventLogPath: eventLog, frameworkRoot: path.join(root, 'missing-framework'), now: '2026-08-21T00:00:00.000Z', hmacKey: 'trailing-key', runId: '20260821100001-1313131313' });
  assert.equal(second.exitCode, 0);
  assert.equal(second.report.verifiedUsage.total, 1);
});

test('incremental cursor preserves CRLF bytes before an incomplete trailing JSON record', async () => {
  const root = tempDir();
  const home = path.join(root, 'home');
  const skills = path.join(root, 'skills');
  const history = path.join(root, 'history');
  const sessionFile = path.join(history, 'session.jsonl');
  const eventLog = path.join(root, 'event-log.sh');
  writeFile(path.join(skills, 'audit', 'SKILL.md'), '# audit\n');
  const sessionMeta = JSON.stringify({ type: 'session_meta', payload: { id: 'crlf-trailing', timestamp: '2026-08-20T00:00:00.000Z' } });
  const usage = JSON.stringify({ event: 'Skill', skill: 'audit', event_id: 'crlf-trailing-1', timestamp: '2026-08-20T00:01:00.000Z' });
  const splitAt = Math.floor(usage.length / 2);
  writeFile(sessionFile, `${sessionMeta}\r\n${usage.slice(0, splitAt)}`);
  writeFile(eventLog, '#!/bin/sh\nexit 0\n', 0o755);
  const config = { projects: {}, providers: { ...emptyProviderConfig(), codex: { roots: [skills], pluginRoots: [], historyRoots: [history] } } };
  const first = await gardener.runGardener('backfill', { home, config, vaultRoot: path.join(root, 'vault'), eventLogPath: eventLog, frameworkRoot: path.join(root, 'missing-framework'), now: '2026-08-21T00:00:00.000Z', hmacKey: 'crlf-trailing-key', runId: '20260821100002-1515151515' });
  assert.equal(first.exitCode, 0);
  const state = gardener.readJson(path.join(home, '.canuto', 'cache', 'skill-gardener', 'state.json'));
  const cursor = Object.values(state.cursors).flatMap((value) => Object.values(value))[0];
  assert.equal(cursor.offset, Buffer.byteLength(`${sessionMeta}\r\n`));
  fs.appendFileSync(sessionFile, `${usage.slice(splitAt)}\r\n`);
  const second = await gardener.runGardener('weekly', { home, config, vaultRoot: path.join(root, 'vault'), eventLogPath: eventLog, frameworkRoot: path.join(root, 'missing-framework'), now: '2026-08-21T00:00:00.000Z', hmacKey: 'crlf-trailing-key', runId: '20260821100003-1616161616' });
  assert.equal(second.exitCode, 0);
  assert.equal(second.report.verifiedUsage.total, 1);
});

test('incremental cursor keeps an LF-less first JSON record for the next run', async () => {
  const root = tempDir();
  const home = path.join(root, 'home');
  const skills = path.join(root, 'skills');
  const history = path.join(root, 'history');
  const sessionFile = path.join(history, 'session.jsonl');
  const eventLog = path.join(root, 'event-log.sh');
  writeFile(path.join(skills, 'audit', 'SKILL.md'), '# audit\n');
  const usage = JSON.stringify({ event: 'Skill', skill: 'audit', event_id: 'incomplete-first-1', timestamp: '2026-08-20T00:01:00.000Z' });
  const splitAt = Math.floor(usage.length / 2);
  writeFile(sessionFile, usage.slice(0, splitAt));
  writeFile(eventLog, '#!/bin/sh\nexit 0\n', 0o755);
  const config = { projects: {}, providers: { ...emptyProviderConfig(), codex: { roots: [skills], pluginRoots: [], historyRoots: [history] } } };
  const first = await gardener.runGardener('backfill', { home, config, vaultRoot: path.join(root, 'vault'), eventLogPath: eventLog, frameworkRoot: path.join(root, 'missing-framework'), now: '2026-08-21T00:00:00.000Z', hmacKey: 'incomplete-first-key', runId: '20260821100004-1717171717' });
  assert.equal(first.exitCode, 0);
  const state = gardener.readJson(path.join(home, '.canuto', 'cache', 'skill-gardener', 'state.json'));
  const cursor = Object.values(state.cursors).flatMap((value) => Object.values(value))[0];
  assert.equal(cursor.offset, 0);
  fs.appendFileSync(sessionFile, `${usage.slice(splitAt)}\n`);
  const second = await gardener.runGardener('weekly', { home, config, vaultRoot: path.join(root, 'vault'), eventLogPath: eventLog, frameworkRoot: path.join(root, 'missing-framework'), now: '2026-08-21T00:00:00.000Z', hmacKey: 'incomplete-first-key', runId: '20260821100005-1818181818' });
  assert.equal(second.exitCode, 0);
  assert.equal(second.report.verifiedUsage.total, 1);
});

test('any partial source blocks promotion for every cursor in the run', async () => {
  const root = tempDir();
  const home = path.join(root, 'home');
  const skills = path.join(root, 'skills');
  const validHistory = path.join(root, 'valid-history');
  const invalidHistory = path.join(root, 'invalid-history');
  const eventLog = path.join(root, 'event-log.sh');
  writeFile(path.join(skills, 'audit', 'SKILL.md'), '# audit\n');
  writeFile(path.join(validHistory, 'session.jsonl'), `${JSON.stringify({ event: 'Skill', skill: 'audit', event_id: 'valid-1', timestamp: '2026-08-20T00:01:00.000Z' })}\n`);
  writeFile(path.join(invalidHistory, 'session.jsonl'), '{invalid-json}\n');
  writeFile(eventLog, '#!/bin/sh\nexit 0\n', 0o755);
  const config = { projects: {}, providers: { ...emptyProviderConfig(), codex: { roots: [skills], pluginRoots: [], historyRoots: [validHistory, invalidHistory] } } };
  const runId = '20260821110000-1414141414';
  const result = await gardener.runGardener('backfill', { home, config, vaultRoot: path.join(root, 'vault'), eventLogPath: eventLog, frameworkRoot: path.join(root, 'missing-framework'), now: '2026-08-21T00:00:00.000Z', hmacKey: 'partial-key', runId });
  assert.equal(result.exitCode, 2);
  assert.equal(result.report.cursorsPromoted.length, 0);
  assert.equal(gardener.readJson(path.join(home, '.canuto', 'cache', 'skill-gardener', 'state.json'), null), null);
  const receipt = gardener.readJson(path.join(root, 'vault', 'projects', 'canuto-framework-v1', 'skill-gardener', 'receipts', `${runId}.json`));
  assert.equal(receipt.cursorPromotion, 'BLOCKED');
  assert.deepEqual(receipt.cursorsPromoted, []);
});

test('cursor promotion is blocked by a degraded event log and pending commits recover idempotently', async () => {
  const root = tempDir();
  const home = path.join(root, 'home');
  const config = { projects: {}, providers: emptyProviderConfig() };
  const missing = await gardener.runGardener('weekly', { home, config, vaultRoot: path.join(root, 'vault'), eventLogPath: path.join(root, 'missing-event-log'), frameworkRoot: path.join(root, 'missing-framework'), now: '2026-08-21T00:00:00.000Z', hmacKey: 'gate-key', runId: '20260821080000-7777777777' });
  assert.equal(missing.exitCode, 2);
  assert.equal(missing.report.postGate.eventLog, 'DEGRADED');
  assert.equal(gardener.readJson(path.join(home, '.canuto', 'cache', 'skill-gardener', 'state.json'), null), null);

  const eventLog = path.join(root, 'event-log.sh');
  writeFile(eventLog, '#!/bin/sh\nexit 0\n', 0o755);
  const crashPoints = [
    ['stage', '20260821080001-8888888888'],
    ['event-log', '20260821080002-9999999999'],
    ['final-artifacts', '20260821080003-aaaaaaaaab'],
    ['commit', '20260821080004-bbbbbbbbbc'],
    ['promotion', '20260821080005-cccccccccd'],
  ];
  for (const [crashAt, runId] of crashPoints) {
    const crashed = await gardener.runGardener('weekly', { home, config, vaultRoot: path.join(root, 'vault'), eventLogPath: eventLog, frameworkRoot: path.join(root, 'missing-framework'), now: '2026-08-21T00:00:00.000Z', hmacKey: 'gate-key', runId, crashAt });
    assert.equal(crashed.exitCode, 1);
    const recovered = await gardener.runGardener('weekly', { home, config, vaultRoot: path.join(root, 'vault'), eventLogPath: eventLog, frameworkRoot: path.join(root, 'missing-framework'), now: '2026-08-21T00:00:00.000Z', hmacKey: 'gate-key', runId });
    assert.equal(recovered.exitCode, 0);
    assert.equal(recovered.report.runId, runId);
  }
});

test('sanitized report and structured events cannot persist prompt, response, command, output, path or unknown fields', () => {
  const event = gardener.sanitizeStructuredEvent({
    schemaVersion: 1,
    kind: 'candidate_signal',
    eventKey: 'a'.repeat(64),
    signalKey: 'b'.repeat(64),
    timestamp: '2026-08-21T00:00:00.000Z',
    provider: 'codex',
    fingerprint: 'tool:search|exe:rg',
    count: 1,
  });
  assert.ok(event);
  assert.equal(gardener.sanitizeStructuredEvent({ ...event, command: 'secret' }), null);
  const report = gardener.sanitizePersistedReport({ prompt: 'x', response: 'y', command: 'z', output: 'q', path: '/tmp/private', safe: true });
  assert.deepEqual(report, { safe: true });
});

test('optional eval adapter is pinned by config and stays outside the critical path', () => {
  const config = gardener.normalizeConfig({ policy: { evalAdapter: { enabled: false, version: '2026.08' } } });
  const result = gardener.runEvalAdapter({ config, fixtureId: 'fixture-1' });
  assert.equal(result.status, 'NOT_CONFIGURED');
  assert.equal(result.criticalPath, false);
  const decision = gardener.evalDecision({ kind: 'new', baseline: { passRate: 0.8 }, candidate: { passRate: 0.96 }, adapterResult: { passRate: 0.96, failures: 0 } });
  assert.equal(decision.eligible, true);
  assert.equal(decision.gainPercentagePoints, 16);
});

test('CLI command matrix rejects invalid invocations before side effects', () => {
  const home = tempDir();
  const crontab = path.join(home, 'crontab');
  const runId = '20260822000000-aaaaaaaaaa';
  const invalid = [
    ['--help', 'weekly'],
    ['unknown'],
    ['cron'],
    ['cron', 'unknown'],
    ['backfill', '--unknown'],
    ['backfill', '--config'],
    ['backfill', '--home', '--json'],
    ['backfill', '--home', home, '--home', home],
    ['backfill', '--config=' + path.join(home, 'config.json')],
    ['backfill', 'extra'],
    ['report'],
    ['report', '--run', runId, '--config', path.join(home, 'config.json')],
    ['cron', 'install', '--config', path.join(home, 'config.json')],
    ['canary', 'record', '--run', runId],
    ['canary', 'record', '--run', runId, '--post-merge', '--run', runId],
  ];
  for (const args of invalid) {
    const result = spawnSync(process.execPath, [path.join(__dirname, 'canuto-skill-gardener.js'), ...args], {
      encoding: 'utf8',
      env: isolatedEnv(home, crontab),
    });
    assert.equal(result.status, 1, `${args.join(' ')}\n${result.stderr}`);
    assert.match(result.stderr, /Argument error|--project is not supported/);
  }
  assert.equal(fs.existsSync(path.join(home, '.canuto')), false);
});

test('CLI valid matrix uses only isolated config and crontab', () => {
  const home = tempDir();
  const crontab = path.join(home, 'crontab');
  const canary = path.join(home, 'canary.json');
  writeFile(crontab, '15 4 * * * keep-me\n');
  const config = path.join(__dirname, '..', 'config', 'skill-gardener.json');
  const calls = [
    ['status', '--json', '--home', home, '--config', config],
    ['cron', 'status', '--json', '--home', home, '--canary', canary, '--dry-run'],
    ['report', '--run', '20260822000000-aaaaaaaaaa', '--home', home, '--json'],
    ['canary', 'status', '--home', home, '--canary', canary],
  ];
  for (const args of calls) {
    const result = spawnSync(process.execPath, [path.join(__dirname, 'canuto-skill-gardener.js'), ...args], {
      encoding: 'utf8',
      env: isolatedEnv(home, crontab),
    });
    assert.doesNotMatch(result.stderr, /Argument error/);
  }
  assert.equal(fs.readFileSync(crontab, 'utf8'), '15 4 * * * keep-me\n');
});

test('loadConfig and loadState fail closed without artifacts', async () => {
  const root = tempDir();
  const missingConfig = path.join(root, 'missing-config.json');
  assert.throws(() => gardener.loadConfig(missingConfig), { message: 'config-missing' });
  const malformedConfig = path.join(root, 'malformed-config.json');
  writeFile(malformedConfig, '{bad');
  assert.throws(() => gardener.loadConfig(malformedConfig), { message: 'config-invalid' });
  const rootConfig = path.join(root, 'array-config.json');
  writeFile(rootConfig, '[]');
  assert.throws(() => gardener.loadConfig(rootConfig), { message: 'config-invalid' });
  const shippedConfig = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'config', 'skill-gardener.json'), 'utf8'));
  const storedConfigCases = [
    {},
    { ...shippedConfig, schemaVersion: 2 },
    { ...shippedConfig, projects: [] },
    { ...shippedConfig, providers: [] },
    { ...shippedConfig, projects: { alpha: [] } },
    { ...shippedConfig, projects: { alpha: { surfaces: [] } } },
    { ...shippedConfig, providers: { ...shippedConfig.providers, codex: [] } },
    { ...shippedConfig, policy: [] },
    { ...shippedConfig, policy: { ...shippedConfig.policy, fingerprintFamilies: [] } },
    { ...shippedConfig, policy: { ...shippedConfig.policy, evalAdapter: [] } },
    { ...shippedConfig, extra: true },
  ];
  for (const [index, value] of storedConfigCases.entries()) {
    const storedPath = path.join(root, `invalid-stored-${index}.json`);
    writeFile(storedPath, JSON.stringify(value));
    assert.throws(() => gardener.loadConfig(storedPath), { message: 'config-invalid' }, JSON.stringify(value));
  }
  assert.equal(gardener.loadConfig(path.join(__dirname, '..', 'config', 'skill-gardener.json')).schemaVersion, 1);
  assert.deepEqual(
    gardener.loadConfig(path.join(__dirname, '..', 'config', 'skill-gardener.json')).providers.codex.roots.map((root) => root.path),
    ['~/.codex/skills', '~/.agents/skills'],
  );
  const loop = path.join(root, 'config-loop');
  fs.symlinkSync('config-loop', loop);
  assert.throws(() => gardener.loadConfig(loop), { message: 'config-read-failed' });

  const statePath = path.join(root, 'state.json');
  assert.deepEqual(gardener.loadState(statePath), {
    schemaVersion: 1,
    cursors: {},
    coverage: {},
    eventKeys: {},
    lifetimeUsage: {},
    detailedEvents: [],
    runs: [],
  });
  writeFile(statePath, '{bad');
  assert.throws(() => gardener.loadState(statePath), { message: 'state-invalid' });
  fs.rmSync(statePath);
  fs.mkdirSync(statePath);
  assert.throws(() => gardener.loadState(statePath), { message: 'state-read-failed' });

  const home = path.join(root, 'home');
  const artifactRoot = path.join(root, 'artifacts');
  const result = await gardener.runGardener('weekly', {
    home,
    stateDir: path.join(root, 'state-dir'),
    artifactRoot,
    configPath: missingConfig,
    hmacKey: 'a'.repeat(64),
    runId: '20260822000001-bbbbbbbbbb',
  });
  assert.equal(result.error, 'config-missing');
  assert.equal(fs.existsSync(path.join(artifactRoot, 'reports')), false);
  assert.equal(fs.existsSync(path.join(artifactRoot, 'receipts')), false);
  assert.equal(fs.existsSync(path.join(root, 'state-dir', 'state.json')), false);
});

test('state schema rejects malformed active containers', () => {
  const root = tempDir();
  const statePath = path.join(root, 'state.json');
  const cases = [
    {},
    { schemaVersion: 2 },
    { cursors: [] },
    { cursors: { source: [] } },
    { cursors: { source: { file: { offset: -1 } } } },
    { cursors: { source: { file: { mtimeMs: '1' } } } },
    { cursors: { source: { file: { identity: 7 } } } },
    { cursors: { source: { file: { prefixHash: 'bad' } } } },
    { coverage: [] },
    { coverage: { source: {} } },
    { coverage: { source: [{ start: 'not-a-date', end: '2026-08-21T00:00:00.000Z', status: 'COMPLETE' }] } },
    { coverage: { source: [{ start: '2026-08-22T00:00:00.000Z', end: '2026-08-21T00:00:00.000Z', status: 'COMPLETE' }] } },
    { coverage: { source: [{ start: '2026-08-21T00:00:00.000Z', end: '2026-08-21T00:00:00.000Z', status: 'UNKNOWN' }] } },
    { coverage: { source: [{ start: '2026-08-21T00:00:00.000Z', end: '2026-08-21T00:00:00.000Z', status: 'COMPLETE', reason: 3 }] } },
    { eventKeys: [] },
    { eventKeys: { bad: 1 } },
    { lifetimeUsage: [] },
    { lifetimeUsage: { ['a'.repeat(64)]: 1.5 } },
    { detailedEvents: {} },
    { detailedEvents: [usageEvent('a'.repeat(64), 'bad-date')] },
    { runs: {} },
    { runs: [{ runId: 'not-canonical', status: 'complete' }] },
    { runs: [{ runId: '20260822000002-cccccccccc', status: 'complete', extra: true }] },
    { runs: [{ runId: '20260822000002-cccccccccc', status: 'unknown' }] },
  ];
  for (const value of cases) {
    writeFile(statePath, JSON.stringify(value));
    assert.throws(() => gardener.loadState(statePath), { message: 'state-invalid' }, JSON.stringify(value));
  }
  writeFile(statePath, JSON.stringify({
    schemaVersion: 1,
    cursors: {},
    coverage: {},
    eventKeys: {},
    lifetimeUsage: {},
    detailedEvents: [],
    runs: [],
    unknown: { prompt: 'drop-me' },
  }));
  assert.throws(() => gardener.loadState(statePath), { message: 'state-invalid' });
});

test('state schema requires complete closed file cursors and preserves remote cursor maps', async () => {
  const root = tempDir();
  const home = path.join(root, 'home');
  const skills = path.join(root, 'skills');
  const history = path.join(root, 'history');
  const eventLog = path.join(root, 'event-log.sh');
  const statePath = path.join(home, '.canuto', 'cache', 'skill-gardener', 'state.json');
  writeFile(path.join(skills, 'audit', 'SKILL.md'), '# audit\n');
  writeFile(path.join(history, 'session.jsonl'), `${JSON.stringify({ event: 'Skill', skill: 'audit', event_id: 'cursor-round-trip', timestamp: '2026-08-21T00:01:00.000Z' })}\n`);
  writeFile(eventLog, '#!/bin/sh\nexit 0\n', 0o755);
  const config = { projects: {}, providers: { ...emptyProviderConfig(), codex: { roots: [skills], pluginRoots: [], historyRoots: [history] } } };
  const run = await gardener.runGardener('backfill', {
    home,
    config,
    vaultRoot: path.join(root, 'vault'),
    eventLogPath: eventLog,
    frameworkRoot: path.join(root, 'missing-framework'),
    now: '2026-08-21T00:00:00.000Z',
    hmacKey: 'cursor-round-trip-key',
    runId: '20260821120000-2222222222',
  });
  assert.equal(run.exitCode, 0);
  const generated = gardener.readJson(statePath);
  const loaded = gardener.loadState(statePath);
  assert.deepEqual(loaded.cursors, generated.cursors);
  const [sourceId, files] = Object.entries(generated.cursors).find(([, value]) => Object.keys(value).length > 0);
  const [[fileId, generatedCursor]] = Object.entries(files);
  const invalidCursors = [
    { name: 'empty', cursor: {} },
    { name: 'partial', cursor: (() => { const cursor = { ...generatedCursor }; delete cursor.prefixLength; return cursor; })() },
    { name: 'unknown-key', cursor: { ...generatedCursor, unexpected: true } },
    { name: 'malformed-null', cursor: { ...generatedCursor, mtimeMs: null } },
    { name: 'malformed-range', cursor: { ...generatedCursor, offset: generatedCursor.size + 1 } },
    { name: 'malformed-fraction', cursor: { ...generatedCursor, size: 0.5 } },
    { name: 'malformed-prefix-length', cursor: { ...generatedCursor, prefixLength: 4097 } },
  ];
  for (const { name, cursor } of invalidCursors) {
    const mutated = JSON.parse(JSON.stringify(generated));
    mutated.cursors = { [sourceId]: { [fileId]: cursor } };
    writeFile(statePath, JSON.stringify(mutated));
    assert.throws(() => gardener.loadState(statePath), { message: 'state-invalid' }, name);
  }
  const remoteState = JSON.parse(JSON.stringify(generated));
  remoteState.cursors = { remoteSource: {} };
  writeFile(statePath, JSON.stringify(remoteState));
  assert.deepEqual(gardener.loadState(statePath).cursors, { remoteSource: {} });
});

function recoveryFixture(root, runId) {
  const home = path.join(root, 'home');
  const vaultRoot = path.join(root, 'vault');
  const eventLogPath = path.join(root, 'event-log.sh');
  writeFile(eventLogPath, '#!/bin/sh\nexit 0\n', 0o755);
  return {
    home,
    vaultRoot,
    eventLogPath,
    frameworkRoot: path.join(root, 'missing-framework'),
    config: { projects: {}, providers: emptyProviderConfig() },
    now: '2026-08-22T00:00:00.000Z',
    hmacKey: 'b'.repeat(64),
    runId,
  };
}

function statePathFor(options) {
  return path.join(options.home, '.canuto', 'cache', 'skill-gardener', 'state.json');
}

function artifactPathFor(options, kind, runId) {
  return path.join(options.vaultRoot, 'projects', 'canuto-framework-v1', 'skill-gardener', kind, `${runId}.json`);
}

test('pending recovery authenticates exact bytes before parsing', async () => {
  const root = tempDir();
  const options = recoveryFixture(root, '20260822000003-dddddddddd');
  const crashed = await gardener.runGardener('weekly', { ...options, crashAt: 'commit' });
  assert.equal(crashed.exitCode, 1);
  const stageDir = path.join(options.home, '.canuto', 'cache', 'skill-gardener', 'staging', options.runId);
  const pendingPath = path.join(stageDir, 'pending-state.json');
  const raw = fs.readFileSync(pendingPath);
  raw[raw.length - 2] = raw[raw.length - 2] === 0x20 ? 0x21 : 0x20;
  fs.writeFileSync(pendingPath, raw);
  const recovered = await gardener.runGardener('weekly', options);
  assert.equal(recovered.error, 'pending-state-hash-mismatch');
  assert.equal(fs.existsSync(statePathFor(options)), false);
  assert.equal(fs.existsSync(stageDir), true);
  assert.equal(gardener.readJson(artifactPathFor(options, 'receipts', options.runId)).cursorPromotion, 'READY');
});

test('pending recovery rejects every malformed state container', async () => {
  const mutations = [
    (state) => { state.cursors = []; },
    (state) => { state.cursors = { source: { file: {} } }; },
    (state) => { state.cursors = { source: { file: { identity: 'fixture', offset: 0, size: 0, mtimeMs: 0, prefixHash: 'a'.repeat(64) } } }; },
    (state) => { state.cursors = { source: { file: { identity: 'fixture', offset: 0, size: 0, mtimeMs: 0, prefixHash: 'a'.repeat(64), prefixLength: 0, unexpected: true } } }; },
    (state) => { state.cursors = { source: { file: { identity: 'fixture', offset: 0, size: 0, mtimeMs: null, prefixHash: 'a'.repeat(64), prefixLength: 0 } } }; },
    (state) => { state.coverage = { source: {} }; },
    (state) => { state.eventKeys = { bad: 1 }; },
    (state) => { state.lifetimeUsage = { ['a'.repeat(64)]: -1 }; },
    (state) => { state.detailedEvents = [usageEvent('a'.repeat(64), 'bad')]; },
    (state) => { state.runs = [{ runId: 'bad', status: 'complete' }]; },
  ];
  for (const [index, mutate] of mutations.entries()) {
    const root = tempDir();
    const options = recoveryFixture(root, `2026082200001${index}-eeeeeeeeee`);
    const crashed = await gardener.runGardener('weekly', { ...options, crashAt: 'commit' });
    assert.equal(crashed.exitCode, 1);
    const stageDir = path.join(options.home, '.canuto', 'cache', 'skill-gardener', 'staging', options.runId);
    const pendingPath = path.join(stageDir, 'pending-state.json');
    const commitPath = path.join(stageDir, 'commit.json');
    const pending = gardener.readJson(pendingPath);
    mutate(pending);
    const pendingRaw = `${JSON.stringify(pending, null, 2)}\n`;
    writeFile(pendingPath, pendingRaw);
    const commit = gardener.readJson(commitPath);
    commit.pendingStateHash = gardener.sha256(Buffer.from(pendingRaw));
    writeFile(commitPath, `${JSON.stringify(commit, null, 2)}\n`);
    const recovered = await gardener.runGardener('weekly', options);
    assert.equal(recovered.error, 'state-invalid', `mutation ${index}`);
    assert.equal(fs.existsSync(statePathFor(options)), false);
    assert.equal(fs.existsSync(stageDir), true);
  }
});

test('recovery repairs READY receipt without rewriting promoted state', async () => {
  const root = tempDir();
  const options = recoveryFixture(root, '20260822000020-fffffffff0');
  const crashed = await gardener.runGardener('weekly', { ...options, crashAt: 'promotion' });
  assert.equal(crashed.exitCode, 1);
  const statePath = statePathFor(options);
  const before = fs.readFileSync(statePath);
  const stageDir = path.join(options.home, '.canuto', 'cache', 'skill-gardener', 'staging', options.runId);
  const savedStage = path.join(root, 'saved-stage');
  fs.cpSync(stageDir, savedStage, { recursive: true });
  assert.equal(gardener.readJson(artifactPathFor(options, 'receipts', options.runId)).cursorPromotion, 'READY');
  const recovered = await gardener.runGardener('weekly', options);
  assert.equal(recovered.exitCode, 0);
  assert.deepEqual(fs.readFileSync(statePath), before);
  assert.equal(gardener.readJson(artifactPathFor(options, 'receipts', options.runId)).cursorPromotion, 'PROMOTED');
  assert.equal(fs.existsSync(stageDir), false);
  fs.cpSync(savedStage, stageDir, { recursive: true });
  const promotedBefore = fs.readFileSync(statePath);
  assert.equal((await gardener.runGardener('weekly', options)).exitCode, 0);
  assert.deepEqual(fs.readFileSync(statePath), promotedBefore);
  assert.equal(fs.existsSync(stageDir), false);
});

test('recovery refuses wrong active-run ancestry for READY repair and PROMOTED cleanup', async () => {
  const root = tempDir();
  const ancestor = recoveryFixture(root, '20260822000021-aaaaaaaaaa');
  const pending = recoveryFixture(root, '20260822000022-bbbbbbbbbb');
  assert.equal((await gardener.runGardener('weekly', ancestor)).exitCode, 0);
  assert.equal((await gardener.runGardener('weekly', { ...pending, crashAt: 'promotion' })).exitCode, 1);
  const stageDir = path.join(pending.home, '.canuto', 'cache', 'skill-gardener', 'staging', pending.runId);
  const pendingPath = path.join(stageDir, 'pending-state.json');
  const commitPath = path.join(stageDir, 'commit.json');
  const pendingState = gardener.readJson(pendingPath);
  pendingState.runs = [{ runId: '20260822000020-9999999999', status: 'complete' }, { runId: pending.runId, status: 'complete' }];
  const pendingRaw = `${JSON.stringify(pendingState, null, 2)}\n`;
  writeFile(pendingPath, pendingRaw);
  const commit = gardener.readJson(commitPath);
  commit.pendingStateHash = gardener.sha256(Buffer.from(pendingRaw));
  writeFile(commitPath, `${JSON.stringify(commit, null, 2)}\n`);
  const receiptPath = artifactPathFor(pending, 'receipts', pending.runId);
  assert.equal(gardener.readJson(receiptPath).cursorPromotion, 'READY');

  assert.equal((await gardener.runGardener('weekly', pending)).exitCode, 0);
  assert.equal(gardener.readJson(receiptPath).cursorPromotion, 'READY');
  assert.equal(fs.existsSync(stageDir), true);

  const promotedReceipt = gardener.readJson(receiptPath);
  promotedReceipt.cursorPromotion = 'PROMOTED';
  writeFile(receiptPath, `${JSON.stringify(promotedReceipt, null, 2)}\n`);
  assert.equal((await gardener.runGardener('weekly', pending)).exitCode, 0);
  assert.equal(fs.existsSync(stageDir), true);
  assert.equal(gardener.readJson(receiptPath).cursorPromotion, 'PROMOTED');
});

test('run B promotes after staged A even when B sorts before A, and terminal mismatches stay pending', async () => {
  const root = tempDir();
  const a = recoveryFixture(root, '20260822000022-fffffffff1');
  const b = recoveryFixture(root, '20260822000021-0000000001');
  const stagedA = await gardener.runGardener('weekly', { ...a, crashAt: 'commit' });
  assert.equal(stagedA.exitCode, 1);
  const promotedB = await gardener.runGardener('weekly', b);
  assert.equal(promotedB.exitCode, 0);
  const stateAfterB = gardener.loadState(statePathFor(b));
  assert.deepEqual(stateAfterB.runs.map((run) => run.runId), [a.runId, b.runId]);

  const rootMismatch = tempDir();
  const active = recoveryFixture(rootMismatch, '20260822000024-0000000002');
  const pending = recoveryFixture(rootMismatch, '20260822000025-fffffffff2');
  const staged = await gardener.runGardener('weekly', { ...pending, crashAt: 'commit' });
  assert.equal(staged.exitCode, 1);
  const pendingStage = path.join(pending.home, '.canuto', 'cache', 'skill-gardener', 'staging', pending.runId);
  const savedStage = path.join(rootMismatch, 'saved-stage');
  fs.renameSync(pendingStage, savedStage);
  const activeRun = await gardener.runGardener('weekly', active);
  assert.equal(activeRun.exitCode, 0);
  fs.renameSync(savedStage, pendingStage);
  const pendingStatePath = path.join(pendingStage, 'pending-state.json');
  const commitPath = path.join(pendingStage, 'commit.json');
  const pendingState = gardener.readJson(pendingStatePath);
  pendingState.runs = [];
  const pendingRaw = `${JSON.stringify(pendingState, null, 2)}\n`;
  writeFile(pendingStatePath, pendingRaw);
  const commit = gardener.readJson(commitPath);
  commit.pendingStateHash = gardener.sha256(Buffer.from(pendingRaw));
  writeFile(commitPath, `${JSON.stringify(commit, null, 2)}\n`);
  const before = fs.readFileSync(statePathFor(active));
  const rerun = await gardener.runGardener('weekly', active);
  assert.equal(rerun.exitCode, 0);
  assert.deepEqual(fs.readFileSync(statePathFor(active)), before);
  assert.equal(fs.existsSync(pendingStage), true);
  assert.equal(gardener.readJson(artifactPathFor(pending, 'receipts', pending.runId)).cursorPromotion, 'READY');
});

test('eligible recovery unions the entire active event ledger into pending state', async () => {
  const root = tempDir();
  const a = recoveryFixture(root, '20260822000028-1111111111');
  const b = recoveryFixture(root, '20260822000029-2222222222');
  assert.equal((await gardener.runGardener('weekly', a)).exitCode, 0);
  const activeStatePath = statePathFor(a);
  const activeState = gardener.loadState(activeStatePath);
  const activeKey = 'a'.repeat(64);
  const pendingKey = 'b'.repeat(64);
  activeState.eventKeys = { [activeKey]: 1 };
  writeFile(activeStatePath, `${JSON.stringify(activeState, null, 2)}\n`);
  assert.equal((await gardener.runGardener('weekly', { ...b, crashAt: 'commit' })).exitCode, 1);
  const stageDir = path.join(b.home, '.canuto', 'cache', 'skill-gardener', 'staging', b.runId);
  const pendingPath = path.join(stageDir, 'pending-state.json');
  const commitPath = path.join(stageDir, 'commit.json');
  const pending = gardener.readJson(pendingPath);
  pending.eventKeys = { [pendingKey]: 1 };
  const pendingRaw = `${JSON.stringify(pending, null, 2)}\n`;
  writeFile(pendingPath, pendingRaw);
  const commit = gardener.readJson(commitPath);
  commit.pendingStateHash = gardener.sha256(Buffer.from(pendingRaw));
  writeFile(commitPath, `${JSON.stringify(commit, null, 2)}\n`);
  assert.equal((await gardener.runGardener('weekly', b)).exitCode, 0);
  assert.deepEqual(Object.keys(gardener.loadState(activeStatePath).eventKeys), [activeKey, pendingKey]);
});

test('stale promoted stage cannot roll back later state fields', async () => {
  const root = tempDir();
  const a = recoveryFixture(root, '20260822000027-aaaaaaaaaa');
  const b = recoveryFixture(root, '20260822000026-bbbbbbbbbb');
  const stagedA = await gardener.runGardener('weekly', { ...a, crashAt: 'commit' });
  assert.equal(stagedA.exitCode, 1);
  const stageA = path.join(a.home, '.canuto', 'cache', 'skill-gardener', 'staging', a.runId);
  const saved = path.join(root, 'saved-stage');
  fs.renameSync(stageA, saved);
  const promotedB = await gardener.runGardener('weekly', b);
  assert.equal(promotedB.exitCode, 0);
  fs.renameSync(saved, stageA);
  const statePath = statePathFor(b);
  const before = fs.readFileSync(statePath);
  const rerun = await gardener.runGardener('weekly', b);
  assert.equal(rerun.exitCode, 0);
  assert.deepEqual(fs.readFileSync(statePath), before);
  assert.equal(fs.existsSync(stageA), true);
  assert.equal(gardener.readJson(artifactPathFor(a, 'receipts', a.runId)).cursorPromotion, 'READY');
  const state = gardener.loadState(statePath);
  assert.deepEqual(state.runs.map((run) => run.runId), [b.runId]);
});

function historyConfig(root, eventRows) {
  const skills = path.join(root, 'skills');
  const history = path.join(root, 'history');
  writeFile(path.join(skills, 'audit', 'SKILL.md'), '# audit\n');
  writeFile(path.join(history, 'session.jsonl'), eventRows.map((row) => JSON.stringify({ event: 'Skill', skill: 'audit', event_id: row.id, timestamp: row.timestamp })).join('\n') + '\n');
  return {
    skills,
    history,
    config: { projects: {}, providers: { ...emptyProviderConfig(), codex: { roots: [skills], pluginRoots: [], historyRoots: [history] } } },
  };
}

test('permanent event ledger survives payload retention', async () => {
  const root = tempDir();
  const fixture = historyConfig(root, [
    { id: 'expired-usage', timestamp: '2026-01-01T00:00:00.000Z' },
  ]);
  const eventLog = path.join(root, 'event-log.sh');
  writeFile(eventLog, '#!/bin/sh\nexit 0\n', 0o755);
  const common = {
    home: path.join(root, 'home'),
    config: fixture.config,
    vaultRoot: path.join(root, 'vault'),
    eventLogPath: eventLog,
    frameworkRoot: path.join(root, 'missing-framework'),
    now: '2026-08-22T00:00:00.000Z',
    hmacKey: 'c'.repeat(64),
  };
  const first = await gardener.runGardener('backfill', { ...common, runId: '20260822000030-1111111111' });
  assert.equal(first.exitCode, 0);
  assert.equal(first.report.verifiedUsage.total, 0);
  const statePath = statePathFor(common);
  const firstState = gardener.loadState(statePath);
  assert.equal(Object.keys(firstState.eventKeys).length, 1);
  assert.deepEqual(firstState.detailedEvents, []);
  const skill = gardener.makeSkillIdentity({ name: 'audit', content: '# audit\n', hmacKey: common.hmacKey });
  assert.equal(firstState.lifetimeUsage[skill.skillKey], 1);
  assert.equal(gardener.readJson(artifactPathFor(common, 'receipts', first.runId)).eventCount, 1);

  const second = await gardener.runGardener('weekly', { ...common, runId: '20260822000031-2222222222' });
  assert.equal(second.exitCode, 0);
  assert.equal(second.report.verifiedUsage.total, 0);
  const secondState = gardener.loadState(statePath);
  assert.equal(Object.keys(secondState.eventKeys).length, 1);
  assert.equal(secondState.lifetimeUsage[skill.skillKey], 1);
});

test('retained views exclusively drive report detail', async () => {
  const root = tempDir();
  const fixture = historyConfig(root, [
    { id: 'expired-detail', timestamp: '2026-01-01T00:00:00.000Z' },
    { id: 'retained-detail', timestamp: '2026-08-21T00:00:00.000Z' },
  ]);
  const eventLog = path.join(root, 'event-log.sh');
  writeFile(eventLog, '#!/bin/sh\nexit 0\n', 0o755);
  const common = {
    home: path.join(root, 'home'),
    config: fixture.config,
    vaultRoot: path.join(root, 'vault'),
    eventLogPath: eventLog,
    frameworkRoot: path.join(root, 'missing-framework'),
    now: '2026-08-22T00:00:00.000Z',
    hmacKey: 'd'.repeat(64),
  };
  const result = await gardener.runGardener('backfill', { ...common, runId: '20260822000032-3333333333' });
  assert.equal(result.exitCode, 0);
  assert.equal(result.report.verifiedUsage.total, 1);
  assert.equal(result.report.verifiedUsage.events[0].timestamp, '2026-08-21T00:00:00.000Z');
  assert.equal(result.report.verifiedUsage.events.some((event) => event.timestamp.startsWith('2026-01')), false);
  assert.equal(gardener.readJson(artifactPathFor(common, 'receipts', result.runId)).eventCount, 2);
  const state = gardener.loadState(statePathFor(common));
  assert.equal(state.detailedEvents.length, 1);
  assert.equal(Object.keys(state.eventKeys).length, 2);
  const skill = gardener.makeSkillIdentity({ name: 'audit', content: '# audit\n', hmacKey: common.hmacKey });
  assert.equal(state.lifetimeUsage[skill.skillKey], 2);
});

test('crash boundaries promote each event exactly once', async () => {
  const root = tempDir();
  const fixture = historyConfig(root, [{ id: 'crash-once', timestamp: '2026-08-21T00:00:00.000Z' }]);
  const eventLog = path.join(root, 'event-log.sh');
  writeFile(eventLog, '#!/bin/sh\nexit 0\n', 0o755);
  const common = {
    home: path.join(root, 'home'),
    config: fixture.config,
    vaultRoot: path.join(root, 'vault'),
    eventLogPath: eventLog,
    frameworkRoot: path.join(root, 'missing-framework'),
    now: '2026-08-22T00:00:00.000Z',
    hmacKey: 'e'.repeat(64),
  };
  const runId = '20260822000033-4444444444';
  assert.equal((await gardener.runGardener('backfill', { ...common, runId, crashAt: 'commit' })).exitCode, 1);
  assert.equal((await gardener.runGardener('backfill', { ...common, runId })).exitCode, 0);
  const statePath = statePathFor(common);
  const skill = gardener.makeSkillIdentity({ name: 'audit', content: '# audit\n', hmacKey: common.hmacKey });
  assert.equal(gardener.loadState(statePath).lifetimeUsage[skill.skillKey], 1);
  const next = await gardener.runGardener('weekly', { ...common, runId: '20260822000034-5555555555' });
  assert.equal(next.exitCode, 0);
  assert.equal(next.report.verifiedUsage.total, 0);
  assert.equal(gardener.loadState(statePath).lifetimeUsage[skill.skillKey], 1);
});

function runInstallerLibrary(home, extra = {}) {
  const crontab = path.join(home, 'crontab');
  const env = {
    ...isolatedEnv(home, crontab),
    CANUTO_INSTALL_LIBRARY_ONLY: '1',
    ...extra,
  };
  return spawnSync('/bin/bash', ['-c', 'source "$1"; setup_skill_gardener', 'skill-gardener-test', path.join(__dirname, '..', 'install.sh')], {
    cwd: path.join(__dirname, '..'),
    encoding: 'utf8',
    env,
  });
}

test('Skill Gardener installer runs through the isolated stock /bin/bash path', () => {
  const root = tempDir();
  const home = path.join(root, 'home');
  fs.mkdirSync(home, { recursive: true });
  const result = runInstallerLibrary(home);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(fs.lstatSync(path.join(home, '.canuto', 'bin', 'canuto-skill-gardener')).isSymbolicLink(), true);
});

test('immutable installer validates before atomic activation', () => {
  const root = tempDir();
  const home = path.join(root, 'home');
  fs.mkdirSync(home, { recursive: true });
  const first = runInstallerLibrary(home);
  assert.equal(first.status, 0, first.stderr);
  const stable = path.join(home, '.canuto', 'bin', 'canuto-skill-gardener');
  assert.equal(fs.lstatSync(stable).isSymbolicLink(), true);
  const target = fs.realpathSync(stable);
  const releaseDir = path.dirname(target);
  const digest = path.basename(releaseDir);
  const cliHash = (file) => require('node:crypto').createHash('sha256').update(fs.readFileSync(file)).digest('hex');
  const expectedDigest = require('node:crypto').createHash('sha256').update(`canuto-skill-gardener-release-v1\0${cliHash(path.join(__dirname, 'canuto-skill-gardener.js'))}\0${cliHash(path.join(__dirname, 'canuto-skill-gardener-lib.js'))}`).digest('hex');
  assert.match(digest, /^[a-f0-9]{64}$/);
  assert.equal(digest, expectedDigest);
  assert.equal(fs.statSync(target).mode & 0o111, 0o111);
  assert.equal(fs.existsSync(path.join(releaseDir, 'canuto-skill-gardener-lib.js')), true);
  assert.equal(fs.existsSync(path.join(home, '.canuto', 'lib', 'canuto-skill-gardener-lib.js')), false);
  const configPath = path.join(home, '.canuto', 'config', 'skill-gardener.json');
  const configBefore = fs.readFileSync(configPath);
  const failed = runInstallerLibrary(home, { CANUTO_SKILL_GARDENER_TEST_FAIL_ACTIVATION: '1' });
  assert.equal(failed.status, 1);
  assert.equal(fs.realpathSync(stable), target);
  assert.deepEqual(fs.readFileSync(configPath), configBefore);
});

test('installer keeps exact legacy config and old runtime when activation fails', () => {
  const root = tempDir();
  const home = path.join(root, 'home');
  fs.mkdirSync(home, { recursive: true });
  const first = runInstallerLibrary(home);
  assert.equal(first.status, 0, first.stderr);
  const stable = path.join(home, '.canuto', 'bin', 'canuto-skill-gardener');
  const oldRuntime = fs.realpathSync(stable);
  const configPath = path.join(home, '.canuto', 'config', 'skill-gardener.json');
  const legacy = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  legacy.projects['lucrando-ai'].surfaces['ssh-papiro'].historyRoots = ['/srv/dev/worktrees/lucrando-ai/main/.codex/sessions'];
  legacy.projects.papiro.surfaces['ssh-papiro'].historyRoots = ['/srv/dev/worktrees/papiro/main/.codex/sessions'];
  legacy.projects['mecesa-v1'].surfaces['ssh-papiro'].roots = ['/srv/dev/worktrees/mecesa-v1/main'];
  legacy.projects['mecesa-v1'].surfaces['ssh-papiro'].historyRoots = ['/srv/dev/worktrees/mecesa-v1/main/.codex/sessions'];
  legacy.providers.hermes.historyRoots = ['~/.hermes/sessions', '~/.hermes/history'];
  writeFile(configPath, `${JSON.stringify(legacy, null, 2)}\n`);
  const originalConfig = fs.readFileSync(configPath);

  const failed = runInstallerLibrary(home, { CANUTO_SKILL_GARDENER_TEST_FAIL_ACTIVATION: '1' });
  assert.equal(failed.status, 1);
  assert.equal(fs.realpathSync(stable), oldRuntime);
  assert.deepEqual(fs.readFileSync(configPath), originalConfig);
  assert.deepEqual(fs.readdirSync(path.dirname(configPath)).filter((name) => name.includes('.tmp-migrate-')), []);
});

test('installer aborts activation when config changes after validation', () => {
  const root = tempDir();
  const home = path.join(root, 'home');
  fs.mkdirSync(home, { recursive: true });
  const first = runInstallerLibrary(home);
  assert.equal(first.status, 0, first.stderr);
  const stable = path.join(home, '.canuto', 'bin', 'canuto-skill-gardener');
  const target = fs.realpathSync(stable);
  const failed = runInstallerLibrary(home, { CANUTO_SKILL_GARDENER_TEST_SWAP_CONFIG_BEFORE_ACTIVATION: '1' });
  assert.equal(failed.status, 1);
  assert.equal(fs.realpathSync(stable), target);
  assert.equal(JSON.parse(fs.readFileSync(path.join(home, '.canuto', 'config', 'skill-gardener.json'), 'utf8')).schemaVersion, 2);
});

test('installer preserves valid config race winner and rejects invalid winner', () => {
  const validRoot = tempDir();
  const validHome = path.join(validRoot, 'home');
  fs.mkdirSync(path.join(validHome, '.canuto', 'config'), { recursive: true });
  const validConfig = fs.readFileSync(path.join(__dirname, '..', 'config', 'skill-gardener.json'));
  writeFile(path.join(validHome, '.canuto', 'config', 'skill-gardener.json'), validConfig);
  const valid = runInstallerLibrary(validHome);
  assert.equal(valid.status, 0, valid.stderr);
  assert.deepEqual(fs.readFileSync(path.join(validHome, '.canuto', 'config', 'skill-gardener.json')), validConfig);

  const invalidRoot = tempDir();
  const invalidHome = path.join(invalidRoot, 'home');
  fs.mkdirSync(path.join(invalidHome, '.canuto', 'config'), { recursive: true });
  const invalidConfigPath = path.join(invalidHome, '.canuto', 'config', 'skill-gardener.json');
  writeFile(invalidConfigPath, '{broken');
  const invalid = runInstallerLibrary(invalidHome);
  assert.equal(invalid.status, 1);
  assert.equal(fs.existsSync(path.join(invalidHome, '.canuto', 'bin', 'canuto-skill-gardener')), false);
  assert.equal(fs.readFileSync(invalidConfigPath, 'utf8'), '{broken');
});

test('installer atomically migrates only the exact legacy Skill Gardener defaults', () => {
  const root = tempDir();
  const home = path.join(root, 'home');
  fs.mkdirSync(home, { recursive: true });
  const first = runInstallerLibrary(home);
  assert.equal(first.status, 0, first.stderr);
  const configPath = path.join(home, '.canuto', 'config', 'skill-gardener.json');
  const legacy = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  legacy.projects['lucrando-ai'].surfaces['ssh-papiro'].historyRoots = ['/srv/dev/worktrees/lucrando-ai/main/.codex/sessions'];
  legacy.projects.papiro.surfaces['ssh-papiro'].historyRoots = ['/srv/dev/worktrees/papiro/main/.codex/sessions'];
  legacy.projects['mecesa-v1'].surfaces['ssh-papiro'].roots = ['/srv/dev/worktrees/mecesa-v1/main'];
  legacy.projects['mecesa-v1'].surfaces['ssh-papiro'].historyRoots = ['/srv/dev/worktrees/mecesa-v1/main/.codex/sessions'];
  legacy.providers.hermes.historyRoots = ['~/.hermes/sessions', '~/.hermes/history'];
  legacy.projects['lucrando-ai'].surfaces.mac.historyRoots = ['/custom/history'];
  legacy.providers.hermes.pluginRoots = ['/custom/hermes/plugins'];
  writeFile(configPath, `${JSON.stringify(legacy, null, 2)}\n`);

  const migrated = runInstallerLibrary(home);
  assert.equal(migrated.status, 0, migrated.stderr);
  const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  assert.deepEqual(config.projects['lucrando-ai'].surfaces['ssh-papiro'].historyRoots, ['~/.codex/sessions', '~/.codex/archived_sessions']);
  assert.deepEqual(config.projects.papiro.surfaces['ssh-papiro'].historyRoots, ['~/.codex/sessions', '~/.codex/archived_sessions']);
  assert.deepEqual(config.projects['mecesa-v1'].surfaces['ssh-papiro'].roots, ['/srv/dev/worktrees/mecesa/main']);
  assert.deepEqual(config.projects['mecesa-v1'].surfaces['ssh-papiro'].historyRoots, ['~/.codex/sessions', '~/.codex/archived_sessions']);
  assert.deepEqual(config.providers.hermes.historyRoots, ['~/.hermes/sessions']);
  assert.deepEqual(config.projects['lucrando-ai'].surfaces.mac.historyRoots, ['/custom/history']);
  assert.deepEqual(config.providers.hermes.pluginRoots, ['/custom/hermes/plugins']);
});

test('installer cleanup refuses a lock nonce mismatch', () => {
  const root = tempDir();
  const home = path.join(root, 'home');
  const releases = path.join(home, '.canuto', 'lib', 'skill-gardener', 'releases');
  fs.mkdirSync(home, { recursive: true });
  const install = path.join(__dirname, '..', 'install.sh');
  const result = spawnSync('/bin/bash', ['-c', 'INSTALL_SCRIPT="$1"; RELEASES_DIR="$2"; source "$INSTALL_SCRIPT"; acquire_skill_gardener_materialize_lock "$RELEASES_DIR" nonce-a; printf \'{"nonce":"nonce-b"}\n\' > "$RELEASES_DIR/.materialize.lock/owner.json"; release_skill_gardener_materialize_lock "$RELEASES_DIR" nonce-a', 'lock-test', install, releases], {
    cwd: path.join(__dirname, '..'),
    encoding: 'utf8',
    env: { ...isolatedEnv(home, path.join(home, 'crontab')), CANUTO_INSTALL_LIBRARY_ONLY: '1' },
  });
  assert.notEqual(result.status, 0);
  assert.equal(fs.existsSync(path.join(releases, '.materialize.lock')), true);
  fs.rmSync(path.join(releases, '.materialize.lock'), { recursive: true, force: true });
});

test('real installer dispatch preserves repair outcome matrix', () => {
  const install = path.join(__dirname, '..', 'install.sh');
  const modes = [
    { name: 'repair', args: ['--repair'], expected: (rc) => rc },
    { name: 'doctor', args: ['--doctor'], expected: (rc) => rc },
    { name: 'install', args: [], expected: (rc) => rc },
    { name: 'update', args: ['--update'], expected: (rc) => rc === 10 ? 0 : rc },
    { name: 'migrate', args: ['--migrate'], expected: (rc) => rc },
  ];
  for (const mode of modes) {
    for (const repairRc of [0, 10, 20, 30]) {
      const root = tempDir();
      const home = path.join(root, 'home');
      const cwd = path.join(root, 'checkout');
      const crontab = path.join(root, 'crontab');
      fs.mkdirSync(home, { recursive: true });
      fs.mkdirSync(cwd, { recursive: true });
      const env = {
        ...isolatedEnv(home, crontab),
        CANUTO_INSTALL_TEST_DISPATCH_REPAIR_RC: String(repairRc),
      };
      const result = spawnSync('/bin/bash', [install, ...mode.args], { cwd, encoding: 'utf8', env });
      assert.equal(result.status, mode.expected(repairRc), `${mode.name}/${repairRc}\n${result.stdout}\n${result.stderr}`);
      const output = `${result.stdout}\n${result.stderr}`;
      if ([10, 30].includes(repairRc)) assert.match(output, /dependency repair failed/i);
      if ([20, 30].includes(repairRc)) assert.match(output, /skill gardener repair failed/i);
      if (mode.name === 'update' && repairRc === 10) assert.match(output, /Continuing update/i);
      if (mode.name === 'update' && [20, 30].includes(repairRc)) assert.match(output, /Framework files may already be updated/i);
      assert.equal(fs.existsSync(path.join(home, '.canuto')), false);
      assert.equal(fs.existsSync(path.join(cwd, '.agents')), false);
      assert.equal(fs.existsSync(crontab), false);
    }
  }
});
