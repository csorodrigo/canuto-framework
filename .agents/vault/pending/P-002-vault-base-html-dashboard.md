---
type: pending
id: P-002
status: pending
priority: low
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
  - vault
  - dashboard
---

# Dashboard HTML local read-only sobre arquivos `.base`

**Pattern:** Servidor HTTP estático (Python stdlib ou bash + python -m http.server) que renderiza `.agents/vault/bases/*.base` em uma página HTML única. Bookmark `localhost:24842/canuto-vault`. Auto-refresh ao final de cada sessão via SessionEnd hook.

**O que mostraria** (refletindo as `.base` que já existem):
- Pending tasks por prioridade (de `pending-tasks.base`)
- Decisions timeline
- Provider reliability trends
- Metrics dashboard
- Rework hotspots

**Por que vale:** o vault Obsidian é ótimo para o usuário do Obsidian, mas a webview única no browser dá visibilidade zero-token a quem não roda Obsidian.

**Restrições:**
- Zero dependências runtime (stdlib only)
- Zero context tokens (skill não roda dentro de Claude — script externo)
- Read-only (nenhuma escrita no vault a partir do dashboard)

**Estimativa:** S-M. Wrapper sobre `vault-bridge.sh` que já existe.

**Bloqueador:** definir parser para `.base` files (formato Obsidian Bases YAML+formulas). Pode usar `obsidian-mcp-server` como source-of-truth ou parser próprio.

**Source:** decisão estratégica em `~/.claude/plans/system-instruction-you-are-working-lovely-goblet.md` (sessão 2026-04-18).
