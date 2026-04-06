#!/usr/bin/env bash
# .agents/hooks/require-tests-for-pr.sh
# PreToolUse hook (matcher: mcp__github__create_pull_request) — blocks PR if tests fail.
# Exit 2 = block + send reason to Claude. Exit 0 = allow.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"

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

if ! run_tests; then
  echo "Tests are failing. Fix all test failures before creating a PR." >&2
  exit 2
fi

exit 0
