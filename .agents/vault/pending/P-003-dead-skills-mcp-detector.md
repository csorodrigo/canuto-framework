---
type: pending
id: P-003
status: pending
priority: medium
owner: ""
provider: ""
created-session: "2026-04-18"
source: "rtk/caveman/token-optimizer evaluation"
inspired-by: "alexgreensh/token-optimizer (clean-room — no code reuse)"
license-note: "upstream is PolyForm Noncommercial — implementation must be original"
rework-count: 0
retry-count: 0
tags:
  - pending
  - tooling-idea
  - audit
  - dead-code
---

# Detector de skills/MCPs nunca invocados

**Pattern:** Script que cruza:
- Lista de skills declaradas em `.agents/skills/*.md`
- Lista de MCP servers em `~/.claude/settings.json` + `.mcp.json` do projeto
- Audit log do vault (`.agents/vault/audit/*.md`) dos últimos N dias

Output: relatório "dead weight" listando skills/MCPs que nunca foram chamados em N dias, com sugestão de remoção.

**Por que vale:**
- Cada skill carregada gasta tokens no system prompt
- Cada MCP server adiciona latência no startup
- Vault já tem audit log → fonte de verdade existe, falta o cruzamento

**Output sugerido:**
```
## Dead Weight Report (últimos 30 dias)
### Skills nunca invocadas
- /absence-reporting (last seen: never) — remover do install.sh?
- /defuddle (last seen: 2026-02-15) — promover ou aposentar?

### MCP servers nunca chamados
- xcodebuild (mac-only, projeto é web) — desabilitar
```

**Estimativa:** S. Reader-only, sem mutations. Pode rodar como `bash .agents/tools/dead-weight-report.sh`.

**Risco:** falsos positivos (skill usada apenas em sessões específicas raras). Mitigação: marcar com `--dry-run` por padrão e exigir confirmação explícita antes de remover.

**Source:** decisão estratégica em `~/.claude/plans/system-instruction-you-are-working-lovely-goblet.md` (sessão 2026-04-18).
