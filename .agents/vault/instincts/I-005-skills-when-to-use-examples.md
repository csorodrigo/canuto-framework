---
type: instinct
id: I-005
category: skills
confidence: high
applied: 0
source-session: "2026-03-23"
last-seen: 2026-03-23
status: active
promoted-to: ""
tags:
  - instinct
  - skills
  - few-shot
  - routing
---

# Skills precisam de "When to Use" + "Examples" para roteamento correto

**Pattern:** Todo arquivo de skill inclui obrigatoriamente uma seção `## When to Use` (com triggers explícitos e exclusões) e uma seção `## Examples` (com par ✅ Good / ❌ Bad).

**Learning:** Skills sem essas seções levam o Maestro a ativar o skill incorretamente (false positives) ou a não ativá-lo quando deveria (false negatives). Few-shot examples ancoram o comportamento do LLM de forma muito mais eficaz do que instruções prosaicas. Sem exemplos, o LLM interpreta o skill livremente; com exemplos, ele replica o padrão mostrado.

**Source:** [[sessions/2026-03-23]] — derivado de SPEC.md §9 (Phase 7, item 26) + [[decisions/D-002-anti-hallucination]]
