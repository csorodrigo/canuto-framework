# Canuto Framework v1.6

Personal multi-agent framework for AI-assisted development. Claude-first by default, Codex-maestro when you are talking directly to Codex. Obsidian-native memory.

This release keeps the v1.6 Obsidian-native runtime and adds a sharper learning-loop layer: project diagnosis, rework detection, session-end learning, pending triage, and safe vault write-back preview. It also adds optional QA skills for dashboards, scrapers, routing, spreadsheets, and frontend visual checks.

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
    coder.md            — Implementer. Writes code following the Architect's plan.
    tester.md           — QA. Focuses on edge cases, error scenarios, coverage gaps.
    debugger.md         — Diagnostician. Investigates test failures and root causes.
    reviewer.md         — Quality gate. Reviews code + generates PR descriptions.
    contextualizer.md   — Knowledge engine. Scans code and maintains context files.
  skills/
    context-maintenance/
      SKILL.md                — How to maintain .context.md and FEATURE-MAP.md.
    api-design.md             — How to design and evolve HTTP/JSON APIs.
    frontend-implementation.md — How to implement frontend features.
    cli-usage.md              — How to safely use CLI commands and scripts.
    security-practices.md     — Rules for secrets, env vars, and security hygiene.
    git-workflow.md           — Branching, commits, and PR conventions.
    plugin-system.md          — How to create and manage opt-in plugins.
    multi-provider.md         — How Maestro delegates to Claude, Codex, GLM.
    metrics.md                — Quality, velocity, compliance, and rework tracking.
    squads.md                 — Parallel workstreams for larger projects.
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
    api-docs-fetch.md         — Fetch current API docs via Context Hub before coding.
    brand-bootstrap.md        — Extract brand assets from URLs via OpenBrand.
    obsidian-markdown.md      — Wikilinks, embeds, callouts, properties, tags.
    obsidian-bases.md         — Database views over notes (.base files).
    json-canvas.md            — Visual maps and flowcharts (.canvas files).
    mcp-obsidian.md           — How the framework uses MCP to interact with the vault.
    obsidian-cli.md           — Interact with vault via Obsidian CLI.
    defuddle.md               — Extract clean markdown from web pages.
    absence-reporting.md      — Personas report what they searched and didn't find.
    cross-persona-flags.md    — Outbound flags between personas for lateral discovery.
    coverage-tracking.md      — Track exploration depth for M/L tasks.
    budget-controls.md        — Token/cost budgets per persona and session.
    governance.md             — Approval gates for high-impact actions.
    audit-trail.md            — Immutable log of session events.
    runtime-flags.md          — Session-scoped behavioral overrides.
    convergence-detection.md  — Multi-persona agreement detection.
    heartbeat.md              — Foundation for autonomous agent activation.
    browser-qa.md             — When/how to use /qa + /browse (gstack) in QA flow.
    product-review.md         — When/how to run /office-hours for L/XL tasks.
  mcp/
    server.json         — MCP server config template (obsidian-mcp-server).
    setup.md            — Setup guide for Obsidian + MCP integration.
  hooks/
    session-save.sh     — Auto-backup vault on Stop.
    session-load.sh     — Load session context on start.
    pre-compact-save.sh — Save context before token compaction.
  tools/
    codex-maestro.sh    — Launch direct Codex runtime with the `maestro` profile.
    vault-sync.sh       — Flush pending sync notes into the active vault backend.
  plugins/              — Opt-in plugin extensions (see plugin-system skill).
  SPEC.md               — Full specification and design decisions.

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
Maestro → Architect → Coder → Tester → Reviewer
                                 ↓ (if tests fail)
                             Debugger → Coder (fix) → Tester (re-run)
```

## Runtime Maestro

- Claude session: Claude Opus remains the Maestro and keeps the existing orchestration flow.
- Direct Codex session: launch `bash .agents/tools/codex-maestro.sh` and Codex becomes the Maestro using `~/.codex/config.toml` profile `maestro` (default target `o1-pro` when supported).
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

```bash
bash install.sh --skill adr
bash install.sh --skill adr --skill session-goals
bash install.sh --skill dashboard-regression-guard
bash install.sh --skill frontend-visual-qa
```

### One-time migration from v1.5 (flat-file memory) to v1.6 (Obsidian vault)

```bash
curl -fsSL https://raw.githubusercontent.com/csorodrigo/canuto-framework/main/install.sh | bash -s -- --migrate
```

### Passive vs Explicit

| Passive after install | Explicitly ask/run |
|-----------------------|--------------------|
| Maestro briefing, normal persona flow, session-save hook, pre-compact-save hook, plan-review hook, Codex pretool guard, instinct lookup, project-doctor on suspicious setup, rework detector on repeated loops, session-end learning, write-back preview before vault writes | `bash install.sh --update`, `bash install.sh --repair`, `bash install.sh --doctor`, `"health check"`, `"triage pending"`, runtime flags like `set FAST_MODE`, slash commands like `/office-hours`, direct skill requests like `"use a skill research"` |

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
2. **Session start**: consulta o vault via MCP, carrega latest session, pending tasks, instincts e stale-context signals. Se setup/memoria/contexto parecerem suspeitos, roda `canuto-project-doctor`.
3. **Planejamento**: limita objetivos da sessao, detecta estilo do projeto e escolhe personas/skills relevantes.
4. **Execucao**: Architect, Coder, Tester, Debugger e Reviewer trabalham no fluxo minimo valido. `canuto-rework-detector` entra quando houver retry loop, review loop, teste repetido ou pendencia recorrente.
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
| `obsidian-writeback-queue` | Passiva com gate ativo | Depois de session learning ou pending triage quando houver proposta de escrever no vault | Preview por padrao; escrita viva so com aprovacao |
| `dashboard-regression-guard` | Ativa opcional | Instalada e chamada em dashboards, BI, admin panels e relatorios visuais | Foca fixtures, totais, filtros e timezone |
| `scraper-resilience` | Ativa opcional | Instalada e chamada em scrapers, collectors e parsers frageis | Foca fixture, selector drift e retries limitados |
| `route-optimizer-qa` | Ativa opcional | Instalada e chamada em roteirizacao, logistica e geocoding | Exige metricas before/after |
| `spreadsheet-delivery-check` | Ativa opcional | Instalada e chamada em entregas `.xlsx`, `.xls`, `.csv` e exports | Reabre arquivo e procura erro de formula |
| `frontend-visual-qa` | Ativa opcional | Instalada e chamada em web apps, landing pages, jogos e UIs interativas | Exige browser real quando visual importa |

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
- Global Obsidian vault at `~/.canuto/vault/`
- MCP server (obsidian-mcp-server) required for vault access
- See `.agents/mcp/setup.md` for configuration

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

**API docs fetch**: Busca docs atualizadas via Context Hub antes de codificar integracoes.

**Brand bootstrap**: Extrai cores, logos e brand name de URLs via OpenBrand para popular `design/profile.md` automaticamente.

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

| Server | Comando | Funcao |
|--------|---------|--------|
| obsidian-mcp-server | `npx obsidian-mcp-server` | Leitura/escrita do vault via Obsidian Local REST API |
| ast-grep | `npx -y @ast-grep/mcp` | Analise AST do codebase |
| openbrand | `npx -y openbrand-mcp` | Extracao de assets de marca via URL |
| context-hub | `npx -y @aisuite/chub-mcp` | Docs de API atualizadas |

Configurados automaticamente pelo `install.sh` em `~/.claude/settings.json`.

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
