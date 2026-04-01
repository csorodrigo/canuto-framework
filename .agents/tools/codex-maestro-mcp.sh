#!/usr/bin/env bash

set -euo pipefail

exec uvx --from codex-as-mcp@latest \
  python "$HOME/.claude/scripts/codex-agent-mcp.py" \
  --server-name codex-maestro \
  --profile maestro \
  --mode coder \
  "$@"
