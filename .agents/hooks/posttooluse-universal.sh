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

INPUT=$(cat 2>/dev/null || true)
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
command="${command:0:200}"

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
  otel_emit_span "$tool_name" "$outcome" "$duration_ms" "$file_path" "$command"
  otel_emit_counter "$tool_name" "$outcome"
} || true

exit 0
