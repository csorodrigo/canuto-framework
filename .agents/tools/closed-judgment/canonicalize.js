'use strict';

const crypto = require('node:crypto');

// Achado da revisão adversarial (Claude blind-reviewer + codex gpt-5.6-sol):
// truncar a entrada ANTES de hashear colide contextos reais diferentes na
// mesma chave, suprimindo silenciosamente uma reavaliação necessária. Este
// módulo hasheia a serialização canônica COMPLETA — nunca trunca a entrada.
// O canonicalizador em si é versionado: mudar a ordenação/serialização aqui
// exige subir CANONICALIZER_VERSION, para não colidir chaves antigas com
// chaves novas silenciosamente.
const CANONICALIZER_VERSION = '1';

function canonicalize(value) {
  if (value === null || value === undefined) return 'null';
  if (typeof value !== 'object') return JSON.stringify(value);
  if (Array.isArray(value)) {
    return `[${value.map((item) => canonicalize(item)).join(',')}]`;
  }
  const keys = Object.keys(value).sort();
  const body = keys.map((key) => `${JSON.stringify(key)}:${canonicalize(value[key])}`).join(',');
  return `{${body}}`;
}

// A chave de idempotência inclui, além do contexto, a versão de tudo que
// afeta o significado do julgamento (achado Codex): canonicalizador, policy,
// manifest de folhas, provedor/modelo/adapter e versão do código. Assim uma
// mudança de política, por exemplo, não fica escondida atrás da mesma chave.
function contextHash({
  context,
  questionId,
  questionVersion,
  policyVersion = 'unset',
  leafManifestVersion = 'unset',
  providerId = 'mock',
  modelId = 'mock',
  adapterVersion = 'unset',
  codeVersion = 'unset',
}) {
  if (!questionId) throw new Error('contextHash requer questionId');
  const keyMaterial = canonicalize({
    canonicalizerVersion: CANONICALIZER_VERSION,
    context,
    questionId,
    questionVersion,
    policyVersion,
    leafManifestVersion,
    providerId,
    modelId,
    adapterVersion,
    codeVersion,
  });
  return crypto.createHash('sha256').update(keyMaterial, 'utf8').digest('hex');
}

module.exports = { CANONICALIZER_VERSION, canonicalize, contextHash };
