---
shortDescription: Append-only event log per project — written by hooks, source of truth for session events; vault notes are projections
version: 1.0.0
---

# Event Log

## Purpose

O event log é a **fonte de verdade mecânica** dos eventos de sessão do Canuto.
Um arquivo JSONL append-only por projeto, escrito **pelos hooks** — nunca
dependente de o agente escolher registrar.

Absorvido do edge-of-chaos (ver `docs/adr/0001-event-log-fonte-de-verdade.md`):
a auditoria de 200 sessões provou que registro por prosa não acontece
(audit-trail teve adesão quase nula). A resposta não é mais prosa — é escrita
mecânica no lifecycle de hooks, com as notas do vault rebaixadas a **projeções**.

## Where

Resolução (via `.agents/tools/event-log.sh`, que usa `canuto-memory.sh`):

1. Vault global: `~/.canuto/vault/projects/<slug>/events/log.jsonl`
2. Vault local: `.agents/vault/events/log.jsonl`
3. Fallback offline: `.agents/.cache/events/log.jsonl` (migre com `/vault-sync`)

## Schema

Uma linha = um evento JSON. Campos base (sempre presentes):

```json
{"ts":"2026-07-26T21:40:53Z","event":"SESSION_END","project":"meu-app","session":"<id>", ...}
```

Tipos de evento e quem escreve:

| Event | Escritor | Payload típico |
|---|---|---|
| `SESSION_START` | hook session-start | branch, health, stale |
| `SESSION_END` | hook session-save (Stop) | backend |
| `PRE_COMPACT` | hook pre-compact-save | backend |
| `TOOL_CALL` | hook posttooluse-universal | tool, outcome, duration_ms, file, cmd |
| `DELEGATION` | hook postdelegate-verify | provider, rc, out_file, verdict |
| `GATE` | hooks de gate (PR, branch) | gate, verdict, reason |
| `CLOSEOUT` | Maestro (CLI, session end) | summary |
| `HANDOFF` | Maestro (CLI, opcional) | from, to, task |
| `REWORK` | Maestro (CLI, quando detectado) | file, count |
| `HEARTBEAT` | heartbeat-run.sh | task, verdict |
| `INSTINCT_ARCHIVED` | instinct-aging.sh | id, reason |

Novos tipos são permitidos (schema aberto); mantenha nomes UPPER_SNAKE.

## Writing (agente)

Hooks escrevem sozinhos. O agente só precisa escrever eventos **semânticos**
que hooks não conseguem inferir:

```bash
bash .agents/tools/event-log.sh append CLOSEOUT actor=maestro summary="3 goals, 1 pending"
bash .agents/tools/event-log.sh append HANDOFF actor=maestro from=maestro to=coder task="auth-flow"
```

Regra: **o gate de session-end verifica CLOSEOUT mecanicamente** — sem o
evento, o hook Stop avisa com evidência. Registrar o CLOSEOUT é parte do
procedimento de `canuto-session-end-learning`, não opcional.

## Reading

```bash
bash .agents/tools/event-log.sh tail 50          # últimos eventos
bash .agents/tools/event-log.sh path             # onde está o log
jq -r 'select(.event=="DELEGATION") | [.ts,.rc,.verdict] | @tsv' <log>
```

O pipeline `framework-session-audit` e o `canuto-project-doctor` devem preferir
o event log a heurísticas de transcript quando ele existir.

## Invariants

- **Append-only.** Nunca edite ou apague linhas. Correção = novo evento.
- **Hooks nunca morrem por telemetria.** Toda escrita degrada em silêncio.
- **Vault é projeção.** Notas de audit/sessão podem ser gerados a partir do
  log; o inverso nunca.
- **Volume:** `TOOL_CALL` registra só tools que mudam estado (Bash, Edit,
  Write, Task, mcp__*) por default. `CANUTO_EVENT_LOG_TOOLS=all|core|off`
  ajusta por sessão.

## Anti-Patterns — DO NOT

- ❌ Escrever nota de audit sem o evento correspondente no log
- ❌ Reordenar, deduplicar ou "limpar" o log (aging/arquivamento é por projeção)
- ❌ Fazer o hook falhar (exit ≠ 0) por erro de escrita do log
- ❌ Registrar payloads gigantes (comandos são truncados a 120 chars por design)
