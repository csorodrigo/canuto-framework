---
type: decision
id: D-007
date: 2026-03-23
status: active
domain: extensibility
related-instincts: []
related-sessions: []
tags:
  - decision
  - plugins
  - extensibility
  - architecture
---

# Plugin architecture (core + opt-in em .agents/plugins/)

**Context:** Diferentes projetos têm necessidades específicas que o framework core não deve carregar para todos. Ex.: CI/CD integrations, database migrations, design systems específicos.

**Decision:** Core skills vivem em `.agents/skills/`. Plugins opcionais vivem em `.agents/plugins/<name>/` com um `plugin.md` manifest. Core sempre ganha em conflitos de nome; plugins usam nomes com namespace. Maestro descobre plugins ativos no session start.

**Reason:** Mantém o core enxuto e sem opiniões fortes. Permite extensões per-project sem forçar complexidade em projetos simples. A estrutura de manifest torna plugins auto-documentados e descobríveis.

**Trade-offs:** Plugins não são atualizados automaticamente com o framework. Aceito — segue o mesmo modelo de distribuição snapshot (D-003) por consistência.

**Related:** [[decisions/D-003-github-template-distribution]]
