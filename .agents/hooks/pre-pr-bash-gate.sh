#!/usr/bin/env bash
# pre-pr-bash-gate.sh — PreToolUse hook (matcher: Bash).
# Fecha o bypass do gate de testes: require-tests-for-pr.sh só intercepta o
# tool MCP do GitHub; um `gh pr create` via Bash passava reto (achado da
# comparação edge-of-chaos 2026-07-26 — "verify at exit, at the one seam
# every publish must cross": a costura é QUALQUER criação de PR).
#
# Exit 2 = bloqueia + razão no stderr (vai para o Claude). Exit 0 = permite.
# Override consciente: CANUTO_SKIP_PR_GATE=1 (fica registrado no event log).

set -uo pipefail

# Sem payload num TTY: `cat` sem stdin fechado bloqueia para sempre e o
# runtime que espera o hook congela junto (regra de TTY/pipe do CLAUDE.md).
INPUT=""
[ -t 0 ] || INPUT=$(cat 2>/dev/null || true)

COMMAND=""
if command -v jq >/dev/null 2>&1; then
  COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || COMMAND=""
else
  COMMAND="$INPUT"
fi

# Só nos interessa criação de PR via gh CLI (aceita flags entre "pr" e "create")
if ! printf '%s' "$COMMAND" | grep -Eq '(^|[;&|[:space:]])gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)'; then
  exit 0
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../tools/event-log.sh" ]; then
  # shellcheck source=../tools/event-log.sh
  . "$SCRIPT_DIR/../tools/event-log.sh"
elif [ -f "$PROJECT_DIR/.agents/tools/event-log.sh" ]; then
  # shellcheck source=/dev/null
  . "$PROJECT_DIR/.agents/tools/event-log.sh"
else
  canuto_event_append() { return 0; }
fi

if [ "${CANUTO_SKIP_PR_GATE:-0}" = "1" ]; then
  canuto_event_append GATE actor=hook gate=pr-tests verdict=skipped reason=CANUTO_SKIP_PR_GATE || true
  echo "[pre-pr-bash-gate] CANUTO_SKIP_PR_GATE=1 — gate de testes pulado (registrado no event log)." >&2
  exit 0
fi

# Reusa o mesmo runner do gate MCP quando disponível
GATE_SCRIPT=""
for candidate in "$SCRIPT_DIR/require-tests-for-pr.sh" \
                 "$PROJECT_DIR/.agents/hooks/require-tests-for-pr.sh"; do
  if [ -f "$candidate" ]; then GATE_SCRIPT="$candidate"; break; fi
done

if [ -z "$GATE_SCRIPT" ]; then
  # Sem runner compartilhado — não inventa política própria, permite e registra.
  canuto_event_append GATE actor=hook gate=pr-tests verdict=unavailable reason=no-gate-script || true
  exit 0
fi

if CLAUDE_PROJECT_DIR="$PROJECT_DIR" bash "$GATE_SCRIPT" </dev/null; then
  canuto_event_append GATE actor=hook gate=pr-tests verdict=pass via=bash-gh || true
  exit 0
else
  canuto_event_append GATE actor=hook gate=pr-tests verdict=fail via=bash-gh || true
  echo "Tests are failing. Fix all test failures before creating a PR (gate: pre-pr-bash-gate, mesmo critério do gate MCP)." >&2
  exit 2
fi
