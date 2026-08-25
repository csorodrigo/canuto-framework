---
type: instinct
id: I-006
category: testing
confidence: medium
applied: 0
source-session: "2026-03-23"
last-seen: 2026-03-23
status: active
promoted-to: ""
tags:
  - instinct
  - testing
  - tester
  - edge-cases
---

# Tester foca em edge cases, não duplica happy path

**Pattern:** O Tester recebe o código do Coder e foca exclusivamente em: edge cases, error scenarios, race conditions, security implications, e coverage gaps. Não reescreve os testes que o Coder já escreveu.

**Learning:** Quando o Tester duplica os testes do Coder, o custo de tokens dobra sem ganho real em qualidade. O valor do Tester está em encontrar os cenários que o Coder não cobriu — especialmente inputs inválidos, estados de erro, e casos limite. Um Tester que duplica happy path é um Coder caro.

**Source:** [[sessions/2026-03-23]] — derivado de SPEC.md §7.2 (Tester Protocol)
