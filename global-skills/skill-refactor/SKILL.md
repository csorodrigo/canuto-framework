---
name: skill-refactor
description: Stage resumable, reviewable refactor candidates for a complete skill estate without mutating live skills.
metadata:
  short-description: Compile isolated skill refactor candidates
---

# Skill Refactor

Use `canuto-skill-refactor` to compile logical skills into an isolated staging
workspace. The compiler is report-and-stage only: it never applies, installs,
archives, deletes, rewires, or modifies a live skill.

## Workflow

1. Run `canuto-skill-refactor --json doctor` and resolve blocked prerequisites.
2. Run `canuto-skill-refactor --json scan --workspace <absolute-staging-dir>`
   with an optional `--config <path>` to inventory configured roots and snapshot
   safe REFACTOR sources.
3. Inspect the bounded work queue with `queue` and one item with `preview
   --name <skill>`.
4. Run `run --workspace <dir>` with the default bounded workers, or continue an
   interrupted run with `run --workspace <dir> --resume`.
5. Run `validate --workspace <dir>` before any separate human review or apply
   gate.

Only candidates inside the workspace are writable by the delegate. Treat
`BLOCKED_PROVENANCE`, source mutation, secret quarantine, failed validation,
and missing receipts as explicit gates; do not infer permission to repair live
skills from a candidate.
