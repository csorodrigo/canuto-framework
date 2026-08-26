#!/usr/bin/env bash
# PostToolUse hook (matcher: .*) - emit per-tool-call OTLP spans and counters.

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../tools/otel-emit.sh" ]; then
  # shellcheck source=../tools/otel-emit.sh
  . "$SCRIPT_DIR/../tools/otel-emit.sh"
elif [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "$CLAUDE_PROJECT_DIR/.agents/tools/otel-emit.sh" ]; then
  # shellcheck source=/dev/null
  . "$CLAUDE_PROJECT_DIR/.agents/tools/otel-emit.sh"
else
  otel_emit_span() { return 0; }
  otel_emit_counter() { return 0; }
fi

export CANUTO_OTEL_HOOK_SOURCE="posttooluse-universal"

# ── Event log: cascata repo → lib global → stub fail-loud ───────────────────
# O antigo stub `return 0` deixava o event log morto EM SILÊNCIO em ~90% dos
# repos consumidores (auditoria 2026-08-01). Sem lib no repo nem em
# ~/.canuto/lib, o stub registra a ausência UMA vez por sessão (marker em
# /tmp) em ~/.canuto/vault/_health/missing-lib.jsonl. Best-effort: nunca falha.
_canuto_missing_lib_note() {
  local marker cwd_s
  marker="${TMPDIR:-/tmp}/canuto-missing-eventlib-${CLAUDE_SESSION_ID:-$PPID}-$1"
  [ -e "$marker" ] && return 0
  : >"$marker" 2>/dev/null || true
  mkdir -p "$HOME/.canuto/vault/_health" 2>/dev/null || return 0
  cwd_s=$(pwd 2>/dev/null || echo unknown)
  cwd_s=$(printf '%s' "$cwd_s" | tr -d '"\\' 2>/dev/null || echo unknown)
  printf '{"ts":"%s","hook":"%s","cwd":"%s","reason":"event-log-lib-missing"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" "$1" "$cwd_s" \
    >>"$HOME/.canuto/vault/_health/missing-lib.jsonl" 2>/dev/null || true
  return 0
}
if [ -f "$SCRIPT_DIR/../tools/event-log.sh" ]; then
  # shellcheck source=../tools/event-log.sh
  . "$SCRIPT_DIR/../tools/event-log.sh"
elif [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "$CLAUDE_PROJECT_DIR/.agents/tools/event-log.sh" ]; then
  # shellcheck source=/dev/null
  . "$CLAUDE_PROJECT_DIR/.agents/tools/event-log.sh"
elif [ -f "$HOME/.canuto/lib/event-log.sh" ]; then
  # shellcheck source=/dev/null
  . "$HOME/.canuto/lib/event-log.sh"
else
  canuto_event_append() { _canuto_missing_lib_note "posttooluse-universal"; return 0; }
fi

# Sem payload num TTY: `cat` sem stdin fechado bloqueia para sempre e o
# runtime que espera o hook congela junto (regra de TTY/pipe do CLAUDE.md).
INPUT=""
[ -t 0 ] || INPUT=$(cat 2>/dev/null || true)
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd -P || pwd)"
AUDIT_DIR="$PROJECT_DIR/.agents/vault/audit"

log_parse_error() {
  mkdir -p "$AUDIT_DIR" 2>/dev/null || return 0
  local date_stamp timestamp
  date_stamp=$(date +%Y-%m-%d 2>/dev/null || printf 'unknown-date')
  timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)
  printf '[%s] %s\n' "$timestamp" "$1" >> "$AUDIT_DIR/${date_stamp}-otel-emit.log" 2>/dev/null || true
}

if ! command -v jq >/dev/null 2>&1; then
  log_parse_error "jq not found; cannot parse PostToolUse payload"
  exit 0
fi

# Ausência de payload ≠ payload corrompido. Sem stdin (TTY, invocação manual)
# não há o que parsear e não há defeito a relatar — sai quieto. Registrar isso
# como "invalid JSON" enchia a trilha de auditoria de alarme falso e escondia a
# ocorrência real, que é payload malformado vindo do runtime.
if [ -z "$INPUT" ]; then
  exit 0
fi

if ! printf '%s' "$INPUT" | jq -e type >/dev/null 2>&1; then
  log_parse_error "invalid PostToolUse JSON payload"
  exit 0
fi

tool_name=$(printf '%s' "$INPUT" | jq -r '.tool_name // "unknown"' 2>/dev/null) || tool_name="unknown"
duration_ms=$(printf '%s' "$INPUT" | jq -r '
  (.tool_response // .tool_output // {}) as $r
  | ($r.duration_ms // $r.durationMs // 0)
' 2>/dev/null) || duration_ms=0
case "$duration_ms" in ''|*[!0-9]*) duration_ms=0 ;; esac

file_path=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null) || file_path=""
command=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || command=""

# Observability may correlate repeated values, but must never export command
# text or filesystem paths. Keep a one-way digest only; if no digest utility is
# available, use a fixed redaction marker rather than leaking the value.
redact_observed_value() {
  local value="$1" digest=""
  [ -n "$value" ] || return 0
  if command -v shasum >/dev/null 2>&1; then
    digest=$(printf '%s' "$value" | shasum -a 256 2>/dev/null | cut -d' ' -f1) || digest=""
  elif command -v sha256sum >/dev/null 2>&1; then
    digest=$(printf '%s' "$value" | sha256sum 2>/dev/null | cut -d' ' -f1) || digest=""
  fi
  if [ -n "$digest" ]; then
    printf 'sha256:%s' "$digest"
  else
    printf 'redacted'
  fi
}
file_digest=$(redact_observed_value "$file_path")
command_digest=$(redact_observed_value "$command")

outcome=$(printf '%s' "$INPUT" | jq -r '
  (.tool_response // .tool_output // {}) as $r
  | if $r.is_error == true then "error"
    elif (($r.exitCode // $r.exit_code // $r.code // 0) | tostring | test("^[0-9]+$") and (($r.exitCode // $r.exit_code // $r.code // 0) | tonumber) != 0) then "error"
    elif ($r.success == false) then "error"
    elif ($r.error != null and $r.error != false and ($r.error | tostring) != "") then "error"
    else "success"
    end
' 2>/dev/null) || outcome="error"

{
  otel_emit_span "$tool_name" "$outcome" "$duration_ms" "$file_digest" "$command_digest"
  otel_emit_counter "$tool_name" "$outcome"
} || true

# ── Event log: TOOL_CALL (fonte de verdade mecânica dos eventos de sessão) ──
# CANUTO_EVENT_LOG_TOOLS: core (default) = só tools que mudam estado ou delegam;
# all = todos os tool calls; off = desliga.
EVENT_TOOLS_MODE="${CANUTO_EVENT_LOG_TOOLS:-core}"
should_log_event=false
case "$EVENT_TOOLS_MODE" in
  all) should_log_event=true ;;
  off) should_log_event=false ;;
  *)
    case "$tool_name" in
      Bash|Edit|Write|MultiEdit|NotebookEdit|Task|Agent|mcp__*) should_log_event=true ;;
    esac
    ;;
esac
if [ "$should_log_event" = true ]; then
  canuto_event_append TOOL_CALL actor=hook tool="$tool_name" outcome="$outcome" \
    duration_ms="$duration_ms" file_sha256="$file_digest" cmd_sha256="$command_digest" || true
fi

exit 0
