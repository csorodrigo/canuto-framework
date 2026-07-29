#!/usr/bin/env bash
# PreToolUse hook (matcher: Edit|Write) - require a fingerprint after repeated validation failures.

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../tools/otel-emit.sh" ]; then
  . "$SCRIPT_DIR/../tools/otel-emit.sh"
elif [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "$CLAUDE_PROJECT_DIR/.agents/tools/otel-emit.sh" ]; then
  . "$CLAUDE_PROJECT_DIR/.agents/tools/otel-emit.sh"
else
  otel_emit_span() { return 0; }
  otel_emit_counter() { return 0; }
fi
export CANUTO_OTEL_HOOK_SOURCE="fingerprint-gate"

emit_hook_otel() {
  local outcome="$1"
  local retry_count="${2:-0}"
  local file_path_arg="${3:-}"
  {
    CANUTO_OTEL_RETRY_COUNT="$retry_count" otel_emit_span "hook.fingerprint_gate" "$outcome" 0 "$file_path_arg"
    otel_emit_counter "hook.fingerprint_gate" "$outcome"
  } || true
}

# Sem payload num TTY: `cat` sem stdin fechado bloqueia para sempre e o
# runtime que espera o hook congela junto (regra de TTY/pipe do CLAUDE.md).
INPUT=""
[ -t 0 ] || INPUT=$(cat)

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd -P || pwd)"
AUDIT_DIR="$PROJECT_DIR/.agents/vault/audit"
PENDING_FILE="$AUDIT_DIR/validation-pending.json"
RETRY_FILE="$AUDIT_DIR/retry-counter.json"

init_storage() {
  mkdir -p "$AUDIT_DIR" 2>/dev/null || return 1
  for f in "$PENDING_FILE" "$RETRY_FILE"; do
    if [ ! -f "$f" ] || ! jq -e type "$f" >/dev/null 2>&1; then
      (printf '{}\n' > "$f") 2>/dev/null || return 1
    fi
  done
}

normalize_path() {
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *) printf '%s/%s\n' "$PROJECT_DIR" "$1" ;;
  esac
}

has_fingerprint() {
  transcript_path="$1"
  if [ -n "$transcript_path" ] && [ -r "$transcript_path" ]; then
    tail -50 "$transcript_path" 2>/dev/null | grep -q 'Fingerprint:' 2>/dev/null && return 0
  fi
  env 2>/dev/null | grep -q 'Fingerprint:' 2>/dev/null && return 0
  return 1
}

reset_counter() {
  tmp="$RETRY_FILE.tmp.$$"
  if jq --arg path "$file_path" 'del(.[$path])' "$RETRY_FILE" 2>/dev/null > "$tmp"; then
    mv "$tmp" "$RETRY_FILE" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  else
    rm -f "$tmp" 2>/dev/null
  fi
}

file_path=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null) || file_path=""
[ -z "$file_path" ] && { emit_hook_otel "allowed"; exit 0; }
file_path=$(normalize_path "$file_path")

transcript_path=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null) || transcript_path=""
init_storage || { emit_hook_otel "allowed" 0 "$file_path"; exit 0; }

count=$(jq -r --arg path "$file_path" '.[$path] // 0' "$RETRY_FILE" 2>/dev/null) || count=0
case "$count" in
  ''|*[!0-9]*) count=0 ;;
esac

if [ "$count" -ge 3 ] 2>/dev/null; then
  if has_fingerprint "$transcript_path"; then
    reset_counter
    emit_hook_otel "allowed" "$count" "$file_path"
    exit 0
  fi

  printf '[fingerprint-gate] Arquivo %s teve 3 falhas sucessivas de validação.\n' "$file_path"
  printf 'Antes de editar de novo, registre no próximo turno:\n'
  printf '  Fingerprint: <causa-raiz observada em file:linha>\n'
  printf '  Comando falhou: <cmd exato>\n'
  printf '  Validação planejada: <como vai confirmar o fix>\n'
  # Enforcement invariant: exit 2 must happen in <10ms after decision.
  # OTel emission is fire-and-forget (see otel-emit.sh).
  CANUTO_OTEL_RETRY_COUNT="$count" otel_emit_span "hook.fingerprint_gate" "blocked" 0 "$file_path" "" || true
  CANUTO_OTEL_RETRY_COUNT="$count" otel_emit_counter "hook.fingerprint_gate" "blocked" || true
  exit 2
fi

emit_hook_otel "allowed" "$count" "$file_path"
exit 0
