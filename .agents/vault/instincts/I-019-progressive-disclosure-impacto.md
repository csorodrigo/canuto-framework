---
type: instinct
id: I-019
date: 2026-03-23
confidence: high
domain: skills
occurrences: 1
related-decisions: [D-011]
related-sessions: [sessions/2026-03-23c]
tags:
  - instinct
  - skills
  - progressive-disclosure
  - token-optimization
---

# I-015 — Progressive Disclosure: Impacto Medido em -65% por Skill Grande

Refatorar uma skill >200 linhas para o modelo de 3 níveis (frontmatter / body / references) reduz significativamente o carregamento em contexto sem perda de funcionalidade.

**Why:** `frontend-design.md` tinha 431 linhas sendo carregadas integralmente toda vez que qualquer task com UI ativava a skill. Na maioria dos casos, apenas o procedimento (linhas 1-100) é necessário — os 331 linhas restantes de padrões estéticos e exemplos raramente são todos consultados em uma única sessão.

**Pilot medido:** `frontend-design.md` (431 linhas, 21.9KB) → `frontend-design/SKILL.md` (164 linhas) + `references/` (carregados sob demanda). Redução de 62% nas linhas sempre em contexto.

**How to apply:**
- Identificar skills >200 linhas com seções claramente separáveis (receitas de código, checklists longos, exemplos extensos)
- Mover para `skill-name/SKILL.md` + `skill-name/references/topic.md`
- O SKILL.md body deve dizer explicitamente "→ leia references/X.md quando precisar de Y"
- Candidatos próximos: `context-maintenance.md` (16KB), `experiment-loop.md` (9.7KB), `continuous-learning.md` (9.6KB)
