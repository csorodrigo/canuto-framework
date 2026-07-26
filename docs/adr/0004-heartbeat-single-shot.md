# ADR-0004 — Heartbeat é single-shot com post-gate; agir no mundo é vetado

Data: 2026-07-26 · Status: aceito

## Contexto

A skill `heartbeat` era declaradamente aspiracional ("await tooling
support") — o Canuto não tinha autonomia nenhuma. O edge-of-chaos prova que
o loop autônomo mínimo é pequeno (ADR-0003 dele): timer → invocação
single-shot do CLI → verificação mecânica → log. O envelope de retry de
~1400 linhas do sistema anterior deles foi deletado de propósito.

## Opções consideradas

1. **Orquestrador residente/daemon** — rejeitada: infra pesada, contra o
   perfil do Canuto (zero-infra, session-based).
2. **Retry/backoff no runner** — rejeitada: o próximo tick do cron É o
   retry; estado de relançamento é complexidade sem evidência de need.
3. **Runner single-shot + post-gate + evento** — aceita.

## Decisão

- `heartbeat-run.sh <task>`: task = arquivo markdown com frontmatter
  (timeout, cli, permission_mode, expect_output) + prompt standalone.
  Execução foreground, `claude -p` ou `codex exec`, sem retry.
- Post-gate mecânico: rc + `expect_output` existente, não-vazio e
  **modificado nesta execução** (mtime ≥ início). Exit 0 não prova entrega.
- Todo run gera evento HEARTBEAT com veredito.
- Agendamento (cron/launchd) é **opt-in explícito** — o install.sh nunca
  agenda nada.
- **Teto de autonomia** (CONTRACT, absorvido do C1 do edge): heartbeat lê,
  absorve e entrega conhecimento para ler. Push, PR, deploy, instalação e
  escrita fora do vault/cache são vetados; agir no mundo exige aprovação
  numa sessão interativa.

## Consequências

- (+) Autonomia real com ~250 linhas de bash e zero infra nova.
- (+) Cadência é o único dial de custo (um beat é sempre a task completa).
- (−) `claude -p` com `permission_mode: acceptEdits` limita o que a task
  pode fazer via Bash — deliberado; escalar permissão é decisão por task,
  documentada no arquivo da task.
