# Monitor Integration Schema

## Audit Events

### MONITOR_START
```markdown
---
type: audit-event
event: MONITOR_START
date: 2026-04-10T14:05:00
actor: maestro
session: "[[sessions/2026-04-10]]"
monitor:
  session: build-monitor-1
  process: "pnpm build"
  profile: build
  mode: scan
  token-budget: 5000
  token-budget-used: 0
impact: low
tags:
  - audit
  - monitor
---
```

### MONITOR_ALERT
```markdown
---
type: audit-event
event: MONITOR_ALERT
date: 2026-04-10T14:07:12
actor: maestro
session: "[[sessions/2026-04-10]]"
monitor:
  session: build-monitor-1
  profile: build
  severity: error
  rule: compilation-error
  evidence: "error TS2307: Cannot find module 'next-auth'"
impact: medium
tags:
  - audit
  - monitor
  - alert
---
```

### MONITOR_STOP
```markdown
---
type: audit-event
event: MONITOR_STOP
date: 2026-04-10T14:20:30
actor: maestro
session: "[[sessions/2026-04-10]]"
monitor:
  session: build-monitor-1
  duration: "00:15:10"
  alerts:
    info: 0
    warn: 1
    error: 2
    critical: 0
  token-budget-used: 2400
  mode-transitions:
    - scan
    - focus
impact: low
tags:
  - audit
  - monitor
---
```

## Metrics Extension

Add the following fields to session metrics documents:

| Field | Description |
|-------|-------------|
| `monitor-sessions` | Count of monitor sessions started |
| `monitor-alerts-info` | Number of info alerts |
| `monitor-alerts-warn` | Number of warn alerts |
| `monitor-alerts-error` | Number of error alerts |
| `monitor-alerts-critical` | Number of critical alerts |
| `monitor-token-budget-used` | Total tokens consumed by monitoring |
| `monitor-triggered-activations` | Number of persona activations caused by alerts |

Metrics body example addition:
```markdown
## Monitor
- Sessions: 1 (build-monitor-1, 15m)
- Alerts: 0 info / 1 warn / 2 error / 0 critical
- Token budget: 2,400 / 5,000 (48%)
- Triggered activations: 1
```

## Trace-Analysis Mapping

| Monitor Signal | Trace Category |
|----------------|----------------|
| Repeated build errors | playbook-gap |
| Crash or OOM alerts | blind-spot-gap |
| Test failure alerts on undersized task | routing-misfire |
| Frequent manual monitoring of same process | skill-gap |

Trace-analysis ingests `vault/audit/*-MONITOR_ALERT-*.md` to seed the categories above. Include evidence snippet + severity when generating digests.
