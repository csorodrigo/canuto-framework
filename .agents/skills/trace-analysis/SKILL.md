---
name: trace-analysis
description: Analyze session traces (audit logs + metrics) to extract actionable signals before instincts run.
shortDescription: Inspect vault traces at session end to classify signals, draft digests, and feed downstream learning.
usedBy: [maestro]
version: 1.0.0
lastUpdated: 2026-04-04
evals:
  - prompt: "session ended, run trace analysis before continuous learning"
    should_trigger: true
  - prompt: "generate a trace digest using audit + metrics for today's session"
    should_trigger: true
  - prompt: "give me today's instincts"
    should_trigger: false
  - prompt: "parse review scores from vault metrics"
    should_trigger: false
---

## Purpose

Run a lightweight, trace-based learning pass **before** `continuous-learning`. Maestro uses this skill at session end (Step 1.5) to:
- Classify observable signals from audit notes, metrics, and the session note into five remediation categories.
- Propose blind-spot candidates and skill ideas when patterns reoccur.
- Produce a normalized digest in `vault/traces/` for future review and experiment routing.

The trace pass never bypasses approval gates — it only surfaces structured proposals.

## Feature Flag

Only run when `CANUTO_TRACE_ANALYSIS=1` is set (environment or project config). If unset, skip with a short note.

## Inputs (read directly, never through JSON exports)

| Source | Path | Notes |
|--------|------|-------|
| Audit events | `vault/audit/{session-date}-*.md` | Filter by current session link to avoid leaking other runs. |
| Metrics snapshot | `vault/metrics/{session-date}-metrics.md` | Contains action counts, rework, file lists. |
| Session note | `vault/sessions/{session-date}.md` | Use "What Was Done", "Rework", "Issues" for context. |
| Review scores template | `vault/metrics/review-scores-template.md` | Dataview queries show scores and trends; do **not** expect JSON. |

If any file is missing, note it and continue. Missing all inputs ⇒ emit digest with `signals-found: 0` (graceful degradation).

## Signal Categories

1. **playbook-gap** — Process or instruction missing/ambiguous (e.g., repeated clarification requests, plan mismatch). Use `references/improvement-patterns.md` for triggers.
2. **blind-spot-gap** — Domain pitfalls observed (bugs repeated, reviewer flags). Use `references/blind-spot-generator.md` to create candidates without duplicates.
3. **instinct-candidate** — Rework loops on same files, repeated debugging journeys, patterns suitable for instincts.
4. **routing-misfire** — Task sizing or persona ordering off (e.g., reroutes, 2+ re-plans, diff touches 5+ files for S scope).
5. **skill-gap** — Manual multi-step workflows repeated 3+ times or identical commands across sessions (see `references/skill-proposer.md`).

For each signal, capture: evidence (quote/link), severity, suggested improvement.

## Overfitting Guard

Before proposing anything ask: **"If this exact task disappeared, would this still matter?"**
- If answer is "no", record as observation but do **not** promote.
- Include an `overfitting-check` field inside each proposal.

## Workflow

1. **Verify flag**: if env flag off → exit with `reason: feature-disabled`.
2. **Identify session date + link** from Maestro context (`sessions/{date}.md`). Determine suffix (task slug, persona, or timestamp) for digest file name.
3. **Collect inputs**: read markdown files as text; parse headings, bullet lists, inline code. Avoid JSON assumptions.
4. **Extract signals**:
   - Use heuristics from `references/improvement-patterns.md` for classification.
   - Map reviewer score drops (dimension < 7.0) to routing or experiment triggers.
   - Detect blind-spot candidates by scanning for repeated mistakes; call `blind-spot-generator` reference for schema.
   - Detect skill candidates via `skill-proposer` reference (audit command counts, session note repetition).
5. **Apply overfitting guard** per signal.
6. **Summarize metrics**: include counts (files touched, reruns, tests) and highlight anomalies.
7. **Write digest**:
   - Path: `vault/traces/{date}-{suffix}-digest.md`
   - Follow schema in `references/digest-schema.md` (frontmatter + markdown sections per category).
   - `signals-found` equals total number of accepted signals; `improvements-proposed` counts actionable items; `improvements-applied` stays `0` until user confirms later.
8. **Hand-offs**:
   - Pass `instinct-candidate` entries to `continuous-learning` Step 2 (respecting approval gate; mark as "awaiting approval").
   - For blind-spot or skill proposals, create `_candidates/` files per their reference docs and mention them in digest.
   - Notify Maestro if routing misfire detected so `adaptive-routing` can adjust next session.
9. **Graceful exit**: if nothing found, still write digest with summary + `signals-found: 0`.

## Output Template

Digest body should include:
```
## Session Overview
- Scope: <size>
- Personas run: Architect → Coder → Reviewer
- Highlights: <bullet list>

## Signals
### playbook-gap
- Signal ID: description (evidence)

### blind-spot-gap
...
```
(See `references/digest-schema.md`.)

## Interactions

- **continuous-learning**: Provide candidate instincts but never auto-save; include `instinct-id: pending` entries.
- **experiment-loop**: When review scores trend below threshold, add `experiment-proposal` entry referencing `experiment-loop/references/auto-triggers.md`.
- **adaptive-routing**: When reroute-worthy data arises, append `routing-misfire` signal and log event for Maestro to mention.

## Failure Modes & Safeguards

- **Missing files**: log `missing-sources` array; digest explains which inputs absent.
- **No signals**: still record metrics summary so future trends have baselines.
- **Vault write failure**: surface error to user; do not re-run automatically.
- **Approval gates**: never bypass; waiting for user counts as `improvements-applied: 0` until approved.

## References

- `references/digest-schema.md` — full digest fields & example
- `references/improvement-patterns.md` — category heuristics
- `references/blind-spot-generator.md` — candidate instructions
- `references/skill-proposer.md` — recurring pattern detection
- `.agents/skills/experiment-loop/references/auto-triggers.md` — score-driven experiments
