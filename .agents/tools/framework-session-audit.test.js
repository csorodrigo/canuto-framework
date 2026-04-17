const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');

const {
  buildProjectSummary,
  buildInventory,
  detectSkillBreakages,
  generateReport,
  parseCodexLogMeta,
  parseCodexLogRecord,
  parseFrontmatter,
  parseSessionSections,
  runAudit,
  writeAuditOutputs,
} = require('./framework-session-audit-lib');

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function writeFile(filePath, content, mode) {
  ensureDir(path.dirname(filePath));
  fs.writeFileSync(filePath, content);
  if (mode) {
    fs.chmodSync(filePath, mode);
  }
}

function makeTempDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'framework-session-audit-test-'));
}

function writeCanutoProject({ workspacesRoot, vaultRoot, slug = 'acme', workspace = 'recife' }) {
  const repoPath = path.join(workspacesRoot, slug, workspace);
  const vaultPath = path.join(vaultRoot, slug);
  writeFile(
    path.join(repoPath, '.agents', 'tools', 'canuto-memory.sh'),
    `#!/usr/bin/env bash
canuto_project_slug(){ printf "${slug}\\n"; }
canuto_resolve_memory_backend(){ printf "global\\t${vaultPath}\\n"; }
`,
    0o755,
  );
  writeFile(path.join(repoPath, '.agents', 'tools', 'session-capture.sh'), '#!/usr/bin/env bash\n', 0o755);
  writeFile(path.join(repoPath, '.agents', 'tools', 'obsidian-healthcheck.sh'), '#!/usr/bin/env bash\n', 0o755);
  writeFile(path.join(repoPath, '.context.md'), `- project: ${slug}\n`);
  ensureDir(path.join(vaultPath, 'sessions'));
  ensureDir(path.join(vaultPath, 'metrics'));
  return { repoPath, vaultPath };
}

function writeBucketProject(tempDir, slug, options = {}) {
  const repoPath = path.join(tempDir, 'workspaces', slug);
  if (options.workspacePath === '') {
    return '';
  }

  ensureDir(path.join(repoPath, '.agents', 'tools'));
  if (options.memoryDir !== false) {
    ensureDir(path.join(repoPath, '.agents', 'memory'));
  }
  if (options.claude !== false) {
    writeFile(path.join(repoPath, 'CLAUDE.md'), `project-slug: ${slug}\n`);
  }
  return repoPath;
}

function makeBucketProject(tempDir, slug, options = {}) {
  const repoPath = writeBucketProject(tempDir, slug, options);
  return {
    project_key: slug,
    project_slug: slug,
    workspace_path: repoPath,
    workspace_root: slug,
    backend_kind: 'global',
    global_vault_path: options.globalVaultPath || path.join(tempDir, 'vault', slug),
    local_vault_path: '',
    memory_script_present: options.memoryScriptPresent !== false,
    session_capture_present: Boolean(options.sessionCapturePresent),
    obsidian_healthcheck_present: Boolean(options.obsidianHealthcheckPresent),
    framework_version_signals: {},
    excluded_reason: '',
    slug_collision: false,
    collision_group: [],
    skill_catalog: [],
  };
}

function makeBucketSession(overrides = {}) {
  return {
    project_key: 'acme',
    session_id: overrides.session_id || 'session-1',
    runtime: 'codex',
    timestamp: overrides.timestamp || '2026-04-16T00:00:00.000Z',
    source_kind: 'codex_log',
    source_path: overrides.source_path || '/tmp/session.jsonl',
    source_log_path: overrides.source_log_path || '/tmp/session.jsonl',
    vault_scope: 'none',
    captured_to_vault: Boolean(overrides.captured_to_vault),
    fallback_used: false,
    health_reason: 'unknown',
    offline_sync: false,
    pending_sync: Boolean(overrides.pending_sync),
    review_fix_cycles: 0,
    tasks_completed: 0,
    tests_run: 0,
    pending_count: 0,
    summary: [],
    what_was_done: [],
    validation: overrides.validation || [],
    learnings: [],
    skill_reads: [],
    skill_breakages: [],
    probable_skill_matches: [],
    evidence_refs: [],
    provider: '',
    model: '',
    token_usage: {},
    estimated_cost_usd: null,
    cost_source: '',
    missing_pricing: [],
    tool_calls: [],
    shell_commands: [],
    mcp_calls: [],
    activity_breakdown: {},
    ...overrides,
  };
}

function makeBucketSessions(total, capturedCount, overrides = {}) {
  return Array.from({ length: total }, (_, index) =>
    makeBucketSession({
      session_id: `session-${index + 1}`,
      captured_to_vault: index < capturedCount,
      ...overrides,
    }),
  );
}

