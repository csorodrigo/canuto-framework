#!/usr/bin/env bash
# =============================================================================
# Canuto Framework — Vault Slug Migration
# Renames a project slug in the vault (directory, canvas files, references).
#
# Usage:
#   bash migrate-slug.sh <old-slug> <new-slug>
#   bash migrate-slug.sh prague lcd-lucrando-com-delivery
#
# What it does:
#   1. Renames projects/{old}/ → projects/{new}/
#   2. Renames canvas/{old}-*.canvas → canvas/{new}-*.canvas
#   3. Updates slug references inside canvas JSON files
#   4. Updates slug references inside project-index.json
#   5. Updates wikilinks and text references in all vault .md files
#   6. Dry-run by default — use --apply to execute
# =============================================================================

set -euo pipefail

VAULT="$HOME/.canuto/vault"

# ── Colors ──
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log()  { echo -e "${CYAN}[migrate]${NC} $1"; }
ok()   { echo -e "${GREEN}[migrate]${NC} ✓ $1"; }
warn() { echo -e "${YELLOW}[migrate]${NC} ⚠️  $1"; }
err()  { echo -e "${RED}[migrate]${NC} ✗ $1"; }

# ── Parse args ──
DRY_RUN=true
OLD_SLUG=""
NEW_SLUG=""

for arg in "$@"; do
  case "$arg" in
    --apply) DRY_RUN=false ;;
    --help|-h)
      echo "Usage: bash migrate-slug.sh <old-slug> <new-slug> [--apply]"
      echo ""
      echo "  <old-slug>   Current project slug in the vault (e.g., prague)"
      echo "  <new-slug>   Desired project slug (e.g., lcd-lucrando-com-delivery)"
      echo "  --apply      Actually execute the changes (default is dry-run)"
      echo ""
      echo "Examples:"
      echo "  bash migrate-slug.sh prague lcd-lucrando-com-delivery          # dry-run"
      echo "  bash migrate-slug.sh prague lcd-lucrando-com-delivery --apply  # execute"
      exit 0
      ;;
    *)
      if [[ -z "$OLD_SLUG" ]]; then
        OLD_SLUG="$arg"
      elif [[ -z "$NEW_SLUG" ]]; then
        NEW_SLUG="$arg"
      fi
      ;;
  esac
done

if [[ -z "$OLD_SLUG" || -z "$NEW_SLUG" ]]; then
  err "Usage: bash migrate-slug.sh <old-slug> <new-slug> [--apply]"
  exit 1
fi

if [[ "$OLD_SLUG" == "$NEW_SLUG" ]]; then
  err "Old and new slugs are the same: $OLD_SLUG"
  exit 1
fi

# ── Validate ──
PROJECT_DIR="$VAULT/projects/$OLD_SLUG"
if [[ ! -d "$PROJECT_DIR" ]]; then
  err "Project directory not found: $PROJECT_DIR"
  exit 1
fi

NEW_PROJECT_DIR="$VAULT/projects/$NEW_SLUG"
if [[ -d "$NEW_PROJECT_DIR" ]]; then
  err "Target directory already exists: $NEW_PROJECT_DIR"
  exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Vault Slug Migration"
echo "  $OLD_SLUG → $NEW_SLUG"
if $DRY_RUN; then
  echo "  Mode: DRY RUN (use --apply to execute)"
else
  echo "  Mode: APPLYING CHANGES"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

CHANGES=0

# ── Step 1: Rename project directory ──
log "Step 1: Rename project directory"
echo "  $PROJECT_DIR → $NEW_PROJECT_DIR"
if ! $DRY_RUN; then
  mv "$PROJECT_DIR" "$NEW_PROJECT_DIR"
  ok "Directory renamed"
fi
CHANGES=$((CHANGES + 1))

