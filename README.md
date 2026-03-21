# Canuto Framework v1.5

Personal multi-agent framework for AI-assisted development. Claude-first, provider-agnostic.

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
    context-maintenance.md    — How to maintain .context.md and FEATURE-MAP.md.
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
    frontend-design.md        — Visual design principles, knobs, and LLM bias correction.
    api-docs-fetch.md         — Fetch current API docs via Context Hub before coding.
    brand-bootstrap.md        — Extract brand assets from URLs via OpenBrand.
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
    product-review.md         — When/how to run /office-hours + /plan-ceo-review for L/XL tasks.
  memory/
    last-session.md     — Summary + goals of the last session (overwritten each time).
    decisions.md        — Append-only log of decisions.
    pending.md          — Specific unfinished tasks from previous sessions.
    metrics.md          — Append-only session metrics log.
    audit-log.md        — Append-only log of significant session events.
    design-profile.md   — Visual identity: mood, typography, colors, knobs, brand source.
    component-inventory.md — Registry of approved UI components.
  plugins/              — Opt-in plugin extensions (see plugin-system skill).
  SPEC.md               — Full specification and design decisions.
registry.md             — Skill registry for core and optional skills.
global-skills/          — Global slash commands installed to ~/.claude/skills/
  office-hours/         — Product reframe (YC-style) before writing a line of code.
  investigate/          — Forensic debugging with Iron Law (no patch without root cause).
  document-release/     — Update docs and changelog post-ship.
  retro/                — Weekly retrospective with framework metrics.
~/.claude/skills/gstack/  — Garry Tan's 21 engineering skills (auto-installed).
  /plan-ceo-review      — CEO-level scope review.
  /plan-eng-review      — Architecture review.
  /qa                   — QA with real Chromium browser.
  /careful              — Guardrails against destructive operations.
  /browse               — In-browser research (requires bun).
  … (+16 more)
```

## Standard Flow

```
Maestro → Architect → Coder → Tester → Reviewer
                                 ↓ (if tests fail)
                             Debugger → Coder (fix) → Tester (re-run)
```

## Installation

### Projeto existente — fresh install

Na raiz do seu projeto:

```bash
curl -fsSL https://raw.githubusercontent.com/csorodrigo/canuto-framework/main/install.sh | bash
```

O script:
- Baixa todas as personas e skills
- Cria os arquivos de memória (last-session, decisions, pending, metrics)
- Cria o `CLAUDE.md` se não existir, ou adiciona as seções faltando se já existir
- Oferece commit ao final

### Atualizar o framework num projeto existente

```bash
curl -fsSL https://raw.githubusercontent.com/csorodrigo/canuto-framework/main/install.sh | bash -s -- --update
```

O `--update` **nunca sobrescreve** `memory/`, `plugins/`, ou `CLAUDE.md` — só atualiza personas e skills. Também atualiza gstack e global skills.

### Verificar se está atualizado

```bash
bash install.sh --check
```

Lista cada arquivo: `✓ OK`, `⚠ OUTDATED`, ou `✗ MISSING`.

### Instalar uma skill opcional

```bash
bash install.sh --skill adr
bash install.sh --skill adr --skill session-goals
```

Veja `registry.md` para a lista completa.

### Projeto novo (via GitHub Template)

Clica em **"Use this template"** no topo do repositório.

---

## Como Funciona

Após a instalação, abre o projeto em Claude. O Maestro vai:
1. Carregar a memória e apresentar o briefing da sessão (goals deferidos + tarefas pendentes).
2. Pedir os objetivos da sessão (até 3 goals).
3. Detectar o estilo do projeto (Canuto / foreign-schema / novo).
4. Orquestrar as personas para a sua tarefa.
5. Ao encerrar: marcar goals, gravar memória, gerar métricas.

## Goals vs Pending Tasks

| | Goals | Pending Tasks |
|--|-------|---------------|
| **O quê** | Intenções da sessão | Tarefas específicas não finalizadas |
| **Exemplo** | "Auth funcionando end-to-end" | "Escrever testes do refresh token" |
| **Onde fica** | `last-session.md` | `pending.md` |
| **Máximo** | 3 por sessão | ilimitado |

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
- Read any .context.md and docs/FEATURE-MAP.md files if they exist.
- If they do not exist, have the Contextualizer create them (with approval).
- Never run Git or shell commands without explicit confirmation.
- When in doubt, ask questions instead of guessing.

## On Session Start
1. Query vault via MCP: latest session note, pending tasks, high-confidence instincts
2. Check for stale contexts (git diff)
3. Present the session briefing
4. Ask what to work on
```

