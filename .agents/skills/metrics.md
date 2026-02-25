shortDescription: How to track quality, velocity, and compliance metrics across sessions.
usedBy: [maestro, reviewer]
version: 1.0.0
lastUpdated: 2026-02-25
copyright: Rodrigo Canuto © 2026.

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

**Healthy signals:**
- 1-3 tasks completed per session (depending on complexity).
- Escalations < 2 per session.

### 3. Compliance Metrics

Tracked per persona invocation:

| Metric | How It's Measured | Collected By |
|--------|-------------------|---------------|
| Format compliance | Did the persona use the required output format? | Maestro |
| Scope compliance | Did the persona stay within its role? (e.g., Coder didn't review) | Maestro |
| Handoff quality | Were all required handoff fields present? | Maestro |
| Anti-pattern violations | Did the persona do something from its "DO NOT" list? | Reviewer/Maestro |

**Healthy signals:**
- Format compliance > 90%.
- Scope violations = 0.

---

## Storage

### File: `.agents/memory/metrics.md`

Metrics are appended to this file at the end of each session.

```markdown
# Metrics Log

---

## Session: YYYY-MM-DD

### Quality
- Review verdict: APPROVE | REQUEST CHANGES
- MUST FIX count: N
- Test failures: N/M
- Debugger invocations: N
- Rework cycles: N

### Velocity
- Tasks completed: N
- Steps executed: N
- Persona transitions: N
- Escalations: N

### Compliance
- Format compliance: N/N personas compliant
- Scope violations: N
- Handoff quality: N/N complete
- Anti-pattern violations: N (details: ...)

### Provider Performance (if multi-provider)
- Provider: <name> — Tasks: N — First-try success: N — Fallbacks: N
```

---

## Procedure

### Collecting Metrics

1. **During the session**: Maestro keeps a running tally of transitions, escalations, and provider usage.
2. **After Reviewer's verdict**: Maestro records quality metrics.
3. **After Tester's report**: Maestro records test metrics.
4. **At session end**: Maestro writes the full metrics entry to `metrics.md`.

### Reviewing Trends

When the user asks about metrics or trends:

1. Read `.agents/memory/metrics.md`.
2. Summarize the last 5-10 sessions.
3. Highlight:
   - Improving or worsening trends.
   - Recurring issues (e.g., "Coder consistently gets REQUEST CHANGES on auth-related tasks").
   - Provider performance comparison (if multi-provider is active).

---

## Guardrails

- Metrics are append-only. Never delete previous entries.
- Metrics collection MUST NOT slow down the session. If a metric is hard to measure, skip it and note "N/A".
- Metrics are descriptive, not prescriptive. They inform decisions but do not automatically change behavior.
- Never fabricate metrics. If a persona was not invoked, do not record metrics for it.
- The metrics file is committed alongside code changes (it's part of `.agents/memory/`).
