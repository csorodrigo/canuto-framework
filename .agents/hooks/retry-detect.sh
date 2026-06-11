#!/usr/bin/env bash
# PostToolUse hook (matcher: Bash) - count consecutive validation failures by last edited file.

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
export CANUTO_OTEL_HOOK_SOURCE="retry-detect"

emit_hook_otel() {
  local outcome="$1"
  local retry_count="${2:-0}"
  local file_path_arg="${3:-}"
  local command_arg="${4:-}"
  {
    CANUTO_OTEL_RETRY_COUNT="$retry_count" otel_emit_span "hook.retry_detect" "$outcome" 0 "$file_path_arg" "$command_arg"
    otel_emit_counter "hook.retry_detect" "$outcome"
  } || true
}

INPUT=$(cat)

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd -P || pwd)"
AUDIT_DIR="$PROJECT_DIR/.agents/vault/audit"
PENDING_FILE="$AUDIT_DIR/validation-pending.json"
RETRY_FILE="$AUDIT_DIR/retry-counter.json"

# NOTE: the rtk PreToolUse rewriter prefixes commands ("npm test" -> "rtk npm test"),
# so the regex must tolerate an optional "rtk [proxy]" prefix or it never matches.
VALIDATION_RE='(^|[[:space:]]*[;&|]+[[:space:]]*)(rtk[[:space:]]+(proxy[[:space:]]+)?)?((npm|bun|pnpm|yarn)[[:space:]]+(run[[:space:]]+)?(test|build|typecheck|tsc|lint)([[:space:]]|$)|npx[[:space:]]+(vitest|jest|mocha|ava|pytest)([[:space:]]|$)|(vitest|jest|mocha|ava|pytest|ruff)([[:space:]]|$)|node[[:space:]]+--test([[:space:]]|$)|bash[[:space:]]+test-|(\./)?install\.sh[[:space:]]+--(test|doctor)([[:space:]]|$)|cargo[[:space:]]+test([[:space:]]|$)|tsc([[:space:]]|$))'

init_storage() {
  mkdir -p "$AUDIT_DIR" 2>/dev/null || return 1
  for f in "$PENDING_FILE" "$RETRY_FILE"; do
    if [ ! -f "$f" ] || ! jq -e type "$f" >/dev/null 2>&1; then
      (printf '{}\n' > "$f") 2>/dev/null || return 1
    fi
  done
}

command=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || command=""
[ -z "$command" ] && { emit_hook_otel "skipped"; exit 0; }

echo "$command" | grep -Eiq "$VALIDATION_RE" 2>/dev/null || { emit_hook_otel "skipped" 0 "" "$command"; exit 0; }
init_storage || { emit_hook_otel "skipped" 0 "" "$command"; exit 0; }

exit_code=$(echo "$INPUT" | jq -r '
  (.tool_response // .tool_output // {}) as $r
  | if $r.exitCode != null then $r.exitCode
    elif $r.exit_code != null then $r.exit_code
    elif $r.success == true then 0
    elif $r.success == false then 1
    else 0
    end
' 2>/dev/null) || exit_code=0

case "$exit_code" in
  ''|0|true)
    (printf '{}\n' > "$RETRY_FILE") 2>/dev/null || true
    emit_hook_otel "success" 0 "" "$command"
    ;;
  *)
    last_edited=$(jq -r 'to_entries | sort_by(.value) | last | .key // empty' "$PENDING_FILE" 2>/dev/null) || last_edited=""
    [ -z "$last_edited" ] && { emit_hook_otel "skipped" 0 "" "$command"; exit 0; }
    tmp="$RETRY_FILE.tmp.$$"
    if jq --arg path "$last_edited" '.[$path] = ((.[$path] // 0) + 1)' "$RETRY_FILE" 2>/dev/null > "$tmp"; then
      if mv "$tmp" "$RETRY_FILE" 2>/dev/null; then
        retry_count=$(jq -r --arg path "$last_edited" '.[$path] // 0' "$RETRY_FILE" 2>/dev/null) || retry_count=0
        emit_hook_otel "retry" "$retry_count" "$last_edited" "$command"
      else
        rm -f "$tmp" 2>/dev/null
        emit_hook_otel "skipped" 0 "$last_edited" "$command"
      fi
    else
      rm -f "$tmp" 2>/dev/null
      emit_hook_otel "skipped" 0 "$last_edited" "$command"
    fi
    ;;
esac

exit 0
