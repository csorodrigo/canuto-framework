---
type: index
purpose: Track codex-reviewer threadIds for cross-session review continuity
created: 2026-03-30
tags:
  - review-threads
  - sessions
---

# Review Threads — Session Continuity

Persist `threadId` from `mcp__codex-reviewer__codex` responses here.
Use `mcp__codex-reviewer__codex-reply(threadId, message)` to resume.

## Active Threads

| Date | Branch | Review Type | threadId | Status | Notes |
|------|--------|-------------|----------|--------|-------|
| — | — | — | — | — | No threads yet |

## Usage

### Save after review:
```
| 2026-03-30 | feat/auth | co-validate | thread_abc123 | open | Initial plan review |
```

### Resume in next session:
```
mcp__codex-reviewer__codex-reply({
  threadId: "thread_abc123",
  message: "Issues from last review have been fixed. Updated diff: ..."
})
```

### Close after merge:
Change status from `open` to `closed`.

## Archive

Threads older than 30 days are archived by `/vault-maintenance`.
