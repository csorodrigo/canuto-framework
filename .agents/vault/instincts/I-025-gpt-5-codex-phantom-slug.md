---
id: I-025
title: `gpt-5-codex` e `o1-pro` são slugs fantasma na conta ChatGPT do Codex CLI
confidence: high
created: 2026-04-18
tags: [codex, models, openai, documentation-drift]
---

# I-025 — `gpt-5-codex` e `o1-pro` não existem na conta ChatGPT

## Pattern

Docs do framework Canuto citavam extensivamente `gpt-5-codex` (coder/fast profiles) e `o1-pro` (maestro/reviewer profiles) como modelos ativos. **Nenhum dos dois existe** em contas ChatGPT do Codex CLI — ambos retornam `ERROR: The 'X' model is not supported when using Codex with a ChatGPT account`.

## Evidence

**Descoberta prévia** (memory `feedback_codex_chatgpt_models.md`, projeto ifood-rafaeldashboard, 2026-04-17): incidente real onde `codex-coder` MCP falhava em 100% das invocações, forçando fallback silencioso pra Claude, porque `~/.codex/config.toml` apontava pros slugs fantasma.

**Sessão 2026-04-18:** auditoria mostrou ~26 arquivos no framework ainda citando os slugs. `~/.codex/config.toml` do usuário já tinha sido corrigido manualmente para `gpt-5.4` em todos os 5 profiles (`coder`, `reviewer`, `architect`, `fast`, `maestro`), variando apenas `model_reasoning_effort` entre `high` e `xhigh`.

## Why

Drift entre documentação e runtime real. Docs foram escritas quando assumiu-se que `gpt-5-codex` existiria; ChatGPT account whitelist é diferente da API OpenAI. Only slugs reais em `~/.codex/models_cache.json`: `gpt-5.4`, `gpt-5.3-codex`, `gpt-5.3-codex-spark`, `gpt-5.4-mini`, `gpt-5.2`, `codex-auto-review`.

## How to apply

- **Modelo canônico atual:** `gpt-5.4` em todos os profiles Codex CLI (conta ChatGPT)
- **Varia só reasoning_effort:** `high` (coder, reviewer, fast) ou `xhigh` (architect, maestro, default)
- **Escalation pattern correto:** `high` → `xhigh` (via architect profile), NÃO `gpt-5-codex` → `o1-pro`
- **Antes de assumir** que um slug OpenAI existe, verificar `~/.codex/models_cache.json` OU rodar `codex exec -m <slug> -c "hi"` uma vez
- **Preservar docs históricos** (v16, v17, v18, session notes) com nota "modelo atual: `gpt-5.4`" no topo — não reescrever corpo, só contextualizar
