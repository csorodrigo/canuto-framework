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
ROOT_DIR="$(cd "$PROJECT_DIR" && git rev-parse --show-toplevel 2>/dev/null || pwd)"
MEMORY_LIB="$ROOT_DIR/.agents/tools/canuto-memory.sh"

if [ -f "$MEMORY_LIB" ]; then
  # shellcheck source=/dev/null
  source "$MEMORY_LIB"
else
  canuto_project_dir()  { echo "${1:-.}"; }
  canuto_project_slug() { basename "${1:-.}"; }
  canuto_cache_dir()    { echo "${1:-.}/.agents/.cache"; }
  canuto_resolve_memory_backend() { printf 'none\t'; }
fi

PROJECT_DIR=$(canuto_project_dir "$PROJECT_DIR")
PROJECT_SLUG=$(canuto_project_slug "$PROJECT_DIR")
CACHE_DIR=$(canuto_cache_dir "$PROJECT_DIR")
BACKEND_KIND=""
BACKEND_DIR=""

IFS=$'\t' read -r BACKEND_KIND BACKEND_DIR < <(canuto_resolve_memory_backend "$PROJECT_DIR")

VAULT_AVAILABLE=false
if [ "$BACKEND_KIND" = "global" ] || [ "$BACKEND_KIND" = "local" ]; then
  VAULT_AVAILABLE=true
  VAULT_DIR="$BACKEND_DIR"
fi

# ── Fallback: save to pending-sync if vault unavailable ───────────────────
if [ "$BACKEND_KIND" = "none" ]; then
  PENDING_SYNC="$CACHE_DIR/pending-sync"
  mkdir -p "$PENDING_SYNC"
  TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
  cat > "$PENDING_SYNC/$TIMESTAMP-session-marker.md" <<EOF
---
type: pending-sync-marker
status: pending
timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
project: $PROJECT_SLUG
source: session-save
tags:
  - pending-sync
  - offline
---

# Offline Session Marker

- recorded_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
- project: $PROJECT_SLUG
- note: No vault or legacy memory backend was available when session-save ran.
EOF
  echo ""
  echo "════════════════════════════════════════"
  echo "  Canuto — OFFLINE Save"
  echo "════════════════════════════════════════"
  echo "  Vault unavailable. State saved to:"
  echo "  $PENDING_SYNC/"
  echo ""
  echo "  On next session with vault available,"
  echo "  run /vault-sync or bash .agents/tools/vault-sync.sh."
  echo "════════════════════════════════════════"
  echo ""
  exit 0
fi

if [ "$BACKEND_KIND" = "legacy" ]; then
  SNAPSHOT_DIR="$BACKEND_DIR/.snapshots"
  TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)_$$
  SNAPSHOT_PATH="$SNAPSHOT_DIR/$TIMESTAMP"

  mkdir -p "$SNAPSHOT_PATH"
  for file in last-session.md decisions.md instincts.md pending.md metrics.md audit-log.md design-profile.md component-inventory.md; do
    if [ -f "$BACKEND_DIR/$file" ]; then
      cp "$BACKEND_DIR/$file" "$SNAPSHOT_PATH/$file"
    fi
  done

  echo "$TIMESTAMP" > "$BACKEND_DIR/.last-save-timestamp"

  echo ""
  echo "════════════════════════════════════════"
  echo "  Canuto — Legacy Session State Saved"
  echo "════════════════════════════════════════"
  echo "  Snapshot: $SNAPSHOT_PATH"
  echo ""
  echo "  Legacy .agents/memory backend detected."
  echo "  Upgrade when ready, but current compatibility state was preserved."
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
