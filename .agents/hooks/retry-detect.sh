#!/usr/bin/env bash
# PostToolUse hook (matcher: Bash) - count consecutive validation failures by last edited file.

set -o pipefail

INPUT=$(cat)

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd -P || pwd)"
AUDIT_DIR="$PROJECT_DIR/.agents/vault/audit"
PENDING_FILE="$AUDIT_DIR/validation-pending.json"
RETRY_FILE="$AUDIT_DIR/retry-counter.json"

VALIDATION_RE='(npm|bun|pnpm|yarn)[[:space:]]+(test|run[[:space:]]+test|run[[:space:]]+build|build|typecheck|tsc|lint)|vitest|jest|^node[[:space:]]+--test|bash[[:space:]]+test-|install\.sh[[:space:]]+--test|ruff|pytest|cargo[[:space:]]+test|tsc([[:space:]]|$)'

init_storage() {
  mkdir -p "$AUDIT_DIR" 2>/dev/null || return 1
  for f in "$PENDING_FILE" "$RETRY_FILE"; do
    if [ ! -f "$f" ] || ! jq -e type "$f" >/dev/null 2>&1; then
      (printf '{}\n' > "$f") 2>/dev/null || return 1
    fi
  done
}

command=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || command=""
[ -z "$command" ] && exit 0

echo "$command" | grep -Eiq "$VALIDATION_RE" 2>/dev/null || exit 0
init_storage || exit 0

exit_code=$(echo "$INPUT" | jq -r '
  if .tool_output.exitCode != null then .tool_output.exitCode
  elif .tool_output.exit_code != null then .tool_output.exit_code
  elif .tool_output.success == true then 0
  elif .tool_output.success == false then 1
  else 0
  end
' 2>/dev/null) || exit_code=0

case "$exit_code" in
  ''|0|true) (printf '{}\n' > "$RETRY_FILE") 2>/dev/null || true ;;
  *)
    last_edited=$(jq -r 'to_entries | sort_by(.value) | last | .key // empty' "$PENDING_FILE" 2>/dev/null) || last_edited=""
    [ -z "$last_edited" ] && exit 0
    tmp="$RETRY_FILE.tmp.$$"
    if jq --arg path "$last_edited" '.[$path] = ((.[$path] // 0) + 1)' "$RETRY_FILE" 2>/dev/null > "$tmp"; then
      mv "$tmp" "$RETRY_FILE" 2>/dev/null || rm -f "$tmp" 2>/dev/null
    else
      rm -f "$tmp" 2>/dev/null
    fi
    ;;
esac

exit 0
