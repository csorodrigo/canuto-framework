---
name: continuous-learning
description: Extract reusable project instincts from session outcomes and reinforce them over time.
shortDescription: Extract, store, and evolve reusable patterns (instincts) from session experience.
usedBy: [maestro, reviewer, coder]
version: 1.2.0
lastUpdated: 2026-03-23
copyright: Rodrigo Canuto © 2026.
evals:
  - prompt: "session is ending, extract any instincts from what we learned today"
    should_trigger: true
  - prompt: "we fixed the same bug 3 times now, lets document this pattern so it doesnt happen again"
    should_trigger: true
  - prompt: "how many instincts do we have in the vault?"
    should_trigger: false
  - prompt: "the coder keeps making the same mistake, review its last output"
    should_trigger: false
---

## When to Use

**Triggers:**
- At session end — Maestro extracts instincts from the session's decisions, rework, and patterns
- User says: `"what did we learn?"`, `"show instincts"`, `"evolve"`, `"what patterns have we found?"`
- After a Reviewer REQUEST CHANGES — extract the "why" as a preventive instinct
- After Debugger diagnosis — extract the root cause pattern as a diagnostic instinct

**Not for:**
- Generic knowledge already covered by skills
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
| **Category** | `code-pattern`, `architecture`, `testing`, `workflow`, `debugging`, `design` |
| **Applied** | Count of times this instinct influenced a decision |

### Confidence Scoring

| Level | Criteria | Behavior |
|-------|----------|----------|
| `low` | First occurrence | Suggested but not enforced |
| `medium` | 2-3 occurrences across sessions | Actively recommended by personas |
| `high` | 4+ occurrences or user-promoted | Treated as a soft rule |

### Instinct Lifecycle

```
Observation → Extraction → Storage → Reinforcement → Promotion (optional)
```

---

## Storage

Each instinct is an individual note at `~/.canuto/vault/projects/{project-slug}/instincts/I-XXX-slug.md`:

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

At the end of each session, **before** writing `last-session.md`:

1. **Scan for signals:**
   - Rework files (count ≥ 3) → potential architecture or planning instinct
   - Reviewer MUST FIX items → potential code-pattern or testing instinct
   - Debugger diagnoses → potential debugging instinct
   - Repeated user corrections → potential workflow instinct

2. **For each signal, check existing instincts:**
   - If a matching instinct exists → **reinforce** (bump confidence, update "Last seen", increment "Applied")
   - If no match → **create new** instinct with `low` confidence

3. **Present to user:**
   ```
   Session Learnings:
   - [NEW] I-007 — [debugging] Auth middleware silently swallows errors
   - [REINFORCED] I-003 — [code-pattern] Form validation (medium → high)

   Save these instincts? [Y/n]
   ```

4. **Only save with user approval.** Never auto-save instincts.

### Applying Instincts (During Session)

Personas consult instincts when relevant:

- **Architect**: Read `high` and `medium` instincts before planning. Consider as soft constraints.
- **Coder**: Read instincts in the relevant category before implementing.
- **Reviewer**: Check if any `code-pattern` or `testing` instinct applies to the current diff.
- **Debugger**: Read `debugging` instincts before investigating — the pattern may already be known.

**Format:**
```
[Maestro] Relevant instincts for this task:
- I-003 [high] Form validation: always validate on blur, not on submit
- I-011 [medium] Auth flows: check token refresh before API calls
```

### Reviewing Instincts

When the user asks to see instincts:

1. `obsidian_list_notes(path="instincts/")` → list all instinct notes
2. Or query via `bases/instincts-by-confidence.base` for grouped view
3. Show applied count and last-seen date
4. Suggest pruning instincts not seen in 10+ sessions
5. Suggest promoting `high` instincts to project rules

### Promoting Instincts

When an instinct reaches `high` confidence and has been applied 5+ times, Maestro suggests promotion to: project rule in `stack.md`, custom skill, or global instinct (visible in ALL projects).

→ **Full promotion workflow** (steps, global instinct frontmatter, promotion tracking): read `references/instinct-promotion.md`

### Pruning Instincts

Instincts with `low` confidence not seen in 5+ sessions:

1. At session start, Maestro notes:
   ```
   Stale instincts (low confidence, not seen in 5+ sessions): I-004, I-008
   Prune them? [Y/n]
   ```
2. On prune: set `status: pruned` in frontmatter (keep for history, stops appearing in active views).

---

## Guardrails

- **Never auto-save instincts.** Always present to user and wait for approval.
- **Max 30 active instincts.** If the list grows beyond 30, trigger a pruning session.
- **Instincts are project-specific.** They do not transfer between projects automatically.
- **Confidence only goes up via real observations.** Never manually inflate confidence.
- **Don't duplicate skills.** If a pattern is already covered by a skill, reference the skill instead.
- **Keep instincts concise.** Pattern + Learning should fit in 2 sentences each.
- **Instinct IDs are never reused.** If I-005 is pruned, the next instinct is still I-031 (or whatever comes next).

→ **Examples** (good/bad instinct extraction, reinforcement): read `references/examples.md`

---

## Bulk classification (v2.0, 2026-04-29)

Para classificar/triagar grande volume de itens (instincts, notas, audits),
delegue a `codex exec --profile fast`:

```bash
codex exec --color never --profile fast \
  -s read-only --skip-git-repo-check \
  -o /tmp/canuto-classify-$$.md \
  "Classifique cada linha em uma label do conjunto {X, Y, Z}:
   <itens>"
```

> Historical note (2026-04-29): previously delegated bulk classify to
> Gemini flash-lite-preview via `bulk-classify` skill (deleted).
> Codex --profile fast cobre o use case com uma dependência a menos.
