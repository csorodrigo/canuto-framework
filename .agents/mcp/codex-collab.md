# Codex Collaboration MCP Server

MCP server that exposes OpenAI Codex CLI as tools for Claude Code, enabling multi-turn collaboration between Claude and Codex.

## Setup

```bash
claude mcp add codex-collab -- npx -y @openai/codex mcp-server
```

### Prerequisites

- Node.js 18+
- OpenAI API key configured (`OPENAI_API_KEY` in environment)
- Claude Code with MCP support

### Verify Installation

After adding the MCP server, these tools should be available:
- `mcp__codex-collab__codex` — Start a new Codex session
- `mcp__codex-collab__codex-reply` — Continue an existing session via `threadId`

## Tools Reference

### `mcp__codex-collab__codex`

Start a new Codex conversation session.

**Parameters:**
- `prompt` (string, required) — The initial prompt for Codex

**Returns:**
- `response` — Codex's response text
- `threadId` — Session ID for follow-up messages

### `mcp__codex-collab__codex-reply`

Continue an existing conversation with Codex.

**Parameters:**
- `threadId` (string, required) — Session ID from a previous call
- `message` (string, required) — Follow-up message

**Returns:**
- `response` — Codex's response text

## Usage Patterns

### Single-Shot Review (simple)
```
1. Call codex with review prompt
2. Read response
3. Done
```

### Multi-Turn with Clarifying Questions (recommended)
```
1. Call codex with initial prompt (tell it to say "ready" when done)
2. If response contains a question → call codex-reply with answer
3. Repeat until "ready" signal received
4. Call codex-reply asking it to share results
5. Process final output
```

### Background Subagent Pattern (for co-review)
```
1. Spawn background subagent
2. Subagent calls codex with prompt
3. Subagent handles clarifying questions via codex-reply
4. Subagent waits for "ready" signal
5. Main agent does independent work
6. When both done: subagent retrieves Codex output
7. Compare and synthesize
```

## Migration from Shell Hooks

This MCP server replaces the `plan-review.sh` shell hook for Codex integration.

| Aspect | Old (Hook) | New (MCP) |
|--------|-----------|-----------|
| Communication | Fire-and-forget | Multi-turn via threadId |
| Trigger | PostToolUse: ExitPlanMode only | Any persona, any time |
| Clarifying questions | Not supported | Supported via codex-reply |
| Bias prevention | Sequential (see plan, then review) | Parallel (independent work) |
| Setup | Copy .sh to ~/.claude/hooks/ | `claude mcp add` one-liner |

## Troubleshooting

- **"MCP tool not found"**: Run `claude mcp add codex-collab -- npx -y @openai/codex mcp-server`
- **"OPENAI_API_KEY not set"**: Export your API key in your shell profile
- **Timeout**: Codex sessions may take 30-60s for complex prompts. The MCP server handles timeouts internally.
- **Not available**: The co-review skill degrades gracefully — if MCP is not configured, it falls back to Claude-only review.
