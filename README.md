# Canuto Framework v1.2

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
  memory/
    last-session.md     — Summary + goals of the last session (overwritten each time).
    decisions.md        — Append-only log of decisions.
    pending.md          — Specific unfinished tasks from previous sessions.
    metrics.md          — Append-only session metrics log.
  plugins/              — Opt-in plugin extensions (see plugin-system skill).
  SPEC.md               — Full specification and design decisions.
registry.md             — Skill registry for core and optional skills.
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
bash install.sh --update
```

O `--update` **nunca sobrescreve** `memory/`, `plugins/`, ou `CLAUDE.md` — só atualiza personas e skills.

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
1. Read .agents/memory/last-session.md
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

## Design Principles

- Small, predictable steps over big, risky jumps.
- Explicit handoffs — every persona transition is announced.
- Escalate to Maestro on unexpected situations — no autonomous decisions.
- Adapt to existing projects — never force the Canuto pattern.
- Invest in bootstrap — rich context files save tokens in every subsequent session.

---

*Canuto Framework v1.2 — Rodrigo Canuto © 2026*
