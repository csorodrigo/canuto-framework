# Alert Rules

## Severity Levels
- **info:** FYI — state changes or low-risk anomalies
- **warn:** may need attention soon; monitor continues
- **error:** action needed; notify assigned persona immediately
- **critical:** immediate action required; escalate to Maestro + owning persona

## Pattern Categories

| Category | Sample Regex |
|----------|--------------|
| Compilation errors | `/error\s*(TS|E)\d+/`, `/error\[E\d+\]/`, `/FAIL/` |
| Test failures | `/FAIL|✗|×|failed/i`, `/\d+ failed/`, `/AssertionError/` |
| Process crashes | `/SIGTERM|SIGKILL|exit code [1-9]/`, `/Segmentation fault/`, `/panic:/` |
| Performance | `/warning.*memory/i`, `/heap out of memory/`, `/timeout/i` |
| Security | `/vulnerability|CVE-\d{4}/i`, `/deprecated.*insecure/i` |

Patterns are additive; profiles can extend with domain-specific rules.

## Compound Rules
- **Warning spam:** 3 warnings of the same type in 60 seconds ⇒ escalate severity to `error` (`alert-rule: warn-spam`)
- **Test collapse:** >50% of executed tests failing during a single run ⇒ escalate to `critical` (`alert-rule: test-collapse`)
- **Deploy rollback:** detection of rollback command after deploy failure ⇒ auto `critical` and ping Maestro + Deploy owner

## Threshold-Then-Act Model
Monitor never takes action itself. For each alert:
1. Present options (acknowledge, pause monitor, open log tail, stop process) to user.
2. Respect persona ownership — Maestro routes if user silent.
3. If automation is requested (e.g., restart dev server), record delegation separately; monitor only observes.

## Routing Defaults
- Build/test warnings → Coder/Tester
- Deploy/CI errors → Maestro
- Security alerts → Reviewer (if session has one) else Maestro

> Keep regex rules in sync with `references/profiles.md`. Update both when adding new process signatures.
