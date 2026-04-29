---
name: ccb
version: 1.0.0
description: Terminal-based multi-model collaboration via claude-code-bridge (CCB) — visible panes for Claude and Codex
author: canuto-framework
requires:
  - multi-provider
compatible: ">=1.6.0"
---

# CCB Plugin (Claude Code Bridge)

Integrates CCB v5.2.6 as an optional delegation backend for Canuto sessions. Adds real terminal-based parallel execution alongside existing API and MCP delegation.

## Skills Provided

| Skill | Trigger | Description |
|-------|---------|-------------|
| `ccb-delegate` | `/ccb-delegate` | Delegate tier-2 tasks to visible CCB terminal panes |
| `ccb-session` | `/ccb-session` | Manage CCB sessions (launch, resume, status) |

## Setup

1. Install CCB:
   ```bash
   git clone https://github.com/bfly123/claude_code_bridge.git
   cd claude_code_bridge
   ./install.sh install
   ```

2. Ensure each CLI is authenticated with your subscription:
   ```bash
   claude          # Anthropic Max login
   codex --login   # ChatGPT Plus/Pro login
   ```

3. Verify installation:
   ```bash
   ccb --version && ask --help && pend --help
   ```

4. Optionally configure CCB preferences in CLAUDE.md:
   ```markdown
   ## Plugins
   - ccb:
     providers: codex             # which providers to launch by default
     auto_approve: false          # -a flag (requires explicit opt-in)
     max_panes: 2                 # terminal real estate limit
   ```

## When Maestro Should Load This Plugin

- User mentions "CCB", "panes", "terminal panes", "visible execution", "split-pane"
- User wants to see multiple providers working simultaneously in terminal
- User requests session resumption across sessions (`-r` flag)
- User wants terminal-based delegation instead of API/MCP delegation
- User runs `ccb codex` or similar commands

## Risks

- **External dependency**: CCB must be installed separately. Framework works identically without it.
- **Terminal multiplexer required**: WezTerm or tmux must be available and running.
- **Pane limits**: Too many panes overwhelm terminal real estate. Plugin caps at 3 concurrent panes.
- **Session logs**: JSONL session logs can grow large. Suggest periodic cleanup via `ccb-session`.
- **Daemon stability**: CCB's `askd` daemon must be running. Auto-restarts on failure but can hang in edge cases.
- **Open issues**: CCB has 37 open issues including multi-instance collision and async deadlocks.

## Notes

This is an **opt-in** plugin. Does not alter default framework behavior. CCB complements (does not replace) the default CLI delegation pattern (`codex exec --profile <name>`).

CCB sessions track operational history (JSONL logs per provider). Canuto's vault remains the source of truth for strategic memory (decisions, instincts, metrics).
