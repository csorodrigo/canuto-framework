#!/usr/bin/env bash
# .agents/hooks/log-commands.sh
# PreToolUse hook (matcher: Bash) — logs every command to an audit trail.
# Never blocks (always exit 0).

set -euo pipefail

# `jq` sem arquivo lê stdin: num TTY ele espera para sempre, e este hook roda
# em TODO comando Bash — o runtime inteiro congela junto. Mesma classe do
# `INPUT=$(cat)` sem guarda, só que disfarçada de leitura de JSON.
cmd=""
if [ ! -t 0 ]; then
  cmd=$(jq -r '.tool_input.command // ""' 2>/dev/null) || cmd=""
fi

[[ -z "$cmd" ]] && exit 0

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
LOG_DIR="$PROJECT_DIR/.agents/tmp"
LOG_FILE="$LOG_DIR/command-log.txt"

mkdir -p "$LOG_DIR"
printf '%s\t%s\n' "$(date -Is 2>/dev/null || date '+%Y-%m-%dT%H:%M:%S')" "$cmd" >> "$LOG_FILE"

exit 0
