#!/usr/bin/env bash
# Cleanup stale review artifacts from .agents/tmp/codex/
# Keeps the 5 most recent files per type, deletes anything older than 7 days.

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
ROOT_DIR="$(cd "$PROJECT_DIR" && git rev-parse --show-toplevel 2>/dev/null || pwd)"
TMP_DIR="$ROOT_DIR/.agents/tmp/codex"

[ -d "$TMP_DIR" ] || exit 0

MAX_AGE_DAYS="${CODEX_CLEANUP_MAX_AGE_DAYS:-7}"
KEEP_RECENT="${CODEX_CLEANUP_KEEP_RECENT:-5}"

# Delete files older than MAX_AGE_DAYS
find "$TMP_DIR" -maxdepth 1 -type f -mtime +"$MAX_AGE_DAYS" -delete 2>/dev/null || true

# For each file type pattern, keep only KEEP_RECENT most recent
for pattern in "pre-commit-*.json" "pre-commit-*.prompt.txt" "pre-commit-*.schema.json" \
               "plan-review-*.json" "plan-review-*.prompt.txt" "plan-review-*.schema.json"; do
  # shellcheck disable=SC2086
  files=$(find "$TMP_DIR" -maxdepth 1 -name "$pattern" -type f 2>/dev/null | sort -r)
  count=0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    count=$((count + 1))
    if [ "$count" -gt "$KEEP_RECENT" ]; then
      rm -f "$f"
    fi
  done <<< "$files"
done

# Remove empty test-run directories
find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d -empty -delete 2>/dev/null || true
