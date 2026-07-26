shortDescription: Scheduled autonomous activation — single-shot runner with mechanical post-gate (real since v1.7).
usedBy: [maestro]
version: 2.0.0
lastUpdated: 2026-07-26
copyright: Rodrigo Canuto © 2026.
inspiration: edge-of-chaos heartbeat (ADR-0003 de lá) — single-shot sem envelope, post-gate que confere o artefato; ver docs/adr/0004-heartbeat-single-shot.md.

## When to Use

**Triggers:**
- Manutenção periódica sem humano presente (triagem de pendings, aging de instincts, digest semanal)
- Monitoramento agendado (auditoria de sessões, saúde do framework)
- User asks: `"set up a heartbeat"`, `"schedule a check"`, `"periodic review"`

**Not for:**
- Sessões interativas normais (Canuto é session-based por default)
- Tarefas one-off (roteamento normal do Maestro)
- Qualquer ação com efeito no mundo (push, PR, deploy) — CONTRACT abaixo

---

## How It Works (implementado — não é mais "future")

```
cron/launchd → heartbeat-run.sh <task> → CLI single-shot (claude -p | codex exec)
             → post-gate mecânico (rc + expect_output tocado nesta execução)
             → evento HEARTBEAT no event log → fim
```

Princípios (absorvidos do edge-of-chaos):
- **Single-shot, sem retry, sem envelope.** Falhou → registrado no log; o
  próximo tick tenta de novo. Complexidade de relançamento não existe.
- **Exit 0 não prova nada.** O post-gate verifica que o artefato esperado
  (`expect_output`) existe, não está vazio e foi modificado nesta execução.
- **Foreground only.** Em modo headless o processo morre no fim do turno —
  nada roda em background (lei do turno).
- **Cadência é o único dial de custo.** Um heartbeat roda sempre a task
  completa; para gastar menos, rode menos vezes.

## Defining Tasks

Um arquivo por task em `.agents/heartbeats/<name>.md`:

```markdown
---
timeout: 900                 # segundos (default 600)
cli: claude                  # claude | codex
permission_mode: acceptEdits # para claude -p
expect_output: .agents/vault/digests/heartbeat-<name>.md
---
<prompt completo e standalone — a sessão nasce do zero, sem contexto>
```

Escreva o prompt como instrução completa: a sessão heartbeat não tem
histórico. Tasks prontas incluídas:

- `.agents/heartbeats/weekly-maintenance.md` — triagem de pendings + aging
  de instincts + digest semanal (agende semanal, ex.: segunda 9h)
- `.agents/heartbeats/usage-audit.md` — auditoria de uso real do framework
  (pipeline forense + delegate-metrics + event logs; agende mensal)

## Running & Scheduling

```bash
bash .agents/tools/heartbeat-run.sh --list
bash .agents/tools/heartbeat-run.sh --dry-run weekly-maintenance
bash .agents/tools/heartbeat-run.sh weekly-maintenance          # roda agora

# agendar (SEMPRE opt-in explícito — gate de governança):
bash .agents/tools/heartbeat-run.sh --install-cron "0 9 * * 1" weekly-maintenance   # Linux
bash .agents/tools/heartbeat-run.sh --install-launchd 604800 weekly-maintenance     # macOS
bash .agents/tools/heartbeat-run.sh --uninstall weekly-maintenance
```

Logs por task em `.agents/.cache/heartbeat-<task>.log`; veredito de cada
execução no event log (`bash .agents/tools/event-log.sh tail 20`).

## CONTRACT — teto de autonomia

Absorvido do edge-of-chaos (C1): o heartbeat **lê, absorve e entrega
conhecimento para ler**. Ele NÃO age no mundo:

- ❌ git push, PR, deploy, instalação de dependências
- ❌ escrita fora do vault do projeto e de `.agents/.cache/`
- ❌ mudar configuração do framework ou do usuário
- ✅ ler código/log/vault, triagem, digest, proposta de ação para a
  próxima sessão humana

Agir no mundo exige aprovação explícita numa sessão interativa — nunca uma
decisão autônoma de heartbeat.

## Anti-Patterns — DO NOT

- ❌ Instalar agendamento sem o usuário pedir (o install.sh nunca agenda)
- ❌ Retry/backoff dentro do runner (o próximo tick é o retry)
- ❌ Task sem `expect_output` fazendo trabalho que produz artefato (post-gate cego)
- ❌ Prompt que assume contexto de sessão anterior (heartbeat nasce do zero)
- ❌ `permission_mode: bypassPermissions` sem necessidade concreta documentada na task
