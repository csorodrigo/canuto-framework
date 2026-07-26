# Canuto Framework — Skill Registry

> Community and official skills installable via `bash install.sh --skill <name>`
>
> To contribute: open a PR adding an entry to the Community Skills table and providing the skill file in `.agents/skills/`.

---

## Core Skills (installed by default)

These skills ship with every install and update automatically.

| Name | Description | Tags |
|------|-------------|------|
| `absence-reporting` | Personas report what they searched and did NOT find, eliminating silence ambiguity | observability |
| `adaptive-routing` | Adjust provider routing based on observed reliability signals | orchestration, routing |
| `api-design` | How to design and evolve HTTP/JSON APIs | backend |
| `audit` | Multi-dimensional UI quality scan (a11y, UX guidelines, interaction states, responsiveness) | design, quality |
| `audit-trail` | Immutable append-only log of all significant session events | observability |
| `auto-analysis` | Deep project scan + cross-project vault intelligence | analytics, onboarding |
| `browser-qa` | Real-browser QA via gstack + authenticated data extraction via Chrome DevTools MCP | testing, quality, scraping |
| `budget-controls` | Token/cost budgets per persona and session with advisory warnings | cost-management |
| `co-review` | Cross-model plan review gate for M/L tasks | review, orchestration |
| `colorize` | BM25 over curated palettes → WCAG-compliant semantic token sets | design, color |
| `cost-routing` | Provider routing matrix: what runs on Claude inline vs Codex spawn | cost-management, orchestration |
| `design-consultation` | Generate a full design system → `design-system/MASTER.md` | design |
| `cli-usage` | How to safely use CLI commands and scripts | devops |
| `context-maintenance` | How to maintain `.context.md`, `FEATURE-MAP.md`, and Repo Index (evaluate-repo pipeline) | documentation, indexation |
| `continuous-learning` | Extract, store, and evolve reusable patterns (instincts) from session experience | learning, memory |
| `convergence-detection` | Detect when multiple personas independently reach the same conclusion | observability |
| `coverage-tracking` | Track exploration depth across personas, areas, and concerns for M/L tasks | observability |
| `cross-persona-flags` | Outbound flags between personas for lateral discovery via Maestro | orchestration |
| `defuddle` | Extract clean markdown from web pages (token-efficient) | web, ingestion |
| `event-log` | Append-only per-project event log written by hooks — source of truth for session events | observability, memory |
| `experiment-loop` | Systematic experiment loops — change, test, measure, keep/discard, repeat | optimization, experimentation |
| `frontend-design` | Visual design consistency with tunable design knobs (variance, motion, density) | design, frontend |
| `frontend-implementation` | How to implement frontend features | frontend |
| `git-workflow` | Branching, commits, and PR conventions | workflow |
| `governance` | Approval gates for high-impact actions (deploy, migration, breaking changes) | governance |
| `health-check` | Diagnose framework setup integrity | diagnostics |
| `canuto-project-doctor` | Diagnose setup, memory coverage, stale context, and framework drift | diagnostics |
| `canuto-session-end-learning` | Extract session learning, pending tasks, decisions, metrics, and candidate instincts | learning, memory |
| `canuto-rework-detector` | Detect retry loops, review loops, stale assumptions, and repeated failed approaches | quality, memory |
| `canuto-pending-triage` | Deduplicate and prioritize pending tasks across vault notes and local memory | productivity, memory |
| `obsidian-writeback-queue` | Stage safe Obsidian/Canuto vault write-back proposals with approval and offline fallback | obsidian, memory |
| `heartbeat` | Scheduled autonomous activation — single-shot runner with mechanical post-gate | orchestration, autonomy |
| `json-canvas` | JSON Canvas: visual maps and flowcharts (.canvas files) | obsidian, visualization |
| `knowledge-ingest` | Ingest external sources (videos, articles, PDFs, meeting transcripts) into structured vault notes | ingestion, knowledge, memory |
| `mcp-obsidian` | How the framework uses MCP to interact with the vault (+ semantic search, multi-MCP connectors) | obsidian, mcp, memory |
| `metrics` | Quality, velocity, compliance, and rework tracking | analytics |
| `monitor` | Long-running monitoring profiles with alert rules | observability |
| `multi-provider` | How Maestro delegates to Claude (tier-1) and Codex (tier-2) | orchestration |
| `obsidian-bases` | Obsidian Bases: database views over notes (.base files) | obsidian, queries |
| `obsidian-cli` | Interact with Obsidian vault via CLI | obsidian, cli |
| `obsidian-markdown` | Obsidian Flavored Markdown: wikilinks, embeds, callouts, properties, tags | obsidian, markdown |
| `plugin-system` | How to create and manage opt-in plugins | extensibility |
| `pr-description` | Auto-generate PR descriptions after review | workflow |
| `research` | Structured investigation workflow with community intelligence (Reddit, HN, X), codebase scan, and vault lookup | research, planning |
| `review` | Manual entry-point for the diff-router (`--auto/--small/--large/--ui/--security/...`) | review, quality |
| `runtime-flags` | Session-scoped behavioral overrides (FAST_MODE, STRICT_MODE, etc.) | configuration |
| `security-practices` | Rules for secrets, env vars, and security hygiene | security |
| `session-goals` | Track session goals explicitly with continuation modes | productivity |
| `session-reset` | Context compaction checkpoint for long sessions | context-management |
| `skill-check-protocol` | The 1% Rule + red-flag rationalizations for skill activation | meta, compliance |
| `skill-creator` | 7-phase skill authoring workflow | meta, authoring |
| `squads` | Parallel domain-based workstreams | orchestration |
| `stack-lock` | Prevent library drift via approved stack | governance, dependencies |
| `stuck-detection` | Detect fix→implement→re-test loops without progress; escalate | quality, observability |
| `trace-analysis` | Session-end trace analysis: playbook gaps, instinct candidates, routing misfires | learning, observability |
| `typeset` | BM25 over font pairings → heading+body + Tailwind config | design, typography |
| `vault-maintenance` | Periodic vault cleanup — archives old sessions, aggregates metrics/audits | maintenance, vault |
| `vault-sync` | Flush offline pending-sync entries back into vault or legacy memory | obsidian, memory, offline |
| `verification-gates` | Anti-fabrication: raw command output required for any test/verification claim | quality, compliance |

