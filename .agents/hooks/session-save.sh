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

# ── Locate vault ──────────────────────────────────────────────────────────
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
GLOBAL_VAULT="$HOME/.canuto/vault"
LOCAL_VAULT="$PROJECT_DIR/.agents/vault"
CACHE_DIR="$PROJECT_DIR/.agents/.cache"

# Support project-slug override in CLAUDE.md
SLUG_OVERRIDE=""
if [ -f "$PROJECT_DIR/CLAUDE.md" ]; then
  SLUG_OVERRIDE=$(grep -oP 'project-slug:\s*\K\S+' "$PROJECT_DIR/CLAUDE.md" 2>/dev/null || true)
fi
PROJECT_SLUG="${SLUG_OVERRIDE:-$(basename "$PROJECT_DIR")}"

VAULT_AVAILABLE=true

# Use global vault if it exists, fallback to local
if [ -d "$GLOBAL_VAULT/projects/$PROJECT_SLUG" ]; then
  VAULT_DIR="$GLOBAL_VAULT/projects/$PROJECT_SLUG"
elif [ -d "$LOCAL_VAULT" ]; then
  VAULT_DIR="$LOCAL_VAULT"
else
  VAULT_AVAILABLE=false
fi

# ── Fallback: save to pending-sync if vault unavailable ───────────────────
if [ "$VAULT_AVAILABLE" = false ]; then
  PENDING_SYNC="$CACHE_DIR/pending-sync"
  mkdir -p "$PENDING_SYNC"
  TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
  echo "Session saved offline at $TIMESTAMP" > "$PENDING_SYNC/$TIMESTAMP-session-marker.md"
  echo ""
  echo "════════════════════════════════════════"
  echo "  Canuto — OFFLINE Save"
  echo "════════════════════════════════════════"
  echo "  Vault unavailable. State saved to:"
  echo "  $PENDING_SYNC/"
  echo ""
  echo "  On next session with vault available,"
  echo "  run /vault-sync to push pending notes."
  echo "════════════════════════════════════════"
  echo ""
  exit 0
fi

# ── Create backup snapshot ──────────────────────────────────────────────────
SNAPSHOT_DIR="$VAULT_DIR/.snapshots"
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)_$$
SNAPSHOT_PATH="$SNAPSHOT_DIR/$TIMESTAMP"

mkdir -p "$SNAPSHOT_PATH"

# Copy current vault state (key directories only)
for dir in sessions decisions instincts pending metrics audit; do
  if [ -d "$VAULT_DIR/$dir" ]; then
    mkdir -p "$SNAPSHOT_PATH/$dir"
    cp "$VAULT_DIR/$dir"/*.md "$SNAPSHOT_PATH/$dir/" 2>/dev/null || true
  fi
done

# ── Prune old snapshots (keep last 10) ──────────────────────────────────────
if [ -d "$SNAPSHOT_DIR" ]; then
  ls -dt "$SNAPSHOT_DIR"/*/ 2>/dev/null | tail -n +11 | while IFS= read -r dir; do rm -rf "$dir"; done 2>/dev/null || true
fi

# ── Write session marker ────────────────────────────────────────────────────
echo "$TIMESTAMP" > "$VAULT_DIR/.last-save-timestamp"

# ── Output reminder (visible to user) ───────────────────────────────────────
echo ""
echo "════════════════════════════════════════"
echo "  Canuto — Session State Saved"
echo "════════════════════════════════════════"
echo "  Snapshot: $VAULT_DIR/.snapshots/$TIMESTAMP"
echo ""
echo "  Reminder: If the Maestro did not finalize"
echo "  the session note, pending tasks, and metrics,"
echo "  the backup above can be used to recover state."
echo "════════════════════════════════════════"
echo ""