function writePricing(filePath) {
  writeFile(
    filePath,
    JSON.stringify({
      timestamp: 0,
      data: {
        'gpt-5-codex': {
          inputCostPerToken: 0.000001,
          outputCostPerToken: 0.000002,
          cacheReadCostPerToken: 0.0000001,
          cacheWriteCostPerToken: 0.0000012,
        },
        'claude-sonnet-test': {
          inputCostPerToken: 0.000003,
          outputCostPerToken: 0.000015,
          cacheReadCostPerToken: 0.0000003,
          cacheWriteCostPerToken: 0.00000375,
        },
      },
    }),
  );
}

test('parseFrontmatter and parseSessionSections keep session body structured', () => {
  const markdown = `---
type: "session"
session_id: "abc"
date: "2026-04-15T13:23:35.050Z"
---

# Session

## Summary
- First bullet

## What Was Done
- Delivered feature

## Validation
- node --test
`;

  const { data, body } = parseFrontmatter(markdown);
  const sections = parseSessionSections(body);

  assert.equal(data.type, 'session');
  assert.equal(data.session_id, 'abc');
  assert.deepEqual(sections.summary, ['First bullet']);
  assert.deepEqual(sections.whatWasDone, ['Delivered feature']);
  assert.deepEqual(sections.validation, ['node --test']);
});

test('parseCodexLogRecord ignores injected skill list and only counts real skill reads', () => {
  const tempDir = makeTempDir();
  const skillPath = path.join(tempDir, '.agents', 'skills', 'monitor', 'SKILL.md');
  writeFile(skillPath, '---\nname: monitor\ntrigger: monitor\n---\n');

  const logPath = path.join(tempDir, 'session.jsonl');
  const records = [
    {
      type: 'session_meta',
      payload: {
        id: 'session-1',
        timestamp: '2026-04-15T13:23:35.050Z',
        cwd: tempDir,
      },
    },
    {
      type: 'response_item',
      payload: {
        type: 'message',
        role: 'user',
        content: [
          {
            type: 'input_text',
            text: `# AGENTS.md instructions\nAvailable skills include ${skillPath}`,
          },
        ],
      },
    },
    {
      type: 'response_item',
      payload: {
        type: 'function_call',
        name: 'exec_command',
        arguments: JSON.stringify({
          cmd: `sed -n '1,120p' '${skillPath}'`,
        }),
      },
    },
  ];
  writeFile(logPath, records.map((record) => JSON.stringify(record)).join('\n'));

  const meta = parseCodexLogMeta(logPath);
  const session = parseCodexLogRecord(meta, 'project-key', [
    {
      id: 'monitor',
      name: 'monitor',
      path: skillPath,
      trigger_phrases: ['monitor'],
    },
  ]);

  assert.deepEqual(session.skill_reads, ['monitor']);
  assert.equal(session.skill_reads.length, 1);
});

test('detectSkillBreakages recognizes concrete skill error evidence', () => {
  const cases = [
    {
      text: 'ENOENT: .agents/skills/co-review/SKILL.md: No such file or directory',
      expected: 'skill-file-missing',
    },
    {
      text: 'Failed to parse YAML at /root/.agents/skills/health-check/SKILL.md',
      expected: 'skill-parse-failure',
    },
    {
      text: 'Error: Skill not found: co-review',
      expected: 'skill-not-found',
    },
    {
      text: 'Unable to read /home/user/.agents/skills/vault-sync/SKILL.md: permission denied',
      expected: 'skill-read-failure',
    },
  ];

  for (const item of cases) {
    assert.deepEqual(detectSkillBreakages(item.text), [item.expected]);
  }
});

test('detectSkillBreakages recognizes flat missing skill path after ENOENT', () => {
  assert.deepEqual(
    detectSkillBreakages('ENOENT: .agents/skills/health-check.md: No such file or directory'),
    ['skill-file-missing'],
  );
});

test('detectSkillBreakages recognizes flat missing skill path after open failure', () => {
  assert.deepEqual(
    detectSkillBreakages("Error: ENOENT: no such file or directory, open '/repo/.agents/skills/codex-pr-writer.md'"),
    ['skill-file-missing'],
  );
});

test('detectSkillBreakages recognizes reverse-order directory parse failure', () => {
  assert.deepEqual(
    detectSkillBreakages('/repo/.agents/skills/co-review/SKILL.md: YAMLException: bad indentation'),
    ['skill-parse-failure'],
  );
});

test('detectSkillBreakages recognizes reverse-order flat parse failure', () => {
  assert.deepEqual(
    detectSkillBreakages('/repo/.agents/skills/health-check.md: SyntaxError: Unexpected token'),
    ['skill-parse-failure'],
  );
});

test('detectSkillBreakages ignores ambient skill mentions', () => {
  const cases = [
    'I will check if skills are missing the latest co-review update',
    'The skill parse tree was rebuilt',
    'Skill not found in the cached index, but will re-fetch on next run',
    '## Skills\n- co-review\n- codex-pr-writer',
  ];

  for (const text of cases) {
    assert.deepEqual(detectSkillBreakages(text), []);
  }
});

