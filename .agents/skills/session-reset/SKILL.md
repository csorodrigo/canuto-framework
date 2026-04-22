---
name: session-reset
description: "Checkpoint/compactação para sessões longas que misturaram auditoria, execução e subagents. Extrai decisões, arquivos tocados, comandos rodados, riscos abertos e próximos testes em um bloco conciso para retomar a sessão sem reler tudo."
skill: session-reset
trigger: /session-reset
persona: maestro
version: 1.0.0
lastUpdated: 2026-04-21
usedBy: [maestro, architect, debugger]
evals:
  - prompt: "o contexto tá pesado demais, compacta pra gente continuar"
    should_trigger: true
  - prompt: "a sessão tá longa, rode um session-reset"
    should_trigger: true
  - prompt: "reinicie a conversa do zero"
    should_trigger: false
  - prompt: "quais skills estão disponíveis?"
    should_trigger: false
---

## Purpose

Prevent `context_bloat_reset` — o cluster de erro mais frequente em 125 das 250 sessões auditadas do florence. Sessões longas misturam auditoria, execução e subagents sem checkpoint estável; quando bate contra a janela de contexto, o agente perde o fio.

Esta skill gera um **bloco de retomada** deterministic que pode ser colado numa nova sessão (ou após `/compact`) para que o trabalho continue sem regredir.

## When to Run

Acione quando qualquer um destes for verdade:

- Usuário pede explicitamente ("compacta", "session reset", "faz um resumo pra eu continuar amanhã").
- Sessão ultrapassou 3 subagents aninhados OU 50+ tool calls.
- Hook `pre-finalize.sh` avisou `validation-pending` em >3 arquivos e o usuário quer parar.
- `canuto-rework-detector` sinalizou `context-bloat` ou `stale-context`.
- Métrica `context_reset_need_rate > 0.5` na última auditoria.

Não acione para começar do zero — use `/briefing` ou abrir nova sessão.

## Procedure

1. **Rastreie decisões** tomadas na sessão:
   - O quê ficou decidido, quem decidiu (usuário/maestro/codex), arquivo:linha impactado.
2. **Inventário de arquivos tocados**:
   - `git status --short` + lista dos paths do transcript com ≥1 Edit/Write.
3. **Comandos executados** que importam para retomada:
   - Testes que rodaram e resultado. Deploys. Installs. Migrations.
4. **Riscos abertos**:
   - Testes falhando, validations pendentes (`validation-pending.json`), rework-counters altos.
5. **Próximos passos concretos** (3-5 itens, acionáveis, não aspiracionais):
   - Cada item = um comando OU um arquivo específico para abrir.
6. **Emita o bloco** no formato abaixo e registre em `.agents/vault/sessions/$(date +%Y-%m-%d)-reset.md` se o vault estiver disponível.

## Output Format

```markdown
## Session Reset — <YYYY-MM-DD HH:MM>

### Onde paramos
<1-2 frases: qual tarefa estava em andamento, em que etapa>

### Decisões tomadas nesta sessão
- <decisão> (file:linha ou contexto)
- <decisão>

### Arquivos tocados
- <path> — <o que mudou>
- <path> — <o que mudou>

### Comandos relevantes rodados
- `<cmd>` → <resultado>
- `<cmd>` → <resultado>

### Riscos e pendências
- <risco> (file:linha se aplicável)
- <validação pendente em>

### Próximos passos (acionáveis)
1. <comando ou arquivo específico>
2. <comando ou arquivo específico>
3. <comando ou arquivo específico>

### Para retomar
Cole este bloco no início da próxima sessão + rode `/briefing`.
```

## Guardrails

- **Não liste tudo.** Filtre por relevância — decisões arquiteturais ficam, debug de sintaxe não.
- **Não crie novas decisões aqui.** Apenas registra as já tomadas. Se precisa decidir algo, escale para Maestro antes.
- **Arquivos tocados ≠ arquivos lidos.** Só conta se teve Edit/Write, não se teve Read.
- **Comandos relevantes ≠ todos os comandos.** Filtra ls/cat/grep exploratórios.
- **Próximos passos acionáveis.** "Revisar arquitetura" não é passo — "abrir file.ts:linha e trocar X por Y" é.

## Examples

### ✅ Good
```
## Session Reset — 2026-04-21 22:00

### Onde paramos
Integrando OTel no framework. Fase 1 (SigNoz + env) completa; Fase 2 (hooks + Mac) em andamento.

### Decisões tomadas
- OTLP via fetch nativo, zero deps (framework-session-audit-lib.js:~L50)
- Meta-regras em ~/.claude/CLAUDE.md global, não por projeto

### Arquivos tocados
- .agents/tools/observability-smoke.sh — criado, 9 probes
- .agents/mcp/setup.md — +4 seções (Observability, Secrets, Vault Git, Rollback)

### Riscos e pendências
- validation-pending em framework-session-audit.test.js
- retry-counter[hammerspoon.lua]=1

### Próximos passos
1. node --test .agents/tools/framework-session-audit.test.js
2. abrir ~/.hammerspoon/init.lua e adicionar Hyper+V Obsidian
3. rodar bash install.sh --doctor --json
```

### ❌ Bad
```
## Session Reset

Trabalhamos bastante hoje, rodamos vários comandos, editamos vários arquivos.
Próximo passo: continuar.
```
(vago, não acionável, não filtra, sem file:linha)

## Related
- `canuto-rework-detector` (detecta quando acionar)
- `canuto-session-end-learning` (complementa no fim da sessão)
- `/briefing` (carrega o bloco de retomada na próxima sessão)
