'use strict';

const { classifyBaseline } = require('./baseline-classifier');

// ⚠️ NÃO É SINAL DE VALOR DO JEV. Nenhuma chamada real de vendor acontece
// nesta fase (gate de DPA ainda não confirmado — ver ADR-0018). Este adapter
// existe só para exercitar a forma do envelope/schema/receipt/idempotência
// ponta a ponta offline. Ele delega para o baseline determinístico por baixo
// dos panos; não meça "precisão do JEV" com o resultado deste módulo.
const PROVIDER_ID = 'mock-adapter';
const MODEL_ID = 'mock-v0';
const ADAPTER_VERSION = '0.1.0-mock';

function mockClassify(text) {
  const result = classifyBaseline(text);
  return {
    ...result,
    reason: `MOCK (não é sinal de vendor real): ${result.reason}`,
  };
}

module.exports = { mockClassify, PROVIDER_ID, MODEL_ID, ADAPTER_VERSION };
