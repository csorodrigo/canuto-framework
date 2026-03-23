# Vault Schema — Experiment Series

Save to `~/.canuto/vault/projects/{project-slug}/experiments/SER-XXX-slug.md`:

```markdown
---
type: experiment-series
id: SER-001
goal: "<goal>"
metric: "<metric>"
direction: higher-is-better | lower-is-better
variable: "<variable>"
status: concluded | active | paused
experiments-count: N
best-experiment: EXP-005
original-baseline: <value>
final-result: <value>
improvement: "+N%"
date-started: YYYY-MM-DD
date-concluded: YYYY-MM-DD
tags:
  - experiment
  - optimization
---

# SER-001: <Goal>

## Configuration
- **Metric:** <metric> (<direction>)
- **Variable:** <variable>
- **Test method:** <description>
- **Threshold:** <min improvement to keep>

## Experiments

| ID | Variation | Result | vs Baseline | Verdict |
|----|-----------|--------|-------------|---------|
| EXP-001 | <desc> | <value> | +N% | KEEP |
| EXP-002 | <desc> | <value> | -N% | DISCARD |
| ... | ... | ... | ... | ... |

## Conclusion

<What we learned. Best variation and why it works.>

## Applied

- [ ] Best variation applied as new default on YYYY-MM-DD
```
