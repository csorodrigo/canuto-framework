---
type: metric-template
purpose: Track Codex review scores over time for quality trend analysis
created: 2026-03-30
tags:
  - metrics
  - review
  - quality-trend
---

# Review Scores — Quality Trend Dashboard

## How to Use

After each Codex review (co-validate, pre-commit, security-gate), append a row to the table below.
Obsidian Dataview queries at the bottom provide trend analysis.

## Review Log

| Date | Branch | Review Type | Reviewer | Overall | Correctness | Security | Performance | Readability | Verdict | threadId |
|------|--------|------------|----------|---------|-------------|----------|-------------|-------------|---------|----------|
| 2026-03-30 | example | co-validate | gpt-5.4 (high, reviewer) | 8.5 | 9 | 8 | 8 | 9 | PASS | thread_example |

## Dataview Queries

### Average Scores (Last 30 Days)

```dataview
TABLE
  round(avg(rows.overall), 1) as "Avg Overall",
  round(avg(rows.correctness), 1) as "Avg Correctness",
  round(avg(rows.security), 1) as "Avg Security",
  round(avg(rows.performance), 1) as "Avg Performance",
  round(avg(rows.readability), 1) as "Avg Readability",
  length(rows) as "Reviews"
FROM "vault/metrics"
WHERE type = "review-score" AND date >= date(today) - dur(30 days)
GROUP BY dateformat(date, "yyyy-'W'WW") as "Week"
SORT "Week" DESC
```

### Failing Reviews (Score < 7.0)

```dataview
TABLE date, branch, review-type, overall, verdict
FROM "vault/metrics"
WHERE type = "review-score" AND overall < 7.0
SORT date DESC
LIMIT 20
```

### Weakest Dimensions

```dataview
TABLE
  round(avg(security), 1) as "Security",
  round(avg(correctness), 1) as "Correctness",
  round(avg(performance), 1) as "Performance",
  round(avg(readability), 1) as "Readability"
FROM "vault/metrics"
WHERE type = "review-score"
GROUP BY true
```

### Review Volume by Type

```dataview
TABLE length(rows) as "Count", round(avg(rows.overall), 1) as "Avg Score"
FROM "vault/metrics"
WHERE type = "review-score"
GROUP BY review-type as "Type"
SORT length(rows) DESC
```

---

## Individual Review Entry Template

When logging a review, create a note in `vault/metrics/` with this frontmatter:

```yaml
---
type: review-score
date: YYYY-MM-DD
branch: feature/xyz
review-type: co-validate | pre-commit | security-gate | competition
reviewer: gpt-5.4 (high, reviewer profile) | gpt-5.4 (high, coder profile)
overall: 8.5
correctness: 9
security: 8
performance: 8
readability: 9
verdict: PASS | FAIL | WARN
threadId: thread_abc123
escalated: false
escalation-from: coder-profile  # only if escalated
tags:
  - review-score
  - metrics
---
```

## Trend Interpretation

| Trend | Meaning | Action |
|-------|---------|--------|
| Overall rising | Code quality improving | Keep current practices |
| Security dropping | New patterns introducing vulnerabilities | Run `/cso` comprehensive audit |
| Readability dropping | Rushed implementations or complex logic | Slow down, add more planning |
| High escalation rate | coder profile struggling with task complexity | Consider bumping default reasoning_effort to xhigh or using architect profile |
| Many FAIL verdicts | Systematic quality issue | Review architecture and constraints |
