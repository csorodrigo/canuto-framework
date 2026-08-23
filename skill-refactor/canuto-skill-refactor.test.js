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
  for (const [key, value] of Object.entries(values)) {
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
});

test('fake delegate validates a candidate, records coverage and leaves live sources unchanged', async (t) => {
  const fixture = scanFixture(t);
  const delegate = fakeDelegate(fixture.root);
  const sourcePath = path.join(fixture.globalA, 'broken-meta', 'SKILL.md');
  const before = lib.sha256(fs.readFileSync(sourcePath));
  const contract = path.join(fixture.root, 'contract.md');
  writeFile(contract, skillText('skill-creator-contract', 'contract'));
  const result = await withEnv({
    CANUTO_SKILL_REFACTOR_DELEGATE: delegate,
    CANUTO_SKILL_REFACTOR_CONTRACT: contract,
    FAKE_DELEGATE_FAIL: undefined,
  }, () => lib.runWorkspace({ workspace: fixture.workspace, workers: 0, limit: 1 }));
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

test('delegate retries once and a missing coverage decision cannot pass', async (t) => {
  const fixture = scanFixture(t);
  const delegate = fakeDelegate(fixture.root);
  const contract = path.join(fixture.root, 'contract.md');
  writeFile(contract, skillText('skill-creator-contract', 'contract'));
  const retried = await withEnv({
    CANUTO_SKILL_REFACTOR_DELEGATE: delegate,
    CANUTO_SKILL_REFACTOR_CONTRACT: contract,
    FAKE_DELEGATE_FAIL: 'first',
  }, () => lib.runWorkspace({ workspace: fixture.workspace, workers: 1, limit: 1 }));
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
  assert.equal(result.liveSources.status, 'UNVERIFIED');
  assert.equal(result.liveSources.unchanged, false);
});

test('source mutation blocks a queued item before delegation', async (t) => {
  const fixture = scanFixture(t);
  const firstPending = lib.loadedWorkspace(fixture.workspace).entries.find((entry) => entry.state.state === 'PENDING');
  const source = firstPending.privateItem.sources[0].sourcePath;
  fs.appendFileSync(source, '\nmutated after scan\n');
  const delegate = fakeDelegate(fixture.root);
  const contract = path.join(fixture.root, 'contract.md');
  writeFile(contract, skillText('skill-creator-contract', 'contract'));
  const result = await withEnv({ CANUTO_SKILL_REFACTOR_DELEGATE: delegate, CANUTO_SKILL_REFACTOR_CONTRACT: contract },
    () => lib.runWorkspace({ workspace: fixture.workspace, workers: 1, limit: 1 }));
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
  const skipped = await withEnv({ CANUTO_SKILL_REFACTOR_DELEGATE: delegate, CANUTO_SKILL_REFACTOR_CONTRACT: contract },
    () => lib.runWorkspace({ workspace: fixture.workspace, workers: 1 }));
  assert.equal(lib.loadedWorkspace(fixture.workspace).entries.find((entry) => entry.skill.name === first.skill.name).state.state, 'RUNNING');
  const resumed = await withEnv({ CANUTO_SKILL_REFACTOR_DELEGATE: delegate, CANUTO_SKILL_REFACTOR_CONTRACT: contract },
    () => lib.runWorkspace({ workspace: fixture.workspace, workers: 1, resume: true, limit: 1 }));
  assert.equal(resumed.results[0].state, 'VALIDATED', JSON.stringify(resumed.results));
  const loaded = lib.loadedWorkspace(fixture.workspace);
  const validated = loaded.entries.find((entry) => entry.state.state === 'VALIDATED');
  const validatedStatePath = path.join(fixture.workspace, 'work-items', validated.skill.name, 'state.json');
  const validatedState = { ...validated.state, state: 'RUNNING', pid: 999999, delegatePid: 999999 };
  writeFile(validatedStatePath, `${JSON.stringify(validatedState, null, 2)}\n`);
  const receiptRun = await withEnv({ CANUTO_SKILL_REFACTOR_DELEGATE: delegate, CANUTO_SKILL_REFACTOR_CONTRACT: contract, FAKE_DELEGATE_FAIL: 'always' },
    () => lib.runWorkspace({ workspace: fixture.workspace, workers: 1, resume: true }));
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
  const result = await withEnv({ CANUTO_SKILL_REFACTOR_DELEGATE: delegate, CANUTO_SKILL_REFACTOR_CONTRACT: contract },
    () => lib.runWorkspace({ workspace: fixture.workspace, workers: 4, limit: 20 }));
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
    await wait(100);
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
  const result = await withEnv({ CANUTO_SKILL_REFACTOR_DELEGATE: delegate, CANUTO_SKILL_REFACTOR_CONTRACT: contract, FAKE_COUNTER: counter },
    () => lib.runWorkspace({ workspace: fixture.workspace, workers: 2, limit: 20 }));
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
  const result = await withEnv({ CANUTO_SKILL_REFACTOR_DELEGATE: delegate, CANUTO_SKILL_REFACTOR_CONTRACT: contract },
    () => lib.runWorkspace({ workspace: fixture.workspace, workers: 1, limit: 1 }));
  assert.equal(result.results[0].state, 'BLOCKED');
  assert.equal(result.results[0].reason, 'source-snapshot-mutated');
});

test('hung delegates are terminated by the bounded timeout', async (t) => {
  const fixture = scanFixture(t);
  const delegate = path.join(fixture.root, 'hung-delegate.js');
  writeFile(delegate, '#!/usr/bin/env node\nsetInterval(() => {}, 1000);\n', 0o700);
  const contract = path.join(fixture.root, 'contract.md');
  writeFile(contract, skillText('skill-creator-contract', 'contract'));
  const result = await withEnv({ CANUTO_SKILL_REFACTOR_DELEGATE: delegate, CANUTO_SKILL_REFACTOR_CONTRACT: contract },
    () => lib.runWorkspace({ workspace: fixture.workspace, workers: 1, limit: 1, delegateTimeoutMs: 50 }));
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
  const result = await withEnv({ CANUTO_SKILL_REFACTOR_DELEGATE: delegate, CANUTO_SKILL_REFACTOR_CONTRACT: contract },
    () => lib.runWorkspace({ workspace: fixture.workspace, workers: 1, limit: 20 }));
  const completed = result.results.find((entry) => entry.name === 'legacy-source');
  assert.equal(completed.state, 'VALIDATED', JSON.stringify(result.results));
});
