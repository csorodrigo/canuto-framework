---
type: decision
id: D-010
date: 2026-03-23
status: active
domain: observability
related-instincts: [I-012]
related-sessions: []
tags:
  - decision
  - observability
  - convergence
  - instincts
---

# Convergence detection para instincts de alta confiança

**Context:** Instincts extraídos de uma única persona ou sessão têm baixa confiança. Precisávamos de um mecanismo para elevar confiança sem aumentar a dependência de input humano explícito.

**Decision:** Quando 2+ personas independentemente chegam à mesma conclusão, Maestro marca como convergente e eleva a confiança para `medium` automaticamente. Findings direcionados (uma persona seguindo sugestão de outra) não contam como independentes. Convergência de 3+ personas eleva para `high`.

**Reason:** Independência entre personas é análoga à revisão por pares — múltiplos observadores sem comunicação prévia chegando ao mesmo resultado é evidência forte. Automatizar essa promoção reduz o trabalho manual de curadoria de instincts.

**Trade-offs:** Requer que Maestro rastreie qual persona reportou o quê, e que preserve essa informação no contexto da sessão. Complexidade de implementação moderada. Aceito: o valor em longo prazo (instincts confiáveis sem overhead manual) justifica.

**Related:** [[instincts/I-012-ausencias-convergentes-prioridade]]
