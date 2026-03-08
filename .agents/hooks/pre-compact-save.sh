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

# ── Locate project ──────────────────────────────────────────────────────────
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
MEMORY_DIR="$PROJECT_DIR/.agents/memory"

if [ ! -d "$MEMORY_DIR" ]; then
  exit 0
fi

# ── Save pre-compaction snapshot ────────────────────────────────────────────
SNAPSHOT_DIR="$MEMORY_DIR/.snapshots"
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
COMPACT_PATH="$SNAPSHOT_DIR/pre-compact-$TIMESTAMP"

mkdir -p "$COMPACT_PATH"

for file in last-session.md pending.md decisions.md metrics.md instincts.md; do
  if [ -f "$MEMORY_DIR/$file" ]; then
    cp "$MEMORY_DIR/$file" "$COMPACT_PATH/$file" 2>/dev/null || true
  fi
done

# ── Output critical context for post-compaction ─────────────────────────────
echo ""
echo "════════════════════════════════════════"
echo "  Canuto — Pre-Compaction Snapshot"
echo "════════════════════════════════════════"
echo ""
echo "Critical context saved to: .agents/memory/.snapshots/pre-compact-$TIMESTAMP"
echo ""

# Output condensed context that survives compaction
echo "── ESSENTIAL CONTEXT (preserve after compaction) ──"
echo ""

# Current pending tasks (strip HTML comments)
if [ -f "$MEMORY_DIR/pending.md" ]; then
  TASKS=$(sed '/<!--/,/-->/d' "$MEMORY_DIR/pending.md" | grep '^\- \[' 2>/dev/null) || TASKS=""
  if [ -n "$TASKS" ]; then
    echo "Pending tasks:"
    echo "$TASKS"
    echo ""
  fi
fi

# Active instincts (top 3 by confidence)
if [ -f "$MEMORY_DIR/instincts.md" ]; then
  INSTINCTS=$(grep -A1 '^### ' "$MEMORY_DIR/instincts.md" 2>/dev/null | head -9) || INSTINCTS=""
  if [ -n "$INSTINCTS" ]; then
    echo "Top instincts:"
    echo "$INSTINCTS"
    echo ""
  fi
fi

echo "════════════════════════════════════════"
echo ""
