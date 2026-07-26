#!/usr/bin/env bash
# validate-config.sh — Validate framework configuration on session start
# Checks CLAUDE.md for required fields and .agents/ structure integrity.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
ROOT_DIR="$(cd "$PROJECT_DIR" && git rev-parse --show-toplevel 2>/dev/null || pwd)"

ERRORS=0
WARNINGS=0

err() { ERRORS=$((ERRORS + 1)); printf '  ERROR  %s\n' "$1" >&2; }
wrn() { WARNINGS=$((WARNINGS + 1)); printf '  WARN   %s\n' "$1" >&2; }
ok()  { printf '  OK     %s\n' "$1"; }

# ── CLAUDE.md ───────────────────────────────────────────────────────────
CLAUDE_MD="$ROOT_DIR/CLAUDE.md"
if [ ! -f "$CLAUDE_MD" ]; then
  err "CLAUDE.md not found at project root"
else
  if ! grep -q 'project-slug:' "$CLAUDE_MD" 2>/dev/null; then
    err "CLAUDE.md missing 'project-slug' field"
  else
    ok "project-slug found"
  fi

  if ! grep -q '\.agents/' "$CLAUDE_MD" 2>/dev/null; then
    wrn "CLAUDE.md does not reference .agents/ framework"
  fi
fi

# ── Required directories ────────────────────────────────────────────────
for dir in ".agents/personas" ".agents/skills" ".agents/tools" ".agents/hooks"; do
  if [ -d "$ROOT_DIR/$dir" ]; then
    ok "$dir exists"
  else
    err "$dir directory missing"
  fi
done

# ── Required tools ──────────────────────────────────────────────────────
for tool in "codex-common.sh" "codex-health-check.sh"; do
  if [ -f "$ROOT_DIR/.agents/tools/$tool" ]; then
    ok "tool: $tool"
  else
    wrn "tool missing: $tool"
  fi
done

# ── Codex config.toml profiles ──────────────────────────────────────────
CONFIG_TOML="$HOME/.codex/config.toml"
if [ -f "$CONFIG_TOML" ]; then
  for profile in coder reviewer; do
    if grep -q "\[profiles\.$profile\]" "$CONFIG_TOML" 2>/dev/null; then
      ok "codex profile: $profile"
    else
      wrn "codex profile missing: $profile"
    fi
  done
else
  wrn "~/.codex/config.toml not found — Codex integration may not work"
fi

# ── Summary ─────────────────────────────────────────────────────────────
echo ""
if [ "$ERRORS" -gt 0 ]; then
  echo "Config validation: $ERRORS errors, $WARNINGS warnings"
  exit 1
elif [ "$WARNINGS" -gt 0 ]; then
  echo "Config validation: $WARNINGS warnings (no errors)"
  exit 0
else
  echo "Config validation: all checks passed"
  exit 0
fi
