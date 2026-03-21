---
type: decision
id: D-002
date: 2026-03-02
status: active
domain: process
related-instincts: []
related-sessions: []
tags:
  - decision
  - process
  - prompting
---

# Anti-Hallucination Protocol + Confidence Tagging + padronização de skills

**Context:** Análise revelou que agentes podiam fazer afirmações não verificadas com tom de certeza, e que skills sem exemplos levavam os agentes a inventar formatos. Maestro também não tinha triggers claros para rotear skills.

**Decision:** Adicionar Anti-Hallucination Protocol (SPEC §3.6) e Confidence Tagging `[CONFIRMED]/[ASSUMED]/[UNCERTAIN]` (SPEC §3.7) como protocolos universais. Adicionar seções "When to Use" e "Examples" (✅/❌) em todos os 16 skills.

**Reason:** Few-shot exemplos ancoram comportamento em LLMs; confidence tags tornam incerteza explícita; triggers de skill evitam roteamento incorreto pelo Maestro.

**Trade-offs:** Volume de edições alto (16 arquivos + SPEC + 2 personas). Aceito — é trabalho de setup, não de manutenção contínua.
