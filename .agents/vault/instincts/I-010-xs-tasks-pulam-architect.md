---
type: instinct
id: I-010
category: efficiency
confidence: medium
applied: 0
source-session: "2026-03-23"
last-seen: 2026-03-23
status: active
promoted-to: ""
tags:
  - instinct
  - efficiency
  - task-sizing
  - tokens
  - architect
---

# XS tasks pulam Architect (40-60% economia de tokens)

**Pattern:** Tasks classificadas como XS (typo fix, rename, single-line change, config tweak) vão diretamente do Maestro para o Coder, sem passar pelo Architect. Tasks S usam Architect em modo abbreviado (2-3 perguntas, não entrevista completa).

**Learning:** O fluxo completo para uma task XS adiciona ~3.000-8.000 tokens de overhead sem benefício real. O Architect não tem como tornar um typo fix "melhor planejado". A classificação XS deve ser conservadora: em caso de dúvida, classificar como S e usar Architect abbreviado. O risco de sub-classificar (ir direto ao Coder numa task que precisava de Architect) é maior que o custo de tokens de um Architect abbreviado desnecessário.

**Source:** [[sessions/2026-03-23]] — derivado de SPEC.md §9 (Phase 5, item 15 — Task Sizing)
