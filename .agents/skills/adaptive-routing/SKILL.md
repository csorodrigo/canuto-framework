---
name: adaptive-routing
description: Detect when task sizing or persona ordering is wrong and facilitate safe reroutes with user approval.
shortDescription: Monitor observable signals (plans, diffs, reviews) to recommend rerouting personas or resizing scope.
usedBy: [maestro]
version: 1.0.0
lastUpdated: 2026-04-04
evals:
  - prompt: "this S task is touching 7 files, should we reroute?"
    should_trigger: true
  - prompt: "architect plan blew up past expectations"
    should_trigger: true
  - prompt: "reroute automatically without asking"
    should_trigger: false
  - prompt: "what is git diff --stat"
    should_trigger: false
---

## Purpose

Route the right persona at the right time. Adaptive routing watches real data (plans, diffs, reviews, coder chatter) and recommends reroutes when the sizing assumptions break. False negatives are acceptable; false positives are disruptive, so every reroute **requires explicit user confirmation**.

## Observable Signals

| Signal | Detection Method | Action |
|--------|------------------|--------|
| Scope creep | Coder or Maestro mentions "need to re-plan" or "scope grew" in audit/session note. | Suggest reroute to Architect for revised plan. |
| Under-estimated plan | Architect produces > expected steps for declared sizing (XS≤1, S≤3, M≤6, L>6). | Recommend promoting scope sizing by one level. |
| Over-estimated plan | Steps far below expectation (e.g., L request but only 2 steps). | Suggest demoting scope or merging personas. |
| Review-loop | Reviewer issues ≥2 `REQUEST CHANGES` on same scope. | Offer reroute to Reviewer/Architect for deeper audit. |
| Blast radius | `git diff --stat` for current branch touches ≥5 files on S task (or ≥10 on M). | Suggest reroute to Architect/Reviewer + warn user. |

## Required Inputs

- Latest Architect plan (step count + files referenced).
- Current sizing label (XS, S, M, L).
- `git diff --stat` output for working tree.
- Reviewer outcome log (counts of REQUEST CHANGES).
- Maestro transcript for mentions of "re-plan".

## Workflow

1. **Detect** signals as they happen (after Architect plan, after `git diff`, after reviews).
2. **Score** severity: count how many thresholds are exceeded.
3. **Prepare routing-check** summary using template below; never reroute silently.
4. **Ask user** for confirmation. Optionally offer options (e.g., Promote to M, Keep S, Pause and split).
5. **Act** only on user approval: update sizing metadata, adjust persona order, log audit event.
6. **Declines** still log `routing-check-declined` for traceability.

## Routing-Check Template

```
[Maestro] Routing Check — AutoAgent v1.8
Signals:
- Blast radius: git diff touches 7 files (S threshold is 2)
- Under-estimated plan: Architect produced 6 steps (S limit 3)
Recommendation: Promote to M and re-run Architect before Coder continues.
Proceed with reroute? [Promote to M / Keep S]
```

Always include:
- Signal list with evidence (counts, file names, reviewer links)
- Recommendation (new sizing + persona adjustments)
- Explicit confirmation prompt

## Audit Event Template

When reroute approved, append note to `vault/audit/{date}-maestro.md`:
```markdown
---
type: REROUTE
date: 2026-04-04
initiator: maestro
reason:
  - blast-radius
  - under-estimated
old-sizing: S
new-sizing: M
personas:
  - architect
  - coder
approval: user
notes: "User ok'd reroute after diff hit 7 files."
---
```
Declines use the same schema with `type: routing-check-declined` and no sizing change.

## Guardrails

- Never rely on invented metrics; stick to actual logs/diffs.
- Never reroute automatically or without user confirmation.
- False negatives acceptable; if unsure, ask for manual review instead of forcing reroute.
- Preserve approval gates in downstream skills (continuous-learning, experiment-loop).

## Integration Points

- Maestro `Task Processing` adds the routing-check immediately after Architect or Coder handoff.
- `trace-analysis` logs routing-misfire signals for later trend tracking.
- `experiment-loop` may use reroute data to propose process experiments (e.g., improved sizing heuristics).
