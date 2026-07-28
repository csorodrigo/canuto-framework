# Canuto Framework v1.6

Personal multi-agent framework for AI-assisted development. Claude-first by default, Codex-maestro when you are talking directly to Codex. Obsidian-native memory.

This release keeps the v1.6 Obsidian-native runtime and adds a sharper learning-loop layer: project diagnosis, rework detection, session-end learning, pending triage, and safe vault write-back preview.

## O que mudou em 2026-07 (absorção edge-of-chaos)

Camada mecânica nova — contratos que sobrevivem porque são código, não prosa:

- **Event log append-only** por projeto (`<vault>/events/log.jsonl`) escrito pelos hooks — fonte de verdade dos eventos de sessão. Notas de auditoria derivam dele, nunca o contrário. ([ADR-0001](docs/adr/0001-event-log-fonte-de-verdade.md))
- **Gates fail-closed nas costuras**: `gh pr create` roda os testes antes (bypass `CANUTO_SKIP_PR_GATE=1` existe, mas é registrado); toda delegação Codex é verificada pós-execução (artefato existe? não-vazio? recente?); o fim de sessão cobra CLOSEOUT com evidência. ([ADR-0002](docs/adr/0002-gates-fail-closed-nas-costuras.md))
- **Heartbeats single-shot**: tarefas agendadas (`.agents/heartbeats/*.md`) rodam via cron/launchd com post-gate mecânico — sem retry envelope, o próximo tick É o retry. ([ADR-0004](docs/adr/0004-heartbeat-single-shot.md))
- **Memória em dois tiers**: tier hipótese grava sozinho (session notes, metrics, instinct candidates `confidence: low`); tier curado exige aprovação humana (promoções, decisions). Instincts frios (low, >30d sem uso) são arquivados automaticamente — nunca deletados. ([ADR-0005](docs/adr/0005-memoria-em-dois-tiers.md))
- **Revisor cego** (`.claude/agents/blind-reviewer.md`): segunda opinião com muro mecânico — só Read/Grep/Glob, sem contexto da sessão. Devolve strikes, nunca reescrita. ([ADR-0006](docs/adr/0006-revisor-cego-muro-mecanico.md))
- **Cegueira de identidade**: o repositório do framework não carrega slug/paths de nenhuma máquina específica; um grep-gate no `test-framework.sh` falha o build se literais de identidade vazarem. ([ADR-0003](docs/adr/0003-cegueira-de-identidade-no-genotipo.md))

Decisões completas (com alternativas rejeitadas e porquê): [`docs/adr/`](docs/adr/).

## Documentation

- [`SUMMARY.md`](SUMMARY.md): short operational summary of the framework, learning loop, and skill activation model.
- [`TUTORIAL.md`](TUTORIAL.md): step-by-step usage, update, session, and rollout guide.
- [`registry.md`](registry.md): core, optional, and global skill registry.

## Structure

