shortDescription: Detect repeated attempts, review-fix loops, stale assumptions, and prior failed approaches before more work is done.
usedBy: [maestro, architect, debugger, reviewer]
version: 1.0.0
lastUpdated: 2026-04-17
copyright: Rodrigo Canuto © 2026.

## Purpose

Prevent the same work from being paid for twice. This skill scans memory and recent session evidence for repeated failures, stale assumptions, review-fix loops, and files that keep changing without converging.

---

## When To Run

Run before planning or continuing when:

- a file has been modified 3+ times in the session
- Reviewer returns REQUEST CHANGES more than once
- the same test fails twice
- the user says something was already tried
- pending tasks repeat across sessions
- the project has high error or rework signals

---

## Sources

Prefer these sources, in order:

1. Current session notes and changed-file map.
2. `.agents/memory/metrics.md`
3. `.agents/memory/pending.md`
4. `.agents/memory/last-session.md`
5. `.agents/memory/decisions.md`
6. Canuto vault project notes, if available.
7. Git history, if shell access is allowed.

---

## Procedure

1. Identify the current task and files in scope.
2. Search memory for matching paths, feature names, errors, test names, or pending tasks.
3. Classify the signal:
   - `retry-loop`: same command/test/fix keeps failing
   - `review-loop`: repeated REQUEST CHANGES on the same area
   - `stale-context`: plan based on outdated context or docs
   - `decision-gap`: missing or disputed architectural/product decision
   - `dirty-state`: uncommitted work obscures what is new
4. Recommend one guardrail before more implementation:
   - re-plan
   - add fixture
   - write smaller test
   - isolate dirty changes
   - create/update decision
   - split task

---

## Output Format

```markdown
## Rework Check

### Signal: none | retry-loop | review-loop | stale-context | decision-gap | dirty-state

### Evidence
- <path/source>: <short observation>

### Risk
<what will likely happen if we keep going unchanged>

### Guardrail Before Continuing
<one concrete action>
```

---

## Guardrails

- Do not block work for weak evidence. Say "signal: none" when there is no useful match.
- Do not search the whole repository when memory already gives enough evidence.
- Do not turn every error into an instinct. Promote only reusable lessons.
- If the signal is strong, Maestro must pause implementation and re-plan or ask the user.
