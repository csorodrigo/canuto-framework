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
# Sem payload num TTY: `cat` sem stdin fechado bloqueia para sempre e o
# runtime que espera o hook congela junto (regra de TTY/pipe do CLAUDE.md).
NOTIFICATION=""
[ -t 0 ] || NOTIFICATION=$(cat 2>/dev/null || echo "")

# Only act on compaction-related notifications
if ! echo "$NOTIFICATION" | grep -Eqi "compact|context.*window|truncat" 2>/dev/null; then
  exit 0
fi

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
  canuto_resolve_memory_backend() { printf 'none\t'; }
fi

EVENT_LIB="$ROOT_DIR/.agents/tools/event-log.sh"
if [ -f "$EVENT_LIB" ]; then
  # shellcheck source=/dev/null
  source "$EVENT_LIB"
else
  canuto_event_append() { return 0; }
fi

PROJECT_DIR=$(canuto_project_dir "$PROJECT_DIR")
PROJECT_SLUG=$(canuto_project_slug "$PROJECT_DIR")
BACKEND_KIND=""
BACKEND_DIR=""

IFS=$'\t' read -r BACKEND_KIND BACKEND_DIR < <(canuto_resolve_memory_backend "$PROJECT_DIR")

canuto_event_append PRE_COMPACT actor=hook backend="$BACKEND_KIND" || true

if [ "$BACKEND_KIND" = "none" ]; then
  exit 0
fi

if [ "$BACKEND_KIND" = "legacy" ]; then
  SNAPSHOT_DIR="$BACKEND_DIR/.snapshots"
  TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
  COMPACT_PATH="$SNAPSHOT_DIR/pre-compact-$TIMESTAMP"

  mkdir -p "$COMPACT_PATH"
  for file in last-session.md decisions.md instincts.md pending.md metrics.md audit-log.md; do
    if [ -f "$BACKEND_DIR/$file" ]; then
      cp "$BACKEND_DIR/$file" "$COMPACT_PATH/$file"
    fi
  done

  echo ""
  echo "════════════════════════════════════════"
  echo "  Canuto — Pre-Compaction Snapshot"
  echo "════════════════════════════════════════"
  echo ""
  echo "Critical context saved to: $COMPACT_PATH"
  echo ""
  echo "── ESSENTIAL CONTEXT (legacy backend) ──"
  echo ""

  if [ -f "$BACKEND_DIR/pending.md" ]; then
    echo "Pending tasks:"
    sed -n '1,15p' "$BACKEND_DIR/pending.md" | sed '/^[[:space:]]*$/d'
    echo ""
  fi

  if [ -f "$BACKEND_DIR/instincts.md" ]; then
    echo "Top instincts:"
    sed -n '1,15p' "$BACKEND_DIR/instincts.md" | sed '/^[[:space:]]*$/d'
    echo ""
  fi

  echo "════════════════════════════════════════"
  echo ""
  exit 0
fi

VAULT_DIR="$BACKEND_DIR"

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
