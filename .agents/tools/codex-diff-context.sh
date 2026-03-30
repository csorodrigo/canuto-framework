#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
MODE="staged"
BASE_REF=""
OUTPUT_FILE=""
DIFF_TARGET="index"
DIFF_CONTEXT_LINES="${CODEX_DIFF_CONTEXT_LINES:-10}"
MAX_PATCH_BYTES="${CODEX_DIFF_MAX_BYTES:-28000}"
MAX_PATCH_LINES="${CODEX_DIFF_MAX_LINES:-480}"
MAX_PATCH_FILES="${CODEX_DIFF_MAX_FILES:-8}"

while [ $# -gt 0 ]; do
  case "$1" in
    --staged)
      MODE="staged"
      ;;
    --uncommitted)
      MODE="uncommitted"
      ;;
    --commit-candidate)
      MODE="commit-candidate"
      DIFF_TARGET="${2:-index}"
      shift
      ;;
    --base)
      MODE="base"
      BASE_REF="${2:-}"
      shift
      ;;
    --output)
      OUTPUT_FILE="${2:-}"
      shift
      ;;
    *)
      echo "Usage: $0 [--staged|--uncommitted|--commit-candidate <index|all-tracked>|--base <ref>] [--output <file>]" >&2
      exit 1
      ;;
  esac
  shift
done

cd "$PROJECT_DIR"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not a git repository." >&2
  exit 1
fi

case "$MODE" in
  staged)
    DIFF_CMD=(git diff --cached "-U$DIFF_CONTEXT_LINES" --no-color)
    STAT_CMD=(git diff --cached --stat=120 --compact-summary --no-color)
    FILE_CMD=(git diff --cached --name-only --diff-filter=ACMR)
    ;;
  uncommitted)
    DIFF_CMD=(git diff "-U$DIFF_CONTEXT_LINES" --no-color)
    STAT_CMD=(git diff --stat=120 --compact-summary --no-color)
    FILE_CMD=(git diff --name-only --diff-filter=ACMR)
    ;;
  commit-candidate)
    if [ "$DIFF_TARGET" = "all-tracked" ]; then
      if git rev-parse --verify HEAD >/dev/null 2>&1; then
        DIFF_CMD=(git diff HEAD "-U$DIFF_CONTEXT_LINES" --no-color)
        STAT_CMD=(git diff HEAD --stat=120 --compact-summary --no-color)
        FILE_CMD=(git diff HEAD --name-only --diff-filter=ACMR)
      else
        DIFF_CMD=(git diff --cached "-U$DIFF_CONTEXT_LINES" --no-color)
        STAT_CMD=(git diff --cached --stat=120 --compact-summary --no-color)
        FILE_CMD=(git diff --cached --name-only --diff-filter=ACMR)
      fi
    else
      DIFF_CMD=(git diff --cached "-U$DIFF_CONTEXT_LINES" --no-color)
      STAT_CMD=(git diff --cached --stat=120 --compact-summary --no-color)
      FILE_CMD=(git diff --cached --name-only --diff-filter=ACMR)
    fi
    ;;
  base)
    if [ -z "$BASE_REF" ]; then
      echo "--base requires a ref." >&2
      exit 1
    fi
    DIFF_CMD=(git diff "$BASE_REF"...HEAD "-U$DIFF_CONTEXT_LINES" --no-color)
    STAT_CMD=(git diff "$BASE_REF"...HEAD --stat=120 --compact-summary --no-color)
    FILE_CMD=(git diff "$BASE_REF"...HEAD --name-only --diff-filter=ACMR)
    ;;
esac

DIFF_OUTPUT="$("${DIFF_CMD[@]}")"
if [ -z "$DIFF_OUTPUT" ]; then
  DIFF_OUTPUT="No changes detected."
fi

STAT_OUTPUT="$("${STAT_CMD[@]}" 2>/dev/null || true)"
if [ -z "$STAT_OUTPUT" ]; then
  STAT_OUTPUT="No file-level diff summary detected."
fi

declare -a CHANGED_FILES=()
while IFS= read -r changed_file; do
  [ -n "$changed_file" ] || continue
  CHANGED_FILES+=("$changed_file")
done < <("${FILE_CMD[@]}" 2>/dev/null | sed '/^$/d')

extract_identifiers() {
  local regex="$1"
  printf '%s\n' "$DIFF_OUTPUT" \
    | grep -E '^[+-][^+-]' \
    | grep -oE "$regex" \
    | sed 's/[(]$//' \
    | sort -u \
    | head -20 \
    || true
}

join_pattern() {
  local joined=""
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    if [ -z "$joined" ]; then
      joined="$item"
    else
      joined="$joined|$item"
    fi
  done
  printf '%s\n' "$joined"
}

