shortDescription: Track session goals from start to finish, with Maestro marking completion at end.
usedBy: [maestro]
version: 1.0.0
lastUpdated: 2026-02-25
copyright: Rodrigo Canuto © 2026.

## When to Use

**Triggers:**
- Session start — Maestro always prompts for goals after the session briefing
- Session end — Maestro marks each goal ✅ / ⏳ / ❌ before writing `last-session.md`
- User skips goals prompt — Maestro infers and records goals from conversation
- User says: `"continue"`, `"pick up where we left off"`, `"targeted session"`, `"fresh start"`

**Not for:**
- Mid-task goal changes (capture those as deviations in the session, not as new goals)

---

## Purpose

Give every session a clear direction and a measurable outcome. At session start, the user defines up to 3 goals. At session end, each goal is marked ✅ achieved or ⏳ carried forward.

---

## Procedure

### On Session Start

After presenting the session briefing, Maestro asks:

> "What are your top goals for this session? (up to 3)"

If the user provides goals, Maestro stores them in-session and includes them in `last-session.md` under `## Goals` when writing the session summary.

If the user skips this step, Maestro infers goals from the conversation and records them at session end.

---

### Goal Format

```markdown
## Goals

- [ ] Goal 1 description
- [ ] Goal 2 description
- [ ] Goal 3 description (optional)
```

---

### On Session End

Before writing `last-session.md`, Maestro reviews each goal and marks:

- `✅` if the goal was fully achieved.
- `⏳` if partially done or deferred.
- `❌` if not started.

Example:

```markdown
## Goals

- ✅ Implement JWT authentication endpoint
- ⏳ Write integration tests (auth done, refresh token tests pending)
- ❌ Update API documentation (ran out of context)
```

---

### Carrying Forward Deferred Goals

Any goal marked `⏳` or `❌` is automatically surfaced in the **next session briefing** as a pending item:

```
Session Briefing:
- Last session (2026-02-25): [summary]
- Deferred goals:
  ⏳ Write integration tests (auth done, refresh token tests pending)
  ❌ Update API documentation
- Stale contexts: none
- Pending tasks: none
```

---

## Examples

### ✅ Good — outcome-oriented goals with honest end-of-session marking

```markdown
## Goals

- ✅ JWT authentication works end-to-end (login, refresh, logout)
- ⏳ Integration tests for auth flow (login done, refresh token tests pending)
- ❌ Update API documentation (ran out of context window)
```

Outcome-oriented ("works end-to-end"), not task-oriented ("write auth code"). Marking is honest — partial work is ⏳, not ✅.

### ❌ Bad — task-oriented goals, over-optimistic marking

```markdown
## Goals

- ✅ Write auth code
- ✅ Write tests
- ✅ Update docs
```

This is bad because: "write auth code" is a task, not an outcome — you can write code that doesn't work. Marking everything ✅ without evidence (Reviewer APPROVE, tests passing) obscures real progress.

---

---

## Session Continuation Modes

> Inspired by pgs-engine's execution modes (full, continue, targeted) — applied to session lifecycle.

When starting a session, Maestro detects or asks for the session mode:

### Mode: `full` (default)

Fresh start. New goals, clean slate. Previous pending tasks are surfaced in the briefing but don't auto-carry.

**When to use:** New feature work, new sprint, or when previous context is no longer relevant.

```
Session mode: full (fresh start)
Goals: [user provides new goals]
```

### Mode: `continue`

Resume where the last session left off. Pending tasks become the session's goals. Maestro skips the goals prompt and uses `pending.md` directly.

**When to use:** User says "continue", "pick up where I left off", or there are significant pending tasks.

```
Session mode: continue
Resuming from last session (2026-03-17):
- ⏳ Write integration tests for refresh token endpoint
- ⏳ Add rate limiting to auth endpoints
- ❌ Update API documentation

These become your session goals. Adjust? [Y/n]
```

### Mode: `targeted`

Focus on a specific area or concern. Maestro narrows scope and skips unrelated pending tasks.

**When to use:** User has a specific urgent fix, investigation, or focused task.

```
Session mode: targeted
Focus: Debug the payment webhook timeout issue
Pending tasks deferred: [3 items from pending.md — not relevant to this focus]
```

### Mode Detection

Maestro infers the mode from user signals:

| Signal | Inferred Mode |
|--------|---------------|
| "Continue", "pick up", "where we left off" | `continue` |
| "Quick fix", "just this one thing", "focused on X" | `targeted` |
| New goals, no reference to previous work | `full` |
| Ambiguous | Ask the user |

### Mode Logging

Session mode is recorded in `last-session.md` and `audit-log.md`:

```markdown
- Session mode: continue (resumed 2 pending tasks from 2026-03-17)
```

---

## Guardrails

- Never skip the goals prompt on session start. Even a quick task benefits from an explicit goal.
- Goals should be outcome-oriented, not task-oriented. "Authentication works end-to-end" is better than "Write auth code".
- Never mark a goal ✅ without actual evidence of completion (Reviewer APPROVE, tests passing, etc.).
- If the user skips the goals prompt, set a single inferred goal based on what they said they wanted.
- Maximum 3 goals per session. Focus over coverage.
