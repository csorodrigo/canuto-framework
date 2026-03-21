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

# Auto-detect vault
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

# ── Build reference graph ────────────────────────────────────────────────
echo "── Scanning vault ──"

declare -A REFERENCED_NOTES
declare -A ALL_NOTES

# Index all notes
while IFS= read -r note; do
  rel_path="${note#"$VAULT_DIR"/}"
  basename_no_ext=$(basename "$note" .md)
  ALL_NOTES["$rel_path"]=1
  TOTAL_NOTES=$((TOTAL_NOTES + 1))
done < <(find "$VAULT_DIR" -name "*.md" -type f -not -path "*/.obsidian/*" 2>/dev/null)

# Find all wikilink targets
while IFS= read -r note; do
  while IFS= read -r target; do
    target=$(echo "$target" | sed 's/\[\[//;s/\]\]//;s/|.*//' | xargs)
    [ -z "$target" ] && continue
    [[ "$target" == http* ]] && continue
    [[ "$target" == \#* ]] && continue
    target_base="${target%%#*}"
    [ -z "$target_base" ] && continue
    REFERENCED_NOTES["$target_base"]=1
  done < <(grep -oP '\[\[[^\]]+\]\]' "$note" 2>/dev/null || true)
done < <(find "$VAULT_DIR" -name "*.md" -type f -not -path "*/.obsidian/*" 2>/dev/null)

# ── Check 1: Orphan notes (no incoming references) ──────────────────────
echo ""
echo "── Orphan Notes (no incoming references) ──"

while IFS= read -r note; do
  rel_path="${note#"$VAULT_DIR"/}"
  basename_no_ext=$(basename "$note" .md)

  # Skip index files, templates, and root-level docs
  [[ "$basename_no_ext" == "_index" ]] && continue
  [[ "$rel_path" == .obsidian/* ]] && continue
  [[ "$basename_no_ext" == "README" ]] && continue
  [[ "$basename_no_ext" == "SPEC" ]] && continue

  # Check if referenced by name or path
  if [ -z "${REFERENCED_NOTES[$basename_no_ext]:-}" ] && \
     [ -z "${REFERENCED_NOTES[$rel_path]:-}" ] && \
     [ -z "${REFERENCED_NOTES[${rel_path%.md}]:-}" ]; then
    echo "  ORPHAN: $rel_path"
    ORPHAN_COUNT=$((ORPHAN_COUNT + 1))
  fi
done < <(find "$VAULT_DIR" -name "*.md" -type f -not -path "*/.obsidian/*" 2>/dev/null)

[ $ORPHAN_COUNT -eq 0 ] && echo "  ✓ No orphan notes found"

# ── Check 2: Broken wikilinks (target doesn't exist) ────────────────────
echo ""
echo "── Broken Wikilinks ──"

while IFS= read -r note; do
  while IFS= read -r match; do
    target=$(echo "$match" | sed 's/\[\[//;s/\]\]//;s/|.*//' | xargs)
    [ -z "$target" ] && continue
    [[ "$target" == http* ]] && continue
    [[ "$target" == \#* ]] && continue
    target_base="${target%%#*}"
    [ -z "$target_base" ] && continue

    # Try to find the target
    found=false
    while IFS= read -r candidate; do
      found=true
      break
    done < <(find "$VAULT_DIR" -name "$target_base.md" -type f 2>/dev/null)

    if ! $found; then
      # Also try exact path
      if [ ! -f "$VAULT_DIR/$target_base" ] && [ ! -f "$VAULT_DIR/$target_base.md" ]; then
        echo "  BROKEN: [[$target]] in $(basename "$note")"
        BROKEN_COUNT=$((BROKEN_COUNT + 1))
      fi
    fi
  done < <(grep -oP '\[\[[^\]]+\]\]' "$note" 2>/dev/null || true)
done < <(find "$VAULT_DIR" -name "*.md" -type f -not -path "*/.obsidian/*" 2>/dev/null)

[ $BROKEN_COUNT -eq 0 ] && echo "  ✓ No broken wikilinks found"

# ── Check 3: Empty required frontmatter ──────────────────────────────────
echo ""
echo "── Empty Required Frontmatter ──"

# Check instincts for missing confidence
while IFS= read -r note; do
  if grep -q "^confidence:$" "$note" 2>/dev/null || \
     grep -q "^confidence: *$" "$note" 2>/dev/null; then
    echo "  EMPTY confidence: $(basename "$note")"
    EMPTY_FM_COUNT=$((EMPTY_FM_COUNT + 1))
  fi
done < <(find "$VAULT_DIR" -path "*/instincts/*.md" -type f 2>/dev/null)

# Check pending tasks for missing priority
while IFS= read -r note; do
  if grep -q "^priority:$" "$note" 2>/dev/null || \
     grep -q "^priority: *$" "$note" 2>/dev/null; then
    echo "  EMPTY priority: $(basename "$note")"
    EMPTY_FM_COUNT=$((EMPTY_FM_COUNT + 1))
  fi
done < <(find "$VAULT_DIR" -path "*/pending/*.md" -type f 2>/dev/null)

[ $EMPTY_FM_COUNT -eq 0 ] && echo "  ✓ All required frontmatter present"

# ── Check 4: Sessions without metrics ────────────────────────────────────
echo ""
echo "── Sessions Without Metrics ──"

while IFS= read -r session; do
  session_date=$(basename "$session" .md)
  # Look for corresponding metrics file
  project_dir=$(dirname "$(dirname "$session")")
  metrics_file="$project_dir/metrics/${session_date}-metrics.md"
  if [ ! -f "$metrics_file" ]; then
    echo "  MISSING metrics for session: $session_date"
    MISSING_METRICS_COUNT=$((MISSING_METRICS_COUNT + 1))
  fi
done < <(find "$VAULT_DIR" -path "*/sessions/*.md" -type f 2>/dev/null)

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
