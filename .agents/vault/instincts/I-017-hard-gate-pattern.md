---
type: instinct
id: I-017
category: process
confidence: high
applied: 0
source-session: "2026-03-23"
last-seen: 2026-03-23
status: active
promoted-to: ""
tags:
  - instinct
  - process
  - architect
  - planning
  - hard-gate
---

# Hard-Gate nomeado bloqueia melhor que regra implícita

**Pattern:** Entre fases críticas de workflow (ex: entrevista → plano, design → implementação), um gate explicitamente nomeado com linguagem de bloqueio ("STOP. Do NOT proceed until...") é significativamente mais respeitado do que uma regra implícita ou nota de rodapé.

**Learning:** O Architect já tinha entrevista obrigatória como instrução, mas a transição para o plano era fluida. Renomear e formalizar o ponto de parada como `<HARD-GATE>` com checklist explícito cria uma barreira que resiste a pressões de tempo e tarefas "óbvias". Inspirado no padrão do `obra/superpowers` onde hard-gates previnem que agentes pulem fases críticas por otimismo prematuro.

**Source:** [[sessions/2026-03-23]] — adotado de obra/superpowers após análise comparativa dos dois frameworks
