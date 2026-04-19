shortDescription: Close sessions by extracting proposed memory, decisions, pending tasks, metrics, and learning notes before any write-back.
usedBy: [maestro]
version: 1.0.0
lastUpdated: 2026-04-17
copyright: Rodrigo Canuto © 2026.

## Purpose

Convert the end of each work session into durable learning. The skill captures what happened, what failed, what was repeated, and what should become memory. It is report-first: show proposed writes before changing `.agents/memory/` or any Obsidian/Canuto vault.

---

## When To Run

Run at session end, before the final summary, and after any task with:

- failed tests or failed tool calls
- repeated implementation attempts
- review fix cycles
- unresolved decisions
- unfinished tasks
- changed project assumptions

---

## Procedure

1. Summarize the session in 3-7 bullets.
2. Mark session goals as achieved, deferred, or not started.
3. Extract concrete pending tasks.
4. Extract decisions that future sessions must know.
5. Extract rework and error signals.
6. Extract candidate instincts: short reusable lessons that reduce future mistakes.
7. Build a write plan:
   - `.agents/memory/last-session.md`
   - `.agents/memory/pending.md`
   - `.agents/memory/decisions.md`
   - `.agents/memory/metrics.md`
   - Canuto vault `projects/<slug>/...` if configured and approved
8. Ask for approval before writing outside the normal session memory flow.

---

## Candidate Instinct Rules

A candidate instinct is worth proposing when it is:

- caused by a real failure, not a theoretical concern
- likely to happen again
- specific enough to change future behavior
- short enough to read during session start

Bad instinct: "Be careful with tests."
Good instinct: "For dashboard date filters, test timezone boundaries with a fixed fixture before touching UI code."

---

## Output Format

```markdown
## Session Learning Draft - YYYY-MM-DD

### Session Summary
- <what changed>

### Goals
- ✅/⏳/❌ <goal> - <evidence>

### Proposed Pending Tasks
- [ ] <specific next action>

### Proposed Decisions
- <decision and reason>

### Proposed Instincts
- <short reusable lesson>

### Metrics
- Review verdict: APPROVE | REQUEST CHANGES | N/A
- Test failures: N/M or N/A
- Rework cycles: N
- Rework files: <paths or none>
- Escalations: N

### Proposed Writes
| Target | Action | Approval Needed |
|--------|--------|-----------------|
| `.agents/memory/last-session.md` | overwrite | normal session close |
| `.agents/memory/pending.md` | append/update | yes if removing/deduping |
```

---

## Guardrails

- Never silently write to Obsidian, the Canuto vault, or external memory.
- Never record vague pending items. Pending tasks must be directly actionable.
- Never fabricate metrics. Use `N/A` when not measured.
- Do not duplicate an existing decision or pending item. Reference it instead.
- Keep the final written memory concise; long evidence belongs in the chat/session log.
