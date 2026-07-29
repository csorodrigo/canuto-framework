#!/usr/bin/env bash
# claude-architect.sh — back-delegation MCP wrapper.
#
# Used ONLY when Codex is the active runtime (e.g. user runs
# `bash .agents/tools/codex-maestro.sh`) and Codex needs to back-delegate
# tier-1 reasoning to Claude Opus. Registered as `mcp__claude-architect`
# in Codex's MCP list.
#
# Note: a unica dependencia e o pacote `mcp`, declarada no cabecalho PEP 723
# do proprio claude-agent-mcp.py. A delegacao tier-2 do Canuto (Codex) NAO passa
# por aqui — ela e CLI direta, via `codex exec --profile <name>`.
#
# Lancado por `uv run --script`, NAO por `uvx --from codex-as-mcp`.
#
# O caminho antigo emprestava o virtualenv do codex-as-mcp so para ter o `mcp`
# no path — nenhuma linha de codigo dele era usada. Como o pedido dele e
# `mcp[cli]>=1.12.4` sem teto, o major 2.0.0 do `mcp` entrou sozinho e removeu
# `mcp.server.fastmcp`; o servidor passou a morrer no import, antes de responder
# o `initialize`, e o Codex reportava "connection closed: initialize response".
#
# Com `--script`, a dependencia esta declarada e travada DENTRO do proprio
# claude-agent-mcp.py (cabecalho PEP 723), onde da para revisar. O uv continua
# cacheando o ambiente por spec, entao a partida segue rapida: medido 815ms
# contra 1287ms do `uvx --from` — o conserto e mais rapido que o defeito.
#
# If running Claude as the active runtime, this wrapper is unused.
set -euo pipefail
exec uv run --script "$HOME/.claude/scripts/claude-agent-mcp.py" \
  --server-name claude-architect \
  --mode architect \
  "$@"
