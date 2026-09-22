'use strict';

const { STATUS } = require('./schema');

// A alternativa determinística que C-01 precisa superar antes de qualquer
// chamada a um vendor real ser justificável (ver plano: "D primeiro; H/I
// residual"). Regras simples e legíveis — nenhuma chamada externa, nenhum
// custo, sem versão de modelo para se preocupar.
const KEYWORD_RULES = [
  [/\bonde\b|\bwhere\b|\blocaliz/i, 'LOCALIZAR'],
  [/\bo que (é|significa|faz)\b|\bexplain\b|\bexplique\b/i, 'EXPLICAR'],
  [/\bpor que\b|\bdebug\b|\bfalha\b|\bbug\b|\binvestig/i, 'INVESTIGAR'],
  [/\bplano\b|\bplan\b|\barquitetura\b|\bcomo (fazer|abordar)\b/i, 'PLANEJAR'],
  [/\bimplementa|\bescreva\b|\bcrie\b|\badicione\b|\bcorrija\b|\bfix\b/i, 'IMPLEMENTAR'],
  [/\brevis(e|ão)\b|\breview\b|\bpr\b/i, 'REVISAR'],
];

function classifyBaseline(text) {
  if (!text || !text.trim()) {
    return { status: STATUS.NOT_EVALUATED, choice: null, reason: 'entrada vazia' };
  }
  for (const [pattern, choice] of KEYWORD_RULES) {
    if (pattern.test(text)) {
      return { status: STATUS.ANSWERED, choice, reason: `baseline:${pattern.source}` };
    }
  }
  // INSUFFICIENT é um CHOICE válido (o classificador respondeu "não sei"),
  // não ABSTAINED (que é para falha de infraestrutura, não conteúdo).
  return { status: STATUS.ANSWERED, choice: 'INSUFFICIENT', reason: 'baseline: nenhuma regra bateu' };
}

module.exports = { classifyBaseline, KEYWORD_RULES };
