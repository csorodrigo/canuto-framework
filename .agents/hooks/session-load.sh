#!/usr/bin/env bash
# session-load.sh — Load and format session context on start
# Can be called manually or via CLAUDE.md instructions.
#
# What it does:
#   1. Reads vault notes (sessions, pending, instincts)
#   2. Outputs a formatted briefing block ready for context injection
#   3. Detects stale .context.md files via git diff
#
# Usage:
#   bash .agents/hooks/session-load.sh
#
# INSTALLATION (optional — for manual use):
#   chmod +x .agents/hooks/session-load.sh

set -euo pipefail

# ── Locate vault ──────────────────────────────────────────────────────────
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
PROJECT_SLUG=$(basename "$PROJECT_DIR")
GLOBAL_VAULT="$HOME/.canuto/vault"
LOCAL_VAULT="$PROJECT_DIR/.agents/vault"

# Use global vault if it exists, fallback to local
if [ -d "$GLOBAL_VAULT/projects/$PROJECT_SLUG" ]; then
  VAULT_DIR="$GLOBAL_VAULT/projects/$PROJECT_SLUG"
elif [ -d "$LOCAL_VAULT" ]; then
  VAULT_DIR="$LOCAL_VAULT"
else
  echo "Not a Canuto project (no vault found)."
  exit 0
fi

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║   Canuto — Session Context Loader        ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ── Last Session ────────────────────────────────────────────────────────────
SESSIONS_DIR="$VAULT_DIR/sessions"
LAST_SESSION=$(ls -t "$SESSIONS_DIR"/*.md 2>/dev/null | head -1)
if [ -n "$LAST_SESSION" ] && [ -f "$LAST_SESSION" ]; then
  SESSION_DATE=$(basename "$LAST_SESSION" .md)
  if [ "$SESSION_DATE" != "YYYY-MM-DD" ] && [ -n "$SESSION_DATE" ]; then
    echo "── Last Session ($SESSION_DATE) ──"
    # Extract summary (exclude the next section's header)
    sed -n '/^## What Was Done/,/^## /{/^## What Was Done/d;/^## /d;p}' "$LAST_SESSION" | head -10
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
PENDING_DIR="$VAULT_DIR/pending"
if [ -d "$PENDING_DIR" ]; then
  TASK_COUNT=$(ls "$PENDING_DIR"/*.md 2>/dev/null | grep -cv '.gitkeep' 2>/dev/null) || TASK_COUNT=0
  if [ "$TASK_COUNT" -gt 0 ]; then
    echo "── Pending Tasks ($TASK_COUNT) ──"
    for f in "$PENDING_DIR"/*.md; do
      [ -f "$f" ] && echo "  - $(basename "$f" .md)"
    done
    echo ""
  else
    echo "── Pending Tasks: none ──"
    echo ""
  fi
else
  echo "── Pending Tasks: none ──"
  echo ""
fi

# ── Instincts (if learning system is active) ────────────────────────────────
INSTINCTS_DIR="$VAULT_DIR/instincts"
if [ -d "$INSTINCTS_DIR" ]; then
  INSTINCT_COUNT=$(ls "$INSTINCTS_DIR"/*.md 2>/dev/null | grep -cv '.gitkeep' 2>/dev/null) || INSTINCT_COUNT=0
  if [ "$INSTINCT_COUNT" -gt 0 ]; then
    echo "── Active Instincts ($INSTINCT_COUNT) ──"
    ls "$INSTINCTS_DIR"/*.md 2>/dev/null | head -5 | while read -r f; do
      echo "  - $(basename "$f" .md)"
    done
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
LAST_SAVE="$VAULT_DIR/.last-save-timestamp"
if [ -f "$LAST_SAVE" ]; then
  echo "── Last auto-save: $(cat "$LAST_SAVE") ──"
  echo ""
fi

echo "Ready. Ask the Maestro what to work on."
echo ""
