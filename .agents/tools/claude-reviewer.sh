#!/usr/bin/env bash
set -euo pipefail
exec uvx --from codex-as-mcp@latest \
  python "$HOME/.claude/scripts/claude-agent-mcp.py" \
  --server-name claude-reviewer \
  --mode reviewer \
  "$@"