trim_patch_excerpt() {
  local output_file="$1"
  local flag_file="$2"
  local line_count=0
  local byte_count=0
  local file_count=0

  : > "$output_file"
  printf '%s\n' "false" > "$flag_file"

  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" == diff\ --git* ]]; then
      if [ "$file_count" -ge "$MAX_PATCH_FILES" ]; then
        printf '%s\n' "true" > "$flag_file"
        break
      fi
      file_count=$((file_count + 1))
    fi

    if [ "$line_count" -ge "$MAX_PATCH_LINES" ]; then
      printf '%s\n' "true" > "$flag_file"
      break
    fi

    next_bytes=$((byte_count + ${#line} + 1))
    if [ "$next_bytes" -gt "$MAX_PATCH_BYTES" ]; then
      printf '%s\n' "true" > "$flag_file"
      break
    fi

    printf '%s\n' "$line" >> "$output_file"
    line_count=$((line_count + 1))
    byte_count=$next_bytes
  done
}

TYPE_PATTERN=$(extract_identifiers '\b[A-Z][A-Za-z0-9_]*\b' | join_pattern)
FUNC_PATTERN=$(extract_identifiers '\b[a-z][A-Za-z0-9_]*\(' | join_pattern)

render_signatures() {
  local file="$1"
  local rendered=false

  if [ -n "$TYPE_PATTERN" ]; then
    if rg -n "^[[:space:]]*(export[[:space:]]+)?(type|interface|enum|class)[[:space:]]+(${TYPE_PATTERN})\\b" "$file" 2>/dev/null | head -20; then
      rendered=true
    fi
  fi

  if [ -n "$FUNC_PATTERN" ]; then
    if rg -n "^[[:space:]]*(export[[:space:]]+)?(async[[:space:]]+)?function[[:space:]]+(${FUNC_PATTERN})\\b|^[[:space:]]*(export[[:space:]]+)?(const|let|var)[[:space:]]+(${FUNC_PATTERN})[[:space:]]*=" "$file" 2>/dev/null | head -20; then
      rendered=true
    fi
  fi

  [ "$rendered" = true ] || return 1
}

RESULT_FILE="${OUTPUT_FILE:-$(mktemp)}"
PATCH_FILE=$(mktemp)
TRUNCATED_FILE=$(mktemp)
trim_patch_excerpt "$PATCH_FILE" "$TRUNCATED_FILE" <<< "$DIFF_OUTPUT"
PATCH_EXCERPT=$(cat "$PATCH_FILE")
PATCH_TRUNCATED=$(cat "$TRUNCATED_FILE")
rm -f "$PATCH_FILE" "$TRUNCATED_FILE"

{
  echo "# Compressed Diff Context"
  echo ""
  echo "## Review Scope"
  echo "- mode: $MODE"
  if [ "$MODE" = "commit-candidate" ]; then
    echo "- commit_target: $DIFF_TARGET"
  fi
  if [ -n "$BASE_REF" ]; then
    echo "- base: $BASE_REF"
  fi
  echo "- files: ${#CHANGED_FILES[@]}"
  echo ""
  echo "## Diff Summary"
  echo '```text'
  printf '%s\n' "$STAT_OUTPUT"
  echo '```'
  echo ""
  echo "## Patch Excerpt"
  if [ "$PATCH_TRUNCATED" = "true" ]; then
    echo "_Truncated to first $MAX_PATCH_FILES files, $MAX_PATCH_LINES lines, and $MAX_PATCH_BYTES bytes._"
  fi
  echo '```diff'
  printf '%s\n' "$PATCH_EXCERPT"
  echo '```'
  echo ""

  if [ "$PATCH_TRUNCATED" = "true" ] && [ ${#CHANGED_FILES[@]} -gt "$MAX_PATCH_FILES" ]; then
    echo "## Omitted Files"
    printf '%s\n' "${CHANGED_FILES[@]:$MAX_PATCH_FILES}"
    echo ""
  fi

  if [ ${#CHANGED_FILES[@]} -gt 0 ]; then
    echo "## Referenced Signatures"
    sig_tmp=$(mktemp)
    for file in "${CHANGED_FILES[@]}"; do
      [ -f "$file" ] || continue
      : > "$sig_tmp"
      if ! render_signatures "$file" >"$sig_tmp" 2>/dev/null; then
        continue
      fi
      if [ -s "$sig_tmp" ]; then
        echo "### $file"
        echo '```text'
        cat "$sig_tmp"
        echo '```'
        echo ""
      fi
    done
    rm -f "$sig_tmp"
  fi
} > "$RESULT_FILE"

cat "$RESULT_FILE"

if [ -z "$OUTPUT_FILE" ]; then
  rm -f "$RESULT_FILE"
fi
