shortDescription: Pattern for scheduled agent activation in autonomous multi-agent setups.
usedBy: [maestro]
version: 1.0.0
lastUpdated: 2026-03-18
copyright: Rodrigo Canuto © 2026.
inspiration: Paperclip — heartbeat-based agent activation with scheduled wake-ups instead of continuous polling.

## When to Use

**Triggers:**
- Future multi-agent autonomous setups where agents run independently
- CI/CD pipeline integration where agents check for work periodically
- Monitoring workflows where agents wake up on schedule to verify system health
- User asks: `"set up a heartbeat"`, `"schedule a check"`, `"periodic review"`

**Not for:**
- Standard interactive sessions (Canuto is session-based by default)
- One-off tasks (use normal Maestro routing)

---

## Purpose

In interactive sessions, Maestro orchestrates work in real-time. But for **autonomous workflows** — CI monitoring, periodic code review, dependency updates — agents need a different model: wake up on schedule, check for work, execute if needed, go back to sleep.

The heartbeat pattern provides this foundation, enabling future evolution from session-based to autonomous orchestration.

---

## Concepts

### Heartbeat

A scheduled wake-up signal that triggers an agent to check for work:

```
Heartbeat: every 30m
Agent: Coder
Action: Check if new commits have tests, run test suite if commits found
```

### Heartbeat Config

Defined in `.agents/heartbeats.yml` (future) or manually triggered:

```yaml
heartbeats:
  - name: test-watcher
    agent: coder
    interval: 30m
    trigger: new-commits-without-tests
    action: run-tests-and-report

  - name: dependency-checker
    agent: architect
    interval: weekly
    trigger: outdated-dependencies
    action: propose-updates

  - name: context-freshness
    agent: contextualizer
    interval: daily
    trigger: stale-context-files
    action: update-context
```

### Heartbeat Lifecycle

```
Sleep → Wake (heartbeat) → Check (is there work?) → Execute (if yes) → Report → Sleep
```

Key principle: **agents don't run continuously**. They wake, check, act, sleep. This keeps costs predictable.

### Cost Control

Each heartbeat has a token budget:
- If the check phase finds no work → minimal cost (~100 tokens)
- If work is found → budget for the execution phase (per budget-controls skill)
- If budget is exceeded → skip this heartbeat, report, try next cycle

---

## Procedure

### Manual Heartbeat (Current)

Until autonomous tooling is available, heartbeats can be simulated manually:

1. User requests a periodic check:
   ```
   "Check for stale contexts every time I start a session"
   ```

2. Maestro adds to session-start routine:
   ```
   [Heartbeat: context-freshness] Checking for stale .context.md files...
   Result: 2 stale files found (src/api/, src/auth/)
   Action: Queue Contextualizer update
   ```

3. Log in audit trail:
   ```
   #### [2026-03-18 10:01] HEARTBEAT — context-freshness check
   - **Result:** 2 stale files detected
   - **Action:** Contextualizer update queued
   ```

### Autonomous Heartbeat (Future)

When multi-agent infrastructure is available:

1. Configure heartbeats in `.agents/heartbeats.yml`
2. External scheduler (cron, CI) triggers the heartbeat
3. Agent wakes, checks trigger condition
4. If triggered: executes action within budget
5. Reports results (PR comment, Slack, log file)
6. Goes back to sleep

### Built-in Heartbeat Patterns

| Pattern | Agent | Interval | Trigger | Action |
|---------|-------|----------|---------|--------|
| `test-watcher` | Coder | Per commit | New code without tests | Run test suite |
| `dependency-checker` | Architect | Weekly | Outdated deps | Propose updates |
| `context-freshness` | Contextualizer | Per session | Stale .context.md | Update context |
| `security-scan` | Reviewer | Weekly | Known vulnerabilities | Report findings |
| `metric-review` | Maestro | Monthly | Accumulated metrics | Trend analysis |

---

## Examples

### ✅ Good — session-start heartbeat check

```
[Heartbeat: context-freshness] Checking for stale .context.md files...
- src/api/.context.md — last updated 2026-03-15, 4 files changed since → STALE
- src/auth/.context.md — last updated 2026-03-17, 0 files changed → FRESH
- src/ui/.context.md — last updated 2026-03-10, 12 files changed → STALE

Action: Queue Contextualizer update for src/api/ and src/ui/
```

### ✅ Good — heartbeat with no work found

```
[Heartbeat: test-watcher] Checking for untested commits...
Result: All recent commits have associated test changes. No action needed.
Cost: ~100 tokens (check only)
```

### ❌ Bad — continuous polling

```
Checking for updates... (every 5 seconds)
Checking for updates...
Checking for updates...
```

This is bad because: heartbeats are scheduled, not polled. Continuous checking wastes resources and provides no value.

---

## Guardrails

- **Heartbeats are opt-in.** The framework is session-based by default. Heartbeats are for users who want autonomous capabilities.
- **Every heartbeat has a budget.** No open-ended execution.
- **Check before acting.** The check phase should be cheap (~100 tokens). Only spend on execution if work is found.
- **Log all heartbeat results.** Even "no work found" gets logged in the audit trail.
- **Don't overlap heartbeats.** If a heartbeat is still running when the next cycle triggers, skip the new cycle.
- **Manual heartbeats are first-class.** Until autonomous tooling exists, session-start checks are the primary implementation.
- **This is a future-facing skill.** Most of the autonomous patterns here await tooling support. The manual patterns work today.
