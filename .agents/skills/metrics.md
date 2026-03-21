shortDescription: How to track quality, velocity, compliance, and rework metrics across sessions.
usedBy: [maestro, reviewer]
version: 1.1.0
lastUpdated: 2026-02-25
copyright: Rodrigo Canuto © 2026.

## When to Use

**Triggers:**
- At session end — Maestro appends the session's metrics to `metrics.md`
- User asks about trends, quality, or performance: `"how are we doing?"`, `"show metrics"`, `"any rework patterns?"`
- Rework is detected in-session (file modified ≥3 times) — emit warning immediately

**Not for:**
- Real-time monitoring during a task (metrics are collected passively, not interactively)

---

## Purpose

Provide visibility into how the framework is performing over time. Metrics help identify recurring problems, measure improvement, and guide decisions about process changes.

Metrics are collected automatically by the Maestro at the end of each session and appended to a persistent log.

---

## Metrics Categories

### 1. Quality Metrics

Tracked per task (feature, bug fix, refactor):

| Metric | How It's Measured | Collected By |
|--------|-------------------|---------------|
| Review verdict | APPROVE vs REQUEST CHANGES on first review | Reviewer |
| MUST FIX count | Number of blocking issues found | Reviewer |
| Test failure rate | Tests failed / tests written (by Tester) | Tester |
| Debugger invocations | How many times Debugger was called | Maestro |
| Rework cycles | Times Coder had to revise after review | Maestro |

**Healthy signals:**
- First-pass approval rate > 70%.
- MUST FIX items per review < 2 on average.
- Debugger invocations < 1 per feature.

### 2. Velocity Metrics

Tracked per session:

| Metric | How It's Measured | Collected By |
|--------|-------------------|---------------|
| Tasks completed | Features/fixes fully done (approved) in this session | Maestro |
| Steps executed | Total Architect plan steps implemented | Maestro |
| Persona transitions | Number of handoffs in the session | Maestro |
| Escalations | Times a persona escalated to Maestro | Maestro |
| Goals achieved | Session goals marked ✅ vs total goals | Maestro |

**Healthy signals:**
- 1-3 tasks completed per session (depending on complexity).
- Escalations < 2 per session.
- Goals achieved rate > 60%.

### 3. Compliance Metrics

Tracked per persona invocation:

| Metric | How It's Measured | Collected By |
|--------|-------------------|---------------|
| Format compliance | Did the persona use the required output format? | Maestro |
| Scope compliance | Did the persona stay within its role? | Maestro |
| Handoff quality | Were all required handoff fields present? | Maestro |
| Anti-pattern violations | Did the persona do something from its "DO NOT" list? | Reviewer/Maestro |

**Healthy signals:**
- Format compliance > 90%.
- Scope violations = 0.

### 4. Rework Detection

Tracked per file per session:

| Signal | Threshold | Action |
|--------|-----------|--------|
| File modified N times | N ≥ 3 | Maestro emits rework warning |
| Coder called after REQUEST CHANGES | > 2 cycles | Maestro flags for Architect re-plan |
| Same test file fails repeatedly | 2+ consecutive failures | Maestro escalates to Debugger |

**Rework Detection Procedure:**

1. Maestro keeps an in-session file modification map: `{ "path/to/file": count }`.
2. Every time Coder reports modifying a file, increment its counter.
3. When any counter reaches 3, emit the rework warning immediately:
   > ⚠️ Rework detected: `<file>` modified 3 times this session. Consider re-planning or breaking the task into smaller steps.
4. At session end, record files with count ≥ 3 in the metrics log.

---

## Storage

### Vault: `.agents/vault/metrics/`

Each session's metrics are stored as an individual note with structured frontmatter:

```markdown
---
type: metric
session: "[[sessions/2026-03-21]]"
date: 2026-03-21
quality-verdict: APPROVE
must-fix-count: 1
test-failures: 0
debugger-invocations: 0
rework-cycles: 1
tasks-completed: 2
persona-transitions: 8
escalations: 0
format-compliance: 100
scope-violations: 0
tags:
  - metric
---

# Metrics — 2026-03-21

## Quality
- Review verdict: APPROVE
- MUST FIX count: 1
- Test failures: 0/12
- Debugger invocations: 0
- Rework cycles: 1
- Rework files: src/auth/token-service.ts (3 modifications)

## Velocity
- Tasks completed: 2
- Persona transitions: 8
- Escalations: 0
- Goals: 2/2 achieved (✅ Add JWT auth, ✅ Write integration tests)

## Compliance
- Format compliance: 4/4 personas compliant
- Scope violations: 0
```

Naming convention: `metrics/YYYY-MM-DD-metrics.md`

Query metrics via `bases/metrics-dashboard.base` for aggregated summaries (Sum, Average, trends).

---

## Procedure

### Collecting Metrics

1. **During the session**: Maestro keeps a running tally of transitions, escalations, file modifications, and provider usage.
2. **After Reviewer's verdict**: Maestro records quality metrics.
3. **After Tester's report**: Maestro records test metrics.
4. **At session end**: Maestro creates a metric note in `vault/metrics/YYYY-MM-DD-metrics.md` and marks goals.

### Reviewing Trends

When the user asks about metrics or trends:

1. Query `bases/metrics-dashboard.base` or `obsidian_list_notes(path="metrics/")`.
2. Read the last 5-10 metric notes and summarize.
3. Highlight:
   - Improving or worsening trends.
   - Recurring rework files (files that appear in rework across multiple sessions → likely a design issue).
   - Goal achievement rate trends.
   - Provider performance comparison (if multi-provider is active).

---

## Examples

### ✅ Good — complete session metrics entry

```markdown
## Session: 2026-03-01

### Quality
- Review verdict: APPROVE
- MUST FIX count: 1
- Test failures: 0/12
- Debugger invocations: 0
- Rework cycles: 1
- Rework files: src/auth/token-service.ts (3 modifications)

### Velocity
- Tasks completed: 2
- Steps executed: 6
- Persona transitions: 8
- Escalations: 0
- Goals: 2/2 achieved (✅ Add JWT auth, ✅ Write integration tests)
```

### ❌ Bad — fabricated or missing metrics

```markdown
## Session: 2026-03-01
Everything went well. Tests passed.
```

This is bad because: no structured fields, unmeasurable, cannot be compared across sessions — trend analysis becomes impossible.

---

## Guardrails

- Metrics are append-only. Never delete previous entries.
- Metrics collection MUST NOT slow down the session. If a metric is hard to measure, skip it and note "N/A".
- Metrics are descriptive, not prescriptive. They inform decisions but do not automatically change behavior.
- Never fabricate metrics. If a persona was not invoked, do not record metrics for it.
- The metrics file is committed alongside code changes (it's part of `.agents/memory/`).