test('detectProbableSkillMatches requires score four or higher', () => {
  const { detectProbableSkillMatches } = require('./framework-session-audit-lib');
  const scoreThreeCatalog = [
    {
      id: 'score-three',
      trigger_phrases: ['alpha beta gamma'],
    },
  ];
  const scoreFourCatalog = [
    {
      id: 'score-four',
      trigger_phrases: ['alpha beta gamma delta'],
    },
  ];

  assert.deepEqual(
    detectProbableSkillMatches(scoreThreeCatalog, ['alpha gamma beta']).map((match) => match.skill_id),
    [],
  );
  assert.deepEqual(
    detectProbableSkillMatches(scoreFourCatalog, ['alpha delta gamma beta']).map((match) => match.skill_id),
    ['score-four'],
  );
});

test('buildProjectSummary excludes project-level skill matches that were read in another session', () => {
  const tempDir = makeTempDir();
  const project = makeBucketProject(tempDir, 'project-read-skill', {
    sessionCapturePresent: true,
    obsidianHealthcheckPresent: true,
  });
  project.skill_catalog = [{ id: 'co-review', trigger_phrases: ['co review'] }];

  const summary = buildProjectSummary(
    project,
    [
      makeBucketSession({
        session_id: 'match-only',
        captured_to_vault: true,
        probable_skill_matches: [{ skill_id: 'co-review', score: 4, matched_phrase: 'co review' }],
      }),
      makeBucketSession({
        session_id: 'read-skill',
        captured_to_vault: true,
        skill_reads: ['co-review'],
      }),
    ],
    200,
    '2026-04-17T00:00:00.000Z',
  );

  assert.deepEqual(summary.top_skills_missed, []);
  assert.equal(summary.skill_status, 'healthy');
});

test('buildProjectSummary counts project-level skill matches that were never read', () => {
  const tempDir = makeTempDir();
  const project = makeBucketProject(tempDir, 'project-missed-skill', {
    sessionCapturePresent: true,
    obsidianHealthcheckPresent: true,
  });
  project.skill_catalog = [{ id: 'co-review', trigger_phrases: ['co review'] }];

  const summary = buildProjectSummary(
    project,
    [
      makeBucketSession({
        session_id: 'match-only',
        captured_to_vault: true,
        probable_skill_matches: [{ skill_id: 'co-review', score: 4, matched_phrase: 'co review' }],
      }),
    ],
    200,
    '2026-04-17T00:00:00.000Z',
  );

  assert.deepEqual(summary.top_skills_missed.map((item) => item.skill_id), ['co-review']);
  assert.equal(summary.top_skills_missed[0].count, 1);
});

test('buildInventory marks slug collisions explicitly', () => {
  const tempDir = makeTempDir();
  const workspacesRoot = path.join(tempDir, 'workspaces');
  const vaultRoot = path.join(tempDir, 'vault');

  const repoOne = path.join(workspacesRoot, 'alpha', 'rome');
  const repoTwo = path.join(workspacesRoot, 'beta', 'paris');

  writeFile(path.join(repoOne, '.agents', 'tools', 'canuto-memory.sh'), '#!/usr/bin/env bash\ncanuto_project_slug(){ printf "shared-slug\\n"; }\ncanuto_resolve_memory_backend(){ printf "none\\t\\n"; }\n', 0o755);
  writeFile(path.join(repoTwo, '.agents', 'tools', 'canuto-memory.sh'), '#!/usr/bin/env bash\ncanuto_project_slug(){ printf "shared-slug\\n"; }\ncanuto_resolve_memory_backend(){ printf "none\\t\\n"; }\n', 0o755);
  ensureDir(path.join(vaultRoot, 'shared-slug'));

  const inventory = buildInventory({ workspacesRoot, vaultRoot });

  assert.equal(inventory.projects.length, 2);
  const workspaceProjects = inventory.projects.filter((project) => project.workspace_path);
  assert.equal(workspaceProjects.length, 2);
  assert.ok(workspaceProjects.every((project) => project.slug_collision));
  assert.equal(new Set(workspaceProjects.map((project) => project.project_key)).size, 2);
});

