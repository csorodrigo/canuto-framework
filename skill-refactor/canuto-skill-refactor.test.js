'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const lib = require('./canuto-skill-refactor-lib');
const cli = require('./canuto-skill-refactor');

function tempDir(t) {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'skill-refactor-test-'));
  t.after(() => {
    makeTreeWritable(root);
    fs.rmSync(root, { recursive: true, force: true, maxRetries: 3, retryDelay: 10 });
  });
  return root;
}

function makeTreeWritable(root) {
  if (!fs.existsSync(root)) return;
  const stat = fs.lstatSync(root);
  if (stat.isSymbolicLink()) return;
  if (stat.isDirectory()) {
    fs.chmodSync(root, 0o700);
    for (const entry of fs.readdirSync(root)) makeTreeWritable(path.join(root, entry));
  } else if (stat.isFile()) fs.chmodSync(root, 0o600);
}

function writeFile(filePath, content, mode = 0o600) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, content, { mode });
  fs.chmodSync(filePath, mode);
}

function skillText(name, marker = 'base') {
  return `---\nname: ${name}\ndescription: Use ${name} for a specific tested workflow (${marker}).\n---\n\n# ${name}\n\nFollow the ${marker} workflow.\n`;
}

function writeSkill(root, name, marker = 'base', extras = {}) {
  const directory = path.join(root, name);
  writeFile(path.join(directory, 'SKILL.md'), extras.skillText || skillText(name, marker));
  for (const [relative, content] of Object.entries(extras.files || {})) writeFile(path.join(directory, relative), content);
  return directory;
}

function provider(roots = [], pluginRoots = [], systemRoots = []) {
  return { roots, pluginRoots, systemRoots, historyRoots: [] };
}

function configFor({ roots = [], pluginRoots = [], systemRoots = [], projects = {} } = {}) {
  return {
    schemaVersion: 1,
    projects,
    providers: {
      codex: provider(roots, pluginRoots, systemRoots),
      claude: provider(),
      hermes: provider(),
      opencode: provider(),
    },
    policy: {
      detailRetentionDays: 180,
      fingerprintFamilies: { tools: [], executables: [], results: [] },
      evalAdapter: { enabled: false, command: 'agent-skill-eval', version: 'v1' },
    },
  };
}

function writeConfig(root, config) {
  const target = path.join(root, 'skill-gardener.json');
  writeFile(target, `${JSON.stringify(config, null, 2)}\n`);
  return target;
}

function scanFixture(t, setup = {}) {
  const root = tempDir(t);
  const live = path.join(root, 'live');
  const globalA = path.join(live, 'global-a');
  const globalB = path.join(live, 'global-b');
  const plugins = path.join(live, 'plugins', 'cache');
  const inactive = path.join(live, '_retired-2026');
  const projectA = path.join(live, 'project-a');
  const projectB = path.join(live, 'project-b');
  for (const directory of [globalA, globalB, plugins, inactive, projectA, projectB]) fs.mkdirSync(directory, { recursive: true });

  writeSkill(globalA, 'keep-one');
  writeSkill(path.join(globalA, '.system'), 'builtin-tool');
  writeSkill(globalA, 'needs-merge', 'variant-a');
  writeSkill(globalB, 'needs-merge', 'variant-b');
  const shared = skillText('resource-diverge', 'shared-entrypoint');
  writeSkill(globalA, 'resource-diverge', 'shared-entrypoint', { skillText: shared, files: { 'references/rules.md': 'rules A\n' } });
  writeSkill(globalB, 'resource-diverge', 'shared-entrypoint', { skillText: shared, files: { 'references/rules.md': 'rules B\n' } });
  writeSkill(globalA, 'broken-meta', 'broken', { skillText: '---\nname: broken-meta\n---\n\n# Broken\n' });
  writeSkill(globalA, 'secret-bundle', 'secret', { files: { '.env.production': 'DO_NOT_COPY=secret-value\n' } });
  writeSkill(path.join(globalA, 'build'), 'legit-build');
  writeSkill(path.join(globalA, 'dist'), 'legit-dist');
  writeSkill(path.join(globalA, 'coverage'), 'legit-coverage');
  writeSkill(path.join(globalA, 'fixtures'), 'legit-fixtures');
  writeSkill(plugins, 'managed-only');
  writeSkill(globalA, 'managed-collision', 'author-copy');
  writeSkill(plugins, 'managed-collision', 'managed-copy');
  writeSkill(inactive, 'old-skill');
  writeSkill(projectA, 'project-conflict', 'project-a');
  writeSkill(projectB, 'project-conflict', 'project-b');

  const projects = {
    alpha: { surfaces: { local: { provider: 'codex', roots: [projectA], aliases: ['A'], historyRoots: [] } } },
    beta: { surfaces: { local: { provider: 'codex', roots: [projectB], aliases: ['B'], historyRoots: [] } } },
  };
  const configPath = writeConfig(root, configFor({ roots: [globalA, globalB, inactive], pluginRoots: [plugins], projects }));
  const workspace = path.join(root, 'workspace');
  const frameworkRoot = path.join(root, 'framework-without-live-skills');
  if (setup.beforeScan) setup.beforeScan({ root, live, globalA, globalB, plugins, inactive, projectA, projectB, workspace, frameworkRoot, configPath });
  const result = lib.scanWorkspace({ workspace, configPath, frameworkRoot, home: root });
  return { root, live, globalA, globalB, plugins, inactive, projectA, projectB, workspace, frameworkRoot, configPath, result };
}

