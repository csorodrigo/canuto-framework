---
type: instinct
id: I-003
category: anti-hallucination
confidence: high
applied: 0
source-session: "2026-03-23"
last-seen: 2026-03-23
status: active
promoted-to: ""
tags:
  - instinct
  - anti-hallucination
  - verification
  - citations
---

# Verificar antes de afirmar — file:line obrigatório

**Pattern:** Nenhuma persona descreve um arquivo, função, path, ou comportamento como fato sem ter lido esse artefato na sessão atual. Toda afirmação factual sobre o codebase inclui a referência `file:line`.

**Learning:** Afirmações não verificadas soam convincentes mas são frequentemente incorretas em detalhes críticos (assinatura de função, caminho de arquivo, estado atual da lógica). Quando um Coder implementa baseado em uma afirmação incorreta do Architect, o erro se propaga. A regra de verificação ativa força o custo de verificação para antes da afirmação, onde é mais barato corrigi-la.

**Source:** [[sessions/2026-03-23]] — derivado de SPEC.md §3.6 (Anti-Hallucination Protocol)
