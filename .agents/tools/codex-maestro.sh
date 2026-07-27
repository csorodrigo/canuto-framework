#!/usr/bin/env bash
# codex-maestro.sh — porta de entrada do runtime Codex direto.
#
# Sessão Codex direta não tem os hooks do Claude Code (SessionStart/Stop),
# então ESTE wrapper é a costura mecânica (ADR-0002): registra SESSION_START
# e SESSION_END no event log e cobra o CLOSEOUT na saída — o mesmo gate do
# session-save.sh do lado Claude, sem depender de disciplina do agente.

set -euo pipefail

if ! command -v codex >/dev/null 2>&1; then
  echo "codex CLI not found. Install it first or run Canuto from Claude." >&2
  exit 1
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
PROFILE="${CANUTO_CODEX_MAESTRO_PROFILE:-maestro}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVENT_LOG="$SCRIPT_DIR/event-log.sh"

if [ -f "$EVENT_LOG" ]; then
  bash "$EVENT_LOG" append SESSION_START actor=codex-maestro runtime=codex || true
fi

_canuto_codex_session_end() {
  local rc=$?
  [ -f "$EVENT_LOG" ] || return 0
  bash "$EVENT_LOG" append SESSION_END actor=codex-maestro runtime=codex rc="$rc" || true

  local log_path today_closeouts
  log_path="$(bash "$EVENT_LOG" path 2>/dev/null || true)"
  today_closeouts=0
  if [ -n "$log_path" ] && [ -f "$log_path" ]; then
    today_closeouts=$(grep '"event":"CLOSEOUT"' "$log_path" 2>/dev/null \
      | grep -c "\"ts\":\"$(date -u +%Y-%m-%d)" 2>/dev/null) || today_closeouts=0
  fi
  if [ "${today_closeouts:-0}" = "0" ]; then
    echo "" >&2
    echo "⚠ GATE: nenhum evento CLOSEOUT registrado hoje${log_path:+ em $log_path}." >&2
    echo "  Rode o session-end-learning e registre antes de encerrar de verdade:" >&2
    echo "  bash .agents/tools/event-log.sh append CLOSEOUT actor=codex-maestro summary=\"...\"" >&2
  else
    echo "✓ CLOSEOUT registrado hoje ($today_closeouts evento(s)) — learning loop ok." >&2
  fi
}
trap _canuto_codex_session_end EXIT

# Sem exec: o trap EXIT precisa disparar depois que o codex retornar.
codex --profile "$PROFILE" -C "$PROJECT_DIR" "$@"
