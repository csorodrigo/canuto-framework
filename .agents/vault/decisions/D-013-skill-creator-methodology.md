---
type: decision
id: D-013
date: 2026-03-23
status: active
domain: skills
related-instincts: [I-016, I-018, I-019]
related-sessions: [sessions/2026-03-23c]
tags:
  - decision
  - skills
  - quality
  - progressive-disclosure
---

# D-011 — Adoção da Metodologia skill-creator

**Context:** O Canuto Framework tinha 46+ skills sem infraestrutura de avaliação formal, sem regras de tamanho, e sem processo documentado para criar novas skills. Skills como `frontend-design.md` (431 linhas) carregavam conteúdo desnecessariamente em contexto a cada ativação.

**Decision:** Adotar 3 elementos da metodologia `anthropics/skills/skill-creator`:
1. **Progressive Disclosure** — 3 níveis de carregamento (frontmatter / body ≤200 linhas / references/ sob demanda)
2. **campo `evals`** inline no frontmatter — 4 prompts mínimos por skill crítica (2 should-trigger, 2 near-miss)
3. **skill `/skill-creator`** nativa — processo estruturado de criação de skills adaptado ao modelo de personas

**Reason:**
- Progressive disclosure reduz consumo de tokens por sessão (pilot: -65% em `frontend-design`)
- `evals` criam fonte de verdade para triggering correto — evita undertriggering/overtriggering em 46+ skills
- `/skill-creator` padroniza como novas skills entram no framework, com qualidade built-in

**Trade-offs:**
- Skills existentes >200 linhas precisam ser refatoradas incrementalmente (dívida técnica conhecida)
- `evals` adicionam ~8 linhas a cada frontmatter crítico (custo pequeno, alto valor de documentação)
- O workflow de 7 fases do `/skill-creator` é mais pesado que criar um `.md` diretamente — compensado pela qualidade resultante

**Not adopted from skill-creator:**
- Packaging `.skill` files (Canuto usa GitHub template)
- eval-viewer Python server (gstack já cobre QA visual)
- Blind A/B comparison agent (custo alto, ROI baixo para o estágio atual)
- Scripts bundled Python (stack do Canuto é TS/Bun)

**Related:** [[sessions/2026-03-23c]], [[instincts/I-016-evals-inline-frontmatter]], [[instincts/I-018-near-misses-mais-valiosos]]
