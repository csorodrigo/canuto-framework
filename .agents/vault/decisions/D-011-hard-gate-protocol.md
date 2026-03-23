---
type: decision
id: D-011
date: 2026-03-23
status: active
domain: process
related-instincts: [I-001, I-013]
related-sessions: []
tags:
  - decision
  - process
  - architect
  - planning
  - hard-gate
---

# Hard-Gate explícito no Architect entre Interview e Plan

**Context:** O Architect já possuía entrevista obrigatória via `AskUserQuestion`, mas a transição para a fase de planejamento era implícita — após responder as perguntas, o agente podia prosseguir para produzir o plano sem um ponto de parada explícito. Em tasks com UI, a aprovação de Design Direction estava documentada no template mas não enforced como gate nomeado.

**Decision:** Formalizar um `<HARD-GATE>` como seção explícita entre a fase de Interview (§3) e a fase de Plan Production (§4) no playbook do Architect. O gate bloqueia textualmente qualquer avanço até que: (1) o usuário tenha respondido todas as perguntas da entrevista, e (2) para tasks com UI, o usuário tenha escolhido uma Design Direction.

**Reason:** Dar nome a um padrão muda como os agentes o respeitam. Um gate implícito é contornável por pressão de tempo ou tarefas "óbvias". Um gate nomeado e com linguagem de bloqueio explícita ("STOP. Do NOT proceed") cria uma barreira psicológica e textual que é muito mais difícil de ignorar. Inspirado no padrão `<HARD-GATE>` do `obra/superpowers`.

**Trade-offs:** Adiciona fricção para tasks XS/S onde o usuário pode considerar a entrevista desnecessária. Aceito — XS tasks não passam pelo Architect. Para S tasks, o Architect já tem modo abreviado (1-2 perguntas).

**Related:** [[instincts/I-001-entrevistar-antes-de-planejar]] [[instincts/I-013-hard-gate-pattern]]
