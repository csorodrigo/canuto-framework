#!/usr/bin/env bash
# PostToolUse hook (matcher: Edit|Write) - mark edited files as pending validation.

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
export CANUTO_OTEL_HOOK_SOURCE="validation-mark"

emit_hook_otel() {
  local outcome="$1"
  local file_path_arg="${2:-}"
  {
    otel_emit_span "hook.validation_mark" "$outcome" 0 "$file_path_arg"
    otel_emit_counter "hook.validation_mark" "$outcome"
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
    if [ ! -s "$f" ]; then
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

file_path=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null) || file_path=""
[ -z "$file_path" ] && { emit_hook_otel "skipped"; exit 0; }

file_path=$(normalize_path "$file_path")
timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')
flagged=0

if init_storage; then
  tmp="$PENDING_FILE.tmp.$$"
  if ! jq --arg path "$file_path" --arg timestamp "$timestamp" '. + {($path): $timestamp}' "$PENDING_FILE" 2>/dev/null > "$tmp"; then
    (printf '{}\n' > "$PENDING_FILE") 2>/dev/null || true
    jq --arg path "$file_path" --arg timestamp "$timestamp" '. + {($path): $timestamp}' "$PENDING_FILE" 2>/dev/null > "$tmp"
  fi
  if [ -s "$tmp" ]; then
    if mv "$tmp" "$PENDING_FILE" 2>/dev/null; then
      flagged=1
    else
      rm -f "$tmp" 2>/dev/null
    fi
  else
    rm -f "$tmp" 2>/dev/null
  fi
fi

if [ "$flagged" -eq 1 ]; then
  emit_hook_otel "flagged" "$file_path"
else
  emit_hook_otel "skipped" "$file_path"
fi

exit 0
