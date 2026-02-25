shortDescription: Diagnose framework setup integrity and detect misconfigurations before they cause session failures.
usedBy: [maestro]
version: 1.0.0
lastUpdated: 2026-02-25
copyright: Rodrigo Canuto © 2026.

## Purpose

Detect broken or missing framework components before they silently degrade session quality. The health check can be triggered on demand or automatically when something seems off.

---

## Trigger

Run a health check when the user says:
- `"health check"`
- `"is the framework ok?"`
- `"diagnose"`
- `"check framework"`

Or when Maestro detects unexpected behavior (missing persona, corrupted memory file, incomplete handoff).

---

## Checklist

### CLAUDE.md
- [ ] File exists at project root.
- [ ] Contains `## Framework` section.
- [ ] Contains `## Preferences` section.
- [ ] Contains `## Project Rules` section.
- [ ] Contains `## On Session Start` section.

### Personas
- [ ] `.agents/personas/maestro.md` exists.
- [ ] `.agents/personas/architect.md` exists.
- [ ] `.agents/personas/coder.md` exists.
- [ ] `.agents/personas/tester.md` exists.
- [ ] `.agents/personas/debugger.md` exists.
- [ ] `.agents/personas/reviewer.md` exists.
- [ ] `.agents/personas/contextualizer.md` exists.

### Core Skills
- [ ] `.agents/skills/` directory is non-empty.
- [ ] `context-maintenance.md` present.
- [ ] `api-design.md` present.
- [ ] `metrics.md` present.

### Memory
- [ ] `.agents/memory/last-session.md` exists.
- [ ] `.agents/memory/decisions.md` exists.
- [ ] `.agents/memory/pending.md` exists.

### SPEC
- [ ] `.agents/SPEC.md` exists.

---

## Output Format

```markdown
## Framework Health Check — YYYY-MM-DD

### ✅ Passing (N items)
- CLAUDE.md: all 4 sections present
- Personas: all 7 present
- Memory: all 3 files present
- SPEC.md: present

### ⚠️ Warnings (N items)
- `.agents/skills/metrics.md` missing (metrics tracking disabled)
- `.agents/memory/metrics.md` missing (will be created on first session end)

### ❌ Failures (N items)
- CLAUDE.md missing `## Framework` section → run `bash install.sh` to fix
- `.agents/personas/reviewer.md` missing → run `bash install.sh --update` to fix

### Verdict: HEALTHY | DEGRADED | BROKEN
```

**HEALTHY**: No failures, 0–2 warnings.  
**DEGRADED**: No failures, 3+ warnings or optional files missing.  
**BROKEN**: 1+ failures (critical files missing or malformed).

---

## Remediation Guide

| Issue | Recommended Fix |
|-------|-----------------|
| CLAUDE.md missing sections | `bash install.sh` (or curl one-liner) |
| Persona files missing | `bash install.sh --update` |
| Skill files missing | `bash install.sh --update` |
| Memory files missing | `bash install.sh` (install mode) |
| SPEC.md missing | `bash install.sh --update` |

---

## Guardrails

- Health check is **read-only**. Never modify files during the check.
- Report all issues, even warnings. Give the full picture.
- Do not run a health check mid-task. Run it before starting work or when explicitly requested.
- If verdict is BROKEN, Maestro must inform the user before proceeding with any task.
