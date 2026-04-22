#!/usr/bin/env bash
# Stop hook - report files still waiting for validation.

set -o pipefail

INPUT=$(cat)
stop_active=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null); [ "$stop_active" = "true" ] && exit 0

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
fi

exit 0
