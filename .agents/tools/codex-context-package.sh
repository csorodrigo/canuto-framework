#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
ROOT_DIR="$(cd "$PROJECT_DIR" && git rev-parse --show-toplevel 2>/dev/null || pwd)"
PROJECT_DIR="$ROOT_DIR"
MEMORY_LIB="$ROOT_DIR/.agents/tools/canuto-memory.sh"
TASK_NAME=""
TASK_ID=""
GOAL=""
PLAN_FILE=""
OUTPUT_FILE=""
THREAD_ID=""
PROVIDER="${CANUTO_HANDOFF_PROVIDER:-codex}"
SOURCE_SESSION=""
declare -a TARGET_FILES=()
declare -a TARGET_DIRS=()
declare -a CONSTRAINTS=()
declare -a DONE_DEFINITION=()

while [ $# -gt 0 ]; do
  case "$1" in
    --task)
      TASK_NAME="${2:-}"
      shift
      ;;
    --task-id)
      TASK_ID="${2:-}"
      shift
      ;;
    --goal)
      GOAL="${2:-}"
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
    --thread-id)
      THREAD_ID="${2:-}"
      shift
      ;;
    --provider)
      PROVIDER="${2:-}"
      shift
      ;;
    --source-session)
      SOURCE_SESSION="${2:-}"
      shift
      ;;
    --constraint)
      CONSTRAINTS+=("${2:-}")
      shift
      ;;
    --done-definition)
      DONE_DEFINITION+=("${2:-}")
      shift
      ;;
    *)
      echo "Usage: $0 --task <name> --output <file> [--task-id <id>] [--goal <text>] [--plan <file>] [--file <path>] [--dir <path>] [--constraint <text>] [--done-definition <text>] [--thread-id <id>] [--provider <name>] [--source-session <id>]" >&2
      exit 1
      ;;
  esac
  shift
done

if [ -z "$TASK_NAME" ] || [ -z "$OUTPUT_FILE" ]; then
  echo "--task and --output are required." >&2
  exit 1
fi

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-'
}

timestamp_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

markdown_list() {
  if [ "$#" -eq 0 ]; then
    echo "- none"
    return
  fi
  local item
  for item in "$@"; do
    [ -n "$item" ] || continue
    echo "- $item"
  done
}

yaml_list() {
  if [ "$#" -eq 0 ]; then
    echo "  - none"
    return
  fi
  local item
  for item in "$@"; do
    [ -n "$item" ] || continue
    printf '  - "%s"\n' "${item//\"/\\\"}"
  done
}

write_envelope_markdown() {
  local note_path="$1"
  mkdir -p "$(dirname "$note_path")"
  cat > "$note_path" <<EOF
---
type: handoff-review
task_id: "$TASK_ID"
goal: "$GOAL"
provider: "$PROVIDER"
thread_id: "$THREAD_ID"
source_session: "$SOURCE_SESSION"
context_package: "$OUTPUT_FILE"
status: active
constraints:
$(yaml_list "${CONSTRAINTS[@]}")
done_definition:
$(yaml_list "${DONE_DEFINITION[@]}")
tags:
  - handoff
  - review
---

# Handoff Review Envelope — $TASK_ID

## Goal

$GOAL

## Constraints

$(markdown_list "${CONSTRAINTS[@]}")

## Done Definition

$(markdown_list "${DONE_DEFINITION[@]}")

## Context Package

- $OUTPUT_FILE
- provider: $PROVIDER
- thread_id: ${THREAD_ID:-none}
EOF
}

persist_envelope_note() {
  local backend_kind="none"
  local backend_dir=""
  local note_path=""
  local timestamp_slug
  timestamp_slug=$(date -u +%Y%m%dT%H%M%SZ)

  if [ -f "$MEMORY_LIB" ]; then
    # shellcheck source=/dev/null
    source "$MEMORY_LIB"
    IFS=$'\t' read -r backend_kind backend_dir < <(canuto_resolve_memory_backend "$PROJECT_DIR")
  fi

  case "$backend_kind" in
    global|local)
      if [ "$TASK_ID" = "bootstrap-context" ]; then
        note_path="$backend_dir/handoffs/bootstrap-context.md"
      else
        note_path="$backend_dir/handoffs/${timestamp_slug}-${TASK_ID}.md"
      fi
      write_envelope_markdown "$note_path"
      printf '%s\n' "$note_path"
      ;;
    legacy)
      note_path="$backend_dir/audit-log.md"
      {
        echo ""
        echo "## HANDOFF_REVIEW — $(timestamp_now)"
        echo "- task_id: $TASK_ID"
        echo "- goal: $GOAL"
        echo "- provider: $PROVIDER"
        echo "- thread_id: ${THREAD_ID:-none}"
        echo "- context_package: $OUTPUT_FILE"
        echo "- constraints:"
        markdown_list "${CONSTRAINTS[@]}"
        echo "- done_definition:"
        markdown_list "${DONE_DEFINITION[@]}"
      } >> "$note_path"
      printf '%s\n' "$note_path"
      ;;
    *)
      if [ -f "$MEMORY_LIB" ]; then
        note_path="$(canuto_pending_sync_dir "$PROJECT_DIR")/${timestamp_slug}-HANDOFF-${TASK_ID}.md"
      else
        note_path="$PROJECT_DIR/.agents/.cache/pending-sync/${timestamp_slug}-HANDOFF-${TASK_ID}.md"
      fi
      write_envelope_markdown "$note_path"
      printf '%s\n' "$note_path"
      ;;
  esac
}

if [ -z "$TASK_ID" ]; then
  TASK_ID="$(date -u +%Y%m%dT%H%M%SZ)-$(slugify "$TASK_NAME")"
fi

if [ -z "$GOAL" ]; then
  GOAL="Prepare scoped context and handoff package for ${TASK_NAME}."
fi

if [ -z "$SOURCE_SESSION" ]; then
  SOURCE_SESSION="$(date +%Y-%m-%d)"
fi

if [ "${#CONSTRAINTS[@]}" -eq 0 ]; then
  CONSTRAINTS=(
    "Use existing patterns in nearby files."
    "Do not add dependencies unless explicitly approved."
    "Add or update happy-path tests for the touched behavior."
    "If context is missing, call it out instead of guessing."
  )
fi

if [ "${#DONE_DEFINITION[@]}" -eq 0 ]; then
  DONE_DEFINITION=(
    "Context package exists at ${OUTPUT_FILE}."
    "Files and directories in scope are listed."
    "Missing context is called out explicitly."
  )
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
    sanitized=$(printf '%s' "$path" | tr '/.' '--' | tr -d '*?[]')
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
  echo "- task_id: $TASK_ID"
  echo ""

  echo "## Handoff Envelope"
  echo "- goal: $GOAL"
  echo "- provider: $PROVIDER"
  echo "- thread_id: ${THREAD_ID:-}"
  echo "- source_session: $SOURCE_SESSION"
  echo ""
  echo "### Constraints"
  markdown_list "${CONSTRAINTS[@]}"
  echo ""
  echo "### Done Definition"
  markdown_list "${DONE_DEFINITION[@]}"
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
  markdown_list "${CONSTRAINTS[@]}"
} > "$OUTPUT_FILE"

ENVELOPE_PATH="$(persist_envelope_note)"
echo "Wrote context package to $OUTPUT_FILE"
echo "Persisted handoff envelope to $ENVELOPE_PATH"
