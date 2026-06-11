shortDescription: Maestro tracks exploration coverage — which personas were consulted, what areas were examined, and where gaps remain.
usedBy: [maestro]
version: 1.0.0
lastUpdated: 2026-03-18
copyright: Rodrigo Canuto © 2026.
inspiration: pgs-engine (session continuation with searchedPartitionIds) + Paperclip (governance dashboards).

## When to Use

**Triggers:**
- Every task M or L — Maestro tracks coverage as the task progresses
- Session end — include coverage summary in session metrics
- User asks: `"what have we covered?"`, `"what's left?"`, `"coverage report"`
- After Reviewer APPROVE — verify coverage is sufficient before closing the task

**Not for:**
- XS/S tasks (overhead not justified)
- Sessions with a single, focused task

---

## Purpose

Answer the question: **"How thoroughly has this task been explored?"**

Without tracking, Maestro can't distinguish between "we checked everything and it's fine" vs. "we only looked at half the problem." Coverage tracking makes exploration depth visible, enabling informed decisions about when to continue, when to stop, and where gaps remain.

---

## Concepts

### Coverage Dimensions

| Dimension | What it Tracks | Example |
|-----------|---------------|---------|
| **Persona coverage** | Which personas have been consulted | Architect ✅, Coder ✅, Reviewer ❌ |
| **Area coverage** | Which codebase areas were touched | src/api/ ✅, src/auth/ ✅, src/ui/ ❌ |
| **Concern coverage** | Which quality concerns were addressed | Correctness ✅, Security ⏳, Performance ❌ |
| **Absence coverage** | Confirmed vs. unexplored absences | 3 confirmed absences, 2 not-checked areas |

### Coverage States

| State | Symbol | Meaning |
|-------|--------|---------|
| Covered | ✅ | Persona consulted / area examined |
| In progress | ⏳ | Currently being addressed |
| Not covered | ❌ | Not yet examined |
| Skipped | ⊘ | Deliberately skipped (with reason) |

---

## Procedure

### Initializing Coverage (Task Start)

When routing a task M or L, Maestro initializes a coverage map:

```markdown
## Coverage Map — [Task Name]

### Personas
- [ ] Architect — planning
- [ ] Coder — implementation + testes (edge cases & coverage)
- [ ] Reviewer — quality gate

### Areas
- [ ] src/api/routes/ — new endpoints
- [ ] src/auth/ — authentication changes
- [ ] src/db/migrations/ — schema changes

### Concerns
- [ ] Correctness — logic and behavior
- [ ] Security — auth, injection, secrets
- [ ] Performance — queries, payload size
- [ ] Design — UI consistency (if applicable)
```

### Updating Coverage (During Task)

After each persona handoff, Maestro updates the map:

```markdown
### Personas
- [x] Architect — planning ✅ (plan approved)
- [x] Coder — implementation ✅ (code written, happy-path tests pass)
- [ ] Coder — edge-case tests & coverage ⏳ (in progress)
- [ ] Reviewer — quality gate
```

### Coverage Report (On Demand or Session End)

```markdown
## Coverage Report — [Task Name]

| Dimension | Covered | Total | % |
|-----------|---------|-------|---|
| Personas | 3 | 4 | 75% |
| Areas | 2 | 3 | 67% |
| Concerns | 2 | 4 | 50% |

### Gaps
- ❌ Performance concern not addressed (no load testing, no query analysis)
- ❌ src/db/migrations/ not covered by tests (Coder)

### Absences Tracked
- 2 confirmed absences (from absence-reporting)
- 1 not-checked area (flagged for future session)

### Recommendation
Coverage is **partial** (64% overall). Consider:
- Coder escrever testes para os edge cases de migration
- Adding a performance check before merging
```

### Coverage Thresholds

| Level | Threshold | Maestro Action |
|-------|-----------|----------------|
| **High** | ≥ 80% across all dimensions | Proceed to merge/close |
| **Medium** | 50-79% | Surface gaps, ask user if acceptable |
| **Low** | < 50% | Warn user, recommend additional passes |

---

## Examples

### ✅ Good — coverage report with actionable gaps

```markdown
## Coverage Report — User Registration Feature

| Dimension | Covered | Total | % |
|-----------|---------|-------|---|
| Personas | 4 | 4 | 100% |
| Areas | 3 | 3 | 100% |
| Concerns | 3 | 4 | 75% |

### Gaps
- ❌ Performance: no analysis of DB query for duplicate email check (sequential scan on unindexed column?)

### Recommendation
Coverage is **high** (94% overall). Single gap is performance — suggest adding an index on `users.email` before merging.
```

### ❌ Bad — coverage without specifics

```
Coverage looks good. We checked most things.
```

This is bad because: no dimensions tracked, no percentages, no gaps identified — the user can't tell what was actually verified.

---

## Guardrails

- **Only track for M/L tasks.** XS/S tasks don't justify the overhead.
- **Coverage is not a bureaucratic exercise.** Keep the map lightweight — 3-5 items per dimension.
- **100% coverage is not always the goal.** Some tasks legitimately skip dimensions (e.g., no UI concern for a backend-only change).
- **Use ⊘ (skipped) honestly.** If a dimension was deliberately skipped, document why.
- **Coverage maps are ephemeral.** They live in the session, not in memory files. Only the summary goes into metrics.
- **Don't block on coverage.** It's advisory — the user decides if gaps are acceptable.
