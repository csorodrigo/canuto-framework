#!/usr/bin/env bash
# session-save.sh — Auto-save session state on Stop
# Dispara via hooks.Stop
#
# What it does:
#   1. Creates a timestamped backup of memory files
#   2. Outputs a reminder for the Maestro to finalize session state
#   3. Ensures no session data is lost on unexpected exits
#
# INSTALLATION:
#   cp .agents/hooks/session-save.sh ~/.claude/hooks/session-save.sh
#   chmod +x ~/.claude/hooks/session-save.sh

set -euo pipefail

# ── Locate project ──────────────────────────────────────────────────────────
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
MEMORY_DIR="$PROJECT_DIR/.agents/memory"

# Exit silently if not a Canuto project
if [ ! -d "$MEMORY_DIR" ]; then
  exit 0
fi

# ── Create backup snapshot ──────────────────────────────────────────────────
SNAPSHOT_DIR="$MEMORY_DIR/.snapshots"
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
SNAPSHOT_PATH="$SNAPSHOT_DIR/$TIMESTAMP"

mkdir -p "$SNAPSHOT_PATH"

# Copy current memory state (ignore errors for empty/missing files)
for file in last-session.md pending.md decisions.md metrics.md instincts.md; do
  if [ -f "$MEMORY_DIR/$file" ]; then
    cp "$MEMORY_DIR/$file" "$SNAPSHOT_PATH/$file" 2>/dev/null || true
  fi
done

# ── Prune old snapshots (keep last 10) ──────────────────────────────────────
if [ -d "$SNAPSHOT_DIR" ]; then
  ls -dt "$SNAPSHOT_DIR"/*/ 2>/dev/null | tail -n +11 | xargs rm -rf 2>/dev/null || true
fi

# ── Write session marker ────────────────────────────────────────────────────
echo "$TIMESTAMP" > "$MEMORY_DIR/.last-save-timestamp"

# ── Output reminder (visible to user) ───────────────────────────────────────
echo ""
echo "════════════════════════════════════════"
echo "  Canuto — Session State Saved"
echo "════════════════════════════════════════"
echo "  Snapshot: .agents/memory/.snapshots/$TIMESTAMP"
echo ""
echo "  Reminder: If the Maestro did not finalize"
echo "  last-session.md, pending.md, and metrics.md,"
echo "  the backup above can be used to recover state."
echo "════════════════════════════════════════"
echo ""
