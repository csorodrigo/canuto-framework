#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
ROOT_DIR="$(cd "$PROJECT_DIR" && git rev-parse --show-toplevel 2>/dev/null || pwd)"
MEMORY_LIB="$ROOT_DIR/.agents/tools/canuto-memory.sh"

if [ ! -f "$MEMORY_LIB" ]; then
  echo "Missing canuto-memory.sh. Repair the framework first." >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$MEMORY_LIB"

PROJECT_DIR=$(canuto_project_dir "$PROJECT_DIR")
PROJECT_SLUG=$(canuto_project_slug "$PROJECT_DIR")
PENDING_SYNC_DIR=$(canuto_pending_sync_dir "$PROJECT_DIR")
BACKEND_KIND=""
BACKEND_DIR=""

IFS=$'\t' read -r BACKEND_KIND BACKEND_DIR < <(canuto_resolve_memory_backend "$PROJECT_DIR")

if [ ! -d "$PENDING_SYNC_DIR" ]; then
  echo "No pending-sync directory found."
  exit 0
fi

PENDING_FILES=()
while IFS= read -r pending_file; do
  [ -n "$pending_file" ] || continue
  PENDING_FILES+=("$pending_file")
done < <(find "$PENDING_SYNC_DIR" -maxdepth 1 -type f -name '*.md' | sort)
if [ "${#PENDING_FILES[@]}" -eq 0 ]; then
  echo "No pending sync files to process."
  exit 0
fi

if [ "$BACKEND_KIND" = "none" ]; then
  echo "No writable memory backend available. Create/repair the vault or legacy memory first." >&2
  exit 1
fi

timestamp_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

sync_to_vault() {
  local vault_dir="$1"
  local source_file="$2"
  local base_name
  base_name=$(basename "$source_file" .md)
  local target="$vault_dir/audit/${base_name}-OFFLINE-SYNC.md"

  cat > "$target" <<EOF
---
type: audit-event
event: OFFLINE_SYNC
date: $(timestamp_now)
actor: System
provider: system
session: ""
impact: medium
task_id: ""
thread_id: ""
related-pending: []
tags:
  - audit
  - offline
  - sync
---

# OFFLINE_SYNC — $PROJECT_SLUG

Synced from:
\`$source_file\`

## Original Payload

$(cat "$source_file")
EOF
}

sync_to_legacy() {
  local legacy_dir="$1"
  local source_file="$2"
  local audit_log="$legacy_dir/audit-log.md"

  {
    echo ""
    echo "## OFFLINE_SYNC — $(timestamp_now)"
    echo "- project: $PROJECT_SLUG"
    echo "- source: $source_file"
    echo ""
    cat "$source_file"
  } >> "$audit_log"
}

SYNCED=0
FAILED=0

for pending_file in "${PENDING_FILES[@]}"; do
  if [ "$BACKEND_KIND" = "legacy" ]; then
    if sync_to_legacy "$BACKEND_DIR" "$pending_file"; then
      rm -f "$pending_file"
      SYNCED=$((SYNCED + 1))
    else
      FAILED=$((FAILED + 1))
    fi
    continue
  fi

  if sync_to_vault "$BACKEND_DIR" "$pending_file"; then
    rm -f "$pending_file"
    SYNCED=$((SYNCED + 1))
  else
    FAILED=$((FAILED + 1))
  fi
done

echo "vault-sync complete: $SYNCED synced, $FAILED failed."
[ "$FAILED" -eq 0 ]
