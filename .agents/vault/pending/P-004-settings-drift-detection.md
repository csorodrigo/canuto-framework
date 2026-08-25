---
type: pending
id: P-004
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
  - drift
  - configuration
---

# Drift detection de `~/.claude/settings.json`

**Pattern:** Hook que tira snapshot diário de `~/.claude/settings.json` + `.mcp.json` em `.agents/vault/audit/config-snapshots/YYYY-MM-DD.json`. Skill `/config-drift` mostra diff dos últimos N dias.

**Por que vale:**
- Configuração drifta silenciosamente: hooks adicionados, MCPs renomeados, permissions mudadas
- Quando algo quebra, é difícil saber "o que mudou desde quando funcionava"
- Vault já tem `audit/` — local natural para snapshots

**Implementação:**
1. Novo hook `daily-config-snapshot.sh` rodando 1x/dia (cron ou primeira sessão do dia)
2. Skill `/config-drift [days]` que mostra diff entre snapshot atual e N dias atrás
3. Alerta visual quando drift inclui mudanças em `permissions.allow`, `hooks.*` ou `mcpServers.*`

**Estimativa:** XS. ~50 linhas bash + skill markdown.

**Cuidado:** `settings.json` pode conter tokens/secrets. Snapshot DEVE rodar `jq 'del(..|.token?, ..|.apiKey?, ..|.password?)'` antes de salvar.

**Integra com:** `P-003` (dead-weight detector) — drift de MCP é sinal de candidato a dead weight.

**Source:** decisão estratégica em `~/.claude/plans/system-instruction-you-are-working-lovely-goblet.md` (sessão 2026-04-18).
