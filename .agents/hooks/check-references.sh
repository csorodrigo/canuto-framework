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
ROOT_DIR="$(cd "$PROJECT_DIR" && git rev-parse --show-toplevel 2>/dev/null || pwd)"
GLOBAL_VAULT="$HOME/.canuto/vault"
LOCAL_VAULT="$ROOT_DIR/.agents/vault"

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
FILES_LIST=$(mktemp)
NOTE_INDEX_FILE=$(mktemp)

cleanup() {
  rm -f "$FILES_LIST" "$NOTE_INDEX_FILE"
}
trap cleanup EXIT

trim_whitespace() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

note_index_contains() {
  local key="${1:-}"
  [ -n "$key" ] || return 1
  grep -Fqx "$key" "$NOTE_INDEX_FILE" 2>/dev/null
}

# ── Collect files to check ───────────────────────────────────────────────
if $CHANGED_ONLY; then
  while IFS= read -r rel_file; do
    [ -n "$rel_file" ] || continue
    case "$rel_file" in
      *.md) printf '%s\n' "$ROOT_DIR/$rel_file" >> "$FILES_LIST" ;;
    esac
  done < <(git -C "$ROOT_DIR" diff --name-only --diff-filter=ACMR 2>/dev/null || true)

  while IFS= read -r rel_file; do
    [ -n "$rel_file" ] || continue
    case "$rel_file" in
      *.md) printf '%s\n' "$ROOT_DIR/$rel_file" >> "$FILES_LIST" ;;
    esac
  done < <(git -C "$ROOT_DIR" diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true)

  if [ -s "$FILES_LIST" ]; then
    sort -u "$FILES_LIST" -o "$FILES_LIST"
  fi
else
  find "$VAULT_DIR" -name "*.md" -type f 2>/dev/null > "$FILES_LIST"
fi

if [ ! -s "$FILES_LIST" ]; then
  echo "[check-references] No markdown files to check."
  exit 0
fi

# ── Build index of existing notes ────────────────────────────────────────
while IFS= read -r note; do
  [ -n "$note" ] || continue
  basename_no_ext=$(basename "$note" .md)
  rel_path="${note#"$VAULT_DIR"/}"
  printf '%s\n' "$basename_no_ext" >> "$NOTE_INDEX_FILE"
  printf '%s\n' "$rel_path" >> "$NOTE_INDEX_FILE"
  printf '%s\n' "${rel_path%.md}" >> "$NOTE_INDEX_FILE"
done < <(find "$VAULT_DIR" -name "*.md" -type f 2>/dev/null)

if [ -s "$NOTE_INDEX_FILE" ]; then
  sort -u "$NOTE_INDEX_FILE" -o "$NOTE_INDEX_FILE"
fi

# ── Check each file ──────────────────────────────────────────────────────
while IFS= read -r file; do
  [ -f "$file" ] || continue
  CHECKED_COUNT=$((CHECKED_COUNT + 1))
  file_dir=$(dirname "$file")

  # Check wikilinks: [[target]] or [[target|alias]]
  while IFS= read -r target; do
    target=$(trim_whitespace "${target%%|*}")
    [ -z "$target" ] && continue

    case "$target" in
      http*|\#*) continue ;;
    esac

    target_base="${target%%#*}"
    [ -z "$target_base" ] && continue

    # Obsidian templates intentionally contain unresolved {{date:...}} links.
    # They are valid only inside the template directory; the same placeholder
    # in a normal note must still fail closed.
    if [[ "$file" == "$VAULT_DIR/.obsidian/templates/"* \
      && "$target_base" == *"{{"* \
      && "$target_base" == *"}}"* ]]; then
      continue
    fi

    if ! note_index_contains "$target_base" && \
       ! note_index_contains "$target_base.md" && \
       [ ! -e "$file_dir/$target_base" ] && \
       [ ! -e "$file_dir/$target_base.md" ] && \
       [ ! -e "$VAULT_DIR/$target_base" ] && \
       [ ! -e "$VAULT_DIR/$target_base.md" ]; then
      echo "  BROKEN wikilink in $(basename "$file"): [[$target]]"
      BROKEN_COUNT=$((BROKEN_COUNT + 1))
    fi
  done < <(perl -ne 'while(/\[\[([^\]]+)\]\]/g){print "$1\n"}' "$file" 2>/dev/null || true)

  # Check relative markdown links: [text](path)
  while IFS= read -r link_path; do
    link_path=$(trim_whitespace "$link_path")
    [ -z "$link_path" ] && continue

    case "$link_path" in
      http*|\#*|mailto:*) continue ;;
    esac

    link_path_base="${link_path%%#*}"
    [ -z "$link_path_base" ] && continue

    if [[ "$link_path_base" == /* ]]; then
      if [ ! -e "$link_path_base" ]; then
        echo "  BROKEN link in $(basename "$file"): ($link_path)"
        BROKEN_COUNT=$((BROKEN_COUNT + 1))
      fi
      continue
    fi

    if [ ! -e "$file_dir/$link_path_base" ] && \
       [ ! -e "$ROOT_DIR/$link_path_base" ] && \
       [ ! -e "$VAULT_DIR/$link_path_base" ]; then
      echo "  BROKEN link in $(basename "$file"): ($link_path)"
      BROKEN_COUNT=$((BROKEN_COUNT + 1))
    fi
  done < <(perl -ne 'while(/\[[^\]]*\]\(([^)]+)\)/g){print "$1\n"}' "$file" 2>/dev/null || true)
done < "$FILES_LIST"

# ── Summary ──────────────────────────────────────────────────────────────
echo ""
if [ "$BROKEN_COUNT" -eq 0 ]; then
  echo "[check-references] ✓ All references OK ($CHECKED_COUNT files checked)"
  exit 0
else
  echo "[check-references] ✗ Found $BROKEN_COUNT broken reference(s) in $CHECKED_COUNT files"
  exit 1
fi
