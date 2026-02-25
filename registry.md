# Canuto Framework — Skill Registry

> Community and official skills installable via `bash install.sh --skill <name>`
>
> To contribute: open a PR adding an entry to the Community Skills table and providing the skill file in `.agents/skills/`.

---

## Official Skills

These skills ship with the framework and are installed by default.

| Name | Description | File | Tags |
|------|-------------|------|------|
| `context-maintenance` | How to maintain `.context.md` and `FEATURE-MAP.md` | `.agents/skills/context-maintenance.md` | core, documentation |
| `api-design` | How to design and evolve HTTP/JSON APIs | `.agents/skills/api-design.md` | core, backend |
| `frontend-implementation` | How to implement frontend features | `.agents/skills/frontend-implementation.md` | core, frontend |
| `cli-usage` | How to safely use CLI commands and scripts | `.agents/skills/cli-usage.md` | core, devops |
| `security-practices` | Rules for secrets, env vars, and security hygiene | `.agents/skills/security-practices.md` | core, security |
| `git-workflow` | Branching, commits, and PR conventions | `.agents/skills/git-workflow.md` | core, workflow |
| `plugin-system` | How to create and manage opt-in plugins | `.agents/skills/plugin-system.md` | core, extensibility |
| `multi-provider` | How Maestro delegates to Claude, Codex, GLM | `.agents/skills/multi-provider.md` | core, orchestration |
| `metrics` | Quality, velocity, and compliance tracking | `.agents/skills/metrics.md` | core, analytics |
| `squads` | Parallel domain-based workstreams | `.agents/skills/squads.md` | core, orchestration |
| `session-goals` | Track session goals with completion status | `.agents/skills/session-goals.md` | workflow, productivity |
| `pr-description` | Auto-generate PR descriptions after review | `.agents/skills/pr-description.md` | workflow, git |
| `adr` | Architecture Decision Records with structured templates | `.agents/skills/adr.md` | architecture, documentation |
| `health-check` | Diagnose framework setup integrity | `.agents/skills/health-check.md` | devops, diagnostics |

---

## Installing a Specific Skill

If you removed a skill or want to add one from the registry:

```bash
# Install a single skill
bash install.sh --skill adr

# Install multiple skills
bash install.sh --skill adr --skill pr-description --skill session-goals
```

The installer downloads the skill file to `.agents/skills/` and offers a git commit.

---

## Community Skills

> None yet. Be the first to contribute!

To contribute a skill:
1. Fork [csorodrigo/canuto-framework](https://github.com/csorodrigo/canuto-framework)
2. Add your skill file to `.agents/skills/`
3. Add an entry below (name, description, file, author, tags)
4. Open a PR

| Name | Description | File | Author | Tags |
|------|-------------|------|--------|------|
| *(none yet)* | | | | |
