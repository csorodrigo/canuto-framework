'use strict';

const assert = require('node:assert/strict');
const test = require('node:test');
const path = require('node:path');
const fs = require('node:fs');
const os = require('node:os');

const TOOLS_DIR = path.join(__dirname, '..', '..', 'tools', 'closed-judgment');
const { validateEnvelope, STATUS } = require(path.join(TOOLS_DIR, 'schema'));
const { canonicalize, contextHash } = require(path.join(TOOLS_DIR, 'canonicalize'));
const { classifyBaseline } = require(path.join(TOOLS_DIR, 'baseline-classifier'));
const { runReplay, checkIdempotency, loadFixtures } = require(path.join(TOOLS_DIR, 'replay'));

const FIXTURES_PATH = path.join(__dirname, 'fixtures', 'c01-replay-corpus.synthetic.jsonl');

test('schema: envelope válido passa', () => {
  const { valid, errors } = validateEnvelope({
    schemaVersion: 'spike-c01-0.1.0',
    judgmentId: 'x',
    questionId: 'C-01',
    contextHash: 'deadbeef',
    status: STATUS.ANSWERED,
    choice: 'LOCALIZAR',
  });
  assert.equal(valid, true, errors.join('; '));
});

test('schema: ANSWERED com choice fora do enum falha', () => {
  const { valid, errors } = validateEnvelope({
    schemaVersion: 'spike-c01-0.1.0',
    judgmentId: 'x',
    questionId: 'C-01',
    contextHash: 'deadbeef',
    status: STATUS.ANSWERED,
    choice: 'NAO_EXISTE',
  });
  assert.equal(valid, false);
  assert.ok(errors.some((e) => e.includes('choice inválida')));
});

test('schema: status não-ANSWERED com choice não-nulo falha', () => {
  const { valid, errors } = validateEnvelope({
    schemaVersion: 'spike-c01-0.1.0',
    judgmentId: 'x',
    questionId: 'C-01',
    contextHash: 'deadbeef',
    status: STATUS.ABSTAINED,
    choice: 'LOCALIZAR',
  });
  assert.equal(valid, false);
  assert.ok(errors.some((e) => e.includes('choice deve ser null')));
});

test('canonicalize: mesma entrada produz o mesmo hash', () => {
  const a = contextHash({ context: { foo: 'bar', n: 1 }, questionId: 'C-01', questionVersion: '1' });
  const b = contextHash({ context: { n: 1, foo: 'bar' }, questionId: 'C-01', questionVersion: '1' });
  assert.equal(a, b, 'ordem de chaves não deve afetar o hash (canonicalização)');
});

test('canonicalize: entradas diferentes que só divergem no final não colidem (sem truncamento)', () => {
  const base = 'x'.repeat(5000);
  const a = contextHash({ context: { text: `${base}AAAA` }, questionId: 'C-01', questionVersion: '1' });
  const b = contextHash({ context: { text: `${base}BBBB` }, questionId: 'C-01', questionVersion: '1' });
  assert.notEqual(a, b, 'hash não pode truncar a entrada antes de hashear (achado da revisão adversarial)');
});

test('canonicalize: versão de policy/manifest/modelo entra na chave', () => {
  const base = { context: { text: 'oi' }, questionId: 'C-01', questionVersion: '1' };
  const a = contextHash({ ...base, policyVersion: 'p1' });
  const b = contextHash({ ...base, policyVersion: 'p2' });
  assert.notEqual(a, b, 'mudar a policyVersion deve mudar a chave, mesmo com o mesmo contexto');
});

test('baseline-classifier: cobre os sete casos do enum de C-01', () => {
  assert.equal(classifyBaseline('onde fica isso').choice, 'LOCALIZAR');
  assert.equal(classifyBaseline('explique esse erro').choice, 'EXPLICAR');
  assert.equal(classifyBaseline('por que isso falhou').choice, 'INVESTIGAR');
  assert.equal(classifyBaseline('monte um plano de migração').choice, 'PLANEJAR');
  assert.equal(classifyBaseline('implementa essa validação').choice, 'IMPLEMENTAR');
  assert.equal(classifyBaseline('revise esse PR').choice, 'REVISAR');
  assert.equal(classifyBaseline('sei lá, olha isso aí').choice, 'INSUFFICIENT');
  assert.equal(classifyBaseline('').status, STATUS.NOT_EVALUATED);
});

test('replay: idempotência — mesmo fixture produz o mesmo contextHash em duas rodadas', () => {
  const fixtures = loadFixtures(FIXTURES_PATH);
  const { stable, mismatches } = checkIdempotency(fixtures);
  assert.equal(stable, true, `contextHash instável em: ${JSON.stringify(mismatches)}`);
});

test('replay: harness roda ponta a ponta sem erro de schema no corpus sintético', () => {
  const tmpOut = fs.mkdtempSync(path.join(os.tmpdir(), 'canuto-closed-judgment-'));
  try {
    const summary = runReplay(FIXTURES_PATH, tmpOut);
    assert.equal(summary.schemaErrors.length, 0, JSON.stringify(summary.schemaErrors));
    assert.equal(summary.idempotency.stable, true);
    assert.ok(summary.metrics.baseline.total > 0);
    assert.ok(fs.existsSync(path.join(tmpOut, 'summary.json')));
  } finally {
    fs.rmSync(tmpOut, { recursive: true, force: true });
  }
});

test('replay: métricas do baseline têm formato correto (não é sinal de valor de C-01, corpus é sintético)', () => {
  // Este teste NÃO assume o baseline acerta tudo — o corpus sintético já
  // expõe 2 misses reais de ambiguidade de palavra-chave (c01-009, c01-011).
  // Isso é sinal do harness funcionando, não um bug a esconder: forçar 0
  // misses aqui seria fabricar o resultado que o gate de decisão existe para
  // medir de verdade, com corpus e rótulo humano de verdade.
  const fixtures = loadFixtures(FIXTURES_PATH);
  const { runOnce, computeMetrics } = require(path.join(TOOLS_DIR, 'replay'));
  const { receipts } = runOnce(fixtures);
  const metrics = computeMetrics(receipts, 'baselineEnvelope');
  assert.ok(metrics.total > 0);
  assert.ok(metrics.coverage >= 0 && metrics.coverage <= 1);
  assert.ok(metrics.precision === null || (metrics.precision >= 0 && metrics.precision <= 1));
  for (const miss of metrics.misses) {
    assert.ok(miss.caseId && miss.expected && miss.got, 'cada miss deve identificar caso/esperado/obtido');
  }
});
