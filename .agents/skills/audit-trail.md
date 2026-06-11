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
- Every monitor lifecycle event (log start, alerts, and stop)

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
| Monitor start | `MONITOR_START` | Background process monitoring begins |
| Monitor alert | `MONITOR_ALERT` | Pattern-matched alert during monitoring |
| Monitor stop | `MONITOR_STOP` | Background process monitoring ends |

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

Vault: `~/.canuto/vault/projects/{project-slug}/audit/`

Each audit event is an individual note with frontmatter:

```markdown
---
type: audit-event
event: HANDOFF
date: 2026-03-18T10:05:00
actor: maestro
session: "[[sessions/2026-03-18]]"
impact: low
tags:
  - audit
  - handoff
---

# Maestro → Architect

**Detail:** Planning user registration feature (Task M).

**Actor:** Maestro

**Impact:** Architect interview started.
```

Naming convention: `audit/YYYY-MM-DD-HHmm-EVENT-summary.md`

Include the time (HHmm) to avoid collisions when multiple events of the same type occur on the same day.

Examples:
- `audit/2026-03-18-1000-SESSION_START.md`
- `audit/2026-03-18-1005-HANDOFF-maestro-architect.md`
- `audit/2026-03-18-1025-GATE-migration-approved.md`
- `audit/2026-03-18-1200-SESSION_END.md`

Query audit events via `bases/audit-by-type.base` for grouped views by event type or actor.

### Writing Entries

Maestro creates individual audit notes in real-time as events occur. Rules:

1. **Never edit previous notes.** Create new notes only.
2. **Timestamp in frontmatter.** Use ISO format `YYYY-MM-DDTHH:mm:ss`.
3. **Keep entries concise.** 2-3 lines max per note body.
4. **Log failures too.** Failed handoffs, rejected gates, dismissed flags — all get their own note.
5. **Use wikilinks** to reference the session: `[[sessions/YYYY-MM-DD]]`.

### Session Summary

At session end, Maestro creates a SESSION_END audit note with summary:

```markdown
---
type: audit-event
event: SESSION_END
date: 2026-03-18T12:00:00
actor: maestro
session: "[[sessions/2026-03-18]]"
impact: low
tags:
  - audit
  - session-end
---

# Session closed

**Duration:** ~2 hours
**Events logged:** 12
**Handoffs:** 6
**Gates triggered:** 1 (migration — approved)
**Rework incidents:** 1 (src/api/auth/register.ts)
**Goals:** 1/2 completed
```

---

## Examples

### ✅ Good — concise, timestamped, actionable entries

```markdown
#### [2026-03-18 14:30] ESCALATION — Coder reports missing dependency
- **Detail:** `zod` not in package.json but referenced in Architect plan step 2
- **Actor:** Coder
- **Impact:** Maestro added `zod` installation to plan, re-routed to Coder

#### [2026-03-18 14:45] FLAG — Coder → Reviewer (suggest)
- **Detail:** Email validation regex may not handle unicode — src/utils/validate.ts:23
- **Actor:** Coder
- **Impact:** Queued for Reviewer pass
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

- **Immutable notes.** Never modify or delete previous audit notes. Create new notes only.
- **Keep it lean.** Each note body is 2-3 lines. Audit notes should not become session transcripts.
- **Log events, not content.** Don't duplicate the handoff content — just note that a handoff happened.
- **One note per event.** Each event gets its own file in `audit/`.
- **Don't log routine messages.** Only log the event types defined above. Not every Maestro message is an audit event.
- **Audit notes are for forensics.** They complement, not replace, `decisions/` (for decisions) and `metrics/` (for numbers).
- **Use wikilinks.** Always link to the session note: `[[sessions/YYYY-MM-DD]]`.
- **Query via Bases.** Use `bases/audit-by-type.base` for filtered/grouped views.
