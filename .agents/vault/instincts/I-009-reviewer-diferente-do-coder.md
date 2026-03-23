---
type: instinct
id: I-009
category: review
confidence: medium
applied: 0
source-session: "2026-03-23"
last-seen: 2026-03-23
status: active
promoted-to: ""
tags:
  - instinct
  - reviewer
  - coder
  - fresh-perspective
  - providers
---

# Reviewer diferente do Coder = perspectiva fresca

**Pattern:** O Reviewer deve usar um provider diferente do Coder (ex.: se Coder usou Claude, Reviewer usa Codex ou vice-versa). Isso é configurado explicitamente em CLAUDE.md.

**Learning:** Um LLM revisando seu próprio output tem viés de confirmação — tende a não questionar as escolhas que ele mesmo fez. Usar um provider diferente força uma perspectiva genuinamente externa. Em prática: o Reviewer encontra mais issues quando opera com contexto diferente do Coder. O anti-padrão é "auto-review" onde Coder e Reviewer são o mesmo provider na mesma sessão.

**Source:** [[sessions/2026-03-23]] — derivado de SPEC.md §3.1 (Roster — "Different-from-coder" para Reviewer) + §2.3 (Provider Strategy)
