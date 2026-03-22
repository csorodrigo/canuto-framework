shortDescription: Extract, store, and evolve reusable patterns (instincts) from session experience.
usedBy: [maestro, reviewer, coder]
version: 1.0.0
lastUpdated: 2026-03-08
copyright: Rodrigo Canuto © 2026.

## When to Use

**Triggers:**
- At session end — Maestro extracts instincts from the session's decisions, rework, and patterns
- User says: `"what did we learn?"`, `"show instincts"`, `"evolve"`, `"what patterns have we found?"`
- After a Reviewer REQUEST CHANGES — extract the "why" as a preventive instinct
- After Debugger diagnosis — extract the root cause pattern as a diagnostic instinct

**Not for:**
- Generic knowledge already covered by skills (e.g., "use TypeScript strict mode" is a rule, not an instinct)
- One-off decisions that belong in `decisions.md` (e.g., "chose JWT over sessions")

---

## Purpose

Capture project-specific patterns that emerge from real development sessions. Unlike skills (generic, reusable across projects) and decisions (one-time choices), **instincts** are learned behaviors specific to THIS project that improve agent performance over time.

Instincts bridge the gap between "what the framework knows" (skills) and "what this project needs" (experience).

---

## Concepts

### Instinct

A reusable pattern learned from experience. Each instinct has:

| Field | Description |
|-------|-------------|
| **ID** | Auto-incrementing (`I-001`, `I-002`, ...) |
| **Pattern** | What was observed (the trigger/situation) |
| **Learning** | What to do about it (the action/response) |
| **Confidence** | `low` (1 occurrence) → `medium` (2-3) → `high` (4+) |
| **Source** | Which session/event originated it |
| **Category** | `code-pattern`, `architecture`, `testing`, `workflow`, `debugging`, `design` |
| **Applied** | Count of times this instinct influenced a decision |

### Confidence Scoring

Confidence increases with repeated observation:

| Level | Criteria | Behavior |
|-------|----------|----------|
| `low` | First occurrence | Suggested but not enforced |
| `medium` | 2-3 occurrences across sessions | Actively recommended by personas |
| `high` | 4+ occurrences or user-promoted | Treated as a soft rule |

### Instinct Lifecycle

```
Observation → Extraction → Storage → Reinforcement → Promotion (optional)
```

1. **Observation**: Something notable happens (rework, bug pattern, review feedback)
2. **Extraction**: Maestro identifies and formalizes the pattern at session end
3. **Storage**: Written as individual note in `~/.canuto/vault/projects/{project-slug}/instincts/I-XXX-slug.md`
4. **Reinforcement**: Same pattern observed again → confidence increases
5. **Promotion** (optional): Two promotion paths:
   - **To project rule**: Promote to `stack.md` or a custom skill (project-scoped).
   - **To global instinct**: Copy to `~/.canuto/vault/global-instincts/` so it appears in ALL projects. Add `source_project` frontmatter field. Use when the pattern is universal (not project-specific)

---

## Storage

### Vault: `~/.canuto/vault/projects/{project-slug}/instincts/`

Each instinct is an individual note with frontmatter:

```markdown
---
type: instinct
id: I-001
category: code-pattern
confidence: low
applied: 0
source-session: "[[sessions/2026-03-21]]"
last-seen: 2026-03-21
status: active
promoted-to: ""
tags:
  - instinct
  - confidence/low
  - category/code-pattern
---

# [Category] Short title

**Pattern:** When/where this occurs.

**Learning:** What to do about it.

**Source:** [[sessions/2026-03-21]]
```

Query instincts via `bases/instincts-by-confidence.base` for grouped views.

---

## Procedure

### Extracting Instincts (Session End)

At the end of each session, **before** writing `last-session.md`, the Maestro reviews the session for learnable patterns:

1. **Scan for signals:**
   - Rework files (count ≥ 3) → potential architecture or planning instinct
   - Reviewer MUST FIX items → potential code-pattern or testing instinct
   - Debugger diagnoses → potential debugging instinct
   - Repeated user corrections → potential workflow instinct
   - Design rejections → potential design instinct

2. **For each signal, check existing instincts:**
   - If a matching instinct exists → **reinforce** (bump confidence, update "Last seen", increment "Applied")
   - If no match → **create new** instinct with `low` confidence

3. **Present to user:**
   ```
   Session Learnings:
   - [NEW] I-007 — [debugging] Auth middleware silently swallows errors → always check middleware error propagation
   - [REINFORCED] I-003 — [code-pattern] Form validation (medium → high) — seen 4 times now

   Save these instincts? [Y/n]
   ```

4. **Only save with user approval.** Never auto-save instincts without confirmation.

