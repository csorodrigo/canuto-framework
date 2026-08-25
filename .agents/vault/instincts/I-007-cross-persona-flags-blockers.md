---
type: instinct
id: I-007
category: observability
confidence: medium
applied: 0
source-session: "2026-03-23"
last-seen: 2026-03-23
status: active
promoted-to: ""
tags:
  - instinct
  - cross-persona-flags
  - blockers
  - observability
---

# Cross-persona flags previnem blockers silenciosos

**Pattern:** Quando uma persona descobre algo relevante para outra persona (ex.: Coder nota um security issue que é domínio do Reviewer, ou Tester vê um padrão que o Architect deveria saber), ela emite um outbound flag via `## Outbound Flags` em vez de ignorar ou agir fora do seu escopo.

**Learning:** Sem flags explícitos, discoveries entre personas se perdem. O Coder silenciará uma preocupação de segurança porque "não é o meu papel". Com flags, a descoberta é roteada pelo Maestro para a persona certa. O anti-padrão é um persona "ajudando" fora do seu escopo — o que viola a separação de responsabilidades.

**Source:** [[sessions/2026-03-23]] — derivado de SPEC.md §11.2 (Cross-Persona Flags)
