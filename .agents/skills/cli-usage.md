shortDescription: How to safely use project CLI commands and scripts.
usedBy: [coder, maestro, reviewer]
version: 1.0.0
lastUpdated: 2026-02-25
copyright: Rodrigo Canuto © 2026.

## Purpose

Ensure that terminal commands and scripts (build, test, lint, migrations, seeds, tools) are used in a way that is:
- Reproducible.
- Safe (no accidental data loss).
- Consistent across different projects.

---

## Procedure

### 1. Discover Available Commands

1. Look for:
   - Scripts in `package.json` (npm/yarn/pnpm).
   - Makefile, Justfile, Taskfile, or similar.
   - Scripts in `bin/`, `scripts/`, `tools/` directories.
2. If documentation exists:
   - Read README, internal docs, or `.context.md` for the scripts directory.

### 2. Choose the Right Way to Run

1. Always prefer:
   - Declared scripts (`npm run build`, `yarn test`, `pnpm lint`) over raw long commands.
   - Named targets in Make/Just over pasting complex commands.
2. Before running:
   - Explain what the command will do (in plain language).
   - Check if it requires environment variables or external services (database, queue, etc.).

### 3. Development Commands

1. For dev servers, watchers, hot-reload:
   - Clearly explain how to start and stop.
   - Avoid running multiple servers on the same port.
2. For tests:
   - Use the project's standard test command.
   - When running a subset of tests, explain the criteria (by file, tag, pattern, etc.).

### 4. Dangerous Commands

Classify a command as "dangerous" if it:
- Deletes data (database drop, storage cleanup).
- Resets state in a shared environment.
- Deploys or modifies infrastructure.

For dangerous commands:
1. Only execute with **explicit user approval**.
2. Repeat the proposed command and its target (e.g., "This runs against staging, not production. Confirm?").
3. If possible, suggest a dry-run alternative first.

### 5. Integration with Plan and Docs

1. When the Architect includes CLI steps (run migrations, setup scripts):
   - Follow exactly what was planned, or explain why you need to change it.
2. Canuto project:
   - Update `.context.md` in script directories when new scripts are created or responsibilities change.
3. Foreign-schema project:
   - Update script docs/README if they exist.

---

## Guardrails

- Do not invent long commands if an equivalent script exists.
- Do not execute destructive commands without clear confirmation, even if the user vaguely suggests it.
- Do not assume sensitive environment variables. If they are missing, ask instead of guessing values.
