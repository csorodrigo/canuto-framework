---
skill: health
trigger: "/health, or when the user asks if providers/MCPs are working"
persona: maestro
version: 1.0.0
lastUpdated: 2026-04-18
shortDescription: >
  Unified health check across all providers (Claude, Codex coder/reviewer,
  Gemini) and MCP servers. Aggregates fragmented checks into a single
  verdict + 0-10 score. Different from /context-health which scores active
  context quality.
usedBy: [maestro]
evals:
  - prompt: "/health"
    should_trigger: true
  - prompt: "check all providers"
    should_trigger: true
  - prompt: "is gemini working?"
    should_trigger: true
  - prompt: "are the mcps connected?"
    should_trigger: true
  - prompt: "how much have we spent"
    should_trigger: false
---

## Purpose

Verifica em 1 comando se **todos os providers e MCPs do Canuto estão operacionais**.
Hoje a verificação é fragmentada (`codex-health-check.sh`, `gemini-smoke-check.sh`,
`claude mcp list`) — esta skill unifica e produz um veredito único.

**Distinção crítica:** `/health` mede **infra** (provider está acessível?).
`/context-health` mede **qualidade do contexto da sessão atual** (cache, drift, repetição).
Skills complementares — não confundir.

---

## When to Use

**Triggers:**
- Usuário escreve `/health`, `/check-all`, `/mounted`, `/status`
- Usuário pergunta "tá tudo conectado?", "is X working?", "provider health"
- Antes de iniciar tasks M/L que dependem de Codex ou Gemini
- Após `claude mcp list` mostrar algum servidor com erro
- Em sessão nova num workspace que não foi tocado em > 1 semana

**Not for:**
- Qualidade do contexto da sessão atual → `/context-health`
- Custo / consumo de tokens → `smart-token-metering`
- Diagnóstico profundo de Codex isolado → `bash .agents/tools/codex-health-check.sh --full`
- Diagnóstico profundo de Gemini isolado → `bash .agents/tools/gemini-smoke-check.sh`

---

## The 6 health signals

| Signal | What it checks | Healthy | Degraded | Source |
|---|---|---|---|---|
| **Claude session** | Você está respondendo (tautológico — sempre PASS quando este skill roda) | running | n/a | the fact `/health` returned |
| **codex-coder MCP** | `mcp__codex-coder__spawn_agent` registrado e o handshake funciona | ✓ Connected | erro de conexão ou ausente | `claude mcp list \| grep "codex-coder "` |
| **codex-reviewer MCP** | `mcp__codex-reviewer__spawn_agent` registrado e funciona | ✓ Connected | erro ou ausente | `claude mcp list \| grep "codex-reviewer "` |
| **Gemini MCP** | `mcp__gemini__*` registrado, ping responde | ✓ Connected + ping echo | erro de OAuth, quota, ou ausente | `claude mcp list \| grep "gemini "` + `mcp__gemini__ping` |
| **Outros MCPs do projeto** | Cada server em `.mcp.json` (project) e `~/.claude/settings.json` (user) está ✓ Connected | todos verdes | algum em erro | `claude mcp list` (cobertura completa) |
| **Smoke check estrutural** | Skills, hooks e refs estão no lugar (Codex + Gemini) | ambos PASS | 1 ou 2 FAIL | `bash .agents/tools/codex-health-check.sh --smoke` + `bash .agents/tools/gemini-smoke-check.sh` |

Sinais ausentes (script não está no projeto, MCP não está configurado neste setup) → marcar `unknown`, não inventar.

---

## Composite Score

Cada sinal vale 0-10. Score composto:

```text
health_score =
  claude_session_score      * 0.05  +   # tautológico, peso baixo
  codex_coder_score         * 0.20  +
  codex_reviewer_score      * 0.20  +
  gemini_mcp_score          * 0.20  +
  other_mcps_score          * 0.15  +
  smoke_check_score         * 0.20
```

