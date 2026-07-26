#!/usr/bin/env bash
# session-start.sh — SessionStart hook
# Corre codex-health-check.sh --json, imprime 2-3 linhas de health + stale context,
# registra SESSION_START em .agents/vault/audit/. Nunca bloqueia (exit 0 sempre).
# Bash 3.2 compatible.

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
export CANUTO_OTEL_HOOK_SOURCE="session-start"

if [ -f "$SCRIPT_DIR/../tools/event-log.sh" ]; then
  . "$SCRIPT_DIR/../tools/event-log.sh"
elif [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "$CLAUDE_PROJECT_DIR/.agents/tools/event-log.sh" ]; then
  . "$CLAUDE_PROJECT_DIR/.agents/tools/event-log.sh"
else
  canuto_event_append() { return 0; }
fi

emit_hook_otel() {
  {
    otel_emit_span "hook.session_start" "success" 0
    otel_emit_counter "hook.session_start" "success"
  } || true
}

# --- Read hook input (ignore errors) --------------------------------------
INPUT="$(cat 2>/dev/null || true)"
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$CWD" ] && CWD="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# --- Resolve repo root (framework install) --------------------------------
ROOT=""
if [ -d "$CWD/.agents" ]; then
  ROOT="$CWD"
elif GIT_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null); [ -n "$GIT_ROOT" ] && [ -d "$GIT_ROOT/.agents" ]; then
  ROOT="$GIT_ROOT"
fi

if [ -z "$ROOT" ] || [ ! -d "$ROOT/.agents" ]; then
  # no framework here — silent exit
  emit_hook_otel
  exit 0
fi

HEALTH_SCRIPT="$ROOT/.agents/tools/codex-health-check.sh"
if [ ! -x "$HEALTH_SCRIPT" ]; then
  emit_hook_otel
  exit 0
fi

# --- Run healthcheck with 4s soft timeout via perl alarm ------------------
HEALTH_JSON=""
if command -v perl >/dev/null 2>&1; then
  HEALTH_JSON=$(perl -e '
    $SIG{ALRM} = sub { exit 0 };
    alarm 4;
    open(my $fh, "-|", @ARGV) or exit 0;
    local $/;
    my $out = <$fh>;
    close $fh;
    print $out;
  ' -- "$HEALTH_SCRIPT" --json --smoke 2>/dev/null)
else
  HEALTH_JSON=$(bash "$HEALTH_SCRIPT" --json --smoke 2>/dev/null)
fi

# --- Summarize health -----------------------------------------------------
HEALTH_LINE=""
if [ -n "$HEALTH_JSON" ]; then
  VERDICT=$(printf '%s' "$HEALTH_JSON" | jq -r '.verdict // "UNKNOWN"' 2>/dev/null)
  PASS=$(printf '%s' "$HEALTH_JSON" | jq -r '.counts.pass // 0' 2>/dev/null)
  WARN=$(printf '%s' "$HEALTH_JSON" | jq -r '.counts.warn // 0' 2>/dev/null)
  FAIL=$(printf '%s' "$HEALTH_JSON" | jq -r '.counts.fail // 0' 2>/dev/null)
  HEALTH_LINE="MCP Health: $VERDICT (pass=$PASS warn=$WARN fail=$FAIL)"
fi

# --- Session header -------------------------------------------------------
SLUG=$(basename "$ROOT")
BRANCH=$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "-")
SESSION_LINE="Session: $SLUG @ $BRANCH"

# --- Stale context check --------------------------------------------------
STALE_LINE=""
LATEST_CONTEXT=""
if [ -d "$ROOT" ]; then
  # newest .context.md in the repo (excluding node_modules/.git)
  LATEST_CONTEXT=$(find "$ROOT" \( -path "*/node_modules" -o -path "*/.git" \) -prune -o -name ".context.md" -print 2>/dev/null | head -200 | xargs stat -f '%m %N' 2>/dev/null | sort -rn | head -1 | awk '{print $2}')
fi
if [ -n "$LATEST_CONTEXT" ] && [ -f "$LATEST_CONTEXT" ]; then
  CHANGED=$(git -C "$ROOT" diff --name-only HEAD 2>/dev/null | wc -l | tr -d ' ')
  if [ "$CHANGED" != "" ] && [ "$CHANGED" -gt 5 ]; then
    STALE_LINE="Stale contexts: $CHANGED files changed since latest .context.md"
  else
    STALE_LINE="Stale contexts: none"
  fi
fi

# --- Emit (≤3 lines to stdout) --------------------------------------------
[ -n "$HEALTH_LINE" ] && printf '%s\n' "$HEALTH_LINE"
printf '%s\n' "$SESSION_LINE"
[ -n "$STALE_LINE" ] && printf '%s\n' "$STALE_LINE"

# --- Audit event ----------------------------------------------------------
AUDIT_DIR="$ROOT/.agents/vault/audit"
if [ -d "$AUDIT_DIR" ] || mkdir -p "$AUDIT_DIR" 2>/dev/null; then
  DATE=$(date +%Y-%m-%d)
  TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  AUDIT_FILE="$AUDIT_DIR/${DATE}-SESSION_START.md"
  {
    if [ ! -f "$AUDIT_FILE" ]; then
      printf -- '---\ntype: SESSION_START\nproject: %s\ndate: %s\n---\n\n' "$SLUG" "$DATE"
    fi
    printf '- **%s** branch=%s health=%s stale=%s\n' \
      "$TS" "$BRANCH" "${VERDICT:-unknown}" "${CHANGED:-0}"
  } >> "$AUDIT_FILE" 2>/dev/null || true
fi

# --- Event log (fonte de verdade; a nota de audit acima é projeção) --------
canuto_event_append SESSION_START actor=hook \
  branch="${BRANCH:-}" health="${VERDICT:-unknown}" stale="${CHANGED:-0}" || true

emit_hook_otel
exit 0
