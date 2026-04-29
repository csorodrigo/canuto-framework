---
skill: codex-pr-writer
trigger: /pr-write, or whenever PR prose is needed — keywords "pull request description", "PR body", "PR summary", "PR writeup", "describe this PR", "summary for merge", "changelog entry", "release notes entry", "merge message", "write up this diff"
persona: maestro
version: 1.1.0
lastUpdated: 2026-04-17
shortDescription: >
  Codex generates PR description, merge summary, and changelog from git diff. Opus only
  validates. Fires before any PR creation or when a human asks for a writeup of pending changes.
  70% savings on documentation tasks.
usedBy: [maestro]
evals:
  - prompt: "write a PR description for these changes"
    should_trigger: true
  - prompt: "generate changelog from the diff"
    should_trigger: true
  - prompt: "describe the pull request body for this branch"
    should_trigger: true
  - prompt: "write the merge summary before I push"
    should_trigger: true
  - prompt: "draft release notes from main...HEAD"
    should_trigger: true
  - prompt: "summarize what changed in this PR"
    should_trigger: true
  - prompt: "review the code"
    should_trigger: false
  - prompt: "run the tests"
    should_trigger: false
---

## Purpose

PR descriptions and changelogs require reading diffs, understanding context,
and writing structured markdown. Delegating to Codex: Opus saves ~10-20K tokens
per PR. Codex reads the diff directly from git.

---

## Procedure

### 1. Spawn Codex PR Writer

```bash
codex exec --color never --profile coder \
  -o /tmp/codex-pr-writer-$$.md \
  "$(cat <<'PROMPT'
Generate a pull request description and changelog entry.

## Instructions
1. Run: git log main...HEAD --oneline
2. Run: git diff main...HEAD --stat
3. Run: git diff main...HEAD (full diff)
4. Write the PR description to .agents/tmp/pr-description.md
5. Write changelog entry to .agents/tmp/changelog-entry.md

## PR Description Format
## Summary
<3-5 bullet points describing what changed and why>

## Changes
<grouped by area: backend, frontend, infra, docs>

## Test Plan
<how to verify these changes work>

## Breaking Changes
<list any breaking changes, or "None">

## Changelog Entry Format
### [version] - {date}
#### Added
- ...
#### Changed
- ...
#### Fixed
- ...

## Rules
- Focus on WHY, not WHAT (the diff shows what)
- Group related changes
- Highlight breaking changes prominently
- Keep PR description under 30 lines
- Keep changelog concise
PROMPT
)"
```

### 2. Opus Validates

Read `.agents/tmp/pr-description.md` and validate:
- Accurate reflection of changes?
- Any sensitive info leaked?
- Tone appropriate?

### 3. Create PR

Use the validated description with `gh pr create`.

---

## Integration

- **/ship skill**: uses this for PR description generation
- **cost-routing.md**: documentation → Codex (70% savings)
- **pr-description.md**: existing skill can delegate to this
