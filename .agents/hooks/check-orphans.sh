#!/usr/bin/env bash
# check-orphans.sh — Post-migration health check: detect new orphan notes,
# broken links, empty frontmatter, and sessions without metrics.
#
# Existing historical debt may be declared in a versioned JSON baseline. The
# baseline is exact: new debt fails, and stale baseline entries fail until they
# are removed. Terminal records (audit, metrics, digests and handoffs) are not
# required to have incoming links, but links contained inside them are checked.
#
# Usage:
#   bash .agents/hooks/check-orphans.sh
#   bash .agents/hooks/check-orphans.sh --vault /path/to/vault
#   CANUTO_VAULT_HEALTH_BASELINE=/path/to/baseline.json bash ...
#
# Exit codes:
#   0 = vault healthy, with any known debt explicitly baselined
#   1 = new issue, malformed baseline, or stale baseline entry

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
ROOT_DIR="$(cd "$PROJECT_DIR" && git rev-parse --show-toplevel 2>/dev/null || pwd)"
GLOBAL_VAULT="$HOME/.canuto/vault"
LOCAL_VAULT="$ROOT_DIR/.agents/vault"

VAULT_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --vault)
      shift
      VAULT_DIR="${1:-}"
      [ -n "$VAULT_DIR" ] || {
        echo "[check-orphans] --vault requires a path" >&2
        exit 64
      }
      ;;
    *)
      echo "[check-orphans] unknown option: $1" >&2
      exit 64
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

[ -d "$VAULT_DIR" ] || {
  echo "[check-orphans] Vault directory not found: $VAULT_DIR" >&2
  exit 1
}

# The framework repository carries its own historical-debt baseline. A global
# or explicitly selected external vault never inherits that baseline by
# accident; provide CANUTO_VAULT_HEALTH_BASELINE to opt in deliberately.
BASELINE_FILE="${CANUTO_VAULT_HEALTH_BASELINE:-}"
if [ -z "$BASELINE_FILE" ] && [ "$VAULT_DIR" = "$LOCAL_VAULT" ]; then
  BASELINE_FILE="$ROOT_DIR/config/vault-health-baseline.json"
fi

ORPHAN_COUNT=0
BROKEN_COUNT=0
EMPTY_FM_COUNT=0
MISSING_METRICS_COUNT=0
STALE_BASELINE_COUNT=0
BASELINED_ORPHAN_COUNT=0
BASELINED_METRICS_COUNT=0
TOTAL_NOTES=0

ALL_NOTES_FILE=$(mktemp)
NOTE_NAMES_FILE=$(mktemp)
NOTE_PATHS_FILE=$(mktemp)
REFERENCED_FILE=$(mktemp)
BASELINE_ORPHANS_FILE=$(mktemp)
BASELINE_METRICS_FILE=$(mktemp)
OBSERVED_BASELINE_ORPHANS_FILE=$(mktemp)
OBSERVED_BASELINE_METRICS_FILE=$(mktemp)

