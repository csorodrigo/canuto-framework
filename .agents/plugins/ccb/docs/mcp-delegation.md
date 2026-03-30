# CCB MCP Delegation Server

MCP server that exposes CCB's multi-provider delegation as tools for Claude Code. Located at `mcp/ccb-delegation/server.py` in the CCB installation (`~/.local/share/codex-dual/mcp/ccb-delegation/`).

## Setup

```bash
claude mcp add ccb-delegation -- python3 ~/.local/share/codex-dual/mcp/ccb-delegation/server.py
```

### Prerequisites

- CCB installed (`ccb --version`)
- CCB daemon (`askd`) running — starts automatically with `ccb`
- Python 3.10+

### Verify Installation

After adding the MCP server, these tools should be available in Claude Code:

| Tool | Description |
|------|-------------|
| `ccb_ask_codex(prompt)` | Send task to Codex pane |
| `ccb_ask_gemini(prompt)` | Send task to Gemini pane |
| `ccb_ask_claude(prompt)` | Send task to another Claude pane |
| `ccb_pend(task_id)` | Retrieve async task result |
| `ccb_ping(provider)` | Check if a provider pane is responsive |

Short aliases also available: `cask` (codex), `gask` (gemini), `lask` (claude), `oask` (opencode).

## Relationship to codex-collab MCP

| Aspect | codex-collab | ccb-delegation |
|--------|-------------|----------------|
| **Backend** | OpenAI Codex CLI directly | CCB askd daemon |
| **Providers** | Codex only | Codex, Gemini, Claude, OpenCode, Droid |
| **Terminal panes** | No (background) | Yes (visible) |
| **Session persistence** | No (threadId in memory) | Yes (JSONL logs, resumable with `-r`) |
| **Multi-turn** | Via threadId | Via session context |
| **Best for** | Bias-free background co-review | Visible multi-provider collaboration |
| **Anchoring risk** | None (output hidden until ready) | Possible (pane output visible) |

Both can coexist. Use codex-collab for bias-free background reviews (co-review skill). Use ccb-delegation for visible, session-persistent multi-provider work.

## How It Works

```
Claude Code → MCP tool call (e.g., ccb_ask_codex)
  → CCB MCP server receives request
  → Routes through askd daemon (socket RPC)
  → Dispatches to Codex pane via codex_comm
  → Task executes visibly in terminal pane
  → Result returned via MCP response (or pend for async)
```

## Configuration

The MCP server reads CCB's standard configuration:
- Config file: `ccb.config` or `.ccb-config.json` (project or global)
- Daemon state: `~/.askd-state.json` (host, port, auth token)
- Task cache: `~/.cache/ccb/delegation/`

## Troubleshooting

| Issue | Solution |
|-------|----------|
| MCP tool not found | Verify CCB daemon is running: check for `askd` process |
| Connection refused | Check daemon socket: `cat ~/.askd-state.json` for host:port |
| Provider not responding | Check individual provider auth: `ccb-ping <provider>` |
| Task timeout | Default is 3600s (`CLAUDE_SYNC_TIMEOUT`). Reduce if needed |
| Stale task results | Clean cache: `rm -rf ~/.cache/ccb/delegation/*` |

If the MCP server is unavailable, the `ccb-delegate` skill falls back to CLI `ask` command, then to codex-collab MCP, then to API delegation.
