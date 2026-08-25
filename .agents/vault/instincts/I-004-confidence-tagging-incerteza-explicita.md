---
type: instinct
id: I-004
category: anti-hallucination
confidence: high
applied: 0
source-session: "2026-03-23"
last-seen: 2026-03-23
status: active
promoted-to: ""
tags:
  - instinct
  - anti-hallucination
  - confidence-tagging
  - uncertainty
---

# Confidence tagging torna incerteza explícita

**Pattern:** Usar `[CONFIRMED]`, `[ASSUMED]`, `[UNCERTAIN]` em planos e diagnósticos para tornar o nível de certeza explícito, não escondido em prosa confiante.

**Learning:** A incerteza escondida em linguagem confiante é mais perigosa que incerteza declarada. Um `[ASSUMED]` visível no plano é um lembrete de que aquele passo precisa de verificação antes da implementação. Um `[UNCERTAIN]` obriga uma pergunta ao usuário antes de prosseguir. Sem tags, o Coder implementa `[ASSUMED]` como se fosse fato, e o bug entra silenciosamente.

**Source:** [[sessions/2026-03-23]] — derivado de SPEC.md §3.7 (Confidence Tagging)
