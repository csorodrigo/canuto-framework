---
type: decision
id: D-008
date: 2026-03-23
status: active
domain: efficiency
related-instincts: [I-010]
related-sessions: []
tags:
  - decision
  - efficiency
  - tokens
  - task-sizing
---

# Task sizing XS/S/M/L para reduzir consumo de tokens

**Context:** O fluxo completo Maestro → Architect → Coder → Tester → Reviewer é excessivo para tarefas triviais (fix typo, rename variable). Cada persona adiciona overhead de tokens significativo.

**Decision:** Maestro classifica toda task antes de rotear: XS (pulam Architect, vão direto ao Coder), S (Architect abbreviado — menos perguntas), M (fluxo padrão), L (fluxo completo + squads opcionais). Classificação baseada em escopo de mudança, não em esforço percebido.

**Reason:** Redução empírica de 40-60% no consumo de tokens em tarefas pequenas. XS e S representam ~60% das tasks em projetos ativos. O trade-off entre thoroughness e custo se resolve por sizing correto, não por cortar corners no processo.

**Trade-offs:** Maestro pode classificar incorretamente. Mitigado: o usuário pode sempre forçar um nível maior explicitamente ("trate como M"). Erro de sub-classificação é mais custoso que over-classificação.

**Related:** [[instincts/I-010-xs-tasks-pulam-architect]]
