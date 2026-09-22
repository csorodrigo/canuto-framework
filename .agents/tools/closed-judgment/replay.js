'use strict';

// Harness offline do spike de C-01 (ver docs/adr/0018-jev-spike-offline-c01.md).
// Sem chamada externa: só baseline determinístico + mock adapter local.
// Uso: node replay.js --fixtures <arquivo.jsonl> [--out <dir>]

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const { SCHEMA_VERSION, STATUS, validateEnvelope } = require('./schema');
const { contextHash } = require('./canonicalize');
const { classifyBaseline } = require('./baseline-classifier');
const { mockClassify, PROVIDER_ID, MODEL_ID, ADAPTER_VERSION } = require('./mock-adapter');

const QUESTION_ID = 'C-01';
const QUESTION_VERSION = '1';
const POLICY_VERSION = 'spike-offline-0'; // não há policy engine ainda — deliberado

function loadFixtures(fixturesPath) {
  const raw = fs.readFileSync(fixturesPath, 'utf8');
  return raw
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line, idx) => {
      try {
        return JSON.parse(line);
      } catch (err) {
        throw new Error(`fixture inválida na linha ${idx + 1}: ${err.message}`);
      }
    });
}

function buildEnvelope({ caseId, classification, source }) {
  const hash = contextHash({
    context: { caseId, text: classification.inputText },
    questionId: QUESTION_ID,
    questionVersion: QUESTION_VERSION,
    policyVersion: POLICY_VERSION,
    leafManifestVersion: 'n/a-offline-spike',
    providerId: source === 'mock' ? PROVIDER_ID : 'baseline-deterministic',
    modelId: source === 'mock' ? MODEL_ID : 'n/a',
    adapterVersion: source === 'mock' ? ADAPTER_VERSION : 'n/a',
    codeVersion: SCHEMA_VERSION,
  });
  return {
    schemaVersion: SCHEMA_VERSION,
    judgmentId: `${caseId}:${source}:${hash.slice(0, 16)}`,
    runId: null, // preenchido pelo caller se necessário
    questionId: QUESTION_ID,
    questionVersion: QUESTION_VERSION,
    contextHash: hash,
    providerId: source === 'mock' ? PROVIDER_ID : 'baseline-deterministic',
    status: classification.status,
    choice: classification.choice,
    reason: classification.reason,
    recordedAt: null, // determinístico de propósito — ver nota de idempotência abaixo
  };
}

function runOnce(fixtures) {
  const receipts = [];
  const schemaErrors = [];
  for (const fixture of fixtures) {
    const baseline = classifyBaseline(fixture.text);
    const mock = mockClassify(fixture.text);

    const baselineEnvelope = buildEnvelope({
      caseId: fixture.id,
      classification: { ...baseline, inputText: fixture.text },
      source: 'baseline',
    });
    const mockEnvelope = buildEnvelope({
      caseId: fixture.id,
      classification: { ...mock, inputText: fixture.text },
      source: 'mock',
    });

    for (const envelope of [baselineEnvelope, mockEnvelope]) {
      const { valid, errors } = validateEnvelope(envelope);
      if (!valid) schemaErrors.push({ caseId: fixture.id, judgmentId: envelope.judgmentId, errors });
    }

    receipts.push({ fixture, baselineEnvelope, mockEnvelope });
  }
  return { receipts, schemaErrors };
}

function computeMetrics(receipts, envelopeKey) {
  let total = 0;
  let answered = 0;
  let correct = 0;
  const misses = [];
  for (const { fixture, [envelopeKey]: envelope } of receipts) {
    total += 1;
    if (!fixture.humanLabel) continue; // sem rótulo adjudicado, não entra na métrica
    if (envelope.status === STATUS.ANSWERED) {
      answered += 1;
      if (envelope.choice === fixture.humanLabel) {
        correct += 1;
      } else {
        misses.push({ caseId: fixture.id, expected: fixture.humanLabel, got: envelope.choice });
      }
    }
  }
  const coverage = total > 0 ? answered / total : 0;
  const precision = answered > 0 ? correct / answered : null;
  return { total, answered, correct, coverage, precision, misses };
}

function checkIdempotency(fixtures) {
  const first = runOnce(fixtures);
  const second = runOnce(fixtures);
  const mismatches = [];
  for (let i = 0; i < first.receipts.length; i += 1) {
    const a = first.receipts[i];
    const b = second.receipts[i];
    if (a.baselineEnvelope.contextHash !== b.baselineEnvelope.contextHash) {
      mismatches.push({ caseId: a.fixture.id, source: 'baseline' });
    }
    if (a.mockEnvelope.contextHash !== b.mockEnvelope.contextHash) {
      mismatches.push({ caseId: a.fixture.id, source: 'mock' });
    }
  }
  return { stable: mismatches.length === 0, mismatches };
}

function runReplay(fixturesPath, outDir) {
  const fixtures = loadFixtures(fixturesPath);
  const { receipts, schemaErrors } = runOnce(fixtures);
  const baselineMetrics = computeMetrics(receipts, 'baselineEnvelope');
  const mockMetrics = computeMetrics(receipts, 'mockEnvelope');
  const idempotency = checkIdempotency(fixtures);

  const summary = {
    generatedBy: 'closed-judgment/replay.js (spike-offline, sem chamada externa)',
    fixturesPath,
    totalCases: fixtures.length,
    schemaErrors,
    idempotency,
    metrics: {
      baseline: baselineMetrics,
      mockAdapterNotVendorSignal: mockMetrics,
    },
  };

  if (outDir) {
    fs.mkdirSync(outDir, { recursive: true });
    fs.writeFileSync(path.join(outDir, 'summary.json'), JSON.stringify(summary, null, 2));
    for (const { fixture, baselineEnvelope, mockEnvelope } of receipts) {
      const caseDir = path.join(outDir, 'cases');
      fs.mkdirSync(caseDir, { recursive: true });
      fs.writeFileSync(
        path.join(caseDir, `${fixture.id}.json`),
        JSON.stringify({ baselineEnvelope, mockEnvelope }, null, 2),
      );
    }
  }

  return summary;
}

function parseArgs(argv) {
  const args = { fixtures: null, out: null };
  for (let i = 0; i < argv.length; i += 1) {
    if (argv[i] === '--fixtures') args.fixtures = argv[++i];
    else if (argv[i] === '--out') args.out = argv[++i];
  }
  return args;
}

if (require.main === module) {
  const { fixtures, out } = parseArgs(process.argv.slice(2));
  if (!fixtures) {
    process.stderr.write('uso: node replay.js --fixtures <arquivo.jsonl> [--out <dir>]\n');
    process.exit(64);
  }
  const summary = runReplay(fixtures, out);
  process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
  const hasSchemaErrors = summary.schemaErrors.length > 0;
  const hasIdempotencyDrift = !summary.idempotency.stable;
  if (hasSchemaErrors || hasIdempotencyDrift) {
    process.stderr.write('FALHA: erro de schema ou de idempotência — ver summary acima.\n');
    process.exit(1);
  }
}

module.exports = { runReplay, runOnce, computeMetrics, checkIdempotency, loadFixtures, buildEnvelope };
