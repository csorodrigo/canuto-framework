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

## Guardrails

- Never skip the goals prompt on session start. Even a quick task benefits from an explicit goal.
- Goals should be outcome-oriented, not task-oriented. "Authentication works end-to-end" is better than "Write auth code".
- Never mark a goal ✅ without actual evidence of completion (Reviewer APPROVE, tests passing, etc.).
- If the user skips the goals prompt, set a single inferred goal based on what they said they wanted.
- Maximum 3 goals per session. Focus over coverage.
