---
type: index
purpose: Track Codex reviewer CLI artifacts for cross-session review continuity
created: 2026-03-30
tags:
  - review-threads
  - sessions
---

# Review Threads — Session Continuity

Persist the review artifact path produced by `codex exec --profile reviewer`.
To resume, re-run `codex exec --profile reviewer` with the previous artifact plus the updated diff in the prompt.

## Active Threads

| Date | Branch | Review Type | Provider | Task ID | Artifact | Status | Notes |
|------|--------|-------------|----------|---------|----------|--------|-------|
| — | — | — | — | — | — | — | No threads yet |

## Usage

### Save after review:
```
| 2026-03-30 | feat/auth | co-validate | codex-reviewer | task-auth-plan | .agents/tmp/codex/co-review-auth.md | open | Initial plan review |
```

### Resume in next session:
```
codex exec --color never --profile reviewer \
  -s read-only --skip-git-repo-check \
  -o .agents/tmp/codex/co-review-auth-rerun.md \
  "$(cat <<'PROMPT'
Previous review artifact: .agents/tmp/codex/co-review-auth.md
Issues from last review have been fixed. Review this updated diff:

--- CHANGES START ---
{updated_diff}
--- CHANGES END ---
PROMPT
)"
```

### Close after merge:
Change status from `open` to `closed`.

## Archive

Threads older than 30 days are archived by `/vault-maintenance`.
