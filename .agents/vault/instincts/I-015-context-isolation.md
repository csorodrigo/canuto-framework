---
type: instinct
id: I-015
category: personas
confidence: medium
applied: 0
source-session: "2026-03-23"
last-seen: 2026-03-23
status: active
promoted-to: ""
tags:
  - instinct
  - personas
  - maestro
  - context
  - handoff
---

# Context pollution degrada output — passar só o necessário em cada handoff

**Pattern:** Cada persona deve receber apenas o contexto necessário para sua tarefa específica. O Maestro deve explicitamente filtrar o que passa nos handoffs: incluir goal, plan step, file paths, constraints e output format; excluir conversation history, outputs de personas anteriores, erros já resolvidos e contexto de exploração.

**Learning:** O sistema de personas do Canuto cria naturalmente algum isolamento, mas sem princípio explícito os handoffs tendiam a carregar contexto acumulado da sessão. Contexto excessivo causa "context pollution": tokens desperdiçados com informação irrelevante, e interferência de estado anterior no output da persona atual. Cada persona deve começar fresh com contexto cirúrgico. Conceito derivado do Subagent-Driven Development do `obra/superpowers`.

**Confidence note:** Medium — princípio novo adotado sem validação em sessões reais ainda. Elevar para high após 3+ sessões confirmando o benefício.

**Source:** [[sessions/2026-03-23]] — adotado de obra/superpowers (context isolation em SDD), adaptado para o modelo de personas do Canuto
