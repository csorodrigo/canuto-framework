---
skill: ccb-session
trigger: /ccb-session
persona: maestro
version: 1.0.0
lastUpdated: 2026-03-29
plugin: ccb
shortDescription: >
  Manage CCB terminal sessions: launch split-pane environment, resume previous
  sessions, check pane status, and clean up session logs.
usedBy: [maestro]
evals:
  - prompt: "start a ccb session with codex"
    should_trigger: true
  - prompt: "resume yesterday's ccb session"
    should_trigger: true
  - prompt: "check ccb pane status"
    should_trigger: true
  - prompt: "delegate this task to codex"
    should_trigger: false
  - prompt: "what's the framework health?"
    should_trigger: false
---

## When to Use

**Triggers:**
- User wants to launch CCB split-pane environment
- User wants to resume a previous CCB session (`-r` flag)
- User asks for CCB session status or cleanup
- On session start, if CCB plugin is active and resumable sessions exist

**Not for:**
- Individual task delegation (use `ccb-delegate`)
- Non-CCB provider management

---

## Procedure

### 1. Launch CCB Environment

```bash
# Default: launch providers from ccb.config
ccb

# Specific providers
ccb codex

# Resume previous session contexts
ccb -r

# Resume with auto-approval (requires explicit user opt-in)
ccb -a -r codex
```

**Before launching**: confirm with the user which providers to include. Never launch without confirmation.

### 2. Check Session Status

```bash
# Ping individual providers
ccb-ping codex

# Check daemon status
# askd state file: ~/.askd-state.json
```

Report:
- Which panes are active
- Which providers are responsive
- JSONL session log paths and sizes

### 3. Resume Previous Session

The `-r` flag loads previous JSONL session logs for each provider, restoring message history. Useful when:
- Canuto session continues from previous day
- Maestro detects pending CCB tasks from last session
- User explicitly asks to resume ("continue where we left off")

### 4. Session Cleanup

Suggest cleanup when:
- JSONL logs exceed 10MB per provider
- Session is older than 7 days with no pending tasks
- User explicitly requests cleanup

Session log locations:
- Claude: `~/.claude/projects/<project-key>/`
- Codex: `~/.codex/sessions/*/messages.jsonl`
- CCB cache: `~/.cache/ccb/`

---

## Integration with Canuto Session Lifecycle

**On Canuto session start** (if CCB plugin is active):
- Check for resumable CCB sessions
- If found, mention in briefing: `[CCB] Resumable session from {date} with {providers}. Resume with /ccb-session resume.`

**On Canuto session end**:
- Report CCB session status (active panes, pending `pend` results)
- CCB sessions persist independently — they survive Canuto session boundaries

**Key distinction**: CCB session persistence (JSONL logs) is operational — it tracks what each provider said. Canuto's vault persistence is strategic — it tracks decisions, instincts, and learnings. They complement each other.

---

## Examples

### Good — launch with confirmation

```
User: start ccb with codex
Maestro: [CCB] Launching split-pane environment.
  - Pane 1: Claude (this session)
  - Pane 2: Codex
  Terminal: WezTerm detected.
  Confirm launch? [y/n]
```

### Good — resume with status

```
User: resume ccb session
Maestro: [CCB] Found resumable session from 2026-03-28:
  - Codex: 23 messages, 2 pending tasks
  Resuming with -r flag...
```

---

## Guardrails

- Never launch CCB panes without user confirmation.
- The `-a` (auto-approval) flag requires explicit opt-in in CLAUDE.md or runtime confirmation.
- Maximum 3 panes (including the orchestrating Claude pane).
- CCB sessions are advisory — Canuto's vault remains the source of truth for memory.
- If the terminal multiplexer (WezTerm/tmux) is not detected, inform user and abort gracefully.