---

## Optional Skills (install on demand)

Useful in specific project types. Install with `bash install.sh --skill <name>`.

| Name | Description | Best for | Tags |
|------|-------------|----------|------|
| *(nenhum no momento — todos os skills ativos são distribuídos por default desde 2026-07-26)* | | | |

### Archived Skills

Os skills abaixo foram movidos para `.agents/skills/_archive/` em 2026-06-11
(auditoria de 200 sessões: 0 leituras em runtime). Para restaurar:
`git mv .agents/skills/_archive/<name>.md .agents/skills/` e re-registrar aqui.

`adr`, `api-docs-fetch`, `brand-bootstrap`, `product-review`, `plan-second-opinion`,
`dashboard-regression-guard`, `scraper-resilience`, `route-optimizer-qa`,
`spreadsheet-delivery-check`, `frontend-visual-qa`, `codex-*` (11 wrappers),
`context-preload`, `context-digest`, `context-health`, `smart-token-metering`,
`lazy-opus-review`, `competition`, `parallel-impl`, `headless-validation`, `health`.

---

## Global Skills (deployed to ~/.claude/skills/ by install.sh)

These skills are slash commands invokable directly in Claude Code. Installed automatically via `bash .agents/hooks/install.sh`.

### Canuto Core

| Command | Description | Tags |
|---------|-------------|------|
| `/office-hours` | YC Office Hours — reframe product idea before coding. Asks forcing questions, generates 3 approaches, saves context for Architect. | product, planning |
| `/investigate` | Forensic debugger — Iron Law: no fix without confirmed root cause. Read-only investigation phase first. | debugging |
| `/document-release` | Post-ship documentation sweep — updates README, FEATURE-MAP.md, .context.md, CHANGELOG after a deploy. | documentation, workflow |
| `/retro` | Weekly retrospective — reads metrics.md, audit-log.md, instincts.md to generate Shipped / Delayed / Learned / Next. | learning, memory |
| `/auto-analysis` | Deep project scan + cross-reference with other vault projects. Generates project-index.json and onboarding-report.md. | analytics, onboarding |
| `/vault-maintenance` | Periodic vault cleanup — archives old sessions, aggregates metrics/audits, cleans snapshots. | maintenance, vault |
| `/vault-sync` | Syncs `.agents/.cache/pending-sync/` back into the active vault or legacy memory backend after offline work. | maintenance, vault, offline |

### Design Skills (via Impeccable)

| Command | Description | Tags |
|---------|-------------|------|
| `/audit` | Systematic multi-dimensional quality scan: a11y, performance, responsiveness, anti-patterns. Severity-prioritized issue list. | design, quality |
| `/animate` | Strategic motion pass — adds or fixes animations with purpose. Distinguishes entrance, micro-interaction, state, and delight. | design, motion |
| `/bolder` | Amplifies safe or generic designs into memorable, distinctive experiences without falling into AI slop. | design |
| `/polish` | Final pre-ship checklist: spacing consistency, all interaction states, keyboard nav, responsive edge cases. | design, quality |
| `/critique` | Holistic UX/design evaluation — hierarchy, information architecture, emotional resonance, discoverability. 10-dimension assessment. | design, ux |
| `/typeset` | Focused typography audit: font choices, size scale, weight contrast, line length, pairing strategy. | design, typography |
| `/harden` | Production resilience: text overflow, i18n, error handling, edge cases, accessibility under stress. | quality, a11y |
| `/colorize` | Strategic color introduction — 60/30/10 balance, OKLCH palettes, semantic color roles. | design, color |
| `/overdrive` | Technically ambitious interfaces: View Transitions, scroll-driven animations, WebGL, virtual scrolling, Web Audio. | design, advanced |
| `/clarify` | Microcopy and interface text improvement — every word earns its place. Error messages, empty states, button copy. | design, copy |

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
