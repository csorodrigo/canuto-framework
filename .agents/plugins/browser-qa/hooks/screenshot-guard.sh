#!/usr/bin/env bash
# PreToolUse hook (matcher: mcp__playwright__browser_take_screenshot|mcp__claude-in-chrome__computer)
# Caps base64 screenshots per session. Auditoria 2026-06: 289 screenshots = 31% dos tokens
# de transcript; piores sessões tiraram 50-80 screenshots em loops de design-iteration.
# Override deliberado: CANUTO_ALLOW_SCREENSHOT=1. Limite: CANUTO_SCREENSHOT_LIMIT (default 10).

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
export CANUTO_OTEL_HOOK_SOURCE="screenshot-guard"

emit_hook_otel() {
  local outcome="$1"
  local count_arg="${2:-0}"
  {
    CANUTO_OTEL_RETRY_COUNT="$count_arg" otel_emit_span "hook.screenshot_guard" "$outcome" 0
    otel_emit_counter "hook.screenshot_guard" "$outcome"
  } || true
}

# jq ausente: nunca quebrar a sessão por causa do guard.
command -v jq >/dev/null 2>&1 || exit 0

# Sem payload num TTY: `cat` sem stdin fechado bloqueia para sempre e o
# runtime que espera o hook congela junto (regra de TTY/pipe do CLAUDE.md).
INPUT=""
[ -t 0 ] || INPUT=$(cat)

tool_name=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || tool_name=""
[ -z "$tool_name" ] && exit 0

# Só atua em chamadas que retornam screenshot base64 inline.
is_screenshot=0
case "$tool_name" in
  mcp__playwright__browser_take_screenshot)
    is_screenshot=1
    ;;
  mcp__claude-in-chrome__computer)
    action=$(echo "$INPUT" | jq -r '.tool_input.action // empty' 2>/dev/null) || action=""
    [ "$action" = "screenshot" ] && is_screenshot=1
    ;;
esac
[ "$is_screenshot" -eq 1 ] || exit 0

# Override deliberado (sessão de QA visual intencional): permite sem contar.
if [ "${CANUTO_ALLOW_SCREENSHOT:-0}" = "1" ]; then
  emit_hook_otel "override" 0
  exit 0
fi

LIMIT="${CANUTO_SCREENSHOT_LIMIT:-10}"
case "$LIMIT" in
  ''|*[!0-9]*) LIMIT=10 ;;
esac

session_id=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null) || session_id=""
[ -z "$session_id" ] && session_id="nosession"
session_id=$(printf '%s' "$session_id" | tr -c 'A-Za-z0-9._-' '_')

payload_cwd=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null) || payload_cwd=""
scope_cwd="${payload_cwd:-${CLAUDE_PROJECT_DIR:-}}"
if [ -z "$scope_cwd" ]; then
  scope_cwd=$(pwd -P 2>/dev/null || pwd)
fi
canonical_cwd=$(cd "$scope_cwd" 2>/dev/null && pwd -P) || canonical_cwd="$scope_cwd"

worktree_id=""
repo_id=""
if worktree_id=$(git -C "$canonical_cwd" rev-parse --show-toplevel 2>/dev/null); then
  worktree_id=$(cd "$worktree_id" 2>/dev/null && pwd -P) || true
  common_dir=$(git -C "$canonical_cwd" rev-parse --git-common-dir 2>/dev/null) || common_dir=""
  case "$common_dir" in
    /*) repo_id="$common_dir" ;;
    '') repo_id="" ;;
    *) repo_id="$worktree_id/$common_dir" ;;
  esac
  [ -n "$repo_id" ] && repo_id=$(cd "$repo_id" 2>/dev/null && pwd -P) || true
else
  worktree_id=""
fi

scope_hash=$(
  printf '%s\n%s\n%s\n' "$repo_id" "$worktree_id" "$canonical_cwd" \
    | shasum -a 256 2>/dev/null \
    | awk '{print substr($1,1,24)}'
) || scope_hash=""
if [ -z "$scope_hash" ]; then
  scope_hash=$(
    printf '%s\n%s\n%s\n' "$repo_id" "$worktree_id" "$canonical_cwd" \
      | cksum 2>/dev/null \
      | awk '{print $1}'
  ) || scope_hash="unknown"
fi

COUNT_FILE="${TMPDIR:-/tmp}/canuto-screenshot-count-$scope_hash-$session_id"

count=0
if [ -f "$COUNT_FILE" ]; then
  count=$(cat "$COUNT_FILE" 2>/dev/null) || count=0
fi
case "$count" in
  ''|*[!0-9]*) count=0 ;;
esac

if [ "$count" -ge "$LIMIT" ] 2>/dev/null; then
  {
    printf '[screenshot-guard] Limite de %s screenshots por sessão atingido — cada screenshot base64 consome contexto permanentemente.\n' "$LIMIT"
    printf 'Alternativas:\n'
    printf '  (1) mcp__playwright__browser_snapshot para verificar o estado da página via texto/a11y\n'
    printf '  (2) screenshot com o parâmetro filename para salvar em disco sem inflar o transcript\n'
    printf '  (3) override deliberado CANUTO_ALLOW_SCREENSHOT=1 para sessão de QA visual intencional\n'
  } >&2
  # Enforcement invariant: exit 2 logo após a decisão; OTel é fire-and-forget.
  emit_hook_otel "blocked" "$count"
  exit 2
fi

new_count=$((count + 1))
(printf '%s\n' "$new_count" > "$COUNT_FILE") 2>/dev/null || true

warn_at=$((LIMIT - 3))
if [ "$warn_at" -gt 0 ] && [ "$new_count" -eq "$warn_at" ] 2>/dev/null; then
  {
    printf '[screenshot-guard] Aviso: %s de %s screenshots usados nesta sessão — o limite está próximo.\n' "$new_count" "$LIMIT"
    printf 'Prefira mcp__playwright__browser_snapshot (texto/a11y) ou passe o parâmetro filename para salvar em disco.\n'
  } >&2
  emit_hook_otel "warned" "$new_count"
  exit 0
fi

emit_hook_otel "allowed" "$new_count"
exit 0
