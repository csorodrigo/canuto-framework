shortDescription: Validate dashboard changes with fixtures, totals, filters, API checks, and visual smoke tests.
usedBy: [architect, coder, tester, reviewer]
version: 1.0.0
lastUpdated: 2026-04-17
copyright: Rodrigo Canuto © 2026.

## Purpose

Prevent dashboard regressions where charts render but numbers, filters, dates, or loading states are wrong. Use this skill for analytics, admin, BI, reporting, and KPI dashboards.

---

## Checklist

- Identify data sources and API/query contracts.
- Use fixed fixtures for at least one known date range.
- Validate totals against source data.
- Test empty, loading, error, and partial-data states.
- Test date/timezone boundaries.
- Verify primary filters change the displayed data.
- Run a browser smoke test or screenshot check when UI is involved.
- Record any known fixture limitations in memory or test docs.

---

## Output Format

```markdown
## Dashboard Regression Check

### Data Contract
- <source/query/API and expected shape>

### Fixtures
- <fixture and expected totals>

### Checks Run
- [ ] totals
- [ ] filters
- [ ] timezone/date boundaries
- [ ] empty/loading/error states
- [ ] screenshot/browser smoke

### Risks
- <remaining risk or none>
```

---

## Guardrails

- Do not trust visual rendering alone; verify numbers.
- Do not update snapshots without explaining what changed.
- Do not add broad end-to-end tests when a small fixture test would catch the issue.
