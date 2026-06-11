shortDescription: Protocol that requires checking for applicable skills before any non-trivial action (the 1% Rule).
usedBy: [maestro, architect, coder, reviewer, contextualizer]
version: 1.0.0
lastUpdated: 2026-03-23
copyright: Rodrigo Canuto © 2026.

## When to Use

**Triggers:**
- Before routing a task (Maestro)
- Before starting implementation of any step (Coder)
- Before producing a plan (Architect)
- Before writing tests (Coder)
- Before diagnosing a bug (fluxo /fix)
- Before reviewing a diff (Reviewer)

**The 1% Rule:** If there is even a **1% chance** that a skill in `.agents/skills/` applies to the current task or sub-step, that skill MUST be checked before proceeding.

**Not for:**
- Trivial lookups or status checks with no behavioral impact
- Tasks where the applicable skill has already been read this session

---

## Purpose

Skills encode hard-won patterns, constraints, and procedures that prevent repeated mistakes. An agent that ignores applicable skills will reinvent decisions already made, violate architectural choices, or miss critical guardrails.

This protocol makes skill checking non-optional. It is the difference between a well-trained agent and one that guesses.

---

## Decision Flowchart

```
Incoming task or step
        │
        ▼
Does any skill in .agents/skills/ apply to this task?
        │
   ┌────┴────┐
  YES      UNSURE
   │          │
   ▼          ▼
Read skill  Read candidate skill(s)
before      before proceeding
proceeding
        │
        ▼
    CLEARLY NO
        │
        ▼
Proceed without skill check
(document why if non-obvious)
```

---

## Red Flags (rationalizations to ignore)

These are common excuses agents give for skipping the skill check. All of them are wrong:

| Rationalization | Why It's Wrong |
|-----------------|---------------|
| "This is too simple for a skill" | Skills exist precisely for repeated, simple actions where consistency matters. |
| "I already know how to do this" | The skill may constrain *how*, not just *whether*. It may have guardrails you don't know. |
| "The skill name doesn't match exactly" | Check adjacent skills. Skill names are approximate. Read the `When to Use` section. |
| "There's time pressure" | A 30-second skill read prevents 30-minute rework. |
| "I've done this before in another session" | Each session starts fresh. Skills are the memory. |

---

## Skill Inventory Hints (by task type)

| Task Type | Skills to Check |
|-----------|----------------|
| New API endpoint | `api-design` |
| UI component | `frontend-implementation`, `frontend-design` |
| Migration or schema change | `supabase-migration` (if applicable) |
| Adding a dependency | `stack-lock` |
| Security concern | `security-practices` |
| Git operations | `git-workflow` |
| CLI usage | `cli-usage` |
| Documentation update | `context-maintenance` |
| Plugin or extension work | `plugin-system` |
| Multi-provider delegation | `multi-provider` |
| Metrics or observability | `metrics`, `audit-trail` |
| Research task | `research` |

---

## Anti-Patterns — DO NOT

- DO NOT assume a skill doesn't exist without listing `.agents/skills/` first.
- DO NOT read a skill and then ignore its guardrails because they seem inconvenient.
- DO NOT apply a skill partially — if the skill defines a mandatory step, it is mandatory.
- DO NOT skip the skill check because the same skill was read in a previous session.
