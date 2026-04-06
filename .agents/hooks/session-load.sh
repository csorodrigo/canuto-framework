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

# ── Fallback: load from cache if vault unavailable ────────────────────────
if [ "$BACKEND_KIND" = "none" ]; then
  if [ -f "$CACHE_DIR/last-briefing.txt" ]; then
    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║   Canuto — OFFLINE MODE                  ║"
    echo "║   Vault unavailable, using cached data   ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""
    cat "$CACHE_DIR/last-briefing.txt"
    echo ""
    # Check for pending-sync items
    if [ -d "$CACHE_DIR/pending-sync" ]; then
      SYNC_COUNT=$(ls "$CACHE_DIR/pending-sync"/*.md 2>/dev/null | wc -l) || SYNC_COUNT=0
      if [ "$SYNC_COUNT" -gt 0 ]; then
        echo "── ⚠ Pending Sync: $SYNC_COUNT notes waiting to be written to vault ──"
        echo ""
      fi
    fi
    echo "Ready. Ask the Maestro what to work on. (vault offline)"
    echo ""
    exit 0
  else
    echo "Not a Canuto project (no vault found, no cache available)."
    exit 0
  fi
fi

if [ "$BACKEND_KIND" = "legacy" ]; then
  LEGACY_DIR="$BACKEND_DIR"

  echo ""
  echo "╔══════════════════════════════════════════╗"
  echo "║   Canuto — Legacy Memory Compatibility   ║"
  echo "╚══════════════════════════════════════════╝"
  echo ""

  if [ -f "$LEGACY_DIR/last-session.md" ]; then
    echo "── Last Session (legacy memory) ──"
    sed -n '1,12p' "$LEGACY_DIR/last-session.md" | sed '/^[[:space:]]*$/d'
    echo ""
  else
    echo "── Last Session: (no previous legacy session recorded) ──"
    echo ""
  fi

  if [ -f "$LEGACY_DIR/pending.md" ]; then
    echo "── Pending Tasks (legacy memory) ──"
    sed -n '1,20p' "$LEGACY_DIR/pending.md" | sed '/^[[:space:]]*$/d'
    echo ""
  else
    echo "── Pending Tasks: none ──"
    echo ""
  fi

  if [ -f "$LEGACY_DIR/instincts.md" ]; then
    echo "── Instincts (legacy memory) ──"
    sed -n '1,15p' "$LEGACY_DIR/instincts.md" | sed '/^[[:space:]]*$/d'
    echo ""
  fi

  mkdir -p "$CACHE_DIR"
  {
    echo "Cached legacy briefing from $(date +%Y-%m-%d\ %H:%M)"
    echo "Project: $PROJECT_SLUG"
    echo "Backend: legacy"
  } > "$CACHE_DIR/last-briefing.txt" 2>/dev/null || true

  if [ -d "$CACHE_DIR/pending-sync" ]; then
    SYNC_COUNT=$(find "$CACHE_DIR/pending-sync" -maxdepth 1 -type f -name '*.md' | wc -l | tr -d ' ') || SYNC_COUNT=0
    if [ "$SYNC_COUNT" -gt 0 ]; then
      echo "── ⚠ Pending Sync: $SYNC_COUNT offline marker(s) ──"
      echo "  Run /vault-sync or bash .agents/tools/vault-sync.sh when a backend is ready."
      echo ""
    fi
  fi

  echo "Ready. Ask the Maestro what to work on."
  echo ""
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
  TASK_COUNT=$(find "$PENDING_DIR" -maxdepth 1 -name "*.md" -not -name ".gitkeep" -type f 2>/dev/null | wc -l) || TASK_COUNT=0
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

# ── Cache briefing for offline fallback ────────────────────────────────────
mkdir -p "$CACHE_DIR"
{
  echo "Cached briefing from $(date +%Y-%m-%d\ %H:%M)"
  echo "Project: $PROJECT_SLUG"
  echo ""
  # Re-extract key info for cache
  if [ -n "${LAST_SESSION:-}" ] && [ -f "$LAST_SESSION" ]; then
    echo "Last session: $(basename "$LAST_SESSION" .md)"
  fi
  if [ "${TASK_COUNT:-0}" -gt 0 ]; then
    echo "Pending tasks: $TASK_COUNT"
  fi
  if [ "${INSTINCT_COUNT:-0}" -gt 0 ]; then
    echo "Active instincts: $INSTINCT_COUNT"
  fi
} > "$CACHE_DIR/last-briefing.txt" 2>/dev/null || true

# ── Auto-sync pending from previous offline session ──────────────────────
if [ -d "$CACHE_DIR/pending-sync" ]; then
  SYNC_COUNT=$(find "$CACHE_DIR/pending-sync" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ') || SYNC_COUNT=0
  if [ "$SYNC_COUNT" -gt 0 ]; then
    VAULT_SYNC="$ROOT_DIR/.agents/tools/vault-sync.sh"
    if [ "$VAULT_AVAILABLE" = true ] && [ -x "$VAULT_SYNC" ]; then
      echo "── Auto-syncing $SYNC_COUNT pending notes... ──"
      if bash "$VAULT_SYNC" 2>/dev/null; then
        echo "  ✓ Pending sync completed."
      else
        echo "  ⚠ Auto-sync failed. Run /vault-sync manually."
      fi
      echo ""
    else
      echo "── ⚠ Pending Sync: $SYNC_COUNT notes from offline session ──"
      echo "  Run /vault-sync when vault is available."
      echo ""
    fi
  fi
fi

echo "Ready. Ask the Maestro what to work on."
echo ""
