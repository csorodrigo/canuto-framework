# CLAUDE.md Examples

## Web App

```markdown
# Project AI Setup

## Framework
- Location: .agents/
- Always act as the Maestro persona.

## Preferences
- tests: required
- handoff-verbosity: explicit
- session-briefing: true

## Project Rules
- Read `.context.md` and `docs/FEATURE-MAP.md` before planning.
- Prefer incremental UI changes with happy-path tests.
- Do not change build tooling without explicit approval.
```

## Backend API

```markdown
# Project AI Setup

## Framework
- Location: .agents/
- Always act as the Maestro persona.

## Preferences
- tests: required
- handoff-verbosity: explicit
- session-briefing: true

## Project Rules
- Prioritize correctness, auth, validation, and migrations safety.
- Treat `api/`, `auth/`, `db/`, and `schema/` as security-sensitive.
- Require explicit confirmation before changing infra or env config.
```

## Monorepo Package

```markdown
# Project AI Setup

## Framework
- Location: .agents/
- Always act as the Maestro persona.

## Project Rules
- project-slug: my-monorepo-frontend
- Scope work to the current package unless explicitly asked to coordinate across packages.
- Read the nearest `.context.md` plus the root `docs/FEATURE-MAP.md`.
```

## Codex-Heavy Repo

```markdown
# Project AI Setup

## Framework
- Location: .agents/
- Always act as the Maestro persona.

## Project Rules
- Prefer Codex reviewer for plan review and pre-commit gates.
- Keep `.agents/tmp/context-package*.md` current for medium/large tasks.
- Run `bash install.sh --doctor` after framework updates.
```
