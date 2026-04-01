#!/usr/bin/env bash
# framework-smoke-test.sh — Smoke tests for Canuto Framework integrity
# Run: bash .agents/tests/framework-smoke-test.sh

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
ROOT_DIR="$(cd "$PROJECT_DIR" && git rev-parse --show-toplevel 2>/dev/null || pwd)"

PASS=0 FAIL=0

pass() { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  \033[31mFAIL\033[0m  %s\n' "$1"; }

echo "Canuto Framework Smoke Tests"
echo "============================="
echo ""

# ── 1. Syntax checks ────────────────────────────────────────────────────
echo "## Bash Syntax"
for f in .agents/hooks/*.sh .agents/tools/*.sh; do
  [ -f "$f" ] || continue
  if bash -n "$f" 2>/dev/null; then
    pass "syntax: $f"
  else
    fail "syntax: $f"
  fi
done

echo ""
echo "## Python Syntax"
for f in .agents/tools/*.py; do
  [ -f "$f" ] || continue
  if python3 -c "import ast; ast.parse(open('$f').read())" 2>/dev/null; then
    pass "syntax: $f"
  else
    fail "syntax: $f"
  fi
done

# ── 2. Required files ───────────────────────────────────────────────────
echo ""
echo "## Required Files"
for f in CLAUDE.md .agents/personas/maestro.md .agents/personas/architect.md \
         .agents/personas/coder.md .agents/personas/reviewer.md \
         .agents/tools/codex-common.sh .agents/tools/codex-health-check.sh \
         .agents/hooks/codex-pretool-guard.sh .agents/hooks/plan-review.sh; do
  if [ -f "$ROOT_DIR/$f" ]; then
    pass "exists: $f"
  else
    fail "missing: $f"
  fi
done

# ── 3. Executable permissions ────────────────────────────────────────────
echo ""
echo "## Executable Permissions"
for f in .agents/tools/codex-common.sh .agents/tools/codex-health-check.sh \
         .agents/hooks/codex-pretool-guard.sh .agents/hooks/plan-review.sh \
         .agents/hooks/cleanup-tmp.sh .agents/hooks/validate-config.sh; do
  [ -f "$ROOT_DIR/$f" ] || continue
  if [ -x "$ROOT_DIR/$f" ] || head -1 "$ROOT_DIR/$f" | grep -q '^#!/'; then
    pass "shebang: $f"
  else
    fail "no shebang or not executable: $f"
  fi
done

# ── 4. Health check (structural mode) ───────────────────────────────────
echo ""
echo "## Health Check (structural)"
if bash "$ROOT_DIR/.agents/tools/codex-health-check.sh" --structural >/dev/null 2>&1; then
  pass "health check --structural passes"
else
  fail "health check --structural failed"
fi

# ── 5. Config validation ────────────────────────────────────────────────
echo ""
echo "## Config Validation"
if [ -f "$ROOT_DIR/.agents/hooks/validate-config.sh" ]; then
  if bash "$ROOT_DIR/.agents/hooks/validate-config.sh" >/dev/null 2>&1; then
    pass "config validation passes"
  else
    fail "config validation failed"
  fi
else
  fail "validate-config.sh not found"
fi

# ── 6. codex-common.sh sourceable ────────────────────────────────────────
echo ""
echo "## Library Sourcing"
if bash -c "source '$ROOT_DIR/.agents/tools/codex-common.sh' && type codex_project_dir >/dev/null 2>&1" 2>/dev/null; then
  pass "codex-common.sh sources cleanly and exports codex_project_dir"
else
  fail "codex-common.sh failed to source"
fi

if [ -f "$ROOT_DIR/.agents/tools/logging.sh" ]; then
  if bash -c "source '$ROOT_DIR/.agents/tools/logging.sh' && type log_info >/dev/null 2>&1" 2>/dev/null; then
    pass "logging.sh sources cleanly and exports log_info"
  else
    fail "logging.sh failed to source"
  fi
fi

if [ -f "$ROOT_DIR/.agents/tools/canuto-memory.sh" ]; then
  if bash -c "source '$ROOT_DIR/.agents/tools/canuto-memory.sh' && type canuto_resolve_memory_backend >/dev/null 2>&1" 2>/dev/null; then
    pass "canuto-memory.sh sources cleanly and exports canuto_resolve_memory_backend"
  else
    fail "canuto-memory.sh failed to source"
  fi
fi

# ── 7. Persona frontmatter ──────────────────────────────────────────────
echo ""
echo "## Persona Frontmatter"
for f in .agents/personas/*.md; do
  [ -f "$f" ] || continue
  bname=$(basename "$f")
  [ "$bname" = "CLAUDE.md" ] && continue
  if head -5 "$f" | grep -q 'shortDescription:'; then
    pass "frontmatter: $bname"
  else
    fail "missing frontmatter: $bname"
  fi
done

# ── Summary ──────────────────────────────────────────────────────────────
echo ""
echo "============================="
if [ "$FAIL" -gt 0 ]; then
  printf '\033[31m%d FAILED\033[0m, %d passed\n' "$FAIL" "$PASS"
  exit 1
else
  printf '\033[32mALL %d PASSED\033[0m\n' "$PASS"
  exit 0
fi
