---
type: decision
id: D-006
date: 2026-03-23
status: active
domain: process
related-instincts: [I-002]
related-sessions: []
tags:
  - decision
  - process
  - handoffs
  - transparency
---

# Handoff protocol explícito com anúncios de transição

**Context:** Em sistemas multi-agente, transições entre personas podem ser invisíveis, criando confusão sobre "quem está agindo" e dificultando debugging quando algo dá errado.

**Decision:** Todas as transições de persona são explícitas e anunciadas ao usuário: "Now acting as Architect. Plan: ...". Apenas transições maiores são anunciadas (plan → code → test → review), não micro-steps. Situações inesperadas SEMPRE escalam para Maestro antes de prosseguir.

**Reason:** Transparência constrói confiança no sistema. O usuário pode intervir em qualquer ponto. Escalação obrigatória previne decisões autônomas sobre situações fora do plano original.

**Trade-offs:** Aumenta o volume de output em sessões longas. Aceito via `handoff-verbosity: milestones-only` em CLAUDE.md para projetos que preferem output mais silencioso.

**Related:** [[instincts/I-002-maestro-roteia-nunca-implementa]]
