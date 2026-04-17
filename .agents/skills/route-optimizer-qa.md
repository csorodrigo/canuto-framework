shortDescription: Validate route optimization with address fixtures, geocoding checks, invalid-address handling, and before/after metrics.
usedBy: [architect, coder, tester, reviewer]
version: 1.0.0
lastUpdated: 2026-04-17
copyright: Rodrigo Canuto © 2026.

## Purpose

Keep route optimization changes measurable. Use this skill for logistics, routing, geocoding, delivery sequencing, territory planning, and route dashboards.

---

## Required Checks

- Fixed address fixture with known valid, ambiguous, and invalid addresses.
- Geocoding cache behavior is explicit.
- Invalid addresses are reported without crashing the run.
- Before/after route metrics are shown:
  - total distance
  - estimated duration
  - number of stops
  - unassigned/invalid stops
- API/provider failures have a fallback or clear user-facing error.
- The optimized route is deterministic for the same fixture, or nondeterminism is documented.

---

## Output Format

```markdown
## Route QA

### Fixture
- <fixture path/source>

### Metrics
| Metric | Before | After | Notes |
|--------|--------|-------|-------|

### Invalid Address Handling
- <behavior>

### Remaining Risks
- <risk or none>
```

---

## Guardrails

- Do not claim optimization improved without before/after metrics.
- Do not hide invalid addresses inside aggregate totals.
- Do not call external geocoding repeatedly when a fixture or cache can prove behavior.
