---
skill: smart-token-metering
trigger: Automatic — Maestro checks budget before each handoff
persona: maestro
version: 1.0.0
lastUpdated: 2026-03-30
shortDescription: >
  Tracks Opus token usage per task. When approaching 80% budget, auto-switches
  remaining work to Codex. Opus does minimal orchestration only.
usedBy: [maestro]
evals:
  - prompt: "how much have we spent this session?"
    should_trigger: true
  - prompt: "switch to economy mode"
    should_trigger: true
  - prompt: "fix this bug"
    should_trigger: false
---

## Purpose

Prevent surprise Anthropic bills by tracking estimated Opus token consumption
and auto-delegating to Codex when budget threshold is reached.

---

## Budget Modes

| Mode | Opus Usage | Codex Usage | When |
|------|-----------|-------------|------|
| **Normal** | Planning + Review + Orchestration | Coding + Testing | Default |
| **Economy** | Orchestration only | Everything else | Budget > 80% |
| **Ultra-Economy** | Minimal routing | All tasks | Budget > 95% |

### Economy Mode Behavior

When `economy` mode activates:
1. Opus stops reading source files → delegates to codex-context-loader
2. Opus stops writing session notes → delegates to codex-session-writer
3. Opus stops generating PR descriptions → delegates to codex-pr-writer
4. Reviews shift to codex-reviewer only (no dual Claude+Codex review)
5. Opus's role reduces to: receive user request → route to Codex → present result

### Ultra-Economy Mode

When `ultra-economy` activates:
1. Everything in economy mode, plus:
2. Opus stops validating Codex output (trust threshold raised to confidence >= 6)
3. Multi-turn conversations answered by referencing cached digests only
4. Warn user: "Running in ultra-economy mode — quality may be reduced"

---

## Token Estimation

Approximate token counts per action:
| Action | Estimated Tokens |
|--------|-----------------|
| Read 1 file | 500-2000 |
| Plan (M task) | 5000-15000 |
| Review diff | 3000-10000 |
| Write session note | 2000-5000 |
| Orchestration message | 500-1500 |

Track cumulative estimate throughout session.

---

## Procedure

### Before Each Handoff
```
[Budget] Session: ~85K / 200K (42%). Mode: Normal.
Next: Coder delegation (~5K Opus for orchestration).
```

### At 80% Threshold
```
[Budget] Session: ~162K / 200K (81%). Switching to Economy mode.
Remaining tasks will maximize Codex delegation.
Options: (a) Continue in economy mode (b) Override — stay normal (c) End session
```

### At 95% Threshold
```
[Budget] Session: ~192K / 200K (96%). Ultra-economy mode.
Opus: routing only. All work delegated to Codex.
Recommend ending session soon.
```

---

## Integration

- **budget-controls.md**: this skill extends budget-controls with auto-switching
- **cost-routing.md**: economy mode changes routing decisions
- **codex-context-loader.md**: activated in economy mode
- **codex-session-writer.md**: activated in economy mode