```
.agents/
  personas/
    maestro.md          — Orchestrator. Manages session lifecycle and delegates.
    architect.md        — Planner. Turns ideas into structured, executable plans.
    coder.md            — Implementer. Writes code + tests following the Architect's plan.
    reviewer.md         — Quality gate. Reviews code + generates PR descriptions.
    contextualizer.md   — Knowledge engine. Scans code and maintains context files.
    investigator.md     — Causa raiz antes do fix. Fase read-only obrigatória; entrega diagnóstico, não correção.
    _archive/           — tester.md e debugger.md (aposentados 2026-06-11: /test e /fix cobrem os fluxos).
  skills/
    context-maintenance/
      SKILL.md                — How to maintain .context.md and FEATURE-MAP.md.
    api-design.md             — How to design and evolve HTTP/JSON APIs.
    frontend-implementation.md — How to implement frontend features.
    security-practices.md     — Rules for secrets, env vars, and security hygiene.
    multi-provider.md         — How Maestro delegates to Claude (tier-1) and Codex (tier-2).
    metrics.md                — Quality, velocity, compliance, and rework tracking.
    event-log.md              — Event log append-only por projeto (fonte de verdade; hooks escrevem).
    heartbeat.md              — Ativação autônoma agendada (runner single-shot + post-gate).
    pr-description.md         — Auto-generate PR descriptions after review.
    health-check.md           — Diagnose framework setup integrity on demand.
    canuto-project-doctor.md  — Diagnose setup, memory, stale context, and framework drift.
    canuto-session-end-learning.md — Extract session learning before vault writes.
    canuto-rework-detector.md — Detect repeated attempts and stale assumptions.
    canuto-pending-triage.md  — Deduplicate and prioritize pending tasks.
    obsidian-writeback-queue.md — Stage safe Obsidian/Canuto vault writes.
    continuous-learning/
      SKILL.md                — Extract reusable instincts from session experience.
    frontend-design/
      SKILL.md                — Visual design principles, knobs, and LLM bias correction.
    obsidian-markdown.md      — Wikilinks, embeds, callouts, properties, tags.
    mcp-obsidian.md           — How the framework uses MCP to interact with the vault.
    defuddle.md               — Extract clean markdown from web pages.
    absence-reporting.md      — Personas report what they searched and didn't find.
    cross-persona-flags.md    — Outbound flags between personas for lateral discovery.
    coverage-tracking.md      — Track exploration depth for M/L tasks.
    budget-controls.md        — Token/cost budgets per persona and session.
    governance.md             — Approval gates for high-impact actions.
    audit-trail.md            — Immutable log of session events.
    runtime-flags.md          — Session-scoped behavioral overrides.
    convergence-detection.md  — Multi-persona agreement detection.
    browser-qa.md             — When/how to use /qa + /browse (gstack) in QA flow.
    _archive/                 — Skills aposentados (auditorias 2026-06-11 e 2026-07-26). Restaurar: git mv de volta.
  mcp/
    server.json         — MCP server config template (obsidian-mcp-server).
    setup.md            — Setup guide for Obsidian + MCP integration.
  hooks/
    session-save.sh          — Auto-backup vault on Stop + gate de CLOSEOUT (avisa se o dia fechou sem evento).
    pre-compact-save.sh      — Save context before token compaction.
    pre-pr-bash-gate.sh      — PreToolUse: intercepta `gh pr create` e roda os testes antes (fail-closed).
    postdelegate-verify.sh   — PostToolUse: verifica artefato de toda delegação Codex (existe/não-vazio/recente).
    require-tests-for-pr.sh  — Gate de testes compartilhado pelos dois caminhos de PR (MCP e gh CLI).
    codex-pretool-guard.sh   — Guarda de pré-commit para delegações Codex.
    settings-snippet.json    — Registro dos hooks para ~/.claude/settings.json (aplicado por hooks/install.sh).
  tools/
    event-log.sh        — Append/tail do event log por projeto (jsonl, flock, nunca falha o caller).
    heartbeat-run.sh    — Runner single-shot de heartbeats + --install-cron/--install-launchd/--uninstall.
    instinct-aging.sh   — Arquiva instincts frios (low, >30d) — nunca deleta. --dry-run por padrão.
    canuto-memory.sh    — Resolução canônica de slug e paths do vault.
    codex-maestro.sh    — Launch direct Codex runtime with the `maestro` profile.
    vault-sync.sh       — Flush pending sync notes into the active vault backend.
  heartbeats/
    weekly-maintenance.md — Task semanal: pending triage + instinct aging + digest.
    usage-audit.md        — Task mensal: auditoria de uso real do framework.
  vps/                  — Infra que roda NA VPS, não em projeto (fora de FRAMEWORK_FILES de propósito).
    bootstrap.sh          — Ponto único: roda tudo na ordem e lista o que sobrou para você.
    runner-setup.sh       — GitHub Actions self-hosted runner via systemd (só repo privado).
    vault-remote-setup.sh — Vault oficial na VPS + Mac como espelho (nunca destrutivo).
    signoz-setup.sh       — SigNoz com bind privado e descoberta de serviços por release.
    uptime-kuma-setup.sh  — Uptime dos apps em produção.
  plugins/_archive/     — Plugins arquivados 2026-07-26 (mecanismo de descoberta nunca foi implementado).
  SPEC.md               — Full specification and design decisions.

docs/adr/               — Architecture Decision Records (contexto, opções rejeitadas e porquê, consequências).
.claude/agents/blind-reviewer.md — Subagent revisor cego (só Read/Grep/Glob).

~/.canuto/vault/          — Global Obsidian vault (one for all projects)
  projects/
    my-app/               — Per-project memory
      sessions/           — Daily session notes
      decisions/          — One note per architectural decision
      instincts/          — Learned patterns from sessions
      pending/            — Unfinished tasks
      handoffs/           — Persisted handoff/review envelopes + resumable context links
      audit/              — Event log (handoffs, gates, rework)
      metrics/            — Session metrics
      design/             — Design profile + component inventory
  bases/                  — Database views (query across projects)
  canvas/                 — Visual maps (persona flow, memory map)

registry.md             — Skill registry for core and optional skills.
global-skills/          — Global slash commands installed to ~/.claude/skills/
~/.claude/skills/gstack/  — Garry Tan's 21 engineering skills (auto-installed).
```