test('runAudit produces compliant summary and merged codex+vault session', async () => {
  const tempDir = makeTempDir();
  const workspacesRoot = path.join(tempDir, 'workspaces');
  const vaultRoot = path.join(tempDir, 'vault');
  const codexRoot = path.join(tempDir, 'codex');

  const repoPath = path.join(workspacesRoot, 'acme', 'recife');
  const vaultPath = path.join(vaultRoot, 'acme');
  const skillPath = path.join(repoPath, '.agents', 'skills', 'monitor', 'SKILL.md');
  const logPath = path.join(codexRoot, '2026', '04', '15', 'rollout-acme.jsonl');

  writeFile(
    path.join(repoPath, '.agents', 'tools', 'canuto-memory.sh'),
    `#!/usr/bin/env bash
canuto_project_slug(){ printf "acme\\n"; }
canuto_resolve_memory_backend(){ printf "global\\t${vaultPath}\\n"; }
`,
    0o755,
  );
  writeFile(path.join(repoPath, '.agents', 'tools', 'session-capture.sh'), '#!/usr/bin/env bash\n', 0o755);
  writeFile(path.join(repoPath, '.agents', 'tools', 'obsidian-healthcheck.sh'), '#!/usr/bin/env bash\n', 0o755);
  writeFile(path.join(repoPath, '.context.md'), '- project: acme\n');
  writeFile(skillPath, '---\nname: monitor\ntrigger: monitor\n---\n');

  writeFile(
    path.join(vaultPath, 'sessions', '2026-04-15T132335Z-session-1.md'),
    `---
type: "session"
session_id: "session-1"
date: "2026-04-15T13:23:35.050Z"
project: "acme"
runtime: "codex"
source_log: "${logPath}"
fallback_used: false
---

# Session

## Summary
- Captured session

## What Was Done
- Implemented monitor flow

## Validation
- bash .agents/tools/obsidian-healthcheck.sh --json
- bash .agents/tools/session-capture.sh

## Learnings
- Monitor is mandatory here
`,
  );
  writeFile(
    path.join(vaultPath, 'metrics', '2026-04-15T132335Z-session-1.md'),
    `---
type: "session-metrics"
session_id: "session-1"
date: "2026-04-15T13:23:35.050Z"
project: "acme"
runtime: "codex"
tasks_completed: 1
tests_run: 2
pending_count: 0
---
`,
  );

  const logRecords = [
    {
      type: 'session_meta',
      payload: {
        id: 'session-1',
        timestamp: '2026-04-15T13:23:35.050Z',
        cwd: repoPath,
      },
    },
    {
      type: 'response_item',
      payload: {
        type: 'message',
        role: 'user',
        content: [
          {
            type: 'input_text',
            text: 'fix the monitor flow and use the right skill',
          },
        ],
      },
    },
    {
      type: 'response_item',
      payload: {
        type: 'function_call',
        name: 'exec_command',
        arguments: JSON.stringify({
          cmd: `sed -n '1,120p' '${skillPath}'`,
        }),
      },
    },
  ];
  writeFile(logPath, logRecords.map((record) => JSON.stringify(record)).join('\n'));

  const result = await runAudit({
    workspacesRoot,
    vaultRoot,
    codexLogRoots: [codexRoot],
    sessionLimit: 200,
    parallelism: 2,
    analysisMode: 'deterministic',
    outputDir: path.join(tempDir, 'out'),
  });

  assert.equal(result.project_summaries.length, 1);
  const summary = result.project_summaries[0];
  assert.equal(summary.project_key, 'acme');
  assert.equal(summary.obsidian_status, 'compliant');
  assert.equal(summary.capture_health, 'healthy');
  assert.equal(summary.skill_status, 'healthy');
  assert.equal(summary.framework_health, 'healthy');
  assert.equal(summary.sessions_analyzed, 1);
  assert.deepEqual(summary.sessions[0].skill_reads, ['monitor']);
  assert.equal(summary.sessions[0].captured_to_vault, true);
});

test('buildProjectSummary assigns expected five-bucket taxonomy', () => {
  const tempDir = makeTempDir();
  const generatedAt = '2026-04-17T00:00:00.000Z';
  const cases = [
    {
      name: 'never-installed',
      project: makeBucketProject(tempDir, 'never-installed', { memoryDir: false }),
      sessions: [makeBucketSession({ captured_to_vault: true })],
    },
    {
      name: 'dormant',
      project: makeBucketProject(tempDir, 'dormant', {
        sessionCapturePresent: true,
        obsidianHealthcheckPresent: true,
      }),
      sessions: [makeBucketSession({ timestamp: '2026-03-01T00:00:00.000Z', captured_to_vault: true })],
    },
    {
      name: 'pre-v1.8',
      project: makeBucketProject(tempDir, 'pre-v1.8', {
        sessionCapturePresent: false,
        obsidianHealthcheckPresent: true,
      }),
      sessions: [makeBucketSession({ captured_to_vault: true })],
    },
    {
      name: 'v1.8-failing',
      project: makeBucketProject(tempDir, 'v1.8-failing', {
        sessionCapturePresent: true,
        obsidianHealthcheckPresent: true,
      }),
      sessions: [
        makeBucketSession({ session_id: 'one', captured_to_vault: true }),
        makeBucketSession({ session_id: 'two', captured_to_vault: true, pending_sync: true }),
        makeBucketSession({ session_id: 'three', captured_to_vault: true }),
      ],
      pendingSyncOrphanRatio: 0.3333,
    },
    {
      name: 'healthy',
      project: makeBucketProject(tempDir, 'healthy', {
        sessionCapturePresent: true,
        obsidianHealthcheckPresent: true,
      }),
      sessions: [makeBucketSession({ captured_to_vault: true })],
    },
  ];

  for (const item of cases) {
    const summary = buildProjectSummary(item.project, item.sessions, 200, generatedAt);
    assert.equal(summary.bucket, item.name);
    if (item.pendingSyncOrphanRatio !== undefined) {
      assert.equal(summary.pending_sync_orphan_ratio, item.pendingSyncOrphanRatio);
    }
  }
});

