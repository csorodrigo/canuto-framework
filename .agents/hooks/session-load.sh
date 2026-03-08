#!/usr/bin/env bash
# session-load.sh — Load and format session context on start
# Can be called manually or via CLAUDE.md instructions.
#
# What it does:
#   1. Reads all memory files
#   2. Outputs a formatted briefing block ready for context injection
#   3. Detects stale .context.md files via git diff
#
# Usage:
#   bash .agents/hooks/session-load.sh
#
# INSTALLATION (optional — for manual use):
#   chmod +x .agents/hooks/session-load.sh

set -euo pipefail

# ── Locate project ──────────────────────────────────────────────────────────
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
MEMORY_DIR="$PROJECT_DIR/.agents/memory"

# Exit silently if not a Canuto project
if [ ! -d "$MEMORY_DIR" ]; then
  echo "Not a Canuto project (no .agents/memory/ found)."
  exit 0
fi

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   Canuto — Session Context Loader        ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── Last Session ────────────────────────────────────────────────────────────
LAST_SESSION="$MEMORY_DIR/last-session.md"
if [ -f "$LAST_SESSION" ] && grep -q "^## Date" "$LAST_SESSION" 2>/dev/null; then
  SESSION_DATE=$(grep -A1 "^## Date" "$LAST_SESSION" | tail -1 | tr -d '[:space:]')
  if [ "$SESSION_DATE" != "YYYY-MM-DD" ] && [ -n "$SESSION_DATE" ]; then
    echo "── Last Session ($SESSION_DATE) ──"
    # Extract summary
    sed -n '/^## What Was Done/,/^## /p' "$LAST_SESSION" | head -10
    echo ""
  else
    echo "── Last Session: (no previous session recorded) ──"
    echo ""
  fi
else
  echo "── Last Session: (no previous session recorded) ──"
  echo ""
fi

# ── Pending Tasks ───────────────────────────────────────────────────────────
PENDING="$MEMORY_DIR/pending.md"
if [ -f "$PENDING" ]; then
  TASK_COUNT=$(grep -c '^\- \[' "$PENDING" 2>/dev/null || echo "0")
  if [ "$TASK_COUNT" -gt 0 ]; then
    echo "── Pending Tasks ($TASK_COUNT) ──"
    grep '^\- \[' "$PENDING"
    echo ""
  else
    echo "── Pending Tasks: none ──"
    echo ""
  fi
fi

# ── Instincts (if learning system is active) ────────────────────────────────
INSTINCTS="$MEMORY_DIR/instincts.md"
if [ -f "$INSTINCTS" ]; then
  INSTINCT_COUNT=$(grep -c '^### ' "$INSTINCTS" 2>/dev/null || echo "0")
  if [ "$INSTINCT_COUNT" -gt 0 ]; then
    echo "── Active Instincts ($INSTINCT_COUNT) ──"
    grep '^### ' "$INSTINCTS" | head -5
    if [ "$INSTINCT_COUNT" -gt 5 ]; then
      echo "  ... and $((INSTINCT_COUNT - 5)) more"
    fi
    echo ""
  fi
fi

# ── Stale Contexts ──────────────────────────────────────────────────────────
if command -v git &> /dev/null && git rev-parse --git-dir > /dev/null 2>&1; then
  echo "── Stale Context Check ──"

  STALE_DIRS=()
  # Find .context.md files and check if sibling source files changed after them
  while IFS= read -r ctx_file; do
    ctx_dir=$(dirname "$ctx_file")
    ctx_mtime=$(stat -c %Y "$ctx_file" 2>/dev/null || stat -f %m "$ctx_file" 2>/dev/null || echo "0")

    # Check if any source file in same dir is newer
    while IFS= read -r src_file; do
      src_mtime=$(stat -c %Y "$src_file" 2>/dev/null || stat -f %m "$src_file" 2>/dev/null || echo "0")
      if [ "$src_mtime" -gt "$ctx_mtime" ] 2>/dev/null; then
        STALE_DIRS+=("$ctx_dir")
        break
      fi
    done < <(find "$ctx_dir" -maxdepth 1 -type f \( -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.py" -o -name "*.go" -o -name "*.rs" -o -name "*.java" \) 2>/dev/null)
  done < <(find "$PROJECT_DIR" -name ".context.md" -not -path "*/node_modules/*" -not -path "*/.git/*" 2>/dev/null)

  if [ ${#STALE_DIRS[@]} -gt 0 ]; then
    echo "  ⚠ Stale .context.md detected in:"
    printf '    - %s\n' "${STALE_DIRS[@]}"
  else
    echo "  All .context.md files are up to date."
  fi
  echo ""
fi

# ── Last Save Timestamp ────────────────────────────────────────────────────
LAST_SAVE="$MEMORY_DIR/.last-save-timestamp"
if [ -f "$LAST_SAVE" ]; then
  echo "── Last auto-save: $(cat "$LAST_SAVE") ──"
  echo ""
fi

echo "Ready. Ask the Maestro what to work on."
echo ""
