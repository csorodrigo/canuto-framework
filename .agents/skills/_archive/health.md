---
skill: health
trigger: "/health, or when the user asks if providers/MCPs are working"
persona: maestro
version: 2.0.0
lastUpdated: 2026-04-29
shortDescription: >
  Unified health check across providers (Claude, Codex CLI) and MCP servers.
  Aggregates fragmented checks into a single verdict + 0-10 score. Different
  from /context-health which scores active context quality.
usedBy: [maestro]
evals:
  - prompt: "/health"
    should_trigger: true
  - prompt: "check all providers"
    should_trigger: true
  - prompt: "is codex working?"
    should_trigger: true
  - prompt: "are the mcps connected?"
    should_trigger: true
  - prompt: "how much have we spent"
    should_trigger: false
---

## Purpose

Verifica em 1 comando se **providers e MCPs do Canuto estão operacionais**.
Hoje a verificação é fragmentada (`codex-health-check.sh`, `claude mcp list`)
— esta skill unifica e produz um veredito único.

**Distinção crítica:** `/health` mede **infra** (provider está acessível?).
`/context-health` mede **qualidade do contexto da sessão atual** (cache, drift, repetição).
Skills complementares — não confundir.

---

## When to Use

**Triggers:**
- Usuário escreve `/health`, `/check-all`, `/mounted`, `/status`
- Usuário pergunta "tá tudo conectado?", "is X working?", "provider health"
- Antes de iniciar tasks M/L que dependem de Codex
- Após `claude mcp list` mostrar algum servidor com erro
- Em sessão nova num workspace que não foi tocado em > 1 semana

**Not for:**
- Qualidade do contexto da sessão atual → `/context-health`
- Custo / consumo de tokens → `smart-token-metering`
- Diagnóstico profundo de Codex isolado → `bash .agents/tools/codex-health-check.sh --full`

---

## The 5 health signals

| Signal | What it checks | Healthy | Degraded | Source |
|---|---|---|---|---|
| **Claude session** | Você está respondendo (tautológico — sempre PASS quando este skill roda) | running | n/a | the fact `/health` returned |
| **Codex CLI** | `codex --version` retorna OK + auth válida + canonical model está nos profiles | version + profiles em `gpt-5.5` | versão antiga, auth quebrada, ou drift de modelo | `codex --version`, `codex exec --profile coder ... 'Reply OK'` |
| **Codex profiles** | `~/.codex/config.toml` tem 5 profiles (coder/reviewer/architect/fast/maestro) com modelo canônico | 5 profiles, todos canonical | profiles missing ou drift de model | `bash .agents/tools/codex-health-check.sh --smoke` |
| **Outros MCPs do projeto** | Cada server em `.mcp.json` (project) e `~/.claude/settings.json` (user) está ✓ Connected | todos verdes | algum em erro | `claude mcp list` (cobertura completa) |
| **Smoke check estrutural** | Skills, hooks e refs estão no lugar | PASS | FAIL ou WARN | `bash .agents/tools/codex-health-check.sh --smoke` |

Sinais ausentes (script não está no projeto, MCP não está configurado neste setup) → marcar `unknown`, não inventar.

---

## Composite Score

Cada sinal vale 0-10. Score composto:

```text
health_score =
  claude_session_score      * 0.05  +   # tautológico, peso baixo
  codex_cli_score           * 0.30  +
  codex_profiles_score      * 0.20  +
  other_mcps_score          * 0.20  +
  smoke_check_score         * 0.25
```

Scoring rules:
- Codex CLI: `10` se version OK + smoke `OK` retorna; `5` se version OK mas smoke falha; `0` se CLI não está no PATH
- Profiles: `10` se 5 profiles com canonical model; `7` se 5 profiles mas algum drifted (ex: gpt-5.4); `0` se profiles missing
- Smoke check: `10` se PASS; `7` se WARN; `0` se FAIL
- Other MCPs: % conectados × 10 (ex: 4/5 conectados = 8/10)

Status:
- `healthy` >= 8.0
- `watch` 5.0-7.9
- `degraded` < 5.0

---

## Procedure

1. **Collect raw data** (todos em paralelo quando possível):
   ```bash
   claude mcp list 2>&1                                    # lista todos os MCPs registrados
   codex --version 2>&1                                    # CLI version
   bash .agents/tools/codex-health-check.sh --smoke 2>&1 || true
   ```
2. **Ping ativo** (custa 1 call, opcional via `--deep`):
   ```bash
   echo 'Reply with: OK' | codex exec --color never --profile coder \
     --skip-git-repo-check -s read-only \
     -o /tmp/codex-health-ping.md - >/dev/null 2>&1
   cat /tmp/codex-health-ping.md  # esperado: "OK"
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
| Codex CLI | OK + ping | 10 | gpt-5.5 reply OK |
| Codex profiles | 5/5 canonical | 10 | gpt-5.5 across all profiles |
| Other MCPs (4/5) | partial | 8 | repomix not responding |
| Smoke check | PASS | 10 | structural OK |

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
1. Roda claude mcp list, codex --version, codex-health-check em paralelo
2. Cada sinal recebe score
3. Output:
[Health] Score: 9.2/10 (healthy). Failing: none.
Salvou: .agents/vault/metrics/health-2026-04-29.md
```

### ✅ Good — flag de degradação concreta

```
Usuário: /health

Maestro:
[Health] Score: 6.5/10 (watch). Failing: profiles drifted (coder/reviewer ainda em gpt-5.4 — re-rode `bash install.sh --doctor`).
```

### ❌ Bad — confundir com /context-health

```
Usuário: meu contexto tá saturado, dá uma olhada

Maestro: NÃO chamar /health. O sinal é qualidade de contexto, não infra.
Skill correta: /context-health.
```

### ❌ Bad — inventar valores quando script não existe

```
Maestro (errado): "Smoke check: PASS"
                  (mas .agents/tools/codex-health-check.sh não roda — codex não está no PATH)

Correto: "Codex CLI: unknown — `codex --version` falhou.
          Score 0. Reinstale com `bash install.sh --doctor` ou `npm install -g @openai/codex`."
```

---

## Integration

- **codex-health-check.sh** (em `.agents/tools/`) — fonte de verdade pro lado Codex
- **context-health.md** — skill irmã que mede qualidade de contexto (não infra)
- **smart-token-metering.md** — mede consumo, este mede disponibilidade
- **.agents/config/models.yaml** — canonical model that profiles should be on
