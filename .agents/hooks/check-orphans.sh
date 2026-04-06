#!/usr/bin/env bash
# check-orphans.sh — Post-migration health check: detect orphan notes, broken links,
# empty frontmatter, and sessions without metrics.
#
# Usage:
#   bash .agents/hooks/check-orphans.sh                       # Check global vault
#   bash .agents/hooks/check-orphans.sh --vault /path/to/vault  # Check specific vault
#
# Exit codes:
#   0 = vault healthy
#   1 = issues found

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
ROOT_DIR="$(cd "$PROJECT_DIR" && git rev-parse --show-toplevel 2>/dev/null || pwd)"
GLOBAL_VAULT="$HOME/.canuto/vault"
LOCAL_VAULT="$ROOT_DIR/.agents/vault"

# Parse args
VAULT_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --vault)
      shift
      VAULT_DIR="${1:-}"
      ;;
  esac
  shift
done

if [ -z "$VAULT_DIR" ]; then
  if [ -d "$GLOBAL_VAULT" ]; then
    VAULT_DIR="$GLOBAL_VAULT"
  elif [ -d "$LOCAL_VAULT" ]; then
    VAULT_DIR="$LOCAL_VAULT"
  else
    echo "[check-orphans] No vault found. Skipping."
    exit 0
  fi
fi

ORPHAN_COUNT=0
BROKEN_COUNT=0
EMPTY_FM_COUNT=0
MISSING_METRICS_COUNT=0
TOTAL_NOTES=0
ALL_NOTES_FILE=$(mktemp)
NOTE_NAMES_FILE=$(mktemp)
NOTE_PATHS_FILE=$(mktemp)
REFERENCED_FILE=$(mktemp)

cleanup() {
  rm -f "$ALL_NOTES_FILE" "$NOTE_NAMES_FILE" "$NOTE_PATHS_FILE" "$REFERENCED_FILE"
}
trap cleanup EXIT

trim_whitespace() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

index_contains() {
  local index_file="$1"
  local key="${2:-}"
  [ -n "$key" ] || return 1
  grep -Fqx "$key" "$index_file" 2>/dev/null
}

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Post-Migration Vault Health Check"
echo "  Vault: $VAULT_DIR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Single find pass — collect all vault notes once ──────────────────────
echo "── Scanning vault ──"

find "$VAULT_DIR" -name "*.md" -type f -not -path "*/.obsidian/*" 2>/dev/null > "$ALL_NOTES_FILE"
TOTAL_NOTES=$(wc -l < "$ALL_NOTES_FILE" | tr -d ' ')

# Index all notes by name and path
while IFS= read -r note; do
  [ -n "$note" ] || continue
  rel_path="${note#"$VAULT_DIR"/}"
  basename_no_ext=$(basename "$note" .md)
  printf '%s\n' "$basename_no_ext" >> "$NOTE_NAMES_FILE"
  printf '%s\n' "$rel_path" >> "$NOTE_PATHS_FILE"
  printf '%s\n' "${rel_path%.md}" >> "$NOTE_PATHS_FILE"
done < "$ALL_NOTES_FILE"

if [ -s "$NOTE_NAMES_FILE" ]; then
  sort -u "$NOTE_NAMES_FILE" -o "$NOTE_NAMES_FILE"
fi

if [ -s "$NOTE_PATHS_FILE" ]; then
  sort -u "$NOTE_PATHS_FILE" -o "$NOTE_PATHS_FILE"
fi

# Extract wikilinks once to build the incoming-reference index
while IFS= read -r note; do
  [ -n "$note" ] || continue
  while IFS= read -r raw_target; do
    target=$(trim_whitespace "${raw_target%%|*}")
    [ -z "$target" ] && continue
    case "$target" in
      http*|\#*) continue ;;
    esac
    target_base="${target%%#*}"
    [ -n "$target_base" ] || continue
    printf '%s\n' "$target_base" >> "$REFERENCED_FILE"
  done < <(perl -ne 'while(/\[\[([^\]]+)\]\]/g){print "$1\n"}' "$note" 2>/dev/null || true)
done < "$ALL_NOTES_FILE"

if [ -s "$REFERENCED_FILE" ]; then
  sort -u "$REFERENCED_FILE" -o "$REFERENCED_FILE"
fi

# ── Check 1: Orphan notes (no incoming references) ──────────────────────
echo ""
echo "── Orphan Notes (no incoming references) ──"

