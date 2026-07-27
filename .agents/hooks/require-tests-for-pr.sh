#!/usr/bin/env bash
# .agents/hooks/require-tests-for-pr.sh
# PreToolUse hook (matcher: mcp__github__create_pull_request) — blocks PR if tests fail.
# Exit 2 = block + send reason to Claude. Exit 0 = allow.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../tools/event-log.sh" ]; then
  # shellcheck source=../tools/event-log.sh
  . "$SCRIPT_DIR/../tools/event-log.sh"
elif [ -f "$PROJECT_DIR/.agents/tools/event-log.sh" ]; then
  # shellcheck source=/dev/null
  . "$PROJECT_DIR/.agents/tools/event-log.sh"
else
  canuto_event_append() { return 0; }
fi

run_tests() {
  if [[ -f "$PROJECT_DIR/test-framework.sh" ]]; then
    bash "$PROJECT_DIR/test-framework.sh" 2>&1 | tail -20
    return "${PIPESTATUS[0]}"
  elif [[ -f "$PROJECT_DIR/package.json" ]] && grep -q '"test"' "$PROJECT_DIR/package.json" 2>/dev/null; then
    cd "$PROJECT_DIR" && npm run test --silent 2>&1 | tail -20
    return "${PIPESTATUS[0]}"
  elif [[ -f "$PROJECT_DIR/Makefile" ]] && grep -q '^test:' "$PROJECT_DIR/Makefile" 2>/dev/null; then
    cd "$PROJECT_DIR" && make test 2>&1 | tail -20
    return "${PIPESTATUS[0]}"
  else
    echo "[require-tests-for-pr] No test runner detected, skipping gate." >&2
    return 0
  fi
}

# Quem chama declara a costura: mcp (default), gh-cli (pre-pr-bash-gate),
# pre-push (git hook runtime-agnóstico).
GATE_VIA="${CANUTO_GATE_VIA:-mcp}"

if ! run_tests; then
  canuto_event_append GATE actor=hook gate=pr-tests verdict=fail via="$GATE_VIA" || true
  echo "Tests are failing. Fix all test failures before creating a PR." >&2
  exit 2
fi

canuto_event_append GATE actor=hook gate=pr-tests verdict=pass via="$GATE_VIA" || true
exit 0
