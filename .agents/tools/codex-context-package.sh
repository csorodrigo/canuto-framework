#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
TASK_NAME=""
PLAN_FILE=""
OUTPUT_FILE=""
declare -a TARGET_FILES=()
declare -a TARGET_DIRS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --task)
      TASK_NAME="${2:-}"
      shift
      ;;
    --plan)
      PLAN_FILE="${2:-}"
      shift
      ;;
    --file)
      TARGET_FILES+=("${2:-}")
      shift
      ;;
    --dir)
      TARGET_DIRS+=("${2:-}")
      shift
      ;;
    --output)
      OUTPUT_FILE="${2:-}"
      shift
      ;;
    *)
      echo "Usage: $0 --task <name> --output <file> [--plan <file>] [--file <path>] [--dir <path>]" >&2
      exit 1
      ;;
  esac
  shift
done

if [ -z "$TASK_NAME" ] || [ -z "$OUTPUT_FILE" ]; then
  echo "--task and --output are required." >&2
  exit 1
fi

cd "$PROJECT_DIR"
mkdir -p "$(dirname "$OUTPUT_FILE")"

declare -a RESOLVED_PATHS=()
for path in "${TARGET_FILES[@]-}"; do
  [ -n "$path" ] || continue
  RESOLVED_PATHS+=("$path")
done
for path in "${TARGET_DIRS[@]-}"; do
  [ -n "$path" ] || continue
  RESOLVED_PATHS+=("$path")
done

if [ ${#RESOLVED_PATHS[@]} -eq 0 ]; then
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    RESOLVED_PATHS+=("$path")
  done < <(git diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true)
fi

declare -a CONTEXT_FILES=()

context_file_seen() {
  local needle="$1"
  local existing
  for existing in "${CONTEXT_FILES[@]-}"; do
    [ "$existing" = "$needle" ] && return 0
  done
  return 1
}

collect_context_file() {
  local start_path="$1"
  local current

  if [ -f "$start_path" ]; then
    current=$(dirname "$start_path")
  else
    current="$start_path"
  fi

  while :; do
    if [ -f "$current/.context.md" ] && ! context_file_seen "$current/.context.md"; then
      CONTEXT_FILES+=("$current/.context.md")
    fi
    if [ "$current" = "." ] || [ "$current" = "/" ] || [ "$current" = "$PROJECT_DIR" ]; then
      break
    fi
    current=$(dirname "$current")
  done
}

for path in "${RESOLVED_PATHS[@]}"; do
  [ -e "$path" ] || continue
  collect_context_file "$path"
done

FEATURE_MAP=""
if [ -f "docs/FEATURE-MAP.md" ]; then
  FEATURE_MAP="docs/FEATURE-MAP.md"
fi

declare -a DIGEST_FILES=()
if [ -d ".agents/vault/digests" ]; then
  for path in "${TARGET_DIRS[@]-}"; do
    sanitized=$(printf '%s' "$path" | tr '/.' '--')
    while IFS= read -r digest; do
      [ -n "$digest" ] || continue
      DIGEST_FILES+=("$digest")
    done < <(find .agents/vault/digests -maxdepth 1 -type f \( -name "*$sanitized*.md" -o -name "*$(basename "$path")*.md" \) 2>/dev/null | sort -u)
  done
fi

{
  echo "# Context Package — $TASK_NAME"
  echo ""
  echo "- generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- project: $(basename "$PROJECT_DIR")"
  echo ""

  echo "## Files and Directories in Scope"
  if [ ${#RESOLVED_PATHS[@]} -eq 0 ]; then
    echo "- none detected"
  else
    for path in "${RESOLVED_PATHS[@]-}"; do
      echo "- $path"
    done
  fi
  echo ""

  echo "## Project Rules"
  if [ -f "CLAUDE.md" ]; then
    sed -n '/^## Project Rules/,/^## /p' CLAUDE.md | sed '1d;$d'
  else
    echo "- CLAUDE.md not found"
  fi
  echo ""

  echo "## Plan"
  if [ -n "$PLAN_FILE" ] && [ -f "$PLAN_FILE" ]; then
    cat "$PLAN_FILE"
  else
    echo "No plan file provided."
  fi
  echo ""

  echo "## Feature Map"
  if [ -n "$FEATURE_MAP" ]; then
    cat "$FEATURE_MAP"
  else
    echo "docs/FEATURE-MAP.md not found."
  fi
  echo ""

  echo "## Context Files"
  if [ ${#CONTEXT_FILES[@]} -eq 0 ]; then
    echo "No .context.md files found for the selected scope."
  else
    for context_file in "${CONTEXT_FILES[@]-}"; do
      echo "### $context_file"
      cat "$context_file"
      echo ""
    done
  fi

  echo "## Digests"
  if [ ${#DIGEST_FILES[@]} -eq 0 ]; then
    echo "No matching digests found in .agents/vault/digests/."
  else
    for digest_file in "${DIGEST_FILES[@]-}"; do
      echo "### $digest_file"
      cat "$digest_file"
      echo ""
    done
  fi

  echo "## Constraints"
  echo "- Use existing patterns in nearby files."
  echo "- Do not add dependencies unless explicitly approved."
  echo "- Add or update happy-path tests for the touched behavior."
  echo "- If context is missing, call it out instead of guessing."
} > "$OUTPUT_FILE"

echo "Wrote context package to $OUTPUT_FILE"
