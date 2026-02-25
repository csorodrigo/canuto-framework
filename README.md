# Canuto Framework v1.1

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
    git-workflow.md           — Branching, commits, and PR conventions (opt-in).
    plugin-system.md          — How to create and manage opt-in plugins.
    multi-provider.md         — How Maestro delegates to Claude, Codex, GLM.
    metrics.md                — Quality, velocity, compliance, and rework tracking.
    squads.md                 — Parallel workstreams for larger projects.
    session-goals.md          — Track session goals with completion status.
    pr-description.md         — Auto-generate PR descriptions after review.
    adr.md                    — Architecture Decision Records with structured templates.
    health-check.md           — Diagnose framework setup integrity on demand.
  memory/
    last-session.md     — Summary + goals of the last session (overwritten each time).
    decisions.md        — Append-only log of architectural/business decisions.
    pending.md          — Unfinished tasks from previous sessions.
    metrics.md          — Append-only session metrics log.
  decisions/            — ADR files: ADR-001-title.md, ADR-002-title.md, ...
  plugins/              — Opt-in plugin extensions (see plugin-system skill).
  SPEC.md               — Full specification and design decisions.
registry.md             — Skill registry for community and official skills.
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
- Cria `.agents/decisions/` para ADRs
- Cria o `CLAUDE.md` se não existir, ou adiciona as seções faltando se já existir
- Oferece commit ao final

### Atualizar o framework num projeto existente

```bash
bash install.sh --update
```

Ou via curl:

```bash
curl -fsSL https://raw.githubusercontent.com/csorodrigo/canuto-framework/main/install.sh | bash -s -- --update
```

O `--update` **nunca sobrescreve** `memory/`, `plugins/`, ou `CLAUDE.md` — só atualiza personas e skills.

### Verificar se está atualizado

```bash
bash install.sh --check
```

Lista cada arquivo com seu status: `✓ OK`, `⚠ OUTDATED`, ou `✗ MISSING`.

### Instalar uma skill extra

```bash
bash install.sh --skill adr
bash install.sh --skill adr --skill pr-description
```

Veja `registry.md` para a lista completa de skills disponíveis.

### Projeto novo (via GitHub Template)

Clica em **"Use this template"** no topo do repositório.

---

## Como Funciona

Após a instalação, abre o projeto em Claude. O Maestro vai:
1. Carregar a memória e apresentar o briefing da sessão.
2. Pedir os objetivos da sessão (até 3 goals).
3. Detectar o estilo do projeto (Canuto / foreign-schema / novo).
4. Orquestrar as personas para a sua tarefa.
5. Ao encerrar: marcar goals, gravar memória, gerar métricas.

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
1. Read .agents/memory/last-session.md
2. Check for stale contexts (git diff)
3. Present the session briefing
4. Ask what to work on
```

## Key Concepts

**Canuto project**: Uses `.context.md` files and `docs/FEATURE-MAP.md` in the Canuto schema. Full framework support.

**Foreign-schema project**: Has its own documentation style. The framework adapts to the existing format without overwriting it.

**Session memory**: The `memory/` folder persists context between sessions, reducing token usage and preventing rework.

**Session goals**: Maestro asks for up to 3 goals at session start and tracks completion. Deferred goals carry to the next session.

**Rework detection**: Maestro warns when the same file is modified 3+ times in a session — a signal to re-plan.

**ADRs**: Architecture Decision Records stored in `.agents/decisions/`. Architect creates them for significant decisions.

**Plugins**: Optional extensions in `.agents/plugins/` that add personas, skills, or templates without touching core files.

**Multi-provider**: Maestro pode delegar personas tier-2 (Coder, Tester, etc.) para Codex ou GLM enquanto mantém decisões estratégicas no Claude.

## Design Principles

- Small, predictable steps over big, risky jumps.
- Explicit handoffs — every persona transition is announced.
- Escalate to Maestro on unexpected situations — no autonomous decisions.
- Adapt to existing projects — never force the Canuto pattern.
- Invest in bootstrap — rich context files save tokens in every subsequent session.

---

*Canuto Framework v1.1 — Rodrigo Canuto © 2026*