### Applying Instincts (During Session)

Personas should consult instincts when relevant:

- **Architect**: Read `high` and `medium` instincts before planning. Consider them as soft constraints.
- **Coder**: Read instincts in the relevant category before implementing. Especially `code-pattern` and `debugging` categories.
- **Reviewer**: Check if any `code-pattern` or `testing` instinct applies to the current diff.
- **Debugger**: Read `debugging` instincts before investigating — the pattern may already be known.

**How to consult:**
```
[Maestro] Relevant instincts for this task:
- I-003 [high] Form validation: always validate on blur, not on submit
- I-011 [medium] Auth flows: check token refresh before API calls
```

### Reviewing Instincts

When the user asks to see instincts:

1. `obsidian_list_notes(path="instincts/")` → list all instinct notes
2. Or query via `bases/instincts-by-confidence.base` for grouped view
3. Show applied count and last-seen date from frontmatter
4. Suggest pruning instincts not seen in 10+ sessions
5. Suggest promoting `high` instincts to project rules

### Promoting Instincts

When an instinct reaches `high` confidence and has been applied 5+ times:

1. Maestro suggests promotion:
   ```
   Instinct I-003 has been reinforced across 6 sessions.
   Promote to:
   (a) Project rule in stack.md
   (b) Custom skill in .agents/skills/
   (c) Global instinct (visible in ALL projects)
   (d) Keep as instinct
   ```

2. On promotion to project rule/skill:
   - Add the rule/skill
   - Mark the instinct as `[PROMOTED → stack.md]` (keep for history, stop enforcing as instinct)

3. On promotion to **global instinct**:
   - Copy the instinct note to `~/.canuto/vault/global-instincts/I-XXX-slug.md`
   - Add `source_project: {project-slug}` to the frontmatter
   - Add `promoted_from: "[[projects/{project-slug}/instincts/I-XXX-slug]]"` to link back
   - Mark the original as `promoted-to: "[[global-instincts/I-XXX-slug]]"`
   - Global instincts appear in **all projects** during session start, tagged as `[GLOBAL]`
   - Use for patterns that are **universal** (not project-specific), e.g.: "always validate env vars at startup", "never swallow errors silently"

### Pruning Instincts

Instincts with `low` confidence that haven't been seen in 5+ sessions are candidates for pruning:

1. At session start, if stale instincts exist, Maestro notes:
   ```
   Stale instincts (low confidence, not seen in 5+ sessions): I-004, I-008
   Prune them? [Y/n]
   ```

2. On prune: set `status: pruned` in the instinct note's frontmatter (keep for history, stops appearing in active views)

---

## Examples

### ✅ Good — well-formed instinct extraction

After a session where the Debugger found that API errors were being swallowed by a try/catch:

```markdown
### I-012 — [debugging] Silent error swallowing in API layer
- **Pattern:** try/catch blocks in src/api/ catch errors but log them without re-throwing
- **Learning:** Always re-throw after logging in API middleware. Check error propagation in any new endpoint.
- **Confidence:** low
- **Source:** Session 2026-03-08 — Debugger traced auth failure to swallowed 401 in src/api/middleware/error-handler.ts
- **Applied:** 0
- **Last seen:** 2026-03-08
```

### ✅ Good — reinforcement of existing instinct

```
Session Learnings:
- [REINFORCED] I-005 — [testing] Missing edge case: empty array inputs (low → medium)
  Previously seen in: Session 2026-03-01
  Now seen in: Session 2026-03-08 (Reviewer caught missing test for empty cart)
```

### ❌ Bad — too generic

```markdown
### I-099 — [code-pattern] Write good code
- **Pattern:** Code sometimes has bugs
- **Learning:** Write better code
```

This is bad because: not actionable, not specific to this project, not something a persona can apply.

### ❌ Bad — should be a decision, not an instinct

```markdown
### I-100 — [architecture] Use Zustand for state
- **Pattern:** Need state management
- **Learning:** Use Zustand
```

This belongs in `decisions.md` or `stack.md`, not instincts. Instincts are about HOW to work, not WHAT to use.

---

## Guardrails

- **Never auto-save instincts.** Always present to user and wait for approval.
- **Max 30 active instincts.** If the list grows beyond 30, trigger a pruning session.
- **Instincts are project-specific.** They do not transfer between projects automatically.
- **Confidence only goes up via real observations.** Never manually inflate confidence.
- **Don't duplicate skills.** If a pattern is already covered by a skill, reference the skill instead of creating an instinct.
- **Keep instincts concise.** Pattern + Learning should fit in 2 sentences each.
- **Instinct IDs are never reused.** If I-005 is pruned, the next instinct is still I-031 (or whatever comes next).
