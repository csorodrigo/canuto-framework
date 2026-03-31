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
| `api-design` | How to design and evolve HTTP/JSON APIs | backend |
| `api-docs-fetch` | Fetch current API/SDK docs via Context Hub (chub) before coding — prevents hallucination | documentation, api |
| `audit-trail` | Immutable append-only log of all significant session events | observability |
| `brand-bootstrap` | Extract brand identity from existing websites | design, branding |
| `budget-controls` | Token/cost budgets per persona and session with advisory warnings | cost-management |
| `cli-usage` | How to safely use CLI commands and scripts | devops |
| `context-maintenance` | How to maintain `.context.md`, `FEATURE-MAP.md`, and Repo Index (evaluate-repo pipeline) | documentation, indexation |
| `continuous-learning` | Extract, store, and evolve reusable patterns (instincts) from session experience | learning, memory |
| `convergence-detection` | Detect when multiple personas independently reach the same conclusion | observability |
| `coverage-tracking` | Track exploration depth across personas, areas, and concerns for M/L tasks | observability |
| `cross-persona-flags` | Outbound flags between personas for lateral discovery via Maestro | orchestration |
| `defuddle` | Extract clean markdown from web pages (token-efficient) | web, ingestion |
| `experiment-loop` | Systematic experiment loops — change, test, measure, keep/discard, repeat | optimization, experimentation |
| `frontend-design` | Visual design consistency with tunable design knobs (variance, motion, density) | design, frontend |
| `frontend-implementation` | How to implement frontend features | frontend |
| `git-workflow` | Branching, commits, and PR conventions | workflow |
| `governance` | Approval gates for high-impact actions (deploy, migration, breaking changes) | governance |
| `health-check` | Diagnose framework setup integrity | diagnostics |
| `heartbeat` | Foundation for scheduled agent activation in autonomous setups | orchestration, future |
| `json-canvas` | JSON Canvas: visual maps and flowcharts (.canvas files) | obsidian, visualization |
| `knowledge-ingest` | Ingest external sources (videos, articles, PDFs, meeting transcripts) into structured vault notes | ingestion, knowledge, memory |
| `mcp-obsidian` | How the framework uses MCP to interact with the vault (+ semantic search, multi-MCP connectors) | obsidian, mcp, memory |
| `metrics` | Quality, velocity, compliance, and rework tracking | analytics |
| `multi-provider` | How Maestro delegates to Claude, Codex, GLM | orchestration |
| `obsidian-bases` | Obsidian Bases: database views over notes (.base files) | obsidian, queries |
| `obsidian-cli` | Interact with Obsidian vault via CLI | obsidian, cli |
| `obsidian-markdown` | Obsidian Flavored Markdown: wikilinks, embeds, callouts, properties, tags | obsidian, markdown |
| `plan-second-opinion` | Legacy planning reference for hook-triggered Codex review flows | planning, review, compatibility |
| `plugin-system` | How to create and manage opt-in plugins | extensibility |
| `pr-description` | Auto-generate PR descriptions after review | workflow |
| `research` | Structured investigation workflow with community intelligence (Reddit, HN, X), codebase scan, and vault lookup | research, planning |
| `runtime-flags` | Session-scoped behavioral overrides (FAST_MODE, STRICT_MODE, etc.) | configuration |
| `security-practices` | Rules for secrets, env vars, and security hygiene | security |
| `squads` | Parallel domain-based workstreams | orchestration |
| `stack-lock` | Prevent library drift via approved stack | governance, dependencies |
| `vault-sync` | Flush offline pending-sync entries back into vault or legacy memory | obsidian, memory, offline |

---

## Optional Skills (install on demand)

Useful in specific project types. Install with `bash install.sh --skill <name>`.

| Name | Description | Best for | Tags |
|------|-------------|----------|------|
| `session-goals` | Track session goals explicitly in a separate skill file | Teams or highly structured workflows | productivity |
| `adr` | Architecture Decision Records | Long-lived projects with multiple contributors | architecture |
| `product-review` | When/how to run /office-hours + /plan-ceo-review before Architect on L/XL features | Product-heavy projects, new features with uncertain scope | product, planning |
| `browser-qa` | Real-browser QA via gstack + authenticated data extraction via Chrome DevTools MCP | Projects with web frontends, critical user flows | testing, quality, scraping |

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
