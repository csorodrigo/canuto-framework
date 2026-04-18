# Experiment Auto-Trigger Rules

Trace analysis can propose (never auto-run) experiment series when review signals degrade. Use these rules to decide when to draft a proposal for the user.

## Review Score Thresholds
- Pull review data from `vault/metrics/review-scores-template.md`.
- For each dimension (Quality, Testing, DX, etc.) maintain a rolling list of the last 5 scored sessions.
- Compute the moving average; if any dimension < **7.0** AND at least **5** reviews exist, propose an experiment series targeting that dimension.
- Include evidence table with session IDs, scores, model used.

## Deduplication
- Group by `task-type` (from session note frontmatter). Do not propose two identical experiments for the same task-type and dimension inside a 7-day window.
- When multiple task-types trigger simultaneously, keep the highest variance (largest drop from 7.0) and mention others as "watch" items.

## Model Affinity Tracking
- Record which model/persona pairing produced the low scores (e.g., `coder:gpt-5.4-high`).
- If the same model appears in ≥3 low-score sessions, note "model-affinity" so user can direct experiments toward prompt/pattern changes for that model.

## Proposal Template
```
Experiment Proposal: Improve Reviewer Quality (avg 6.6/10 over last 5 S tasks)
Metric: Reviewer Quality score (higher is better)
Variable ideas: reviewer checklist prompt, enforce adaptive routing before coding, require unit test diff summary.
Evidence:
- 2026-04-02 (task-type: api-fix, model: coder/gpt-5.4-high) — 6.5
- 2026-04-03 ...
Recommendation: start SER-00X once user approves.
```

## Hard Guardrails
- Auto-triggers surface **proposals only**. They never call `experiment-loop` automatically.
- Always wait for user approval before creating or running an experiment series.
- If scores recover (moving average ≥7.0) before user responds, close the proposal as `stale` in the digest.
