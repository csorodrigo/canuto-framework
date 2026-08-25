---
type: instinct
id: I-012
category: observability
confidence: medium
applied: 0
source-session: "2026-03-23"
last-seen: 2026-03-23
status: active
promoted-to: ""
tags:
  - instinct
  - absence-reporting
  - convergence
  - investigation
---

# Ausências convergentes (2+ personas) = prioridade de investigação alta

**Pattern:** Quando 2 ou mais personas independentemente reportam não ter encontrado algo (ex.: "não encontrei testes para este módulo", "não há documentação para este endpoint"), Maestro eleva para investigação prioritária antes de prosseguir com a task principal.

**Learning:** Uma ausência reportada por uma persona pode ser um gap de exploração. A mesma ausência reportada por 2 personas independentes é muito provavelmente uma lacuna real no projeto. A falta de testes, documentação, ou tratamento de erro — quando confirmada convergentemente — representa risco técnico maior do que qualquer feature nova. Ignorar ausências convergentes é a principal fonte de débito técnico silencioso.

**Source:** [[sessions/2026-03-23]] — derivado de SPEC.md §11.1 (Absence Reporting) + §11.8 (Convergence Detection)