# ── Step 2: Rename canvas files ──
log "Step 2: Rename canvas files"
for canvas in "$VAULT/canvas/${OLD_SLUG}-"*.canvas; do
  [[ -f "$canvas" ]] || continue
  base=$(basename "$canvas")
  new_base="${base/$OLD_SLUG/$NEW_SLUG}"
  echo "  $base → $new_base"
  if ! $DRY_RUN; then
    mv "$canvas" "$VAULT/canvas/$new_base"
  fi
  CHANGES=$((CHANGES + 1))
done

# ── Step 3: Update references inside canvas JSON files ──
log "Step 3: Update slug references in canvas files"
for canvas in "$VAULT/canvas/${NEW_SLUG}-"*.canvas "$VAULT/canvas/${OLD_SLUG}-"*.canvas; do
  [[ -f "$canvas" ]] || continue
  if grep -q "$OLD_SLUG" "$canvas" 2>/dev/null; then
    echo "  $(basename "$canvas"): replacing '$OLD_SLUG' → '$NEW_SLUG'"
    if ! $DRY_RUN; then
      sed -i "s|$OLD_SLUG|$NEW_SLUG|g" "$canvas"
    fi
    CHANGES=$((CHANGES + 1))
  fi
done

# ── Step 4: Update project-index.json ──
log "Step 4: Update project-index.json"
# After step 1, the file is at the new path
INDEX_FILE="$NEW_PROJECT_DIR/project-index.json"
if $DRY_RUN; then
  INDEX_FILE="$PROJECT_DIR/project-index.json"
fi
if [[ -f "$INDEX_FILE" ]]; then
  if grep -q "$OLD_SLUG" "$INDEX_FILE" 2>/dev/null; then
    echo "  project-index.json: replacing '$OLD_SLUG' → '$NEW_SLUG'"
    if ! $DRY_RUN; then
      sed -i "s|$OLD_SLUG|$NEW_SLUG|g" "$INDEX_FILE"
    fi
    CHANGES=$((CHANGES + 1))
  fi
else
  warn "project-index.json not found (run /auto-analysis after migration)"
fi

# ── Step 5: Update references in vault .md files ──
log "Step 5: Update references in vault markdown files"
# Search for:
#   - wikilinks: [[projects/old-slug/...]]
#   - text: projects/old-slug
#   - frontmatter: source_project: old-slug
MD_COUNT=0
while IFS= read -r -d '' mdfile; do
  if grep -q "$OLD_SLUG" "$mdfile" 2>/dev/null; then
    echo "  $(echo "$mdfile" | sed "s|$VAULT/||")"
    if ! $DRY_RUN; then
      sed -i "s|$OLD_SLUG|$NEW_SLUG|g" "$mdfile"
    fi
    MD_COUNT=$((MD_COUNT + 1))
  fi
done < <(find "$VAULT" -name '*.md' -print0 2>/dev/null)
if [[ $MD_COUNT -gt 0 ]]; then
  log "  Found $MD_COUNT markdown files with references"
  CHANGES=$((CHANGES + MD_COUNT))
else
  ok "No markdown files reference '$OLD_SLUG'"
fi

# ── Step 6: Update cross-reference reports ──
log "Step 6: Update cross-reference reports"
for report in "$VAULT/reports/"*.md; do
  [[ -f "$report" ]] || continue
  if grep -q "$OLD_SLUG" "$report" 2>/dev/null; then
    echo "  $(basename "$report")"
    if ! $DRY_RUN; then
      sed -i "s|$OLD_SLUG|$NEW_SLUG|g" "$report"
    fi
    CHANGES=$((CHANGES + 1))
  fi
done

# ── Summary ──
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if $DRY_RUN; then
  echo "  DRY RUN complete: $CHANGES changes would be made"
  echo ""
  echo "  To apply: bash migrate-slug.sh $OLD_SLUG $NEW_SLUG --apply"
else
  echo "  Migration complete: $CHANGES changes applied"
  echo ""
  echo "  Next steps:"
  echo "  1. Open Obsidian and verify vault integrity"
  echo "  2. Run /auto-analysis to regenerate project-index.json"
  echo "  3. Run install.sh --install from the project directory"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
