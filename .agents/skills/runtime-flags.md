shortDescription: Environment flags that alter framework behavior per-session without editing config files.
usedBy: [maestro]
version: 1.0.0
lastUpdated: 2026-03-18
copyright: Rodrigo Canuto © 2026.
inspiration: everything-claude-code — hook-based runtime configuration with environment variable flags.

## When to Use

**Triggers:**
- User says: `"skip design review"`, `"strict mode"`, `"fast mode"`, `"verbose"`, `"quiet"`
- User sets a flag explicitly: `"set SKIP_TESTER=true"`
- Maestro detects a session context that benefits from a flag (e.g., quick fix session → suggest `FAST_MODE`)

**Not for:**
- Permanent configuration changes (those go in `CLAUDE.md` or `stack.md`)
- Per-project settings (those are config, not flags)

---

## Purpose

Allow temporary behavioral overrides for a single session without modifying permanent config files. Flags are session-scoped — they disappear when the session ends.

This bridges the gap between rigid config (CLAUDE.md) and ad-hoc user requests, giving structured control over framework behavior.

---

## Concepts

### Flag Types

| Flag | Default | Effect |
|------|---------|--------|
| `FAST_MODE` | false | Skip optional passes: abbreviated Architect, skip Tester for S tasks, skip Design Lens in Reviewer |
| `STRICT_MODE` | false | Enforce all optional checks: full Architect for all sizes, Tester for all sizes, all Review lenses |
| `SKIP_TESTER` | false | Skip the Tester persona entirely (Coder → Reviewer directly) |
| `SKIP_DESIGN_REVIEW` | false | Skip the Design Lens (Pass 3) in Reviewer |
| `VERBOSE_HANDOFFS` | false | Include full context in every handoff (overrides `handoff-verbosity` config) |
| `QUIET_MODE` | false | Minimal announcements — only errors and final results |
| `DRY_RUN` | false | Personas describe what they would do without actually executing |
| `BUDGET_STRICT` | false | Enable hard-stop on budget (overrides `hard-stop: false` default) |

### Flag Syntax

User can set flags in natural language or explicitly:

```
# Natural language (Maestro interprets)
"Let's go fast today, skip tests"
→ Maestro sets: FAST_MODE=true, SKIP_TESTER=true

# Explicit
"Set STRICT_MODE=true"
→ Maestro sets: STRICT_MODE=true
```

### Flag Conflicts

Some flags conflict. Maestro resolves by priority:

| Conflict | Resolution |
|----------|------------|
| FAST_MODE + STRICT_MODE | STRICT_MODE wins (safety over speed) |
| SKIP_TESTER + STRICT_MODE | STRICT_MODE wins (Tester runs) |
| QUIET_MODE + VERBOSE_HANDOFFS | VERBOSE_HANDOFFS wins (explicit request) |

---

## Procedure

### Setting Flags

1. User requests a behavioral change (explicit or natural language)
2. Maestro interprets and maps to flags
3. Maestro confirms:
   ```
   🏁 Runtime flags set for this session:
   - FAST_MODE = true (skip optional passes)
   - SKIP_TESTER = true (Coder → Reviewer directly)

   These flags expire at session end. Confirm? [Y/n]
   ```
4. On approval, Maestro applies flags to all subsequent routing decisions

### Checking Active Flags

User asks: `"what flags are active?"` or `"show flags"`

```
🏁 Active Runtime Flags:
- FAST_MODE = true (set by user at session start)
- SKIP_DESIGN_REVIEW = true (set by user after task 1)

Default flags (not set): STRICT_MODE, VERBOSE_HANDOFFS, QUIET_MODE, DRY_RUN, BUDGET_STRICT
```

### Applying Flags

Maestro checks active flags at each routing decision:

```
# Without flags (default)
[Task S] Routing: Maestro → Architect (abbrev) → Coder → Tester → Reviewer

# With FAST_MODE
[Task S] Routing: Maestro → Coder → Reviewer (fast mode: Architect + Tester skipped)

# With STRICT_MODE
[Task S] Routing: Maestro → Architect (full) → Coder → Tester → Reviewer (strict: full flow for all sizes)
```

### Logging Flags

Active flags are recorded in the audit log at session start:

```markdown
#### [2026-03-18 10:00] SESSION_START — Session opened
- **Flags:** FAST_MODE=true, SKIP_TESTER=true
- **Goals:** Quick bug fixes (3 XS tasks)
```

And in `last-session.md`:
```markdown
- Flags used: FAST_MODE, SKIP_TESTER (user requested fast session for bug fixes)
```

---

## Examples

### ✅ Good — natural language flag setting with confirmation

```
User: "Let's be strict today, I want full review on everything"

Maestro:
🏁 Runtime flags set for this session:
- STRICT_MODE = true (full flow for all task sizes, all review lenses)

This means even XS tasks will go through Architect + Tester. Confirm? [Y/n]
```

### ✅ Good — flag affecting routing

```
[Task XS | FAST_MODE] Routing directly to Coder — Architect and Tester skipped.
Note: FAST_MODE active. Happy-path tests still required (Coder responsibility).
```

### ❌ Bad — silently applying flags

```
[Maestro → Coder] Implementing the fix.
(Secretly skips Tester because user said "go fast" earlier)
```

This is bad because: flags must be announced and confirmed. Silent behavior changes violate the explicit handoff principle.

### ❌ Bad — persisting flags across sessions

```
Last session had FAST_MODE on. Keeping it for this session.
```

This is bad because: flags are session-scoped. Each session starts clean. If the user wants the same flags, they set them again.

---

## Guardrails

- **Flags are session-scoped.** They never persist across sessions.
- **Always confirm before applying.** Show what the flag does and ask for approval.
- **Announce flag effects at routing.** Make it visible when a flag changes the normal flow.
- **STRICT_MODE always wins conflicts.** Safety over convenience.
- **Flags don't disable governance gates.** No flag can bypass approval gates — those are always active.
- **Log flags in audit trail.** Every flag set/unset is an auditable event.
- **Maximum 4 flags active simultaneously.** More than that indicates the user should change config, not stack flags.
