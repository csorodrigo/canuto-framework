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
GLOBAL_VAULT="$HOME/.canuto/vault"
LOCAL_VAULT="$PROJECT_DIR/.agents/vault"

# Parse args
VAULT_DIR=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --vault) shift; VAULT_DIR="$1" ;;
    *) ;;
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

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Post-Migration Vault Health Check"
echo "  Vault: $VAULT_DIR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── Single find pass — collect all vault notes once ──────────────────────
echo "── Scanning vault ──"

mapfile -t ALL_NOTE_FILES < <(find "$VAULT_DIR" -name "*.md" -type f -not -path "*/.obsidian/*" 2>/dev/null)
TOTAL_NOTES=${#ALL_NOTE_FILES[@]}

declare -A NOTE_EXISTS    # basename (no ext) -> 1
declare -A NOTE_BY_PATH   # rel_path -> 1
declare -A REFERENCED_NOTES
declare -A WIKILINKS_BY_NOTE  # note_path -> space-separated targets (for reuse in Check 2)

# Index all notes by name and path
for note in "${ALL_NOTE_FILES[@]}"; do
  rel_path="${note#"$VAULT_DIR"/}"
  basename_no_ext=$(basename "$note" .md)
  NOTE_EXISTS["$basename_no_ext"]=1
  NOTE_BY_PATH["$rel_path"]=1
  NOTE_BY_PATH["${rel_path%.md}"]=1
done

# Extract wikilinks once — populate both REFERENCED_NOTES and WIKILINKS_BY_NOTE
for note in "${ALL_NOTE_FILES[@]}"; do
  targets=""
  while IFS= read -r raw; do
    target="${raw//\[\[}"
    target="${target//\]\]}"
    target="${target%%|*}"
    target="${target## }"
    target="${target%% }"
    [ -z "$target" ] && continue
    [[ "$target" == http* ]] && continue
    [[ "$target" == \#* ]] && continue
    target_base="${target%%#*}"
    [ -z "$target_base" ] && continue
    REFERENCED_NOTES["$target_base"]=1
    targets+="$target_base"$'\n'
  done < <(grep -oP '\[\[[^\]]+\]\]' "$note" 2>/dev/null || true)
  [ -n "$targets" ] && WIKILINKS_BY_NOTE["$note"]="$targets"
done

# ── Check 1: Orphan notes (no incoming references) ──────────────────────
echo ""
echo "── Orphan Notes (no incoming references) ──"

for note in "${ALL_NOTE_FILES[@]}"; do
  rel_path="${note#"$VAULT_DIR"/}"
  basename_no_ext=$(basename "$note" .md)

  [[ "$basename_no_ext" == "_index" ]] && continue
  [[ "$rel_path" == .obsidian/* ]] && continue
  [[ "$basename_no_ext" == "README" ]] && continue
  [[ "$basename_no_ext" == "SPEC" ]] && continue

  if [ -z "${REFERENCED_NOTES[$basename_no_ext]:-}" ] && \
     [ -z "${REFERENCED_NOTES[$rel_path]:-}" ] && \
     [ -z "${REFERENCED_NOTES[${rel_path%.md}]:-}" ]; then
    echo "  ORPHAN: $rel_path"
    ORPHAN_COUNT=$((ORPHAN_COUNT + 1))
  fi
done

[ $ORPHAN_COUNT -eq 0 ] && echo "  ✓ No orphan notes found"

# ── Check 2: Broken wikilinks (target doesn't exist) ────────────────────
echo ""
echo "── Broken Wikilinks ──"

for note in "${ALL_NOTE_FILES[@]}"; do
  targets="${WIKILINKS_BY_NOTE[$note]:-}"
  [ -z "$targets" ] && continue

  while IFS= read -r target_base; do
    [ -z "$target_base" ] && continue
    # Resolve via pre-built indexes — no find calls needed
    if [ -z "${NOTE_EXISTS[$target_base]:-}" ] && \
       [ -z "${NOTE_BY_PATH[$target_base]:-}" ] && \
       [ ! -f "$VAULT_DIR/$target_base" ] && \
       [ ! -f "$VAULT_DIR/$target_base.md" ]; then
      echo "  BROKEN: [[$target_base]] in $(basename "$note")"
      BROKEN_COUNT=$((BROKEN_COUNT + 1))
    fi
  done <<< "$targets"
done

[ $BROKEN_COUNT -eq 0 ] && echo "  ✓ No broken wikilinks found"

# ── Check 3: Empty required frontmatter ──────────────────────────────────
echo ""
echo "── Empty Required Frontmatter ──"

for note in "${ALL_NOTE_FILES[@]}"; do
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
done

[ $EMPTY_FM_COUNT -eq 0 ] && echo "  ✓ All required frontmatter present"

# ── Check 4: Sessions without metrics ────────────────────────────────────
echo ""
echo "── Sessions Without Metrics ──"

for note in "${ALL_NOTE_FILES[@]}"; do
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
done

[ $MISSING_METRICS_COUNT -eq 0 ] && echo "  ✓ All sessions have metrics"

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

if [ $TOTAL_ISSUES -eq 0 ]; then
  echo "  Verdict: VAULT HEALTHY ✓"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 0
else
  echo "  Verdict: $TOTAL_ISSUES issue(s) found"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 1
fi
