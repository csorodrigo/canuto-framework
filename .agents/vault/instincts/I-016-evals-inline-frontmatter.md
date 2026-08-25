---
type: instinct
id: I-016
date: 2026-03-23
confidence: medium
domain: skills
occurrences: 1
related-decisions: [D-011]
related-sessions: [sessions/2026-03-23c]
tags:
  - instinct
  - skills
  - evals
  - quality
---

# I-013 — Evals Co-localizados no Frontmatter da Skill

Armazenar `evals` inline no frontmatter YAML da skill (não em arquivo externo) é a abordagem correta para o Canuto Framework.

**Why:** Arquivos externos de eval (como `evals/evals.json`) criam proliferação de arquivos e desacoplam a spec de teste da implementação. No frontmatter, os evals ficam co-localizados com a skill, são lidos na mesma operação, e são visíveis no contexto quando a skill é carregada.

**How to apply:**
- Todo skill crítico deve ter campo `evals` no frontmatter com 4 entradas mínimas
- 2 `should_trigger: true`: 1 caso óbvio + 1 edge case sem nomear o skill explicitamente
- 2 `should_trigger: false`: near-misses (mesmo domínio, intenção diferente) — não prompts obviamente irrelevantes
- Prompts devem ser realistas: contexto, linguagem casual, typos, detalhes específicos
