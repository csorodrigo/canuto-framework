---
type: pending
id: P-001
status: pending
priority: medium
owner: maestro
provider: ""
created-session: "2026-04-18"
source: "rtk/caveman/token-optimizer evaluation"
inspired-by: "alexgreensh/token-optimizer (clean-room — no code reuse)"
license-note: "upstream is PolyForm Noncommercial — implementation must be original"
rework-count: 0
retry-count: 0
tags:
  - pending
  - skill-idea
  - context-health
  - metrics
---

# Quality-score 7-signal por sessão

**Pattern:** Skill nova `/context-health` que pontua o estado do contexto da sessão atual em 7 sinais (0-10 cada, score composto). Complementa `smart-token-metering` (que mede consumo) sem duplicar.

**7 sinais propostos** (a definir/refinar na implementação):
1. **Cache hit rate** — % de input tokens vindos de cache
2. **Skill activation density** — skills carregadas / skills realmente invocadas
3. **MEMORY.md drift** — entradas órfãs ou pós linha 200 (invisíveis)
4. **MCP server health** — % de servidores MCP que efetivamente firaram nesta sessão
5. **Compaction proximity** — distância até próximo trigger de compaction
6. **Subagent cost share** — % do gasto da sessão consumido por subagents
7. **Repetition index** — turnos com prompts similares (loops detectados)

**Output:** badge inline + relatório markdown salvo em `vault/metrics/`. Score < 5 dispara warning.

**Por que vale:** o vault já tem `metrics/` mas só registra consumo, não qualidade. Score expõe degradação antes do usuário notar.

**Implementação:** delegar a Codex (M-size). Saída esperada: `.agents/skills/context-health.md` no formato padrão (frontmatter + When to Use + Examples).

**Source:** decisão estratégica em `~/.claude/plans/system-instruction-you-are-working-lovely-goblet.md` (sessão 2026-04-18).