## Standard Flow

```
Maestro → Architect → Coder → Reviewer
                         ↓
                    /test or /fix when deeper QA/debugging is needed
```

## Runtime Maestro

- Claude session: Claude remains the Maestro (alias `fable`, fallback `opus`) and keeps the existing orchestration flow.
- Direct Codex session: launch `bash .agents/tools/codex-maestro.sh` and Codex becomes the Maestro via the `maestro` role. Model and effort come from `.agents/config/models.yaml` — never pinned in docs, and never from the legacy `[profiles.*]` blocks of `config.toml` (ignored since codex-cli 0.135; the live path is `~/.codex/<role>.config.toml`).
- Cross-runtime handoff: `context-package.md` now carries a persisted handoff envelope (`task_id`, `goal`, `constraints`, `done_definition`, `thread_id`) into the vault so Claude and Codex resume with less reread.

## Quick Start

Guia completo: [docs/TUTORIAL.md](docs/TUTORIAL.md)
Resumo operacional: [SUMMARY.md](SUMMARY.md)
Tutorial rapido: [TUTORIAL.md](TUTORIAL.md)
Tutorial visual: [docs/TUTORIAL-VISUAL.html](docs/TUTORIAL-VISUAL.html)
Troubleshooting: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
Catalogo de skills: [registry.md](registry.md)
Exemplos de `CLAUDE.md`: [docs/CLAUDE-EXAMPLES.md](docs/CLAUDE-EXAMPLES.md)

### Fresh install (new project)

```bash
cd my-project
curl -fsSL https://raw.githubusercontent.com/csorodrigo/canuto-framework/main/install.sh | bash
```

Roda em **macOS e Linux**. Sem Homebrew (VPS), o instalador usa `apt`/`dnf` e
trata `rtk`, `bun` e `gcloud` como opcionais — eles não têm caminho de instalação
fora do brew e não são necessários para o framework funcionar.

### Infraestrutura na VPS

CI self-hosted (sem cota de Actions), vault oficial fora do Mac, uptime e
telemetria: [`.agents/vps/README.md`](.agents/vps/README.md).

To view the visual guide locally:

```bash
open docs/TUTORIAL-VISUAL.html
```

### Update an existing project that already uses Canuto

```bash
cd my-project
bash install.sh --update
```

`bash install.sh --update` is now the standard path. The installer refreshes itself from `main` before applying the update, so it still works even if the local `install.sh` is stale.

