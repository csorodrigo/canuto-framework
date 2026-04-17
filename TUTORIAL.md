# Canuto Framework v1.6 Tutorial

This tutorial explains how to install, update, use, and roll out the current Canuto Framework in real projects.

## 1. Install Canuto In A Project

From the root of the target project:

```bash
curl -fsSL https://raw.githubusercontent.com/csorodrigo/canuto-framework/main/install.sh | bash
```

The installer copies:

- `.agents/personas/`
- `.agents/skills/`
- `.agents/SPEC.md`
- `.agents/memory/`
- `CLAUDE.md`

It creates memory files only during fresh install. Updates do not overwrite project memory.

## 2. Update A Project

After this branch is merged into GitHub `main`, update an existing project with:

```bash
bash install.sh --update
```

If the project does not keep a local copy of `install.sh`, run the GitHub installer in update mode:

```bash
curl -fsSL https://raw.githubusercontent.com/csorodrigo/canuto-framework/main/install.sh | bash -s -- --update
```

The update mode refreshes personas, core skills, `.agents/SPEC.md`, and missing `CLAUDE.md` rules. It does not touch:

- `.agents/memory/`
- `.agents/plugins/`
- project source files

## 3. Validate A Branch Before GitHub Main Is Published

The v1.6 installer refreshes itself from `main` before applying normal project updates. When validating a framework branch before merge, run checks against the local checkout:

```bash
CANUTO_SOURCE_DIR="$PWD" bash install.sh --check
```

Use this only inside the `canuto-framework` repository or a disposable test setup. The normal project-safe path remains:

```bash
curl -fsSL https://raw.githubusercontent.com/csorodrigo/canuto-framework/main/install.sh | bash -s -- --update
```

Do not update many real projects from an unpublished branch unless the branch has passed `bash install.sh --test`, `CANUTO_SOURCE_DIR="$PWD" bash install.sh --check`, and at least one smoke install.

## 4. Verify A Project

Run:

```bash
bash install.sh --check
```

The check mode reports missing, outdated, or version-unknown framework files. Files without a `version:` frontmatter field are reported as unknown instead of failing the check.

## 5. Install Optional Skills

Core learning-loop skills ship by default. Optional domain skills are installed only when a project needs them.

Examples:

```bash
bash install.sh --skill dashboard-regression-guard
bash install.sh --skill scraper-resilience
bash install.sh --skill route-optimizer-qa
bash install.sh --skill spreadsheet-delivery-check
bash install.sh --skill frontend-visual-qa
```

Use `registry.md` to see the full skill list.

## 6. Start A Canuto Session

Open the project in Claude. Maestro should:

1. Read `CLAUDE.md`.
2. Load `.agents/personas/maestro.md`.
3. Read `.agents/memory/last-session.md`.
4. Read `.agents/memory/pending.md` and `.agents/memory/metrics.md` when present.
5. Check for stale context from dirty files or stale `.context.md` and `docs/FEATURE-MAP.md`.
6. Run `canuto-project-doctor` if setup, memory, or context looks suspicious.
7. Present a short session briefing.
8. Ask what to work on.

## 7. Work Through The Persona Flow

The normal flow is:

```text
Maestro -> Architect -> Coder -> Tester -> Reviewer
                              -> Debugger -> Coder -> Tester
```

Use this pattern:

- Architect plans the smallest coherent change.
- Coder implements and reports changed files.
- Tester validates behavior and edge cases.
- Debugger investigates concrete failures.
- Reviewer checks risk, tests, and PR readiness.
- Maestro coordinates handoffs and escalations.

## 8. Prevent Rework

`canuto-rework-detector` should run before continuing when there is evidence of repeated effort:

- Same test fails twice.
- Same file is changed three or more times in one session.
- Reviewer requests changes repeatedly in the same area.
- User says the approach was already tried.
- Pending tasks repeat across sessions.

The detector should output one practical guardrail before more implementation, such as adding a fixture, splitting the task, updating a decision, or re-planning.

## 9. Close The Session

Before the final answer, Maestro runs `canuto-session-end-learning` and drafts:

- Session summary.
- Goal status.
- Pending tasks.
- Decisions.
- Rework/error signals.
- Candidate instincts.
- Metrics.
- Proposed writes.

Local memory updates belong in `.agents/memory/`. Obsidian or Canuto vault writes must go through `obsidian-writeback-queue`.

## 10. Use Obsidian Or Canuto Vault Write-back

Default mode is preview. The framework must show:

- Vault path.
- Project slug.
- Target note path.
- Action: create, append, or update.
- Short content summary.
- Risk.

Live write mode requires explicit user approval and a verified write method: filesystem, Local REST API, or MCP bridge.

## 11. Roll Out Across Projects

Recommended rollout:

1. Merge the framework branch into `csorodrigo/canuto-framework` `main`.
2. Pick one active project and run `bash install.sh --update`.
3. Open the project in Claude and confirm session start uses the new learning-loop rules.
4. Run `bash install.sh --check`.
5. Install optional domain skills only where useful.
6. Repeat for the remaining projects.

## 12. Troubleshooting

| Problem | Fix |
|---------|-----|
| Installer says the source repo is the target | Run the command from the target project root, not from `canuto-framework`. |
| `--check` reports unknown versions | The file has no `version:` field. This is informational unless the file is also missing or outdated. |
| Project memory did not update | Updates intentionally do not overwrite `.agents/memory/`. Session-end learning updates memory at session close. |
| Obsidian write-back did not happen | Check whether the write was only previewed or queued. Live write requires explicit approval and a verified bridge. |
| Optional skill not found | Confirm the skill exists in `registry.md` and `.agents/skills/` on the selected source, local or GitHub. |
