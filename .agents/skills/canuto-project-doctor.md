shortDescription: Diagnose Canuto installation, memory coverage, stale context, and learning-loop health before work starts.
usedBy: [maestro, reviewer]
version: 1.0.0
lastUpdated: 2026-04-17
copyright: Rodrigo Canuto © 2026.

## Purpose

Run a read-only project diagnosis that explains whether this repository is ready for productive agent work. This skill turns framework drift, stale context, missing memory, missing skills, and repeated rework signals into a concrete remediation list.

Use it before risky work, after framework updates, or when a project feels confusing, stale, or inconsistent.

---

## Inputs To Check

- `CLAUDE.md`
- `.agents/SPEC.md`
- `.agents/personas/`
- `.agents/skills/`
- `.agents/memory/last-session.md`
- `.agents/memory/pending.md`
- `.agents/memory/decisions.md`
- `.agents/memory/metrics.md`
- `.context.md` files and `docs/FEATURE-MAP.md`
- Git status and recent commits, if shell access is allowed.
- Canuto vault project directory, if configured or discoverable.

This skill is read-only. Do not edit files during the diagnosis.

---

## Checklist

### Framework Installation

- Required personas are present.
- Required core skills are present.
- `CLAUDE.md` contains Framework, Preferences, Project Rules, and On Session Start sections.
- Installed skill versions look internally consistent.

### Memory Coverage

- `last-session.md` has a useful recent summary.
- `pending.md` contains concrete tasks, not broad intentions.
- `decisions.md` records architectural or product decisions when they exist.
- `metrics.md` has recent session entries, or the absence is explained.

### Learning Loop

- Session-end workflow captured done work, pending work, decisions, metrics, and rework signals.
- Errors and repeated attempts were promoted into decisions, pending items, or instincts.
- If Obsidian/Canuto vault is used, local memory and vault notes do not contradict each other.

### Stale Context

- `.context.md` files are newer than the source directories they summarize, or stale areas are listed.
- `docs/FEATURE-MAP.md` still matches current user-facing flows.
- Dirty files are grouped by likely intent: implementation, generated output, docs, temporary, unknown.

### Project Alignment

- The project is classified as Canuto, foreign-schema, or new.
- Conductor repo/workspace path and vault project path are linked, or the missing link is reported.
- Optional domain skills are installed only when useful for this project type.

---

## Output Format

```markdown
## Canuto Project Doctor - YYYY-MM-DD

### Verdict: HEALTHY | DEGRADED | BROKEN

### Findings
| Area | Status | Evidence | Impact |
|------|--------|----------|--------|
| Framework | OK/WARN/FAIL | <path or observation> | <why it matters> |

### Immediate Fixes
1. <highest leverage fix>
2. <next fix>

### Optional Improvements
- <domain skill or workflow to install/adapt>

### Do Not Start Yet If
- <blocking condition, or "none">
```

---

## Guardrails

- Never modify files during the doctor run.
- Never mark the project HEALTHY if required personas, core skills, or memory files are missing.
- Do not require Canuto schema for foreign-schema projects. Diagnose and adapt.
- Prefer a short, actionable report over a full file dump.
- If the project is BROKEN, Maestro must present the diagnosis before delegating any work.
