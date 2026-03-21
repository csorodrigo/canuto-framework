#!/usr/bin/env bash
# pre-compact-save.sh — Save critical context before token compaction
# Dispara via hooks.Notification (detects compaction warnings)
#
# What it does:
#   1. Detects if the notification is about context compaction
#   2. Saves a pre-compaction snapshot of memory + current session state
#   3. Outputs a formatted context summary for the compacted window
#
# INSTALLATION:
#   cp .agents/hooks/pre-compact-save.sh ~/.claude/hooks/pre-compact-save.sh
#   chmod +x ~/.claude/hooks/pre-compact-save.sh

set -euo pipefail

# ── Read notification from stdin ────────────────────────────────────────────
NOTIFICATION=$(cat 2>/dev/null || echo "")

# Only act on compaction-related notifications
if ! echo "$NOTIFICATION" | grep -Eqi "compact|context.*window|truncat" 2>/dev/null; then
  exit 0
fi

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
  exit 0
fi

# ── Save pre-compaction snapshot ────────────────────────────────────────────
SNAPSHOT_DIR="$VAULT_DIR/.snapshots"
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
COMPACT_PATH="$SNAPSHOT_DIR/pre-compact-$TIMESTAMP"

mkdir -p "$COMPACT_PATH"

for dir in sessions decisions instincts pending metrics audit; do
  if [ -d "$VAULT_DIR/$dir" ]; then
    mkdir -p "$COMPACT_PATH/$dir"
    cp "$VAULT_DIR/$dir"/*.md "$COMPACT_PATH/$dir/" 2>/dev/null || true
  fi
done

# ── Output critical context for post-compaction ─────────────────────────────
echo ""
echo "════════════════════════════════════════"
echo "  Canuto — Pre-Compaction Snapshot"
echo "════════════════════════════════════════"
echo ""
echo "Critical context saved to: $VAULT_DIR/.snapshots/pre-compact-$TIMESTAMP"
echo ""

# Output condensed context that survives compaction
echo "── ESSENTIAL CONTEXT (preserve after compaction) ──"
echo ""

# Current pending tasks (list files in pending/)
PENDING_DIR="$VAULT_DIR/pending"
if [ -d "$PENDING_DIR" ]; then
  TASKS=$(ls "$PENDING_DIR"/*.md 2>/dev/null | xargs -I{} basename {} .md) || TASKS=""
  if [ -n "$TASKS" ]; then
    echo "Pending tasks:"
    echo "$TASKS" | while read -r task; do echo "  - $task"; done
    echo ""
  fi
fi

# Active instincts (list files in instincts/)
INSTINCTS_DIR="$VAULT_DIR/instincts"
if [ -d "$INSTINCTS_DIR" ]; then
  INSTINCTS=$(ls "$INSTINCTS_DIR"/*.md 2>/dev/null | head -5 | xargs -I{} basename {} .md) || INSTINCTS=""
  if [ -n "$INSTINCTS" ]; then
    echo "Top instincts:"
    echo "$INSTINCTS" | while read -r inst; do echo "  - $inst"; done
    echo ""
  fi
fi

echo "════════════════════════════════════════"
echo ""
