#!/usr/bin/env bash
# claude-architect.sh — back-delegation MCP wrapper.
#
# Used ONLY when Codex is the active runtime (e.g. user runs
# `bash .agents/tools/codex-maestro.sh`) and Codex needs to back-delegate
# tier-1 reasoning to Claude Opus. Registered as `mcp__claude-architect`
# in Codex's MCP list.
#
# Note: depends on `codex-as-mcp` (PyPI package, not our retired
# codex-coder/reviewer wrappers). codex-as-mcp is a generic MCP launcher
# library — Canuto's tier-2 Codex delegation does NOT use it (CLI direct
# via `codex exec --profile <name>` instead).
#
# SEM `@latest`, e isso é deliberado. O sufixo força o uv a resolver a versão
# mais nova NO PYPI a cada lançamento — uma ida à rede por servidor, por sessão,
# no caminho de abertura do Codex. Medido: 357-803ms com `@latest` contra 52ms
# usando o cache; e quando a rede vai mal isso vira o timeout de 30s por servidor
# que o Codex reporta ("MCP client for `claude-reviewer` timed out after 30
# seconds"). Sem o sufixo, o uv usa o que já está em cache e só vai à rede na
# primeira vez — que o instalador adianta com `uv tool install`.
#
# If running Claude as the active runtime, this wrapper is unused.
set -euo pipefail
exec uvx --from codex-as-mcp \
  python "$HOME/.claude/scripts/claude-agent-mcp.py" \
  --server-name claude-architect \
  --mode architect \
  "$@"