test('buildProjectSummary computes last session age and null for empty projects', () => {
  const tempDir = makeTempDir();
  const project = makeBucketProject(tempDir, 'age-check', {
    sessionCapturePresent: true,
    obsidianHealthcheckPresent: true,
  });

  const recent = buildProjectSummary(
    project,
    [makeBucketSession({ timestamp: '2026-04-15T12:00:00.000Z', captured_to_vault: true })],
    200,
    '2026-04-17T00:00:00.000Z',
  );
  const empty = buildProjectSummary(project, [], 200, '2026-04-17T00:00:00.000Z');

  assert.equal(recent.last_session_age_days, 1.5);
  assert.equal(empty.last_session_age_days, null);
});

test('buildProjectSummary applies bucket priority before tool-version checks', () => {
  const tempDir = makeTempDir();
  const project = makeBucketProject(tempDir, 'dormant-pre18', {
    sessionCapturePresent: false,
    obsidianHealthcheckPresent: false,
  });
  const summary = buildProjectSummary(
    project,
    [makeBucketSession({ timestamp: '2026-03-01T00:00:00.000Z', captured_to_vault: true })],
    200,
    '2026-04-17T00:00:00.000Z',
  );

  assert.equal(summary.bucket, 'dormant');
});

test('buildProjectSummary classifies zero-session projects without memory dir as never-installed', () => {
  const tempDir = makeTempDir();
  const project = makeBucketProject(tempDir, 'zero-sessions', {
    memoryDir: false,
    sessionCapturePresent: true,
    obsidianHealthcheckPresent: true,
  });
  const summary = buildProjectSummary(project, [], 200, '2026-04-17T00:00:00.000Z');

  assert.equal(summary.bucket, 'never-installed');
});

test('buildProjectSummary treats recent global-vault projects without workspace as installed signal', () => {
  const tempDir = makeTempDir();
  const project = makeBucketProject(tempDir, 'global-only', {
    memoryScriptPresent: false,
    sessionCapturePresent: true,
    obsidianHealthcheckPresent: true,
  });
  project.workspace_path = null;
  project.global_vault_path = path.join(tempDir, 'vault', 'global-only');

  const summary = buildProjectSummary(
    project,
    [makeBucketSession({ captured_to_vault: true })],
    200,
    '2026-04-17T00:00:00.000Z',
  );

  assert.notEqual(summary.bucket, 'never-installed');
  assert.equal(summary.bucket, 'healthy');
});

test('buildProjectSummary clamps future session age to zero', () => {
  const tempDir = makeTempDir();
  const project = makeBucketProject(tempDir, 'future-age', {
    sessionCapturePresent: true,
    obsidianHealthcheckPresent: true,
  });
  const summary = buildProjectSummary(
    project,
    [makeBucketSession({ timestamp: '2026-04-18T00:00:00.000Z', captured_to_vault: true })],
    200,
    '2026-04-17T00:00:00.000Z',
  );

  assert.equal(summary.last_session_age_days, 0);
});

test('buildProjectSummary classifies low capture ratio with full v1.8 tool set as v1.8-failing', () => {
  const tempDir = makeTempDir();
  const project = makeBucketProject(tempDir, 'low-capture', {
    sessionCapturePresent: true,
    obsidianHealthcheckPresent: true,
  });
  const summary = buildProjectSummary(project, makeBucketSessions(10, 3), 200, '2026-04-17T00:00:00.000Z');

  assert.equal(summary.bucket, 'v1.8-failing');
});

test('buildProjectSummary does not classify missing memory script projects as v1.8-failing', () => {
  const tempDir = makeTempDir();
  const project = makeBucketProject(tempDir, 'missing-memory-script', {
    memoryScriptPresent: false,
    sessionCapturePresent: true,
    obsidianHealthcheckPresent: true,
  });
  const summary = buildProjectSummary(project, makeBucketSessions(10, 3), 200, '2026-04-17T00:00:00.000Z');

  assert.equal(summary.bucket, 'never-installed');
  assert.notEqual(summary.bucket, 'v1.8-failing');
});

