#!/usr/bin/env bash
# Stop hook - report files still waiting for validation.

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
export CANUTO_OTEL_HOOK_SOURCE="pre-finalize"

emit_hook_otel() {
  local outcome="$1"
  local pending_count="${2:-0}"
  {
    CANUTO_OTEL_PENDING_COUNT="$pending_count" otel_emit_span "hook.pre_finalize" "$outcome" 0
    otel_emit_counter "hook.pre_finalize" "$outcome"
  } || true
}

INPUT=$(cat)
stop_active=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null); [ "$stop_active" = "true" ] && { emit_hook_otel "success"; exit 0; }

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

if init_storage && jq -e 'length > 0' "$PENDING_FILE" >/dev/null 2>&1; then
  files=$(jq -r 'keys[:5] | join(", ")' "$PENDING_FILE" 2>/dev/null) || files=""
  [ -n "$files" ] && printf '[pre-finalize] pending validation for: %s\n' "$files"
  pending_count=$(jq -r 'length' "$PENDING_FILE" 2>/dev/null) || pending_count=0
  emit_hook_otel "pending" "$pending_count"
else
  emit_hook_otel "success"
fi

exit 0
