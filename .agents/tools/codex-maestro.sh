#!/usr/bin/env bash

set -euo pipefail

if ! command -v codex >/dev/null 2>&1; then
  echo "codex CLI not found. Install it first or run Canuto from Claude." >&2
  exit 1
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
PROFILE="${CANUTO_CODEX_MAESTRO_PROFILE:-maestro}"

exec codex --profile "$PROFILE" -C "$PROJECT_DIR" "$@"
