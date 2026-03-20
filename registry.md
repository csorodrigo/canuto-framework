# Canuto Framework — Skill Registry

> Community and official skills installable via `bash install.sh --skill <name>`
>
> To contribute: open a PR adding an entry to the Community Skills table and providing the skill file in `.agents/skills/`.

---

## Core Skills (installed by default)

These skills ship with every install and update automatically.

| Name | Description | Tags |
|------|-------------|------|
| `context-maintenance` | How to maintain `.context.md`, `FEATURE-MAP.md`, and Repo Index (evaluate-repo pipeline) | documentation, indexation |
| `api-design` | How to design and evolve HTTP/JSON APIs | backend |
| `frontend-implementation` | How to implement frontend features | frontend |
| `cli-usage` | How to safely use CLI commands and scripts | devops |
| `security-practices` | Rules for secrets, env vars, and security hygiene | security |
| `git-workflow` | Branching, commits, and PR conventions | workflow |
| `plugin-system` | How to create and manage opt-in plugins | extensibility |
| `multi-provider` | How Maestro delegates to Claude, Codex, GLM | orchestration |
| `metrics` | Quality, velocity, compliance, and rework tracking | analytics |
| `squads` | Parallel domain-based workstreams | orchestration |
| `pr-description` | Auto-generate PR descriptions after review | workflow |
| `health-check` | Diagnose framework setup integrity | diagnostics |
| `continuous-learning` | Extract, store, and evolve reusable patterns (instincts) from session experience | learning, memory |
| `absence-reporting` | Personas report what they searched and did NOT find, eliminating silence ambiguity | observability |
| `cross-persona-flags` | Outbound flags between personas for lateral discovery via Maestro | orchestration |
| `coverage-tracking` | Track exploration depth across personas, areas, and concerns for M/L tasks | observability |
| `budget-controls` | Token/cost budgets per persona and session with advisory warnings | cost-management |
| `governance` | Approval gates for high-impact actions (deploy, migration, breaking changes) | governance |
| `audit-trail` | Immutable append-only log of all significant session events | observability |
| `runtime-flags` | Session-scoped behavioral overrides (FAST_MODE, STRICT_MODE, etc.) | configuration |
| `convergence-detection` | Detect when multiple personas independently reach the same conclusion | observability |
| `heartbeat` | Foundation for scheduled agent activation in autonomous setups | orchestration, future |

---

## Optional Skills (install on demand)

Useful in specific project types. Install with `bash install.sh --skill <name>`.

| Name | Description | Best for | Tags |
|------|-------------|----------|------|
| `session-goals` | Track session goals explicitly in a separate skill file | Teams or highly structured workflows | productivity |
| `adr` | Architecture Decision Records | Long-lived projects with multiple contributors | architecture |
| `product-review` | When/how to run /office-hours + /plan-ceo-review before Architect on L/XL features | Product-heavy projects, new features with uncertain scope | product, planning |
| `browser-qa` | When/how to use gstack's /qa + /browse for real-browser UI testing | Projects with web frontends, critical user flows | testing, quality |

---

## Global Skills (deployed to ~/.claude/skills/ by install.sh)

These skills are slash commands invokable directly in Claude Code. Installed automatically via `bash .agents/hooks/install.sh`.

| Command | Description | Tags |
|---------|-------------|------|
| `/office-hours` | YC Office Hours — reframe product idea before coding. Asks forcing questions, generates 3 approaches, saves context for Architect. | product, planning |
| `/investigate` | Forensic debugger — Iron Law: no fix without confirmed root cause. Read-only investigation phase first. | debugging |
| `/document-release` | Post-ship documentation sweep — updates README, FEATURE-MAP.md, .context.md, CHANGELOG after a deploy. | documentation, workflow |
| `/retro` | Weekly retrospective — reads metrics.md, audit-log.md, instincts.md to generate Shipped / Delayed / Learned / Next. | learning, memory |

---

## Installing an Optional Skill

```bash
# Single skill
bash install.sh --skill adr

# Multiple skills
bash install.sh --skill adr --skill session-goals
```

---

## Community Skills

> None yet. Be the first to contribute!

To contribute:
1. Fork [csorodrigo/canuto-framework](https://github.com/csorodrigo/canuto-framework)
2. Add your skill file to `.agents/skills/`
3. Add an entry below and open a PR

| Name | Description | File | Author | Tags |
|------|-------------|------|--------|------|
| *(none yet)* | | | | |