cleanup() {
  rm -f \
    "$ALL_NOTES_FILE" \
    "$NOTE_NAMES_FILE" \
    "$NOTE_PATHS_FILE" \
    "$REFERENCED_FILE" \
    "$BASELINE_ORPHANS_FILE" \
    "$BASELINE_METRICS_FILE" \
    "$OBSERVED_BASELINE_ORPHANS_FILE" \
    "$OBSERVED_BASELINE_METRICS_FILE"
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

is_terminal_category() {
  case "$1" in
    audit/*|metrics/*|digests/*|handoffs/*) return 0 ;;
    *) return 1 ;;
  esac
}

load_baseline() {
  [ -n "$BASELINE_FILE" ] || return 0
  [ -f "$BASELINE_FILE" ] || {
    echo "[check-orphans] Baseline not found: $BASELINE_FILE" >&2
    return 1
  }
  command -v python3 >/dev/null 2>&1 || {
    echo "[check-orphans] python3 is required to validate the baseline" >&2
    return 1
  }

  python3 - \
    "$BASELINE_FILE" \
    "$BASELINE_ORPHANS_FILE" \
    "$BASELINE_METRICS_FILE" <<'PYEOF'
import json
import pathlib
import sys

source, orphan_out, metrics_out = sys.argv[1:]
try:
    with open(source, encoding="utf-8") as fh:
        data = json.load(fh)
except Exception as exc:
    raise SystemExit(f"invalid JSON baseline {source}: {exc}")

if not isinstance(data, dict) or data.get("schemaVersion") != 1:
    raise SystemExit("baseline must be an object with schemaVersion=1")


def validated_list(key: str) -> list[str]:
    values = data.get(key, [])
    if not isinstance(values, list):
        raise SystemExit(f"baseline field {key} must be an array")
    result: list[str] = []
    for value in values:
        if not isinstance(value, str) or not value.strip():
            raise SystemExit(f"baseline field {key} contains a non-string or empty path")
        value = value.strip()
        pure = pathlib.PurePosixPath(value)
        if pure.is_absolute() or ".." in pure.parts or "\\" in value:
            raise SystemExit(f"unsafe baseline path in {key}: {value}")
        result.append(value)
    if len(result) != len(set(result)):
        raise SystemExit(f"baseline field {key} contains duplicate paths")
    return sorted(result)

orphan_notes = validated_list("orphanNotes")
missing_metrics = validated_list("missingMetrics")

with open(orphan_out, "w", encoding="utf-8") as fh:
    for item in orphan_notes:
        fh.write(item + "\n")
with open(metrics_out, "w", encoding="utf-8") as fh:
    for item in missing_metrics:
        fh.write(item + "\n")
PYEOF
}

if ! load_baseline; then
  echo "[check-orphans] Refusing to run with an invalid baseline." >&2
  exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Post-Migration Vault Health Check"
echo "  Vault: $VAULT_DIR"
if [ -n "$BASELINE_FILE" ]; then
  echo "  Baseline: $BASELINE_FILE"
else
  echo "  Baseline: none"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "── Scanning vault ──"
find "$VAULT_DIR" -name "*.md" -type f -not -path "*/.obsidian/*" 2>/dev/null > "$ALL_NOTES_FILE"
TOTAL_NOTES=$(wc -l < "$ALL_NOTES_FILE" | tr -d ' ')

while IFS= read -r note; do
  [ -n "$note" ] || continue
  rel_path="${note#"$VAULT_DIR"/}"
  basename_no_ext=$(basename "$note" .md)
  printf '%s\n' "$basename_no_ext" >> "$NOTE_NAMES_FILE"
  printf '%s\n' "$rel_path" >> "$NOTE_PATHS_FILE"
  printf '%s\n' "${rel_path%.md}" >> "$NOTE_PATHS_FILE"
done < "$ALL_NOTES_FILE"

[ ! -s "$NOTE_NAMES_FILE" ] || sort -u "$NOTE_NAMES_FILE" -o "$NOTE_NAMES_FILE"
[ ! -s "$NOTE_PATHS_FILE" ] || sort -u "$NOTE_PATHS_FILE" -o "$NOTE_PATHS_FILE"

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

[ ! -s "$REFERENCED_FILE" ] || sort -u "$REFERENCED_FILE" -o "$REFERENCED_FILE"

echo ""
echo "── Orphan Notes (new debt only) ──"
while IFS= read -r note; do
  [ -n "$note" ] || continue
  rel_path="${note#"$VAULT_DIR"/}"
  basename_no_ext=$(basename "$note" .md)

  [ "$basename_no_ext" = "_index" ] && continue
  [ "$basename_no_ext" = "README" ] && continue
  [ "$basename_no_ext" = "SPEC" ] && continue
  is_terminal_category "$rel_path" && continue

  if ! index_contains "$REFERENCED_FILE" "$basename_no_ext" && \
     ! index_contains "$REFERENCED_FILE" "$rel_path" && \
     ! index_contains "$REFERENCED_FILE" "${rel_path%.md}"; then
    if index_contains "$BASELINE_ORPHANS_FILE" "$rel_path"; then
      echo "  BASELINED orphan: $rel_path"
      printf '%s\n' "$rel_path" >> "$OBSERVED_BASELINE_ORPHANS_FILE"
      BASELINED_ORPHAN_COUNT=$((BASELINED_ORPHAN_COUNT + 1))
    else
      echo "  NEW ORPHAN: $rel_path"
      ORPHAN_COUNT=$((ORPHAN_COUNT + 1))
    fi
  fi
done < "$ALL_NOTES_FILE"

[ "$ORPHAN_COUNT" -ne 0 ] || echo "  ✓ No new orphan notes found"

echo ""
echo "── Broken Wikilinks ──"
while IFS= read -r note; do
  [ -n "$note" ] || continue
  note_dir=$(dirname "$note")
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
       [ ! -e "$note_dir/$target_base" ] && \
       [ ! -e "$note_dir/$target_base.md" ] && \
       [ ! -e "$VAULT_DIR/$target_base" ] && \
       [ ! -e "$VAULT_DIR/$target_base.md" ]; then
      echo "  BROKEN: [[$target_base]] in $(basename "$note")"
      BROKEN_COUNT=$((BROKEN_COUNT + 1))
    fi
  done < <(perl -ne 'while(/\[\[([^\]]+)\]\]/g){print "$1\n"}' "$note" 2>/dev/null || true)
done < "$ALL_NOTES_FILE"

[ "$BROKEN_COUNT" -ne 0 ] || echo "  ✓ No broken wikilinks found"

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

[ "$EMPTY_FM_COUNT" -ne 0 ] || echo "  ✓ All required frontmatter present"

echo ""
echo "── Sessions Without Metrics (new debt only) ──"
while IFS= read -r note; do
  [ -n "$note" ] || continue
  case "$note" in
    */sessions/*.md)
      rel_path="${note#"$VAULT_DIR"/}"
      session_date=$(basename "$note" .md)
      project_dir=$(dirname "$(dirname "$note")")
      metrics_file="$project_dir/metrics/${session_date}-metrics.md"
      if [ ! -f "$metrics_file" ]; then
        if index_contains "$BASELINE_METRICS_FILE" "$rel_path"; then
          echo "  BASELINED missing metrics: $rel_path"
          printf '%s\n' "$rel_path" >> "$OBSERVED_BASELINE_METRICS_FILE"
          BASELINED_METRICS_COUNT=$((BASELINED_METRICS_COUNT + 1))
        else
          echo "  NEW MISSING metrics: $rel_path"
          MISSING_METRICS_COUNT=$((MISSING_METRICS_COUNT + 1))
        fi
      fi
      ;;
  esac
done < "$ALL_NOTES_FILE"

[ "$MISSING_METRICS_COUNT" -ne 0 ] || echo "  ✓ No new sessions are missing metrics"

echo ""
echo "── Baseline Exactness ──"
while IFS= read -r rel_path; do
  [ -n "$rel_path" ] || continue
  if ! index_contains "$OBSERVED_BASELINE_ORPHANS_FILE" "$rel_path"; then
    echo "  STALE orphan baseline entry: $rel_path"
    STALE_BASELINE_COUNT=$((STALE_BASELINE_COUNT + 1))
  fi
done < "$BASELINE_ORPHANS_FILE"

while IFS= read -r rel_path; do
  [ -n "$rel_path" ] || continue
  if ! index_contains "$OBSERVED_BASELINE_METRICS_FILE" "$rel_path"; then
    echo "  STALE metrics baseline entry: $rel_path"
    STALE_BASELINE_COUNT=$((STALE_BASELINE_COUNT + 1))
  fi
done < "$BASELINE_METRICS_FILE"

[ "$STALE_BASELINE_COUNT" -ne 0 ] || echo "  ✓ Baseline exactly matches known historical debt"

TOTAL_ISSUES=$((ORPHAN_COUNT + BROKEN_COUNT + EMPTY_FM_COUNT + MISSING_METRICS_COUNT + STALE_BASELINE_COUNT))

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Total notes: $TOTAL_NOTES"
echo "  New orphan notes: $ORPHAN_COUNT"
echo "  Baselined orphan notes: $BASELINED_ORPHAN_COUNT"
echo "  Broken links: $BROKEN_COUNT"
echo "  Empty frontmatter: $EMPTY_FM_COUNT"
echo "  New missing metrics: $MISSING_METRICS_COUNT"
echo "  Baselined missing metrics: $BASELINED_METRICS_COUNT"
echo "  Stale baseline entries: $STALE_BASELINE_COUNT"
echo ""

if [ "$TOTAL_ISSUES" -eq 0 ]; then
  echo "  Verdict: VAULT HEALTHY ✓"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 0
fi

echo "  Verdict: $TOTAL_ISSUES new/stale issue(s) found"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
exit 1
