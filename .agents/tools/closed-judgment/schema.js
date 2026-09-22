'use strict';

// Envelope mínimo do spike-offline de C-01 (ver docs/adr/0018-jev-spike-offline-c01.md).
// Isto NÃO é o envelope genérico multi-pergunta do plano original (schemaVersion
// versionado, registry, policy engine) — esse fica para depois do gate de decisão,
// só se um segundo caso real justificar generalizar.

const SCHEMA_VERSION = 'spike-c01-0.1.0';

const STATUS = Object.freeze({
  ANSWERED: 'ANSWERED',
  ABSTAINED: 'ABSTAINED',
  NOT_APPLICABLE: 'NOT_APPLICABLE',
  NOT_EVALUATED: 'NOT_EVALUATED',
});

// Enum de C-01 (ver plano: "qual o tipo principal da tarefa?").
const C01_CHOICES = Object.freeze([
  'LOCALIZAR',
  'EXPLICAR',
  'INVESTIGAR',
  'PLANEJAR',
  'IMPLEMENTAR',
  'REVISAR',
  'INSUFFICIENT',
]);

const STATUS_VALUES = new Set(Object.values(STATUS));

function validateEnvelope(envelope) {
  const errors = [];
  if (!envelope || typeof envelope !== 'object') {
    return { valid: false, errors: ['envelope ausente ou não é objeto'] };
  }
  if (envelope.schemaVersion !== SCHEMA_VERSION) {
    errors.push(`schemaVersion esperado "${SCHEMA_VERSION}", recebido "${envelope.schemaVersion}"`);
  }
  if (!envelope.judgmentId) errors.push('judgmentId ausente');
  if (!envelope.questionId) errors.push('questionId ausente');
  if (!envelope.contextHash) errors.push('contextHash ausente (chave de idempotência)');
  if (!STATUS_VALUES.has(envelope.status)) {
    errors.push(`status inválido: ${envelope.status}`);
  }
  if (envelope.status === STATUS.ANSWERED) {
    if (!C01_CHOICES.includes(envelope.choice)) {
      errors.push(`choice inválida para status ANSWERED: ${envelope.choice}`);
    }
  } else if (envelope.choice !== null && envelope.choice !== undefined) {
    errors.push(`choice deve ser null quando status é ${envelope.status}, recebido: ${envelope.choice}`);
  }
  return { valid: errors.length === 0, errors };
}

module.exports = { SCHEMA_VERSION, STATUS, C01_CHOICES, validateEnvelope };
