#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
ROOT_DIR="$(cd "$PROJECT_DIR" && git rev-parse --show-toplevel 2>/dev/null || pwd)"
JSON_OUTPUT=false

while [ $# -gt 0 ]; do
  case "$1" in
    --json)
      JSON_OUTPUT=true
      ;;
  esac
  shift
done

PASS=0
WARN=0
FAIL=0
ITEMS_FILE=$(mktemp)

cleanup() {
  rm -f "$ITEMS_FILE"
}
trap cleanup EXIT

record() {
  local status="$1"
  local message="$2"
  printf '%s\t%s\n' "$status" "$message" >> "$ITEMS_FILE"
}

pass() {
  PASS=$((PASS + 1))
  record "PASS" "$1"
  if [ "$JSON_OUTPUT" = false ]; then
    echo "  PASS  $1"
  fi
}

warn() {
  WARN=$((WARN + 1))
  record "WARN" "$1"
  if [ "$JSON_OUTPUT" = false ]; then
    echo "  WARN  $1"
  fi
}

fail() {
  FAIL=$((FAIL + 1))
  record "FAIL" "$1"
  if [ "$JSON_OUTPUT" = false ]; then
    echo "  FAIL  $1"
  fi
}

if [ "$JSON_OUTPUT" = false ]; then
  echo ""
  echo "Canuto Consumer Smoke Test"
  echo ""
fi

if [ -d "$ROOT_DIR/.agents" ]; then
  pass ".agents present"
else
  fail ".agents missing"
fi

for file_path in \
  "$ROOT_DIR/CLAUDE.md" \
  "$ROOT_DIR/AGENTS.md" \
  "$ROOT_DIR/.context.md" \
  "$ROOT_DIR/docs/FEATURE-MAP.md"; do
  if [ -f "$file_path" ]; then
    pass "file present: ${file_path#$ROOT_DIR/}"
  else
    fail "missing file: ${file_path#$ROOT_DIR/}"
  fi
done

for section in "## Framework" "## Preferences" "## On Session Start"; do
  if [ -f "$ROOT_DIR/CLAUDE.md" ] && grep -q "$section" "$ROOT_DIR/CLAUDE.md" 2>/dev/null; then
    pass "CLAUDE.md section present: $section"
  else
    fail "CLAUDE.md missing section: $section"
  fi
done

for file_path in \
  "$ROOT_DIR/.agents/hooks/install.sh" \
  "$ROOT_DIR/.agents/hooks/plan-review.sh" \
  "$ROOT_DIR/.agents/hooks/codex-pretool-guard.sh" \
  "$ROOT_DIR/.agents/tools/codex-health-check.sh" \
  "$ROOT_DIR/.agents/tools/canuto-consumer-smoke.sh"; do
  if [ -x "$file_path" ]; then
    pass "runtime executable: ${file_path#$ROOT_DIR/}"
  else
    fail "runtime file missing or not executable: ${file_path#$ROOT_DIR/}"
  fi
done

if [ -d "$ROOT_DIR/.agents/tmp" ]; then
  pass ".agents/tmp present"
else
  warn ".agents/tmp missing"
fi

if find "$ROOT_DIR/.agents/vault/digests" -maxdepth 1 -type f ! -name '.gitkeep' -print -quit 2>/dev/null | grep -q .; then
  pass "at least one digest note present"
else
  warn "no digest notes present"
fi

VERDICT="HEALTHY"
EXIT_CODE=0
if [ "$FAIL" -gt 0 ]; then
  VERDICT="BROKEN"
  EXIT_CODE=1
elif [ "$WARN" -gt 0 ]; then
  VERDICT="DEGRADED"
fi

if [ "$JSON_OUTPUT" = true ]; then
  python3 - "$ITEMS_FILE" "$ROOT_DIR" "$VERDICT" "$PASS" "$WARN" "$FAIL" <<'PYEOF'
import json
import sys

items_file, root_dir, verdict, pass_count, warn_count, fail_count = sys.argv[1:]
results = []
with open(items_file, encoding="utf-8") as fh:
    for line in fh:
        status, message = line.rstrip("\n").split("\t", 1)
        results.append({"status": status, "message": message})

print(json.dumps({
    "tool": "canuto-consumer-smoke",
    "project_root": root_dir,
    "verdict": verdict,
    "counts": {
        "pass": int(pass_count),
        "warn": int(warn_count),
        "fail": int(fail_count),
    },
    "results": results,
}, ensure_ascii=True))
PYEOF
else
  echo ""
  echo "Verdict: $VERDICT ($PASS passing, $WARN warnings, $FAIL failures)"
fi

exit "$EXIT_CODE"