test('buildProjectSummary tolerates undefined skill catalog', () => {
  const tempDir = makeTempDir();
  const project = makeBucketProject(tempDir, 'missing-skill-catalog', {
    sessionCapturePresent: true,
    obsidianHealthcheckPresent: true,
  });
  delete project.skill_catalog;

  const summary = buildProjectSummary(
    project,
    [makeBucketSession({ captured_to_vault: true })],
    200,
    '2026-04-17T00:00:00.000Z',
  );

  assert.equal(summary.skill_catalog_count, 0);
});

test('writeAuditOutputs keeps Project buckets report table in stable taxonomy order', () => {
  const tempDir = makeTempDir();
  const generatedAt = '2026-04-17T00:00:00.000Z';
  const summaries = [
    buildProjectSummary(
      makeBucketProject(tempDir, 'healthy-project', {
        sessionCapturePresent: true,
        obsidianHealthcheckPresent: true,
      }),
      [makeBucketSession({ captured_to_vault: true })],
      200,
      generatedAt,
    ),
    buildProjectSummary(
      makeBucketProject(tempDir, 'failing-project', {
        sessionCapturePresent: true,
        obsidianHealthcheckPresent: true,
      }),
      makeBucketSessions(10, 3),
      200,
      generatedAt,
    ),
    buildProjectSummary(
      makeBucketProject(tempDir, 'pre18-project', {
        sessionCapturePresent: false,
        obsidianHealthcheckPresent: true,
      }),
      [makeBucketSession({ captured_to_vault: true })],
      200,
      generatedAt,
    ),
    buildProjectSummary(
      makeBucketProject(tempDir, 'dormant-project', {
        sessionCapturePresent: true,
        obsidianHealthcheckPresent: true,
      }),
      [makeBucketSession({ timestamp: '2026-03-01T00:00:00.000Z', captured_to_vault: true })],
      200,
      generatedAt,
    ),
    buildProjectSummary(
      makeBucketProject(tempDir, 'never-project', {
        memoryDir: false,
        sessionCapturePresent: true,
        obsidianHealthcheckPresent: true,
      }),
      [makeBucketSession({ captured_to_vault: true })],
      200,
      generatedAt,
    ),
  ];
  const rankings = {
    obsidian_noncompliance: [],
    low_skill_adoption: [],
    operational_breakage: [],
  };
  const options = {
    workspacesRoot: path.join(tempDir, 'workspaces'),
    vaultRoot: path.join(tempDir, 'vault'),
    codexLogRoots: [path.join(tempDir, 'codex')],
    sessionLimit: 200,
    analysisMode: 'deterministic',
  };
  const report = generateReport({
    generatedAt,
    inventory: { projects: [], excluded: [] },
    projectSummaries: summaries,
    rankings,
    options,
  });
  const result = {
    generated_at: generatedAt,
    inventory: { projects: [], excluded: [] },
    project_summaries: summaries,
    rankings,
    report,
    cost_dashboard: {},
    cost_dashboard_report: '',
  };
  const firstOutputDir = path.join(tempDir, 'out-one');
  const secondOutputDir = path.join(tempDir, 'out-two');
  writeAuditOutputs(firstOutputDir, result);
  writeAuditOutputs(secondOutputDir, result);

  const firstReport = fs.readFileSync(path.join(firstOutputDir, '03-report.md'), 'utf8');
  const secondReport = fs.readFileSync(path.join(secondOutputDir, '03-report.md'), 'utf8');
  const bucketRows = firstReport
    .slice(firstReport.indexOf('## Project buckets'), firstReport.indexOf('## Overview'))
    .split('\n')
    .filter((line) => line.startsWith('| ') && !line.startsWith('| Bucket') && !line.startsWith('|---'));

  assert.deepEqual(
    bucketRows.map((line) => line.split('|')[1].trim()),
    ['never-installed', 'dormant', 'pre-v1.8', 'v1.8-failing', 'healthy'],
  );
  assert.ok(firstReport.includes('Breakage and probable-match signals are heuristic; verify specific counts against source logs before acting.'));
  assert.equal(firstReport, secondReport);
});

