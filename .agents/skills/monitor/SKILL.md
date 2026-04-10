---
name: monitor
description: Real-time process monitoring during active development with smart alerting and pipeline integration.
shortDescription: Stream and analyze background process events in real-time — feed alerts into audit-trail and metrics pipeline.
usedBy: [maestro]
version: 1.0.0
lastUpdated: 2026-04-10
copyright: Rodrigo Canuto © 2026.
evals:
  - prompt: "monitor the build while I work on the next task"
    should_trigger: true
  - prompt: "watch the dev server for errors in the background"
    should_trigger: true
  - prompt: "show me the test results from last run"
    should_trigger: false
  - prompt: "run the health check on the framework"
    should_trigger: false
---

## When to Use

**Triggers:**
- User says "monitor the build", "watch tests", "keep an eye on the server"
- Background process launched via Ctrl+B with expectation of side-channel monitoring
- Maestro detects long-running build/test/deploy/dev-server process that benefits from /monitor streaming

**Not for:**
- One-off command execution (run it inline instead)
- Post-hoc log analysis (use `trace-analysis`)
- Health checks (use `health-check`)
- Scheduled periodic checks (use `heartbeat`)

---

## Purpose

Bridge real-time observation with the post-hoc pipeline. Audit-trail, metrics, and trace-analysis capture **what already happened**. Monitor captures **what is happening now**: it streams output from background processes via Claude Code's `/monitor`, applies intelligent sampling, detects actionable patterns, and feeds structured events into audit + metrics so other personas can react without leaving their focus.

---

## Concepts

### Monitor Session
A named monitoring context (e.g., `build-monitor-1`) attached to a background process. Holds lifecycle state, token budget, mode (Scan/Focus/Full), and profile metadata.

### Monitor Profile
Predefined config per process type (build, test, deploy, dev-server, ci-pipeline). Profiles define watched commands, sampling interval, alert thresholds, and routing. Details: `references/profiles.md`.

### Alert
Pattern-matched event with severity (`info`, `warn`, `error`, `critical`). Alerts route to personas and audit events per `references/alert-rules.md`.

### Sampling Strategy
Controls how much output is processed:
- **Scan:** default; read every Nth line (profile-defined, default 10). Minimal cost.
- **Focus:** triggered by pattern detection; read every line for a 30s context window. Moderate cost, auto-exits.
- **Full:** explicit user request; stream entire output until stopped or budget exhausted. Highest cost.

---

## Dual Activation
- **Opt-in:** user sets `CANUTO_MONITOR=1` or directly requests monitoring.
- **Auto-suggest:** Maestro prompts to start monitoring when Ctrl+B (or similar) launches long-running background processes; user must confirm before activation.

---

## Token Budget
Each monitor session gets 5K tokens per 10-minute window. If usage exceeds budget, drop to Scan-only mode, warn Maestro, and log a `MONITOR_ALERT` with severity `warn` explaining the downgrade. Budget rules mirror `heartbeat` cost controls.

---

## Monitor Lifecycle
1. **Start:** `MONITOR_START` event logged with process, profile, mode, and budget.
2. **Sample:** apply profile's Scan interval; maintain rolling buffer for Focus windows.
3. **Detect:** evaluate lines against alert rules + compound thresholds.
4. **Alert:** emit in-session notification + `MONITOR_ALERT` audit event (non-blocking to user flow).
5. **Feed:** append stats to metrics counters for real-time dashboards.
6. **Stop:** on user stop or process end, emit `MONITOR_STOP` with summary (duration, tokens, alerts).

---

## Procedure
1. Maestro identifies a monitorable process (explicit user request or background detection).
2. Select an existing profile or create a temporary override per `references/profiles.md`.
3. Start monitoring using Claude Code `/monitor` stream; log `MONITOR_START`.
4. Apply sampling strategy (Scan by default, escalate to Focus when triggers fire, Full only on user mandate).
5. When alert rules match (`references/alert-rules.md`):
   - Emit in-session notification without stealing focus.
   - Log `MONITOR_ALERT` with severity + evidence.
   - Route alert to assigned persona; update metrics counters.
6. When monitoring stops (user stop, process exit, or budget exhaustion):
   - Summarize stats (duration, tokens, alerts, mode transitions).
   - Log `MONITOR_STOP` and push counters to metrics snapshot.
7. At session end, metrics aggregator includes monitor stats so `trace-analysis` can treat alerts as signal inputs.

---

## New Audit Event Types
- `MONITOR_START` — monitoring session begins (record process, profile, budget, initiator).
- `MONITOR_ALERT` — pattern-matched alert with severity + evidence snippet.
- `MONITOR_STOP` — monitoring session ends; include summary counters.

Details + schema: `references/integration-schema.md`.

---

## Integration Points
- **audit-trail:** consumes new event types for lifecycle logging.
- **metrics:** stores session-level monitor stats and budget usage.
- **trace-analysis:** treats `MONITOR_ALERT` notes as signal sources.
- **heartbeat:** if monitor already watching a concern, heartbeat watcher for same concern can be skipped.

---

## Guardrails
- Monitoring is never silent; opt-in or confirmed auto-suggest only.
- Enforce token budgets; auto-downgrade to Scan on overage.
- Only enter Full mode on explicit user instruction.
- Alerts must be actionable per `references/alert-rules.md`; ignore noise.
- Monitor observes only; it never modifies, restarts, or kills processes.
- Avoid duplication with heartbeat; pick one mechanism per concern.
- Log every session (start, alerts, stop) to audit trail for traceability.
- Requires Claude Code `/monitor` (v2.1.98+). If unavailable, explain fallback (manual sampling) and log feature degradation.