while IFS= read -r note; do
  [ -n "$note" ] || continue
  rel_path="${note#"$VAULT_DIR"/}"
  basename_no_ext=$(basename "$note" .md)

  [[ "$basename_no_ext" == "_index" ]] && continue
  [[ "$rel_path" == .obsidian/* ]] && continue
  [[ "$basename_no_ext" == "README" ]] && continue
  [[ "$basename_no_ext" == "SPEC" ]] && continue

  if ! index_contains "$REFERENCED_FILE" "$basename_no_ext" && \
     ! index_contains "$REFERENCED_FILE" "$rel_path" && \
     ! index_contains "$REFERENCED_FILE" "${rel_path%.md}"; then
    echo "  ORPHAN: $rel_path"
    ORPHAN_COUNT=$((ORPHAN_COUNT + 1))
  fi
done < "$ALL_NOTES_FILE"

[ "$ORPHAN_COUNT" -eq 0 ] && echo "  ✓ No orphan notes found"

# ── Check 2: Broken wikilinks (target doesn't exist) ────────────────────
echo ""
echo "── Broken Wikilinks ──"

while IFS= read -r note; do
  [ -n "$note" ] || continue
  while IFS= read -r raw_target; do
    target=$(trim_whitespace "${raw_target%%|*}")
    [ -z "$target" ] && continue
    case "$target" in
      http*|\#*) continue ;;
    esac

    target_base="${target%%#*}"
    [ -n "$target_base" ] || continue

    if ! index_contains "$NOTE_NAMES_FILE" "$target_base" && \
       ! index_contains "$NOTE_PATHS_FILE" "$target_base" && \
       [ ! -f "$VAULT_DIR/$target_base" ] && \
       [ ! -f "$VAULT_DIR/$target_base.md" ]; then
      echo "  BROKEN: [[$target_base]] in $(basename "$note")"
      BROKEN_COUNT=$((BROKEN_COUNT + 1))
    fi
  done < <(perl -ne 'while(/\[\[([^\]]+)\]\]/g){print "$1\n"}' "$note" 2>/dev/null || true)
done < "$ALL_NOTES_FILE"

[ "$BROKEN_COUNT" -eq 0 ] && echo "  ✓ No broken wikilinks found"

# ── Check 3: Empty required frontmatter ──────────────────────────────────
echo ""
echo "── Empty Required Frontmatter ──"

while IFS= read -r note; do
  [ -n "$note" ] || continue
  case "$note" in
    */instincts/*.md)
      if grep -qE "^confidence: *$" "$note" 2>/dev/null; then
        echo "  EMPTY confidence: $(basename "$note")"
        EMPTY_FM_COUNT=$((EMPTY_FM_COUNT + 1))
      fi
      ;;
    */pending/*.md)
      if grep -qE "^priority: *$" "$note" 2>/dev/null; then
        echo "  EMPTY priority: $(basename "$note")"
        EMPTY_FM_COUNT=$((EMPTY_FM_COUNT + 1))
      fi
      ;;
  esac
done < "$ALL_NOTES_FILE"

[ "$EMPTY_FM_COUNT" -eq 0 ] && echo "  ✓ All required frontmatter present"

# ── Check 4: Sessions without metrics ────────────────────────────────────
echo ""
echo "── Sessions Without Metrics ──"

while IFS= read -r note; do
  [ -n "$note" ] || continue
  case "$note" in
    */sessions/*.md)
      session_date=$(basename "$note" .md)
      project_dir=$(dirname "$(dirname "$note")")
      metrics_file="$project_dir/metrics/${session_date}-metrics.md"
      if [ ! -f "$metrics_file" ]; then
        echo "  MISSING metrics for session: $session_date"
        MISSING_METRICS_COUNT=$((MISSING_METRICS_COUNT + 1))
      fi
      ;;
  esac
done < "$ALL_NOTES_FILE"

[ "$MISSING_METRICS_COUNT" -eq 0 ] && echo "  ✓ All sessions have metrics"

# ── Summary ──────────────────────────────────────────────────────────────
TOTAL_ISSUES=$((ORPHAN_COUNT + BROKEN_COUNT + EMPTY_FM_COUNT + MISSING_METRICS_COUNT))

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Total notes: $TOTAL_NOTES"
echo "  Orphan notes: $ORPHAN_COUNT"
echo "  Broken links: $BROKEN_COUNT"
echo "  Empty frontmatter: $EMPTY_FM_COUNT"
echo "  Missing metrics: $MISSING_METRICS_COUNT"
echo ""

if [ "$TOTAL_ISSUES" -eq 0 ]; then
  echo "  Verdict: VAULT HEALTHY ✓"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 0
else
  echo "  Verdict: $TOTAL_ISSUES issue(s) found"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 1
fi
