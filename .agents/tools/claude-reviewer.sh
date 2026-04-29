#!/usr/bin/env bash
# claude-reviewer.sh — back-delegation MCP wrapper.
#
# Used ONLY when Codex is the active runtime (e.g. user runs
# `bash .agents/tools/codex-maestro.sh`) and Codex needs to back-delegate
# code review to Claude Sonnet for cross-model bias-free review.
# Registered as `mcp__claude-reviewer` in Codex's MCP list.
#
# Note: depends on `codex-as-mcp@latest` (PyPI package, not our retired
# codex-coder/reviewer wrappers). codex-as-mcp is a generic MCP launcher
# library — Canuto's tier-2 Codex delegation does NOT use it (CLI direct
# via `codex exec --profile <name>` instead).
#
# If running Claude as the active runtime, this wrapper is unused.
set -euo pipefail
exec uvx --from codex-as-mcp@latest \
  python "$HOME/.claude/scripts/claude-agent-mcp.py" \
  --server-name claude-reviewer \
  --mode reviewer \
  "$@"
