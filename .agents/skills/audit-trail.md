shortDescription: Maintain an immutable, append-only log of all significant mutations during sessions.
usedBy: [maestro]
version: 1.0.0
lastUpdated: 2026-03-18
copyright: Rodrigo Canuto © 2026.
inspiration: Paperclip — immutable audit logging with complete mutation history for compliance and debugging.

## When to Use

**Triggers:**
- Every persona handoff (log the transition)
- Every governance gate decision (log approval/rejection)
- Every rework event (log the re-implementation trigger)
- Every escalation (log the issue and resolution)
- Session start and end (log lifecycle events)

**Not for:**
- Individual code changes (that's git history)
- Internal persona reasoning (that's the handoff content)

---

## Purpose

`decisions.md` captures architectural/business decisions. The **audit trail** captures everything else that happened — handoffs, gates, rework, escalations, failures. It answers: **"What happened, when, and why?"**

This creates a forensic timeline of the session, enabling post-mortem analysis and pattern detection across sessions.

---

## Concepts

### Audit Event Types

| Type | Code | When Logged |
|------|------|-------------|
| Session start | `SESSION_START` | Session begins |
| Session end | `SESSION_END` | Session closes |
| Handoff | `HANDOFF` | Persona transition |
| Gate decision | `GATE` | Governance gate approved/rejected |
| Rework | `REWORK` | File modified 3+ times |
| Escalation | `ESCALATION` | Persona reports unexpected issue |
| Flag | `FLAG` | Cross-persona flag emitted |
| Budget warning | `BUDGET` | Token budget threshold reached |
| Instinct | `INSTINCT` | New instinct extracted or reinforced |

### Audit Entry Format

```markdown
#### [YYYY-MM-DD HH:MM] TYPE — summary
- **Detail:** what happened
- **Actor:** which persona
- **Impact:** what changed as a result
```

---

## Procedure

### Storage

File: `.agents/memory/audit-log.md`

Structure:
```markdown
# Audit Log

> Append-only record of significant session events.
> Each session appends a dated section. Never edit previous entries.

---

## Session 2026-03-18

#### [2026-03-18 10:00] SESSION_START — Session opened
- **Goals:** Implement user registration, add email validation
- **Pending from last session:** Write integration tests for auth

#### [2026-03-18 10:05] HANDOFF — Maestro → Architect
- **Detail:** Planning user registration feature (Task M)
- **Actor:** Maestro
- **Impact:** Architect interview started

#### [2026-03-18 10:25] GATE — migration approved
- **Detail:** Add users table with email uniqueness constraint
- **Actor:** User (via governance gate)
- **Impact:** Coder proceeds with migration

#### [2026-03-18 11:15] REWORK — src/api/auth/register.ts modified 3 times
- **Detail:** First attempt had validation bug, second had type error
- **Actor:** Coder (triggered by Debugger diagnosis)
- **Impact:** Rework warning issued, consider re-planning

#### [2026-03-18 12:00] SESSION_END — Session closed
- **Goals:** ✅ User registration, ⏳ Email validation (deferred)
- **Events logged:** 8
- **Rework incidents:** 1
```

### Writing Entries

Maestro appends entries in real-time as events occur. Rules:

1. **Never edit previous entries.** Append only.
2. **Timestamp every entry.** Use `[YYYY-MM-DD HH:MM]` format.
3. **Keep entries concise.** 2-3 lines max per entry.
4. **Log failures too.** Failed handoffs, rejected gates, dismissed flags — all are logged.

### Session Summary

At session end, Maestro adds a summary entry:

```markdown
#### [2026-03-18 12:00] SESSION_END — Summary
- **Duration:** ~2 hours
- **Events logged:** 12
- **Handoffs:** 6 (Maestro→Architect, Architect→Coder, Coder→Tester, Tester→Reviewer, Maestro→Debugger, Debugger→Coder)
- **Gates triggered:** 1 (migration — approved)
- **Rework incidents:** 1 (src/api/auth/register.ts)
- **Flags emitted:** 2 (1 resolved, 1 deferred)
- **Goals:** 1/2 completed
```

---

## Examples

### ✅ Good — concise, timestamped, actionable entries

```markdown
#### [2026-03-18 14:30] ESCALATION — Coder reports missing dependency
- **Detail:** `zod` not in package.json but referenced in Architect plan step 2
- **Actor:** Coder
- **Impact:** Maestro added `zod` installation to plan, re-routed to Coder

#### [2026-03-18 14:45] FLAG — Coder → Tester (suggest)
- **Detail:** Email validation regex may not handle unicode — src/utils/validate.ts:23
- **Actor:** Coder
- **Impact:** Queued for Tester pass
```

### ❌ Bad — verbose, narrative-style log

```markdown
#### Session notes
So we started by talking about the auth feature and the Architect came up with a plan
that looked pretty good. Then the Coder implemented it but there were some issues with
the validation logic that needed to be fixed a couple of times...
```

This is bad because: not structured, no timestamps, no event types, not searchable or parseable.

---

## Guardrails

- **Append-only.** Never modify or delete previous entries. The audit trail is immutable.
- **Keep it lean.** Each entry is 2-3 lines. The audit log should not become a session transcript.
- **Log events, not content.** Don't duplicate the handoff content — just note that a handoff happened.
- **One session per section.** Use `## Session YYYY-MM-DD` headers to separate sessions.
- **Don't log routine messages.** Only log the event types defined above. Not every Maestro message is an audit event.
- **Audit log is for forensics.** It complements, not replaces, `decisions.md` (for decisions) and `metrics.md` (for numbers).