test('runAudit builds Codex cost dashboard fields from token_count and tool calls', async () => {
  const tempDir = makeTempDir();
  const workspacesRoot = path.join(tempDir, 'workspaces');
  const vaultRoot = path.join(tempDir, 'vault');
  const codexRoot = path.join(tempDir, 'codex');
  const pricingPath = path.join(tempDir, 'pricing.json');
  const outputDir = path.join(tempDir, 'out');
  writePricing(pricingPath);
  const { repoPath } = writeCanutoProject({ workspacesRoot, vaultRoot });
  const logPath = path.join(codexRoot, '2026', '04', '15', 'rollout-acme.jsonl');

  const records = [
    {
      type: 'session_meta',
      payload: {
        id: 'codex-cost-1',
        timestamp: '2026-04-15T13:23:35.050Z',
        cwd: repoPath,
      },
    },
    {
      type: 'turn_context',
      payload: {
        model: 'gpt-5-codex',
      },
    },
    {
      type: 'response_item',
      payload: {
        type: 'message',
        role: 'user',
        content: [{ type: 'input_text', text: 'inspect this flow' }],
      },
    },
    {
      type: 'response_item',
      payload: {
        type: 'function_call',
        name: 'exec_command',
        call_id: 'call-1',
        arguments: JSON.stringify({ cmd: 'grep -R "foo" src' }),
      },
    },
    {
      type: 'response_item',
      payload: {
        type: 'function_call',
        name: 'mcp__playwright__browser_snapshot',
        call_id: 'call-2',
        arguments: '{}',
      },
    },
    {
      type: 'event_msg',
      payload: {
        type: 'token_count',
        info: {
          total_token_usage: {
            input_tokens: 1000,
            cached_input_tokens: 200,
            output_tokens: 50,
            reasoning_output_tokens: 0,
            total_tokens: 1050,
          },
        },
      },
    },
  ];
  writeFile(logPath, records.map((record) => JSON.stringify(record)).join('\n'));

  const result = await runAudit({
    workspacesRoot,
    vaultRoot,
    codexLogRoots: [codexRoot],
    claudeProjectsRoot: path.join(tempDir, 'missing-claude-projects'),
    claudeTelemetryRoot: path.join(tempDir, 'missing-claude-telemetry'),
    pricingPath,
    sessionLimit: 200,
    parallelism: 2,
    analysisMode: 'deterministic',
    outputDir,
  });
  writeAuditOutputs(outputDir, result);

  const summary = result.project_summaries[0];
  const session = summary.sessions[0];
  assert.equal(session.provider, 'openai');
  assert.equal(session.model, 'gpt-5-codex');
  assert.equal(session.token_usage.uncached_input_tokens, 800);
  assert.equal(session.estimated_cost_usd, 0.00092);
  assert.deepEqual(session.tool_calls.map((item) => item.name), ['bash', 'browser_snapshot']);
  assert.equal(session.shell_commands[0].name, 'grep');
  assert.equal(session.mcp_calls[0].name, 'playwright');
  assert.ok(session.activity_breakdown.Exploration);
  assert.equal(summary.cost_summary.estimated_cost_usd, 0.00092);
  assert.equal(result.cost_dashboard.rankings.by_project[0].project_key, 'acme');
  assert.ok(fs.existsSync(path.join(outputDir, '04-cost-dashboard.json')));
  assert.ok(fs.existsSync(path.join(outputDir, '04-cost-dashboard.md')));
});

test('runAudit computes Claude project log cost from assistant usage', async () => {
  const tempDir = makeTempDir();
  const workspacesRoot = path.join(tempDir, 'workspaces');
  const vaultRoot = path.join(tempDir, 'vault');
  const claudeProjectsRoot = path.join(tempDir, 'claude-projects');
  const pricingPath = path.join(tempDir, 'pricing.json');
  writePricing(pricingPath);
  const { repoPath } = writeCanutoProject({ workspacesRoot, vaultRoot });
  const logPath = path.join(claudeProjectsRoot, 'project', 'claude-cost-1.jsonl');

  const records = [
    {
      type: 'system',
      sessionId: 'claude-cost-1',
      timestamp: '2026-04-15T13:23:35.050Z',
      cwd: repoPath,
    },
    {
      type: 'user',
      sessionId: 'claude-cost-1',
      timestamp: '2026-04-15T13:23:36.050Z',
      cwd: repoPath,
      message: { role: 'user', content: 'check git state' },
    },
    {
      type: 'assistant',
      sessionId: 'claude-cost-1',
      timestamp: '2026-04-15T13:23:37.050Z',
      cwd: repoPath,
      message: {
        role: 'assistant',
        model: 'claude-sonnet-test',
        usage: {
          input_tokens: 100,
          cache_creation_input_tokens: 10,
          cache_read_input_tokens: 20,
          output_tokens: 5,
        },
        content: [
          {
            type: 'tool_use',
            name: 'Bash',
            input: { command: 'git status --short' },
          },
        ],
      },
    },
  ];
  writeFile(logPath, records.map((record) => JSON.stringify(record)).join('\n'));

  const result = await runAudit({
    workspacesRoot,
    vaultRoot,
    codexLogRoots: [path.join(tempDir, 'missing-codex')],
    claudeProjectsRoot,
    claudeTelemetryRoot: path.join(tempDir, 'missing-telemetry'),
    pricingPath,
    sessionLimit: 200,
    parallelism: 2,
    analysisMode: 'deterministic',
    outputDir: path.join(tempDir, 'out'),
  });

  const session = result.project_summaries[0].sessions[0];
  assert.equal(session.provider, 'anthropic');
  assert.equal(session.model, 'claude-sonnet-test');
  assert.equal(session.estimated_cost_usd, 0.000419);
  assert.equal(session.shell_commands[0].name, 'git');
  assert.ok(session.activity_breakdown['Git Ops']);
});