Scoring rules:
- Cada MCP: `10` se ✓ Connected, `0` se erro/ausente, `5` se ausente mas opcional (ex: gemini sem OAuth configurado vale 5 — degradado mas esperado)
- Smoke check: `10` se ambos PASS, `7` se 1 FAIL, `0` se 2 FAIL
- Other MCPs: % conectados × 10 (ex: 4/5 conectados = 8/10)

Status:
- `healthy` >= 8.0
- `watch` 5.0-7.9
- `degraded` < 5.0

---

## Procedure

1. **Collect raw data** (todos em paralelo quando possível):
   ```bash
   claude mcp list 2>&1                           # lista todos os MCPs registrados
   bash .agents/tools/codex-health-check.sh --smoke 2>&1 || true
   bash .agents/tools/gemini-smoke-check.sh 2>&1 || true   # (se existir)
   ```
2. **Ping ativo** (custa 1 call cada, opcional via `--deep`):
   ```
   mcp__gemini__ping({ prompt: "health" })        # gemini live
   ```
3. **Score cada sinal** per regras acima.
4. **Compose** weighted score.
5. **Render** o relatório no formato abaixo.
6. **Salvar** em `.agents/vault/metrics/health-YYYY-MM-DD.md`.

---

## Output format

### Inline badge (sempre)

```
[Health] Score: N.N/10 (healthy|watch|degraded). Failing: <signal-list ou "none">.
```

### Markdown report (salvar em vault)

```markdown
---
type: metric
metric: provider-health
date: YYYY-MM-DD
score: N.N
status: healthy|watch|degraded
tags: [metrics, health]
---

# Provider Health — YYYY-MM-DD

**Score:** N.N/10
**Status:** healthy|watch|degraded
**Recommendation:** uma frase.

| Signal | Status | Score | Note |
|---|---|---|---|
| Claude session | running | 10 | (tautológico) |
| codex-coder MCP | ✓ Connected | 10 | handshake OK |
| codex-reviewer MCP | ✓ Connected | 10 | handshake OK |
| Gemini MCP | ✓ Connected + ping echo | 10 | OAuth ativo |
| Other MCPs (4/5) | partial | 8 | repomix not responding |
| Smoke check | both PASS | 10 | structural OK |

## Unknowns
(quando algum sinal foi neutro-5 por dado faltando)

## Failing signals
(quando score < 8)

## Next actions
1. ...
```

---

## Examples

### ✅ Good — quick health snapshot

```
Usuário: /health

Maestro:
1. Roda claude mcp list, codex-health-check, gemini-smoke-check em paralelo
2. Cada MCP recebe score
3. Output:
[Health] Score: 9.2/10 (healthy). Failing: none.
Salvou: .agents/vault/metrics/health-2026-04-18.md
```

### ✅ Good — flag de degradação concreta

```
Usuário: /health

Maestro:
[Health] Score: 6.5/10 (watch). Failing: gemini MCP (OAuth expirou — re-auth com `gemini auth login`).
```

### ❌ Bad — confundir com /context-health

```
Usuário: meu contexto tá saturado, dá uma olhada

Maestro: NÃO chamar /health. O sinal é qualidade de contexto, não infra.
Skill correta: /context-health.
```

### ❌ Bad — inventar valores quando script não existe

```
Maestro (errado): "Smoke check Gemini: PASS"
                  (mas .agents/tools/gemini-smoke-check.sh não está em main)

Correto: "Smoke check Gemini: unknown — gemini-smoke-check.sh ausente do repo.
          Score neutro 5. Adicione o script para cobertura completa."
```

---

## Integration

- **codex-health-check.sh** (em `.agents/tools/`) — fonte de verdade pro lado Codex
- **gemini-smoke-check.sh** (em `.agents/tools/`) — fonte de verdade pro lado Gemini (verificar se já está em main antes de assumir disponível)
- **gemini-routing.md** — gotchas que afetam scoring (ex: gemini-2.5-pro banido conta como degraded se aparecer roteado)
- **context-health.md** — skill irmã que mede qualidade de contexto (não infra)
- **smart-token-metering.md** — mede consumo, este mede disponibilidade