function fakeDelegate(root) {
  const target = path.join(root, 'fake-delegate.js');
  writeFile(target, `#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const taskPath = process.argv[3];
const resultPath = process.argv[4];
const cwd = process.cwd();
const attemptPath = path.join(cwd, '.fake-attempt');
let attempt = 1;
try { attempt = Number(fs.readFileSync(attemptPath, 'utf8')) + 1; } catch {}
fs.writeFileSync(attemptPath, String(attempt));
if (process.env.FAKE_ENV_OUTPUT) fs.writeFileSync(process.env.FAKE_ENV_OUTPUT, JSON.stringify(process.env));
if (process.env.FAKE_DELEGATE_FAIL === 'always' || (process.env.FAKE_DELEGATE_FAIL === 'first' && attempt === 1)) process.exit(7);
const task = fs.readFileSync(taskPath, 'utf8');
const name = task.match(/Logical skill name: ([^\\n]+)/)[1].trim();
const candidate = path.join(cwd, 'candidate', name);
fs.mkdirSync(path.join(candidate, 'agents'), { recursive: true });
fs.writeFileSync(path.join(candidate, 'SKILL.md'), '---\\nname: ' + name + '\\ndescription: Consolidated candidate for the tested ' + name + ' workflow.\\n---\\n\\n# ' + name + '\\n\\nUse the reconciled candidate instructions and preserve source behavior.\\n');
fs.writeFileSync(path.join(candidate, 'agents', 'openai.yaml'), 'interface:\\n  display_name: "' + name + '"\\n  short_description: "Consolidated tested workflow"\\n  default_prompt: "Use $' + name + ' to run the reconciled workflow."\\n');
const coveragePath = path.join(cwd, 'coverage.md');
const coverage = fs.readFileSync(coveragePath, 'utf8')
  .replace('status: prepared', 'status: completed')
  .replace(/preservation-decision: PENDING/g, 'preservation-decision: Preserved commands, constraints, resources, and invocation policy in the consolidated candidate.');
fs.writeFileSync(coveragePath, coverage);
fs.writeFileSync(resultPath, 'candidate generated\\n');
`, 0o700);
  return target;
}