## Key Concepts

**Session memory**: O `memory/` persiste contexto entre sessões, reduzindo tokens e evitando retrabalho.

**Rework detection**: Maestro avisa quando o mesmo arquivo é modificado 3+ vezes na sessão.

**PR description auto**: Reviewer gera o body do PR automaticamente no APPROVE.

**Health check**: Diga "health check" pro Maestro rodar um diagnóstico completo do framework.

**Plugins**: Extensões opcionais em `.agents/plugins/` sem tocar nos arquivos core.

**Multi-provider**: Maestro pode delegar personas tier-2 para Codex ou GLM.

**Design knobs**: Três parâmetros tunáveis (DESIGN_VARIANCE, MOTION_INTENSITY, VISUAL_DENSITY) controlam o output visual globalmente. Configuráveis por projeto em `design-profile.md`.

**LLM bias correction**: Regras anti-padrão que previnem UIs genéricas de AI (Inter banido, hero centrado proibido com variance alta, estados obrigatórios de loading/empty/error).

**API docs fetch**: Busca docs atualizadas via Context Hub (`chub`) antes de codificar integrações — previne hallucination de APIs.

**Brand bootstrap**: Extrai cores, logos e brand name de URLs via OpenBrand para popular `design-profile.md` automaticamente.

**Absence reporting**: Personas reportam explicitamente o que buscaram e NÃO encontraram — eliminando ambiguidade de silêncio.

**Cross-persona flags**: Personas emitem flags sugerindo que outra persona investigue uma descoberta — lateral discovery via Maestro.

**Coverage tracking**: Maestro rastreia profundidade de exploração (personas, áreas, concerns) para tasks M/L.

**Budget controls**: Limites de token/custo por persona e sessão com warnings advisórios.

**Governance gates**: Checkpoints de aprovação humana para ações de alto impacto (deploy, migration, breaking changes).

**Audit trail**: Log imutável de eventos significativos (handoffs, gates, rework, escalations) em `audit-log.md`.

**Runtime flags**: Overrides de comportamento por sessão (FAST_MODE, STRICT_MODE, etc.) sem editar config.

**Convergence detection**: Quando 2+ personas chegam à mesma conclusão independentemente, Maestro marca como alta confiança.

**Session modes**: 3 modos de sessão — `full` (do zero), `continue` (retomar pending), `targeted` (foco específico).

**Heartbeat** (futuro): Padrão para ativação autônoma de agentes via wake-ups agendados.

## MCP Servers Incluídos

| Server | Comando | Função |
|--------|---------|--------|
| ast-grep | `npx -y @ast-grep/mcp` | Análise AST do codebase |
| openbrand | `npx -y openbrand-mcp` | Extração de assets de marca via URL |
| context-hub | `npx -y @aisuite/chub-mcp` | Docs de API atualizadas |

Configurados automaticamente pelo `install.sh` em `~/.claude/settings.json`.

## Global Skills (~/.claude/skills/)

Instalados globalmente — disponíveis em qualquer projeto.

| Skill | Origem | Descrição |
|-------|--------|-----------|
| `/office-hours` | Canuto | Reframe de produto YC-style antes de codar |
| `/investigate` | Canuto | Debugging forense com Iron Law |
| `/document-release` | Canuto | Atualizar docs e changelog pós-ship |
| `/retro` | Canuto | Retrospectiva semanal com métricas do framework |
| `/plan-ceo-review` | gstack | Revisão de escopo nível CEO |
| `/plan-eng-review` | gstack | Revisão de arquitetura |
| `/qa` | gstack | QA com browser Chromium real |
| `/careful` | gstack | Guardrails contra operações destrutivas |
| `/browse` | gstack | Pesquisa in-browser (requer bun) |
| `+16 mais` | gstack | Ver `~/.claude/skills/gstack/` |

**gstack** (Garry Tan's engineering skills) é clonado automaticamente em `~/.claude/skills/gstack` e requer `git`. O binário `/browse` requer `bun`.

## Design Principles

- Small, predictable steps over big, risky jumps.
- Explicit handoffs — every persona transition is announced.
- Escalate to Maestro on unexpected situations — no autonomous decisions.
- Adapt to existing projects — never force the Canuto pattern.
- Invest in bootstrap — rich context files save tokens in every subsequent session.

---

*Canuto Framework v1.5 — Rodrigo Canuto © 2026*
