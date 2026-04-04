#!/usr/bin/env bash
# .agents/hooks/protect-files.sh
# PreToolUse hook (matcher: Edit|Write) — blocks edits to sensitive files.
# Exit 2 = block + send reason to Claude. Exit 0 = allow.

set -euo pipefail

file=$(jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null) || file=""

[[ -z "$file" ]] && exit 0

protected_patterns=(
  '\.env($|\.)'
  '\.git/'
  '\.pem$'
  '\.key$'
  '\.p12$'
  '\.pfx$'
  'secrets/'
  '\.agents/vault/'
)

for pattern in "${protected_patterns[@]}"; do
  if echo "$file" | grep -qiE "$pattern"; then
    echo "Blocked: '$file' is a protected file (matched '$pattern'). Explain why this edit is necessary and ask the user for permission." >&2
    exit 2
  fi
done

exit 0