`--update` never overwrites `vault/`, `plugins/`, or `CLAUDE.md`; it updates personas, skills, hooks, runtime helpers, and support docs.

### Validate install or update

```bash
# quick integrity check
bash install.sh --check

# smoke test recommended after install/update
bash install.sh --test

# repair runtime state without redoing a full install
bash install.sh --repair

# repair + validate in one command
# also bootstraps .agents/tmp/context-package.md and a handoff envelope in the vault
bash install.sh --doctor
```

If you are maintaining the framework itself, run:

```bash
bash test-framework.sh
```

### Optional skill install

Desde 2026-07-26 todos os skills ativos são distribuídos por default — não há
skills opcionais no momento. Skills aposentados vivem em
`.agents/skills/_archive/` (restaurar: `git mv` de volta + re-registrar no
`registry.md`). O mecanismo `--skill <name>` continua funcionando para skills
futuros ou da comunidade.

### One-time migration from v1.5 (flat-file memory) to v1.6 (Obsidian vault)

```bash
curl -fsSL https://raw.githubusercontent.com/csorodrigo/canuto-framework/main/install.sh | bash -s -- --migrate
```

### Passive vs Explicit

| Passive after install | Explicitly ask/run |
|-----------------------|--------------------|
| Maestro briefing, normal persona flow, session-save hook (+ gate de CLOSEOUT), pre-compact-save hook, Codex pretool guard, event log escrito pelos hooks, gate de PR em `gh pr create`, verificação pós-delegação Codex, tier hipótese da memória (auto-grava e anuncia), instinct lookup, project-doctor on suspicious setup, rework detector on repeated loops, session-end learning, write-back preview before curated vault writes | `bash install.sh --update`, `bash install.sh --repair`, `bash install.sh --doctor`, agendar heartbeats (`bash .agents/tools/heartbeat-run.sh --install-cron/--install-launchd`), `"health check"`, `"triage pending"`, co-review com `blind-reviewer`, runtime flags like `set FAST_MODE`, slash commands like `/office-hours`, direct skill requests like `"use a skill research"` |

### New project via GitHub template

Click **Use this template** at the top of the repository.

---

## Obsidian Setup (uma vez)

O framework usa um vault Obsidian global em `~/.canuto/vault/` para memoria. Setup unico:

1. **Instale o Obsidian** — [obsidian.md](https://obsidian.md)
2. **Abra o vault** — File → Open folder as vault → `~/.canuto/vault/`
3. **Instale o plugin Local REST API** — Settings → Community Plugins → Browse → "Local REST API" → Install → Enable
4. **Rode `install.sh`** em qualquer projeto — ele pede a API key e configura o MCP automaticamente

Depois disso, nunca mais precisa mexer. O vault fica aberto no Obsidian e todos os projetos gravam memoria ali, cada um na sua pasta `projects/{nome}/`.

O runtime grava handoffs persistidos em `projects/{nome}/handoffs/`. Se a sessao estiver offline ou sem MCP no momento do save, os envelopes vao para `.agents/.cache/pending-sync/` e podem ser sincronizados depois com `/vault-sync` ou `bash .agents/tools/vault-sync.sh`.

---

## Como Funciona

Apos a instalacao, abra o projeto em Claude ou inicie o runtime direto do Codex com `bash .agents/tools/codex-maestro.sh`. O Maestro conduz este ciclo:

1. **Bootstrap**: carrega `CLAUDE.md`, personas, skills, vault, context package e projeto ativo.
2. **Session start**: consulta o vault direto no filesystem (paths resolvidos por `.agents/tools/canuto-memory.sh`), carrega latest session, pending tasks, instincts e stale-context signals. Se setup/memoria/contexto parecerem suspeitos, roda `canuto-project-doctor`.
3. **Planejamento**: limita objetivos da sessao, detecta estilo do projeto e escolhe personas/skills relevantes.
4. **Execucao**: Architect, Coder e Reviewer trabalham no fluxo minimo valido; Coder escreve os testes no mesmo spawn e `/test` ou `/fix` entram quando a task exige QA/debugging dedicado. `canuto-rework-detector` entra quando houver retry loop, review loop, teste repetido ou pendencia recorrente.
5. **QA e review**: Reviewer valida risco, testes, handoffs, PR readiness e, quando aplicavel, skills opcionais de dominio.
6. **Session end**: `canuto-session-end-learning` reconcilia goals, pending, decisions, metrics, rework e candidate instincts.
7. **Write-back seguro**: `obsidian-writeback-queue` prepara preview/queue antes de qualquer escrita fora da memoria normal do projeto.

## Skill Activation Model

Skills no Canuto nao sao daemons. Elas sao playbooks que Maestro/personas chamam conforme regras do ciclo, evidencia da sessao ou pedido explicito do usuario.

| Skill | Tipo | Como e chamada | Observacao |
|------|------|----------------|------------|
| `canuto-project-doctor` | Passiva condicional | No session start quando setup, memoria ou contexto parecerem suspeitos; tambem por pedido explicito como "health check" | Read-only |
| `canuto-rework-detector` | Passiva condicional | Antes de continuar quando houver retry, review loop, stale context, dirty-state ou tarefa repetida | Pode pausar implementacao para replanejar |
| `canuto-session-end-learning` | Passiva obrigatoria | No encerramento da sessao, antes do resumo final | Propõe memoria, metricas e candidate instincts |
| `canuto-pending-triage` | Passiva condicional | Quando pending no vault acumular duplicatas, itens vagos ou backlog grande; tambem por pedido explicito | Nunca apaga pendencia sem aprovacao |
| `obsidian-writeback-queue` | Passiva com gate ativo | Depois de session learning ou pending triage quando houver proposta de escrever no tier curado do vault | Preview por padrao; escrita viva so com aprovacao. Tier hipotese (session notes, metrics, instinct candidates) grava direto e anuncia |
| `event-log` | Passiva mecanica | Hooks escrevem sozinhos (SESSION, GATE, DELEGATION, HEARTBEAT, CLOSEOUT) | Append-only; correcao = novo evento, nunca edicao |
| `heartbeat` | Agendada | Cron/launchd chama `heartbeat-run.sh <task>` | Single-shot + post-gate; sem retry envelope |

Skills de QA opcionais antigos (`dashboard-regression-guard`, `scraper-resilience`,
`route-optimizer-qa`, `spreadsheet-delivery-check`, `frontend-visual-qa`) foram
arquivados em 2026-06-11 — restauraveis de `.agents/skills/_archive/`.

Passiva nao significa silenciosa: a persona deve explicar que esta usando a skill e resumir a evidencia. Ativa significa que a skill entra por tipo de tarefa, por instalacao opcional com `--skill`, ou por pedido direto.

## Goals vs Pending Tasks

| | Goals | Pending Tasks |
|--|-------|---------------|
| **O que** | Intencoes da sessao | Tarefas especificas nao finalizadas |
| **Exemplo** | "Auth funcionando end-to-end" | "Escrever testes do refresh token" |
| **Onde fica** | `sessions/YYYY-MM-DD.md` | `pending/task-slug.md` |
| **Maximo** | 3 por sessao | ilimitado |

## CLAUDE.md Template

```markdown
# Project AI Setup

You are my coding orchestrator for this repository.

## Framework
- Location: .agents/
- Always act as the **Maestro** persona defined in the framework.
- Delegate to other personas as defined in their playbooks.

## Preferences
- tests: required
- handoff-verbosity: explicit
- session-briefing: true

## Project Rules
- Before finalizing any plan, always interview the user in detail using AskUserQuestion about implementation choices, UI/UX decisions, trade-offs, and concerns. Never assume — always ask first.
- Read any .context.md and docs/FEATURE-MAP.md files if they exist.
- If they do not exist, have the Contextualizer create them (with approval).
- Never run Git or shell commands without explicit confirmation.
- When in doubt, ask questions instead of guessing.

## Memory System
- Caminho canônico de leitura/escrita: filesystem direto no vault global (`~/.canuto/vault/projects/<slug>/`). Resolução de paths via `source .agents/tools/canuto-memory.sh`
- Event log append-only por projeto em `<vault>/events/log.jsonl` — escrito pelos hooks, fonte de verdade dos eventos de sessão
- MCP obsidian-vault é opcional (filesystem é o caminho real); see `.agents/mcp/setup.md`

## On Session Start
1. Query vault via MCP: latest session note, pending tasks, high-confidence instincts
2. Check for stale contexts (git diff)
3. Run canuto-project-doctor if setup, memory, or context looks suspicious
4. Present the session briefing
5. Ask what to work on

## On Session End
1. Run canuto-session-end-learning before closing
2. Update vault memory with summary, pending tasks, decisions, metrics, and instincts
3. Use obsidian-writeback-queue for any non-standard Obsidian/Canuto vault write-back
4. Never write outside the resolved project vault path without explicit approval
```

## Key Concepts

**Obsidian vault**: Memoria global em `~/.canuto/vault/`, acessada via MCP. Cada projeto tem sua pasta. Um vault, todos os projetos.

**Session memory**: O vault persiste contexto entre sessoes como notas atomizadas com frontmatter, reduzindo tokens e evitando retrabalho.

**Bootstrap context package**: `bash install.sh --doctor` e `bash install.sh --repair` garantem um `.agents/tmp/context-package.md` inicial para retomada rapida entre Claude e Codex.

**Handoff envelope**: Toda passagem relevante entre runtimes pode carregar `task_id`, `goal`, `constraints`, `done_definition` e `thread_id`, persistidos em `handoffs/`.

**Rework detection**: Maestro avisa quando o mesmo arquivo e modificado 3+ vezes na sessao.

**Learning loop**: No fim da sessao, Maestro extrai pendencias, decisoes, metricas, rework e candidate instincts antes de qualquer write-back nao padrao.

**Safe vault write-back**: Escrita fora do fluxo normal de sessao passa por preview/queue/aprovacao com `obsidian-writeback-queue`.

**PR description auto**: Reviewer gera o body do PR automaticamente no APPROVE.

**Health check**: Diga "health check" pro Maestro rodar um diagnostico completo do framework.

**Plugins**: Extensoes opcionais em `.agents/plugins/` sem tocar nos arquivos core.

**Multi-provider**: Claude continua Claude-first; Codex pode assumir como maestro quando o runtime e iniciado direto no Codex. Os handoffs usam o mesmo vault.

**Design knobs**: Tres parametros tunaveis (DESIGN_VARIANCE, MOTION_INTENSITY, VISUAL_DENSITY) controlam o output visual globalmente. Configuraveis por projeto em `design/profile.md`.

**LLM bias correction**: Regras anti-padrao que previnem UIs genericas de AI.

**Event log**: `<vault>/events/log.jsonl` append-only por projeto, escrito pelos hooks. Projecoes (notas, digests, metricas) derivam dele. `bash .agents/tools/event-log.sh tail 20` mostra os ultimos eventos.

**Gates fail-closed**: PR sem testes nao nasce (`gh pr create` interceptado); delegacao sem artefato grita; dia sem CLOSEOUT gera aviso com evidencia. Bypass existe, mas deixa rastro no log.

**Heartbeat**: Ativacao autonoma agendada. `bash .agents/tools/heartbeat-run.sh --install-cron "0 9 * * 1" weekly-maintenance` (Linux) ou `--install-launchd 604800 weekly-maintenance` (macOS). O digest em `.agents/vault/digests/` e a prova de execucao.

**Memoria em dois tiers**: hipotese (auto-grava, anuncia) vs curada (aprovacao humana). `instinct-aging.sh` arquiva candidatos frios apos 30 dias — nunca deleta.

**Revisor cego**: subagent `blind-reviewer` com só Read/Grep/Glob — segunda opiniao sem contaminacao do contexto da sessao. Strikes e veredito, nunca reescrita.

**Absence reporting**: Personas reportam o que buscaram e NAO encontraram.

**Cross-persona flags**: Personas emitem flags sugerindo que outra persona investigue uma descoberta.

**Coverage tracking**: Maestro rastreia profundidade de exploracao para tasks M/L.

**Budget controls**: Limites de token/custo por persona e sessao com warnings advisorios.

**Governance gates**: Checkpoints de aprovacao humana para acoes de alto impacto.

**Audit trail**: Log imutavel de eventos significativos como notas individuais no vault.

**Runtime flags**: Overrides de comportamento por sessao (FAST_MODE, STRICT_MODE, etc.) sem editar config.

**Convergence detection**: Quando 2+ personas chegam a mesma conclusao independentemente, Maestro marca como alta confianca.

**Session modes**: 3 modos — `full` (do zero), `continue` (retomar pending), `targeted` (foco especifico).

## MCP Servers

| Server | Comando | Onde | Funcao |
|--------|---------|------|--------|
| obsidian-mcp-server | `npx obsidian-mcp-server` | opcional (Claude e Codex) | Leitura/escrita do vault via Obsidian Local REST API — filesystem direto e o caminho real |
| ast-grep | `npx -y @ast-grep/mcp` | Claude + Codex | Analise AST do codebase |
| playwright | `npx -y @anthropic-ai/mcp-server-playwright` | Codex | Automacao de browser para agentes Codex |
| claude-architect / claude-reviewer | `~/.claude/scripts/claude-*.sh` (via `uvx` codex-as-mcp) | **so Codex** | Back-delegation Codex→Claude — nunca registrados no settings.json do Claude (numa sessao Claude seriam servidores mortos) |

Configurados automaticamente por `install.sh` + `.agents/hooks/install.sh`. Removidos em 2026-07-27: `openbrand` e `context-hub` (unicos consumidores eram skills em `_archive/`; re-adicione com `claude mcp add` se voltar a usar).

## Global Skills (~/.claude/skills/)

Instalados globalmente — disponiveis em qualquer projeto.

| Skill | Origem | Descricao |
|-------|--------|-----------|
| `/office-hours` | Canuto | Reframe de produto YC-style antes de codar |
| `/investigate` | Canuto | Debugging forense com Iron Law |
| `/document-release` | Canuto | Atualizar docs e changelog pos-ship |
| `/retro` | Canuto | Retrospectiva semanal com metricas do framework |
| `/plan-ceo-review` | gstack | Revisao de escopo nivel CEO |
| `/plan-eng-review` | gstack | Revisao de arquitetura |
| `/qa` | gstack | QA com browser Chromium real |
| `/careful` | gstack | Guardrails contra operacoes destrutivas |
| `/browse` | gstack | Pesquisa in-browser (requer bun) |
| `+16 mais` | gstack | Ver `~/.claude/skills/gstack/` |

**gstack** (Garry Tan's engineering skills) e clonado automaticamente em `~/.claude/skills/gstack` e requer `git`. O binario `/browse` requer `bun`.

## Design Principles

- Small, predictable steps over big, risky jumps.
- Explicit handoffs — every persona transition is announced.
- Escalate to Maestro on unexpected situations — no autonomous decisions.
- Adapt to existing projects — never force the Canuto pattern.
- Invest in bootstrap — rich context files save tokens in every subsequent session.

---

*Canuto Framework v1.6 — Rodrigo Canuto &copy; 2026*
