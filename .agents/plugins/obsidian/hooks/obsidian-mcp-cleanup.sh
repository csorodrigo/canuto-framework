#!/usr/bin/env bash
set -u

if [ "${CANUTO_OBSIDIAN_PLUGIN_ACTIVE:-0}" != "1" ]; then
  exit 0
fi

guard="${CANUTO_OBSIDIAN_MCP_GUARD:-$HOME/.codex/bin/obsidian-mcp-guard}"
[ -x "$guard" ] || exit 0
exec "$guard" --cleanup-only