test('Claude telemetry costUSD overrides computed Claude project cost when mapped', async () => {
  const tempDir = makeTempDir();
  const workspacesRoot = path.join(tempDir, 'workspaces');
  const vaultRoot = path.join(tempDir, 'vault');
  const claudeProjectsRoot = path.join(tempDir, 'claude-projects');
  const claudeTelemetryRoot = path.join(tempDir, 'telemetry');
  const pricingPath = path.join(tempDir, 'pricing.json');
  writePricing(pricingPath);
  const { repoPath } = writeCanutoProject({ workspacesRoot, vaultRoot });
  const logPath = path.join(claudeProjectsRoot, 'project', 'claude-telemetry-1.jsonl');
  const telemetryPath = path.join(claudeTelemetryRoot, 'events.json');

  writeFile(
    logPath,
    [
      {
        type: 'system',
        sessionId: 'claude-telemetry-1',
        timestamp: '2026-04-15T13:23:35.050Z',
        cwd: repoPath,
      },
      {
        type: 'assistant',
        sessionId: 'claude-telemetry-1',
        timestamp: '2026-04-15T13:23:37.050Z',
        cwd: repoPath,
        message: {
          role: 'assistant',
          model: 'claude-sonnet-test',
          usage: { input_tokens: 10, output_tokens: 1 },
          content: [],
        },
      },
    ].map((record) => JSON.stringify(record)).join('\n'),
  );
  writeFile(
    telemetryPath,
    JSON.stringify({
      event_type: 'ClaudeCodeInternalEvent',
      event_data: {
        event_name: 'tengu_api_success',
        session_id: 'claude-telemetry-1',
        additional_metadata: JSON.stringify({ costUSD: 1.23 }),
      },
    }),
  );

  const result = await runAudit({
    workspacesRoot,
    vaultRoot,
    codexLogRoots: [path.join(tempDir, 'missing-codex')],
    claudeProjectsRoot,
    claudeTelemetryRoot,
    pricingPath,
    sessionLimit: 200,
    parallelism: 2,
    analysisMode: 'deterministic',
    outputDir: path.join(tempDir, 'out'),
  });

  const session = result.project_summaries[0].sessions[0];
  assert.equal(session.estimated_cost_usd, 1.23);
  assert.equal(session.cost_source, 'claude-telemetry');
});

test('missing pricing preserves tokens and records the model gap', async () => {
  const tempDir = makeTempDir();
  const workspacesRoot = path.join(tempDir, 'workspaces');
  const vaultRoot = path.join(tempDir, 'vault');
  const codexRoot = path.join(tempDir, 'codex');
  const pricingPath = path.join(tempDir, 'pricing.json');
  writePricing(pricingPath);
  const { repoPath } = writeCanutoProject({ workspacesRoot, vaultRoot });
  const logPath = path.join(codexRoot, '2026', '04', '15', 'rollout-acme.jsonl');

  writeFile(
    logPath,
    [
      {
        type: 'session_meta',
        payload: { id: 'missing-pricing-1', timestamp: '2026-04-15T13:23:35.050Z', cwd: repoPath },
      },
      {
        type: 'turn_context',
        payload: { model: 'unknown-expensive-model' },
      },
      {
        type: 'event_msg',
        payload: {
          type: 'token_count',
          info: {
            total_token_usage: {
              input_tokens: 100,
              cached_input_tokens: 0,
              output_tokens: 10,
              total_tokens: 110,
            },
          },
        },
      },
    ].map((record) => JSON.stringify(record)).join('\n'),
  );

  const result = await runAudit({
    workspacesRoot,
    vaultRoot,
    codexLogRoots: [codexRoot],
    claudeProjectsRoot: path.join(tempDir, 'missing-claude-projects'),
    claudeTelemetryRoot: path.join(tempDir, 'missing-claude-telemetry'),
    pricingPath,
    sessionLimit: 200,
    parallelism: 2,
    analysisMode: 'deterministic',
    outputDir: path.join(tempDir, 'out'),
  });

  const session = result.project_summaries[0].sessions[0];
  assert.equal(session.token_usage.total_tokens, 110);
  assert.equal(session.estimated_cost_usd, null);
  assert.deepEqual(session.missing_pricing, ['unknown-expensive-model']);
  assert.deepEqual(result.cost_dashboard.missing_pricing, ['unknown-expensive-model']);
});
