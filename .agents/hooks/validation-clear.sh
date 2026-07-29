#!/usr/bin/env bash
# PostToolUse hook (matcher: Bash) - clear pending validation after validation commands.

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
export CANUTO_OTEL_HOOK_SOURCE="validation-clear"

emit_hook_otel() {
  local outcome="$1"
  local command_arg="${2:-}"
  {
    otel_emit_span "hook.validation_clear" "$outcome" 0 "" "$command_arg"
    otel_emit_counter "hook.validation_clear" "$outcome"
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

echo "$command" | grep -Eiq "$VALIDATION_RE" 2>/dev/null || { emit_hook_otel "skipped" "$command"; exit 0; }

# Only clear pending when the validation command actually succeeded.
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
    if init_storage; then
      (printf '{}\n' > "$PENDING_FILE") 2>/dev/null || true
      (printf '{}\n' > "$RETRY_FILE") 2>/dev/null || true
    fi
    emit_hook_otel "success" "$command"
    ;;
  *) emit_hook_otel "skipped" "$command" ;;
esac

exit 0
