#!/usr/bin/env bash
# check-references.sh — Detect broken wikilinks and relative links in vault markdown files.
#
# Usage:
#   bash .agents/hooks/check-references.sh                    # Check all .md files in vault
#   bash .agents/hooks/check-references.sh --changed-only     # Check only git-modified .md files
#
# Exit codes:
#   0 = all references OK
#   1 = broken references found

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
GLOBAL_VAULT="$HOME/.canuto/vault"
LOCAL_VAULT="$PROJECT_DIR/.agents/vault"

# Use global vault if it exists, fall back to local
if [ -d "$GLOBAL_VAULT" ]; then
  VAULT_DIR="$GLOBAL_VAULT"
elif [ -d "$LOCAL_VAULT" ]; then
  VAULT_DIR="$LOCAL_VAULT"
else
  echo "[check-references] No vault found. Skipping."
  exit 0
fi

CHANGED_ONLY=false
[[ "${1:-}" == "--changed-only" ]] && CHANGED_ONLY=true

BROKEN_COUNT=0
CHECKED_COUNT=0

# ── Collect files to check ───────────────────────────────────────────────
if $CHANGED_ONLY; then
  mapfile -t FILES < <(git diff --name-only --diff-filter=ACMR 2>/dev/null | grep '\.md$' || true)
  # Also check staged files
  mapfile -t STAGED < <(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null | grep '\.md$' || true)
  FILES=("${FILES[@]}" "${STAGED[@]}")
else
  mapfile -t FILES < <(find "$VAULT_DIR" -name "*.md" -type f 2>/dev/null)
fi

if [ ${#FILES[@]} -eq 0 ]; then
  echo "[check-references] No markdown files to check."
  exit 0
fi

# ── Build index of existing notes ────────────────────────────────────────
declare -A NOTE_INDEX
while IFS= read -r note; do
  # Index by filename without extension (for wikilink resolution)
  basename_no_ext=$(basename "$note" .md)
  NOTE_INDEX["$basename_no_ext"]="$note"
  # Also index by relative path from vault root
  rel_path="${note#"$VAULT_DIR"/}"
  NOTE_INDEX["$rel_path"]="$note"
done < <(find "$VAULT_DIR" -name "*.md" -type f 2>/dev/null)

# ── Check each file ─────────────────────────────────────────────────────
for file in "${FILES[@]}"; do
  [ -f "$file" ] || continue
  CHECKED_COUNT=$((CHECKED_COUNT + 1))
  file_dir=$(dirname "$file")

  # Check wikilinks: [[target]] or [[target|alias]]
  while IFS= read -r match; do
    target=$(echo "$match" | sed 's/\[\[//;s/\]\]//;s/|.*//' | xargs)
    [ -z "$target" ] && continue

    # Skip external links and anchors
    [[ "$target" == http* ]] && continue
    [[ "$target" == \#* ]] && continue

    # Strip anchor from target
    target_base="${target%%#*}"
    [ -z "$target_base" ] && continue

    # Try to resolve: by name, by relative path, by path with .md
    if [ -z "${NOTE_INDEX[$target_base]:-}" ] && \
       [ -z "${NOTE_INDEX[$target_base.md]:-}" ] && \
       [ ! -f "$file_dir/$target_base" ] && \
       [ ! -f "$file_dir/$target_base.md" ] && \
       [ ! -f "$VAULT_DIR/$target_base" ] && \
       [ ! -f "$VAULT_DIR/$target_base.md" ]; then
      echo "  BROKEN wikilink in $(basename "$file"): [[$target]]"
      BROKEN_COUNT=$((BROKEN_COUNT + 1))
    fi
  done < <(grep -oP '\[\[[^\]]+\]\]' "$file" 2>/dev/null || true)

  # Check relative markdown links: [text](path)
  while IFS= read -r match; do
    link_path=$(echo "$match" | grep -oP '\]\(\K[^)]+' | head -1)
    [ -z "$link_path" ] && continue

    # Skip external links, anchors, and mailto
    [[ "$link_path" == http* ]] && continue
    [[ "$link_path" == \#* ]] && continue
    [[ "$link_path" == mailto:* ]] && continue

    # Strip anchor
    link_path_base="${link_path%%#*}"
    [ -z "$link_path_base" ] && continue

    # Resolve relative to file's directory
    if [ ! -f "$file_dir/$link_path_base" ] && [ ! -f "$link_path_base" ]; then
      echo "  BROKEN link in $(basename "$file"): ($link_path)"
      BROKEN_COUNT=$((BROKEN_COUNT + 1))
    fi
  done < <(grep -oP '\[[^\]]*\]\([^)]+\)' "$file" 2>/dev/null || true)
done

# ── Summary ──────────────────────────────────────────────────────────────
echo ""
if [ $BROKEN_COUNT -eq 0 ]; then
  echo "[check-references] ✓ All references OK ($CHECKED_COUNT files checked)"
  exit 0
else
  echo "[check-references] ✗ Found $BROKEN_COUNT broken reference(s) in $CHECKED_COUNT files"
  exit 1
fi
