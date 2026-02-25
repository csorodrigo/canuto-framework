# Canuto Framework — Skill Registry

> Community and official skills installable via `bash install.sh --skill <name>`
>
> To contribute: open a PR adding an entry to the Community Skills table and providing the skill file in `.agents/skills/`.

---

## Core Skills (installed by default)

These skills ship with every install and update automatically.

| Name | Description | Tags |
|------|-------------|------|
| `context-maintenance` | How to maintain `.context.md` and `FEATURE-MAP.md` | documentation |
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

---

## Optional Skills (install on demand)

Useful in specific project types. Install with `bash install.sh --skill <name>`.

| Name | Description | Best for | Tags |
|------|-------------|----------|------|
| `session-goals` | Track session goals explicitly in a separate skill file | Teams or highly structured workflows | productivity |
| `adr` | Architecture Decision Records | Long-lived projects with multiple contributors | architecture |

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