async function withEnv(values, callback) {
  const previous = {};
  const scoped = { ...values };
  for (const [key, value] of Object.entries(scoped)) {
    previous[key] = process.env[key];
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
  try { return await callback(); } finally {
    for (const [key, value] of Object.entries(previous)) {
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

function testValidator(root) {
  const target = path.join(root, 'test-quick-validate.py');
  writeFile(target, `#!/usr/bin/env python3
import pathlib
import sys

candidate = pathlib.Path(sys.argv[1])
sys.exit(0 if (candidate / 'SKILL.md').is_file() and (candidate / 'SKILL.md').read_text().startswith('---') else 1)
`, 0o700);
  return target;
}

function withTestEnv(fixture, values, callback) {
  return withEnv(values, callback);
}

function runWithTestDelegate(fixture, delegate, options = {}) {
  return lib.runWorkspace({
    ...options,
    workspace: fixture.workspace,
    delegatePath: delegate,
    allowTestDelegate: true,
    validatorPath: testValidator(fixture.root),
    allowTestValidator: true,
  });
}

test('CLI parser is strict and supports JSON before the command', () => {
  assert.equal(cli.parseArgs(['--json', 'doctor']).command, 'doctor');
  assert.deepEqual(cli.parseArgs(['run', '--workspace', '/tmp/work', '--workers', '4', '--resume']).options, { workspace: '/tmp/work', workers: '4', resume: true });
  assert.equal(cli.parseArgs(['run', '--workspace', 'relative']).error.code, 'workspace-absolute-required');
  assert.equal(cli.parseArgs(['run', '--workspace', '/tmp/work', '--workers', '0']).error.code, 'workers-invalid');
  assert.equal(cli.parseArgs(['queue', '--workspace', '/tmp/work', '--resume']).error.code, 'option-not-allowed');
});

test('scan classifies the full estate and preserves resource-only divergence', (t) => {
  const fixture = scanFixture(t);
  const byName = new Map(fixture.result.manifest.items.map((item) => [item.name, item]));
  assert.equal(byName.get('keep-one').classification, 'KEEP');
  assert.equal(byName.get('builtin-tool').classification, 'MANAGED');
  assert.equal(byName.get('needs-merge').classification, 'REFACTOR');
  assert.equal(byName.get('resource-diverge').classification, 'REFACTOR');
  assert.ok(byName.get('resource-diverge').reasons.includes('divergent-resource-bundles'));
  assert.equal(byName.get('broken-meta').classification, 'REFACTOR');
  assert.equal(byName.get('managed-only').classification, 'MANAGED');
  assert.equal(byName.get('managed-collision').classification, 'REFACTOR');
  assert.ok(byName.get('managed-collision').reasons.includes('managed-name-collision'));
  assert.equal(byName.get('old-skill').classification, 'INACTIVE');
  assert.equal(byName.get('project-conflict').classification, 'BLOCKED_PROVENANCE');
  assert.equal(byName.get('secret-bundle').state, 'BLOCKED');
  assert.equal(byName.get('legit-build').classification, 'KEEP');
  assert.equal(byName.get('legit-dist').classification, 'KEEP');
  assert.equal(byName.get('legit-coverage').classification, 'KEEP');
  assert.equal(byName.get('legit-fixtures').classification, 'KEEP');

  const provenance = JSON.parse(fs.readFileSync(path.join(fixture.workspace, 'provenance.json'), 'utf8'));
  const divergent = provenance.items[byName.get('resource-diverge').workItemId];
  assert.equal(divergent.sources.length, 2);
  assert.notEqual(divergent.sources[0].contentHash, divergent.sources[1].contentHash);
  assert.equal(fs.statSync(path.join(fixture.workspace, 'provenance.json')).mode & 0o777, 0o600);
  const publicText = fs.readFileSync(path.join(fixture.workspace, 'manifest.json'), 'utf8');
  assert.doesNotMatch(publicText, /\/tmp\/|sourcePath|secret-value/);
  const stagedText = fs.readdirSync(path.join(fixture.workspace, 'work-items', 'secret-bundle'), { recursive: true }).join('\n');
  assert.doesNotMatch(stagedText, /\.env|secret-value/);
});

test('scan is idempotent and refuses both live-root overlap and scan replacement', (t) => {
  const fixture = scanFixture(t);
  const second = lib.scanWorkspace({ workspace: fixture.workspace, configPath: fixture.configPath, frameworkRoot: fixture.frameworkRoot, home: fixture.root });
  assert.equal(second.changed, false);
  assert.throws(
    () => lib.scanWorkspace({ workspace: path.join(fixture.globalA, 'unsafe-workspace'), configPath: fixture.configPath, frameworkRoot: fixture.frameworkRoot, home: fixture.root }),
    (error) => error.code === 'workspace-live-root',
  );
  writeSkill(fixture.globalA, 'new-after-scan');
  assert.throws(
    () => lib.scanWorkspace({ workspace: fixture.workspace, configPath: fixture.configPath, frameworkRoot: fixture.frameworkRoot, home: fixture.root }),
    (error) => error.code === 'workspace-scan-mismatch',
  );
});

test('run, validate, queue and preview revalidate a workspace relocated under a live root', async (t) => {
  const fixture = scanFixture(t);
  const relocatedRoot = path.join(fixture.live, 'relocated-live-root');
  fs.mkdirSync(relocatedRoot, { recursive: true });
  const config = JSON.parse(fs.readFileSync(fixture.configPath, 'utf8'));
  config.providers.codex.roots.push(relocatedRoot);
  writeFile(fixture.configPath, `${JSON.stringify(config, null, 2)}\n`);
  const relocatedWorkspace = path.join(relocatedRoot, 'workspace');
  fs.renameSync(fixture.workspace, relocatedWorkspace);
  await assert.rejects(() => lib.runWorkspace({ workspace: relocatedWorkspace, limit: 0 }), (error) => error.code === 'workspace-live-root');
  for (const operation of [
    () => lib.validateWorkspace({ workspace: relocatedWorkspace }),
    () => lib.queueWorkspace(relocatedWorkspace),
    () => lib.previewWorkspace(relocatedWorkspace, 'needs-merge'),
  ]) assert.throws(operation, (error) => error.code === 'workspace-live-root');
});

test('generated reconciliation failure is visible in status and exit code', async (t) => {
  const fixture = scanFixture(t);
  const entry = lib.loadedWorkspace(fixture.workspace).entries.find((item) => item.state.state === 'PENDING');
  const statePath = path.join(fixture.workspace, 'work-items', entry.skill.name, 'state.json');
  writeFile(statePath, `${JSON.stringify({ ...entry.state, state: 'GENERATED' }, null, 2)}\n`);
  const result = await lib.runWorkspace({ workspace: fixture.workspace, workers: 1, limit: 0 });
  const failed = result.results.find((item) => item.name === entry.skill.name);
  assert.equal(failed.state, 'FAILED');
  assert.equal(failed.claimed, false);
  assert.equal(result.status, 'PARTIAL');
  assert.equal(result.exitCode, 2);
  assert.equal(result.counts.failedOrBlocked, 1);
});

test('candidate validation rejects broken references, scaffolds and stale copies', (t) => {
  const root = tempDir(t);
  const candidate = writeSkill(root, 'candidate-one', 'candidate', {
    files: { 'agents/openai.yaml': 'interface:\n  default_prompt: "Use $candidate-one for this workflow."\n' },
  });
  const valid = lib.validateCandidate(candidate, 'candidate-one', ['not-this-hash'], { requireChanged: true });
  assert.equal(valid.valid, true, valid.reasons.join(','));
  writeFile(path.join(candidate, 'SKILL.md'), `${skillText('candidate-one', 'candidate')}\n[Missing](references/missing.md)\nTODO\n`);
  const broken = lib.validateCandidate(candidate, 'candidate-one');
  assert.equal(broken.valid, false);
  assert.ok(broken.reasons.includes('missing-local-reference'));
  assert.ok(broken.reasons.includes('unfinished-scaffold-marker'));
  writeFile(path.join(candidate, 'SKILL.md'), skillText('candidate-one', 'candidate'));
  const unchanged = lib.validateCandidate(candidate, 'candidate-one', [lib.sha256(skillText('candidate-one', 'candidate'))], { requireChanged: true });
  assert.ok(unchanged.reasons.includes('unchanged-source'));
  writeFile(path.join(candidate, 'SKILL.md'), '---\nname: Candidate One\ndescription: This looks normalized but violates the exact skill contract.\nextra: unsafe\n---\n\n# Invalid\n');
  const invalidContract = lib.validateCandidate(candidate, 'candidate-one');
  assert.ok(invalidContract.reasons.includes('name-mismatch'));
  assert.ok(invalidContract.reasons.includes('unexpected-frontmatter-key'));
  writeFile(path.join(candidate, 'SKILL.md'), `${skillText('candidate-one', 'candidate')}\nTags: tasks, todo, reminders.\n`);
  assert.equal(lib.validateCandidate(candidate, 'candidate-one').valid, true);
  writeFile(path.join(candidate, 'SKILL.md'), `${skillText('candidate-one', 'candidate')}\nAção segura com acentuação.\n`);
  assert.equal(lib.validateCandidate(candidate, 'candidate-one').valid, true);
});

test('oversized source files are represented as blocked work instead of being read wholesale', (t) => {
  const fixture = scanFixture(t, {
    beforeScan({ globalA }) {
      writeFile(path.join(globalA, 'oversized-source', 'SKILL.md'), Buffer.alloc(lib.MAX_FILE_BYTES + 1, 'x'));
    },
  });
  const item = lib.loadedWorkspace(fixture.workspace).entries.find((entry) => entry.skill.name === 'oversized-source');
  assert.equal(item.state.state, 'BLOCKED');
  assert.equal(item.state.reason, 'source-file-too-large');
  assert.ok(item.skill.reasons.includes('source-file-too-large'));
});

test('bounded reads fail closed when the pathname is replaced during the read', (t) => {
  const root = tempDir(t);
  const target = path.join(root, 'mutable.txt');
  const oldTarget = path.join(root, 'mutable.old.txt');
  writeFile(target, 'original content\n');
  const originalReadSync = fs.readSync;
  let swapped = false;
  fs.readSync = (...args) => {
    const bytes = originalReadSync(...args);
    if (!swapped) {
      swapped = true;
      fs.renameSync(target, oldTarget);
      writeFile(target, 'replacement content\n');
    }
    return bytes;
  };
  try {
    assert.throws(() => lib.readFileBounded(target, lib.MAX_FILE_BYTES, { failureCode: 'file-mutated', tooLargeCode: 'file-too-large' }), (error) => error.code === 'file-mutated');
  } finally {
    fs.readSync = originalReadSync;
  }
});

test('fake delegate validates a candidate, records coverage and leaves live sources unchanged', async (t) => {
  const fixture = scanFixture(t);
  const delegate = fakeDelegate(fixture.root);
  const sourcePath = path.join(fixture.globalA, 'broken-meta', 'SKILL.md');
  const before = lib.sha256(fs.readFileSync(sourcePath));
  const contract = path.join(fixture.root, 'contract.md');
  writeFile(contract, skillText('skill-creator-contract', 'contract'));
  const result = await withTestEnv(fixture, {
    CANUTO_SKILL_REFACTOR_DELEGATE: delegate,
    CANUTO_SKILL_REFACTOR_CONTRACT: contract,
    FAKE_DELEGATE_FAIL: undefined,
  }, () => runWithTestDelegate(fixture, delegate, { workers: 0, limit: 1 }));
  assert.equal(result.workers, 1);
  assert.equal(result.claimed, 1);
  assert.equal(result.results[0].state, 'VALIDATED', JSON.stringify(result.results));
  assert.equal(lib.sha256(fs.readFileSync(sourcePath)), before);
  const preview = lib.previewWorkspace(fixture.workspace, result.results[0].name);
  assert.equal(preview.state, 'VALIDATED');
  assert.equal(preview.coverageReceipt.present, true);
  assert.equal(preview.candidate.valid, true);
  const coverage = fs.readFileSync(path.join(fixture.workspace, 'work-items', result.results[0].name, 'coverage.md'), 'utf8');
  assert.match(coverage, /^status: completed$/m);
  assert.doesNotMatch(coverage, /PENDING/);
});

test('concurrent resumes claim one work item and conditional unlock preserves a replacement owner', async (t) => {
  const fixture = scanFixture(t);
  const delegate = slowCountingDelegate(fixture.root);
  const counter = path.join(fixture.root, 'resume-counter.json');
  const contract = path.join(fixture.root, 'contract.md');
  writeFile(contract, skillText('skill-creator-contract', 'contract'));
  const first = lib.loadedWorkspace(fixture.workspace).entries.find((entry) => entry.state.state === 'PENDING');
  const statePath = path.join(fixture.workspace, 'work-items', first.skill.name, 'state.json');
  writeFile(statePath, `${JSON.stringify({ ...first.state, state: 'RUNNING', pid: 999999, delegatePid: 999999 }, null, 2)}\n`);
  const lockRelease = lib.acquireLock(fixture.workspace, first.skill);
  assert.equal(typeof lockRelease, 'function');
  const lockPath = path.join(fixture.workspace, 'work-items', first.skill.name, '.claim.lock');
  const displacedPath = `${lockPath}.displaced`;
  fs.renameSync(lockPath, displacedPath);
  writeFile(lockPath, JSON.stringify({ pid: process.pid, token: 'replacement-owner', createdAt: new Date().toISOString() }));
  lockRelease();
  assert.equal(JSON.parse(fs.readFileSync(lockPath, 'utf8')).token, 'replacement-owner');
  fs.rmSync(lockPath, { force: true });
  fs.rmSync(displacedPath, { force: true });
  const competingOwner = lib.acquireLock(fixture.workspace, first.skill);
  assert.equal(typeof competingOwner, 'function');
  assert.equal(lib.acquireLock(fixture.workspace, first.skill), null);
  competingOwner();

  const originalWriteFileSync = fs.writeFileSync;
  let publishedOwner;
  let injecting = false;
  fs.writeFileSync = function interceptLockPublication(target, value, ...args) {
    const result = originalWriteFileSync.call(fs, target, value, ...args);
    if (!injecting && typeof target === 'number' && String(value).includes('"token"')) {
      injecting = true;
      publishedOwner = lib.acquireLock(fixture.workspace, first.skill);
    }
    return result;
  };
  let displacedPublisher;
  try { displacedPublisher = lib.acquireLock(fixture.workspace, first.skill); } finally { fs.writeFileSync = originalWriteFileSync; }
  assert.equal(displacedPublisher, null);
  assert.equal(typeof publishedOwner, 'function');
  publishedOwner();

  const results = await withTestEnv(fixture, { CANUTO_SKILL_REFACTOR_DELEGATE: delegate, CANUTO_SKILL_REFACTOR_CONTRACT: contract, FAKE_COUNTER: counter, FAKE_DELAY_MS: '5000' },
    () => Promise.all([
      runWithTestDelegate(fixture, delegate, { workers: 1, resume: true, limit: 1 }),
      runWithTestDelegate(fixture, delegate, { workers: 1, resume: true, limit: 1 }),
    ]));
  const itemResults = results.flatMap((result) => result.results).filter((item) => item.name === first.skill.name);
  assert.equal(itemResults.filter((item) => item.claimed).length, 1, JSON.stringify(results));
});

test('delegate receives only the isolated allowlist and untrusted paths are rejected', async (t) => {
  const fixture = scanFixture(t);
  const delegate = fakeDelegate(fixture.root);
  const contract = path.join(fixture.root, 'contract.md');
  const envOutput = path.join(fixture.root, 'delegate-env.json');
  writeFile(contract, skillText('skill-creator-contract', 'contract'));
  process.env.CANUTO_SKILL_REFACTOR_TEST_ALLOW_DELEGATE = '1';
  try { assert.equal(lib.trustedDelegatePath(delegate), false); } finally { delete process.env.CANUTO_SKILL_REFACTOR_TEST_ALLOW_DELEGATE; }
  assert.equal(lib.trustedDelegatePath(delegate, true), true);
  const canonicalValidator = lib.defaultValidatorPath();
  process.env.CANUTO_SKILL_REFACTOR_VALIDATOR = delegate;
  try { assert.equal(lib.defaultValidatorPath(), canonicalValidator); } finally { delete process.env.CANUTO_SKILL_REFACTOR_VALIDATOR; }
  const result = await withTestEnv(fixture, {
    CANUTO_SKILL_REFACTOR_DELEGATE: delegate,
    CANUTO_SKILL_REFACTOR_CONTRACT: contract,
    FAKE_ENV_OUTPUT: envOutput,
    SECRET_NOT_ALLOWED: 'must-not-cross-boundary',
  }, () => runWithTestDelegate(fixture, delegate, { workers: 1, limit: 1 }));
  assert.equal(result.results[0].state, 'VALIDATED', JSON.stringify(result.results));
  const childEnv = JSON.parse(fs.readFileSync(envOutput, 'utf8'));
  assert.equal(childEnv.CODEX_DELEGATE_SANDBOX, 'workspace-write');
  assert.equal(childEnv.CODEX_DELEGATE_CWD, path.join(fixture.workspace, 'work-items', result.results[0].name));
  assert.equal(childEnv.SECRET_NOT_ALLOWED, undefined);
  assert.equal(childEnv.CANUTO_SKILL_REFACTOR_DELEGATE, undefined);
});

test('delegate retries once and a missing coverage decision cannot pass', async (t) => {
  const fixture = scanFixture(t);
  const delegate = fakeDelegate(fixture.root);
  const contract = path.join(fixture.root, 'contract.md');
  writeFile(contract, skillText('skill-creator-contract', 'contract'));
  const retried = await withTestEnv(fixture, {
    CANUTO_SKILL_REFACTOR_DELEGATE: delegate,
    CANUTO_SKILL_REFACTOR_CONTRACT: contract,
    FAKE_DELEGATE_FAIL: 'first',
  }, () => runWithTestDelegate(fixture, delegate, { workers: 1, limit: 1 }));
  assert.equal(retried.results[0].state, 'VALIDATED', JSON.stringify(retried.results));
  const state = lib.loadedWorkspace(fixture.workspace).entries.find((entry) => entry.skill.name === retried.results[0].name).state;
  assert.equal(state.attempts, 2);

  const skill = { name: 'coverage-check' };
  const workspace = path.join(fixture.root, 'coverage-workspace');
  const item = path.join(workspace, 'work-items', skill.name);
  writeFile(path.join(item, 'coverage.md'), '# Candidate coverage receipt\n\nstatus: completed\n\n- v-a: abc\n  preservation-decision: PENDING\n');
  assert.equal(lib.coverageValid(workspace, skill, { sources: [{ contentHash: 'abc' }] }), false);
});

test('validate reports pending refactors as partial instead of a false-ready estate', (t) => {
  const fixture = scanFixture(t);
  const result = lib.validateWorkspace({ workspace: fixture.workspace });
  assert.equal(result.status, 'PARTIAL');
  assert.ok(result.results.some((item) => item.state === 'PENDING' && item.valid === false && item.reason === 'pending'));
  assert.ok(result.results.some((item) => item.name === 'project-conflict' && item.state === 'BLOCKED' && item.valid === false && item.reason === 'multiple-project-provenance'));
  assert.equal(result.exitCode, 2);
  assert.equal(result.liveSources.status, 'UNVERIFIED');
  assert.equal(result.liveSources.unchanged, false);
});

test('validate fails closed when a KEEP entrypoint or resource changes or the estate gains a skill after scan', (t) => {
  const mutated = scanFixture(t);
  fs.appendFileSync(path.join(mutated.globalA, 'keep-one', 'SKILL.md'), '\nMudança após o scan.\n');
  const mutatedResult = lib.validateWorkspace({ workspace: mutated.workspace });
  assert.equal(mutatedResult.status, 'PARTIAL');
  assert.equal(mutatedResult.exitCode, 2);
  assert.equal(mutatedResult.liveSources.status, 'UNVERIFIED');
  assert.equal(mutatedResult.results[0].reason, 'estate-drift');

  const resourceMutated = scanFixture(t, {
    beforeScan({ globalA }) {
      writeFile(path.join(globalA, 'keep-one', 'references', 'rules.md'), 'rules before scan\n');
    },
  });
  fs.writeFileSync(path.join(resourceMutated.globalA, 'keep-one', 'references', 'rules.md'), 'rules after scan\n');
  const resourceMutatedResult = lib.validateWorkspace({ workspace: resourceMutated.workspace });
  assert.equal(resourceMutatedResult.status, 'PARTIAL');
  assert.equal(resourceMutatedResult.exitCode, 2);
  assert.equal(resourceMutatedResult.liveSources.status, 'UNVERIFIED');
  assert.equal(resourceMutatedResult.results[0].reason, 'estate-drift');

  const added = scanFixture(t);
  writeSkill(added.globalA, 'added-after-scan', 'new estate member');
  const addedResult = lib.validateWorkspace({ workspace: added.workspace });
  assert.equal(addedResult.status, 'PARTIAL');
  assert.equal(addedResult.exitCode, 2);
  assert.equal(addedResult.results[0].reason, 'estate-drift');
});

test('managed and deeply nested uninspectable bundles remain blocked', (t) => {
  const managed = scanFixture(t, {
    beforeScan({ plugins }) {
      writeFile(path.join(plugins, 'managed-only', '.env.production'), 'DO_NOT_COPY=secret-value\n');
    },
  });
  const managedScan = managed.result.manifest.items.find((item) => item.name === 'managed-only');
  assert.equal(managedScan.classification, 'MANAGED');
  assert.equal(managedScan.state, 'BLOCKED');
  assert.ok(managedScan.reasons.includes('secret-looking-file'));
  const initialValidation = lib.validateWorkspace({ workspace: managed.workspace });
  const initialManaged = initialValidation.results.find((item) => item.name === 'managed-only');
  assert.equal(initialValidation.status, 'PARTIAL');
  assert.equal(initialManaged.valid, false);
  assert.equal(initialManaged.reason, 'secret-looking-file');
  fs.writeFileSync(path.join(managed.plugins, 'managed-only', '.env.production'), 'DO_NOT_COPY=changed-secret\n');
  const mutatedValidation = lib.validateWorkspace({ workspace: managed.workspace });
  assert.equal(mutatedValidation.status, 'PARTIAL');
  assert.equal(mutatedValidation.results.find((item) => item.name === 'managed-only').valid, false);

  const deep = scanFixture(t, {
    beforeScan({ globalA }) {
      let directory = path.join(globalA, 'keep-one');
      for (let depth = 0; depth < 33; depth += 1) directory = path.join(directory, `level-${depth}`);
      writeFile(path.join(directory, 'rules.md'), 'too deep\n');
    },
  });
  const deepSkill = deep.result.manifest.items.find((item) => item.name === 'keep-one');
  assert.equal(deepSkill.state, 'BLOCKED');
  assert.ok(deepSkill.reasons.includes('source-depth-exceeded'));
  const deepValidation = lib.validateWorkspace({ workspace: deep.workspace });
  assert.equal(deepValidation.status, 'PARTIAL');
  assert.equal(deepValidation.results.find((item) => item.name === 'keep-one').valid, false);

  const candidateRoot = path.join(deep.root, 'deep-candidate');
  writeSkill(path.dirname(candidateRoot), path.basename(candidateRoot), 'deep candidate');
  let candidateDirectory = candidateRoot;
  for (let depth = 0; depth < 33; depth += 1) candidateDirectory = path.join(candidateDirectory, `level-${depth}`);
  writeFile(path.join(candidateDirectory, 'rules.md'), 'too deep\n');
  const candidateValidation = lib.validateCandidate(candidateRoot, 'deep-candidate', []);
  assert.equal(candidateValidation.valid, false);
  assert.ok(candidateValidation.reasons.includes('candidate-depth-exceeded'));
});

test('source mutation blocks a queued item before delegation', async (t) => {
  const fixture = scanFixture(t);
  const firstPending = lib.loadedWorkspace(fixture.workspace).entries.find((entry) => entry.state.state === 'PENDING');
  const source = firstPending.privateItem.sources[0].sourcePath;
  fs.appendFileSync(source, '\nmutated after scan\n');
  const delegate = fakeDelegate(fixture.root);
  const contract = path.join(fixture.root, 'contract.md');
  writeFile(contract, skillText('skill-creator-contract', 'contract'));
  const result = await withTestEnv(fixture, { CANUTO_SKILL_REFACTOR_DELEGATE: delegate, CANUTO_SKILL_REFACTOR_CONTRACT: contract },
    () => runWithTestDelegate(fixture, delegate, { workers: 1, limit: 1 }));
  assert.equal(result.results[0].state, 'BLOCKED');
  assert.equal(result.results[0].reason, 'source-mutated');
});

function runCliJson(argumentsList, environment) {
  const { spawnSync } = require('node:child_process');
  const result = spawnSync(process.execPath, [path.join(__dirname, 'canuto-skill-refactor.js'), ...argumentsList], {
    cwd: path.join(__dirname, '..'),
    env: environment,
    encoding: 'utf8',
  });
  return { ...result, json: result.stdout.trim() ? JSON.parse(result.stdout) : null };
}

test('CLI scan, queue, preview and validate keep stdout JSON-only and errors machine-readable', (t) => {
  const fixture = scanFixture(t);
  makeTreeWritable(fixture.workspace);
  fs.rmSync(fixture.workspace, { recursive: true, force: true });
  const delegate = fakeDelegate(fixture.root);
  const environment = {
    ...process.env,
    HOME: fixture.root,
    CANUTO_SKILL_REFACTOR_FRAMEWORK_ROOT: fixture.frameworkRoot,
    CANUTO_SKILL_REFACTOR_DELEGATE: delegate,
    CANUTO_SKILL_REFACTOR_CONTRACT: path.join(fixture.root, 'contract.md'),
  };
  writeFile(path.join(fixture.root, 'contract.md'), skillText('skill-creator-contract', 'contract'));
  const scan = runCliJson(['--json', 'scan', '--workspace', fixture.workspace, '--config', fixture.configPath], environment);
  assert.equal(scan.status, 0);
  assert.equal(scan.json.command, 'scan');
  assert.doesNotMatch(scan.stdout, /\[canuto-skill-refactor\]/);
  const queue = runCliJson(['--json', 'queue', '--workspace', fixture.workspace], environment);
  assert.equal(queue.status, 0);
  assert.ok(queue.json.counts.classifications.REFACTOR >= 3);
  const preview = runCliJson(['--json', 'preview', '--workspace', fixture.workspace, '--name', 'needs-merge'], environment);
  assert.equal(preview.status, 0);
  assert.equal(preview.json.classification, 'REFACTOR');
  const validation = runCliJson(['--json', 'validate', '--workspace', fixture.workspace], environment);
  assert.equal(validation.status, 2);
  assert.equal(validation.json.status, 'PARTIAL');
  const bad = runCliJson(['--json', 'queue', '--workspace', fixture.workspace, '--config', fixture.configPath], environment);
  assert.equal(bad.status, 2);
  assert.equal(bad.json.error.code, 'option-not-allowed');
});

test('resume reclaims a dead RUNNING item and does not delegate when a valid receipt already exists', async (t) => {
  const fixture = scanFixture(t);
  const delegate = fakeDelegate(fixture.root);
  const contract = path.join(fixture.root, 'contract.md');
  writeFile(contract, skillText('skill-creator-contract', 'contract'));
  const first = lib.loadedWorkspace(fixture.workspace).entries.find((entry) => entry.state.state === 'PENDING');
  const statePath = path.join(fixture.workspace, 'work-items', first.skill.name, 'state.json');
  const state = { ...first.state, state: 'RUNNING', pid: 999999, delegatePid: 999999 };
  writeFile(statePath, `${JSON.stringify(state, null, 2)}\n`);
  const skipped = await withTestEnv(fixture, { CANUTO_SKILL_REFACTOR_DELEGATE: delegate, CANUTO_SKILL_REFACTOR_CONTRACT: contract },
    () => runWithTestDelegate(fixture, delegate, { workers: 1 }));
  assert.equal(lib.loadedWorkspace(fixture.workspace).entries.find((entry) => entry.skill.name === first.skill.name).state.state, 'RUNNING');
  const resumed = await withTestEnv(fixture, { CANUTO_SKILL_REFACTOR_DELEGATE: delegate, CANUTO_SKILL_REFACTOR_CONTRACT: contract },
    () => runWithTestDelegate(fixture, delegate, { workers: 1, resume: true, limit: 1 }));
  assert.equal(resumed.results[0].state, 'VALIDATED', JSON.stringify(resumed.results));
  const loaded = lib.loadedWorkspace(fixture.workspace);
  const validated = loaded.entries.find((entry) => entry.state.state === 'VALIDATED');
  const validatedStatePath = path.join(fixture.workspace, 'work-items', validated.skill.name, 'state.json');
  const validatedState = { ...validated.state, state: 'RUNNING', pid: 999999, delegatePid: 999999 };
  writeFile(validatedStatePath, `${JSON.stringify(validatedState, null, 2)}\n`);
  const receiptRun = await withTestEnv(fixture, { CANUTO_SKILL_REFACTOR_DELEGATE: delegate, CANUTO_SKILL_REFACTOR_CONTRACT: contract, FAKE_DELEGATE_FAIL: 'always' },
    () => runWithTestDelegate(fixture, delegate, { workers: 1, resume: true }));
  assert.equal(receiptRun.results.find((entry) => entry.name === validated.skill.name).state, 'VALIDATED');
});
test('source symlink escapes are quarantined before a delegate can run', (t) => {
  const fixture = scanFixture(t, {
    beforeScan({ root, globalA, globalB }) {
      const outside = path.join(root, 'outside.md');
      writeFile(outside, 'private outside content');
      const escaped = writeSkill(globalA, 'symlink-escape', 'a');
      writeSkill(globalB, 'symlink-escape', 'b');
      fs.mkdirSync(path.join(escaped, 'references'), { recursive: true });
      fs.symlinkSync(outside, path.join(escaped, 'references', 'outside.md'));
    },
  });
  const item = lib.loadedWorkspace(fixture.workspace).entries.find((entry) => entry.skill.name === 'symlink-escape');
  assert.equal(item.state.state, 'BLOCKED');
  assert.equal(item.state.reason, 'source-path-escape');
  assert.doesNotMatch(JSON.stringify(fs.readdirSync(path.join(fixture.workspace, 'work-items', 'symlink-escape'), { recursive: true })), /outside/);
});

test('all duplicate source paths for a resource-divergent variant are revalidated', async (t) => {
  const fixture = scanFixture(t, {
    beforeScan({ live, globalA, configPath }) {
      const duplicateRoot = path.join(live, 'global-c');
      fs.mkdirSync(duplicateRoot, { recursive: true });
      writeSkill(duplicateRoot, 'resource-diverge', 'shared-entrypoint', { skillText: skillText('resource-diverge', 'shared-entrypoint'), files: { 'references/rules.md': 'rules A\n' } });
      const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
      config.providers.codex.roots.splice(1, 0, duplicateRoot);
      fs.writeFileSync(configPath, `${JSON.stringify(config, null, 2)}\n`);
    },
  });
  const privateItem = lib.loadedWorkspace(fixture.workspace).entries.find((entry) => entry.skill.name === 'resource-diverge').privateItem;
  assert.equal(privateItem.sources.length, 2);
  const duplicateSource = privateItem.sources.find((source) => source.sourcePaths.length === 2);
  assert.ok(duplicateSource);
  const other = duplicateSource.sourcePaths[1];
  fs.appendFileSync(other.replace(/SKILL\.md$/, 'references/rules.md'), '\nmutated duplicate resource\n');
  const delegate = fakeDelegate(fixture.root);
  const contract = path.join(fixture.root, 'contract.md');
  writeFile(contract, skillText('skill-creator-contract', 'contract'));
  const result = await withTestEnv(fixture, { CANUTO_SKILL_REFACTOR_DELEGATE: delegate, CANUTO_SKILL_REFACTOR_CONTRACT: contract },
    () => runWithTestDelegate(fixture, delegate, { workers: 4, limit: 20 }));
  const item = result.results.find((entry) => entry.name === 'resource-diverge');
  assert.ok(item, JSON.stringify(result.results));
  assert.equal(item.state, 'BLOCKED');
  assert.equal(item.reason, 'source-mutated');
});
function slowCountingDelegate(root) {
  const target = path.join(root, 'slow-counting-delegate.js');
  writeFile(target, `#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const taskPath = process.argv[3];
const resultPath = process.argv[4];
const counter = process.env.FAKE_COUNTER;
const lockPath = counter + '.lock';
const wait = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
async function take() { while (true) { try { fs.mkdirSync(lockPath); return; } catch { await wait(4); } } }
async function update(delta) {
  await take();
  try {
    const value = fs.existsSync(counter) ? JSON.parse(fs.readFileSync(counter, 'utf8')) : { active: 0, max: 0 };
    value.active += delta;
    value.max = Math.max(value.max, value.active);
    fs.writeFileSync(counter, JSON.stringify(value));
  } finally { fs.rmSync(lockPath, { recursive: true, force: true }); }
}
(async () => {
  await update(1);
  try {
    const task = fs.readFileSync(taskPath, 'utf8');
    const name = task.match(/Logical skill name: ([^\\n]+)/)[1].trim();
    const candidate = path.join(process.cwd(), 'candidate', name);
    fs.mkdirSync(path.join(candidate, 'agents'), { recursive: true });
    fs.writeFileSync(path.join(candidate, 'SKILL.md'), '---\\nname: ' + name + '\\ndescription: A delayed bounded candidate for ' + name + ' workflow.\\n---\\n\\n# Candidate\\n');
    fs.writeFileSync(path.join(candidate, 'agents', 'openai.yaml'), 'interface:\\n  default_prompt: "Use $' + name + ' for this workflow."\\n');
    const coverage = path.join(process.cwd(), 'coverage.md');
    fs.writeFileSync(coverage, fs.readFileSync(coverage, 'utf8').replace('status: prepared', 'status: completed').replace(/preservation-decision: PENDING/g, 'preservation-decision: Preserved bounded workflow decisions.'));
    fs.writeFileSync(resultPath, 'generated');
    await wait(Number(process.env.FAKE_DELAY_MS || 100));
  } finally { await update(-1); }
})().catch((error) => { process.stderr.write(String(error.stack || error)); process.exitCode = 1; });
`, 0o700);
  fs.chmodSync(target, 0o700);
  return target;
}

test('bounded concurrency never exceeds the requested worker count', async (t) => {
  const fixture = scanFixture(t, {
    beforeScan({ globalA, globalB }) {
      for (let index = 1; index <= 4; index += 1) {
        const name = 'bulk-' + index;
        writeSkill(globalA, name, 'a-' + index);
        writeSkill(globalB, name, 'b-' + index);
      }
    },
  });
  const delegate = slowCountingDelegate(fixture.root);
  const counter = path.join(fixture.root, 'delegate-counter.json');
  const contract = path.join(fixture.root, 'contract.md');
  writeFile(contract, skillText('skill-creator-contract', 'contract'));
  const result = await withTestEnv(fixture, { CANUTO_SKILL_REFACTOR_DELEGATE: delegate, CANUTO_SKILL_REFACTOR_CONTRACT: contract, FAKE_COUNTER: counter },
    () => runWithTestDelegate(fixture, delegate, { workers: 2, limit: 20 }));
  assert.equal(result.status, 'READY', JSON.stringify(result.results));
  assert.ok(JSON.parse(fs.readFileSync(counter, 'utf8')).max <= 2);
  for (let index = 1; index <= 4; index += 1) {
    const item = lib.loadedWorkspace(fixture.workspace).entries.find((entry) => entry.skill.name === 'bulk-' + index);
    assert.equal(item.state.state, 'VALIDATED');
  }
});

test('tampered source snapshots are blocked before delegation', async (t) => {
  const fixture = scanFixture(t);
  const firstPending = lib.loadedWorkspace(fixture.workspace).entries.find((entry) => entry.state.state === 'PENDING');
  const snapshot = path.join(fixture.workspace, 'work-items', firstPending.skill.name, 'sources', firstPending.privateItem.sources[0].variantId, 'SKILL.md');
  fs.chmodSync(snapshot, 0o600);
  fs.appendFileSync(snapshot, '\ntampered snapshot\n');
  const delegate = fakeDelegate(fixture.root);
  const contract = path.join(fixture.root, 'contract.md');
  writeFile(contract, skillText('skill-creator-contract', 'contract'));
  const result = await withTestEnv(fixture, { CANUTO_SKILL_REFACTOR_DELEGATE: delegate, CANUTO_SKILL_REFACTOR_CONTRACT: contract },
    () => runWithTestDelegate(fixture, delegate, { workers: 1, limit: 1 }));
  assert.equal(result.results[0].state, 'BLOCKED');
  assert.equal(result.results[0].reason, 'source-snapshot-mutated');
});

test('hung delegates are terminated by the bounded timeout', async (t) => {
  const fixture = scanFixture(t);
  const delegate = path.join(fixture.root, 'hung-delegate.js');
  writeFile(delegate, '#!/usr/bin/env node\nsetInterval(() => {}, 1000);\n', 0o700);
  const contract = path.join(fixture.root, 'contract.md');
  writeFile(contract, skillText('skill-creator-contract', 'contract'));
  const result = await withTestEnv(fixture, { CANUTO_SKILL_REFACTOR_DELEGATE: delegate, CANUTO_SKILL_REFACTOR_CONTRACT: contract },
    () => runWithTestDelegate(fixture, delegate, { workers: 1, limit: 1, delegateTimeoutMs: 50 }));
  assert.equal(result.results[0].state, 'FAILED');
  assert.equal(result.results[0].reason, 'delegate-failed');
  const state = lib.loadedWorkspace(fixture.workspace).entries.find((entry) => entry.skill.name === result.results[0].name).state;
  assert.equal(state.attempts, 2);
});

test('legacy Markdown sources are snapshotted as folders and can complete validation', async (t) => {
  const fixture = scanFixture(t, {
    beforeScan({ globalA, globalB }) {
      writeFile(path.join(globalA, 'legacy-source.md'), skillText('legacy-source', 'a'));
      writeFile(path.join(globalB, 'legacy-source.md'), skillText('legacy-source', 'b'));
    },
  });
  const item = lib.loadedWorkspace(fixture.workspace).entries.find((entry) => entry.skill.name === 'legacy-source');
  assert.equal(item.skill.classification, 'REFACTOR');
  assert.equal(item.privateItem.sources[0].mode, 'legacy');
  const delegate = fakeDelegate(fixture.root);
  const contract = path.join(fixture.root, 'contract.md');
  writeFile(contract, skillText('skill-creator-contract', 'contract'));
  const result = await withTestEnv(fixture, { CANUTO_SKILL_REFACTOR_DELEGATE: delegate, CANUTO_SKILL_REFACTOR_CONTRACT: contract },
    () => runWithTestDelegate(fixture, delegate, { workers: 1, limit: 20 }));
  const completed = result.results.find((entry) => entry.name === 'legacy-source');
  assert.equal(completed.state, 'VALIDATED', JSON.stringify(result.results));
});
