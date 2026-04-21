---
skill: glm-routing
trigger: Maestro consulta antes de delegar para fallback GLM
persona: maestro
version: 1.0.0
lastUpdated: 2026-04-20
shortDescription: >
  GLM-4.6 routing cheat-sheet via Z.AI. Fallback para Codex (coder/reviewer).
usedBy: [maestro]
---

## Purpose

Cheat-sheet para o provedor GLM (GLM-4.6 via Z.AI). Atua como fallback quando
Codex atinge limite semanal ou concurrency.

---

## Provider Info

| Propriedade | Valor |
|-----------|-------|
| **Endpoint** | `https://api.z.ai/api/coding/paas/v4` (**Coding Plan**) |
| **Modelo primário** | `glm-5.1` (concurrency: 1) |
| **Modelo fallback** | `glm-4.7` (concurrency: 1, usado em saturação 429) |
| **Alternativas** | `glm-5-turbo` (concurrency: 1), `glm-4.5-air` (concurrency: 5) |
| **Context window** | 200K in / 200K out |
| **Auth** | `Authorization: Bearer $ZAI_API_KEY` |
| **Streaming** | Suportado |
| **Pricing** | Ver docs.z.ai (plano GLM Coding disponível, similar ao Codex $20/mo) |

---

## MCP Servers

| Nome | Comando | Profile | Uso |
|------|---------|--------|-----|
| `glm-coder` | `~/.claude/scripts/glm-coder.sh` | coder | Implementação (equivale a `codex-coder`) |
| `glm-reviewer` | `~/.claude/scripts/glm-reviewer.sh` | reviewer | Review (equivale a `codex-reviewer`) |

**Configuração**: Registrados em `~/.claude/settings.json` quando `ZAI_API_KEY` está presente em
`~/.config/canuto/zai.env` (chmod 600) ou como env var.

---

## Tool-Calling

GLM via Z.AI é **OpenAI-compatible**:

```json
{
  "model": "glm-4.6",
  "messages": [...],
  "tools": [...],
  "tool_choice": "auto"
}
```

- `tools` segue shape padrão OpenAI
- `tool_choice`: `"auto"` | `{"type": "function", "name": "..."}`
- `tool_calls` em resposta é idêntico ao formato OpenAI

---

## Gotchas Conhecidos

1. **Concurrency limit por modelo** — Não compartilhado. Se `glm-4.6` usar 3/3 slots,
   o reviewer usa `glm-4.5` (concurrency 10) automaticamente.

2. **HTTP 429** — Wrapper tenta fallback para `glm-4.5` uma vez antes de falhar.
   Logado em `~/.claude/logs/glm-fallback.log`.

3. **Formato de prompt** — GLM é compatível com OpenAI, mas pode ter comportamento
   ligeiramente diferente em edge cases (ex: instruções entre aspas triplas).

4. **Reasoning opcional** — GLM-Zero disponível mas não usado por padrão para manter
   consistência com Codex.

5. **Credencial** — `ZAI_API_KEY` deve estar em `~/.config/canuto/zai.env` com chmod 600.
   Nunca commitar esse arquivo.

---

## Quando Usar GLM

**SIM:**
- Codex atingiu limite semanal (429 com "weekly limit")
- Codex está em timeout consecutivo (2+ vezes)
- `CODEX_ONLY` não está setado (respeita opt-out)

**NÃO:**
- Security gate (triple review continua Codex + Gemini + Opus)
- Sensitive operations sem fallback explícito do usuário
- Quando usuário seta `CODEX_ONLY=1`

---

## Matriz de Uso

| Task Type | Primary | Fallback | Nunca |
|-----------|---------|-----------|-------|
| Code generation | codex-coder → glm-coder → claude | — | Não usar para security gate |
| Code review | codex-reviewer → glm-reviewer → gemini → claude | — | Não substituir triple review |
| Test-fix loop | codex-coder → glm-coder → claude | — | — |
| Context digest | gemini → codex → claude | — | GLM não otimizado para isso |
| Bulk classify | gemini-flash → claude | — | GLM não otimizado para volume |

---

## Health Check

```bash
bash ~/.claude/scripts/glm-health-check.sh
```

Retorna:
- endpoint: `https://api.z.ai/api/paas/v4/chat/completions`
- modelo: `glm-4.6`
- status code: HTTP code
- latency: ms
- resposta: preview da response

Exit 0 se OK, 1 se falha.

---

## Logs

- Fallbacks: `~/.claude/logs/glm-fallback.log`
  ```
  timestamp origin=glm-4.6 destination=glm-4.5 reason=http_429_concurrency_limit
  ```

---

## Ver Instalação

```bash
# Verificar MCPs registrados
claude mcp list | grep glm

# Verificar wrappers instalados
ls -la ~/.claude/scripts/glm-*.sh

# Health check
bash ~/.claude/scripts/glm-health-check.sh
```
