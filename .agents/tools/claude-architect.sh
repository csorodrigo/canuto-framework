#!/usr/bin/env bash
# claude-architect.sh — back-delegation MCP wrapper.
#
# Used ONLY when Codex is the active runtime (e.g. user runs
# `bash .agents/tools/codex-maestro.sh`) and Codex needs to back-delegate
# tier-1 reasoning to Claude Opus. Registered as `mcp__claude-architect` in Codex's MCP list.
#
# Note: a unica dependencia e o pacote `mcp`, declarada no cabecalho PEP 723
# do proprio claude-agent-mcp.py. A delegacao tier-2 do Canuto (Codex) NAO passa
# por aqui — ela e CLI direta, via `codex exec --profile <name>`.
#
# DOIS caminhos, e a ordem importa para o tempo de abertura do Codex.
#
# Preferido: o python do venv fixo que o instalador monta a partir do cabecalho
# PEP 723. Medido num MacBook Air: `uv run --script` gasta ~1,1s SO na camada do
# uv, antes de o Python comecar — vezes dois servidores, em toda sessao. O venv
# direto pula isso inteiro.
#
# Reserva: `uv run --script`, que resolve o ambiente sozinho. Existe para o caso
# de venv ausente ou quebrado — degradar para "abre devagar" e muito melhor que
# degradar para "nao abre". Sem esta linha, um venv corrompido derrubaria a
# back-delegation em vez de so atrasa-la.
#
# O que NAO da para acelerar: ~2,6s do `import mcp.server.fastmcp`, que arrasta
# o pydantic. E preco da biblioteca, igual nos dois caminhos.
#
# If running Claude as the active runtime, this wrapper is unused.
set -euo pipefail

MCP_SCRIPT="$HOME/.claude/scripts/claude-agent-mcp.py"
MCP_VENV_PY="$HOME/.claude/scripts/.mcp-venv/bin/python"

if [ -x "$MCP_VENV_PY" ]; then
  exec "$MCP_VENV_PY" "$MCP_SCRIPT" \
    --server-name claude-architect \
    --mode architect \
    "$@"
fi

exec uv run --script "$MCP_SCRIPT" \
  --server-name claude-architect \
  --mode architect \
  "$@"
