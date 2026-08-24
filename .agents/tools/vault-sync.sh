#!/usr/bin/env bash

set -euo pipefail

umask 077

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
ROOT_DIR="$(cd "$PROJECT_DIR" && git rev-parse --show-toplevel 2>/dev/null || pwd)"
MEMORY_LIB="$ROOT_DIR/.agents/tools/canuto-memory.sh"
EVENT_LOG="$ROOT_DIR/.agents/tools/event-log.sh"
COMMAND="${1:-sync}"

if [ ! -f "$MEMORY_LIB" ]; then
  echo "Missing canuto-memory.sh. Repair the framework first." >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$MEMORY_LIB"

PROJECT_DIR=$(canuto_project_dir "$PROJECT_DIR")
PROJECT_SLUG=$(canuto_project_slug "$PROJECT_DIR")
PENDING_SYNC_DIR=$(canuto_pending_sync_dir "$PROJECT_DIR")
BACKEND_KIND=""
BACKEND_DIR=""

IFS=$'\t' read -r BACKEND_KIND BACKEND_DIR < <(canuto_resolve_memory_backend "$PROJECT_DIR")

timestamp_now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

usage() {
  cat <<'EOF_USAGE'
Usage:
  vault-sync.sh
  vault-sync.sh sync
  vault-sync.sh validate-candidate <candidate.md>
  vault-sync.sh stage-candidate <candidate.md>

Memory candidates use schema canuto-memory-candidate/v1 and are always staged
under memory-candidates/. This tool never promotes candidates into decisions,
instincts, stack rules, or global memory.
EOF_USAGE
}

candidate_field() {
  local file="$1"
  local key="$2"
  awk -v key="$key" '
    NR == 1 && $0 == "---" { in_frontmatter = 1; next }
    in_frontmatter && $0 == "---" { exit }
    in_frontmatter && index($0, key ":") == 1 {
      value = substr($0, length(key) + 2)
      sub(/^[[:space:]]+/, "", value)
      sub(/[[:space:]]+$/, "", value)
      gsub(/^"|"$/, "", value)
      print value
      exit
    }
  ' "$file"
}

candidate_fail() {
  echo "memory-candidate rejected: $1" >&2
  return 64
}

validate_candidate() {
  local file="$1"
  local size="" schema="" type="" id="" project="" tier="" authority=""
  local status="" confidence="" target_kind="" source_system="" source_session="" source_evidence=""

  [ -f "$file" ] || candidate_fail "file not found: $file"
  size=$(wc -c < "$file" | tr -d '[:space:]')
  [ -n "$size" ] && [ "$size" -le 32768 ] || candidate_fail "file exceeds 32768 bytes"
  [ "$(head -1 "$file")" = "---" ] || candidate_fail "YAML frontmatter is required"
  [ "$(grep -c '^---$' "$file" 2>/dev/null || true)" -ge 2 ] || candidate_fail "frontmatter is not closed"

  schema=$(candidate_field "$file" schema)
  type=$(candidate_field "$file" type)
  id=$(candidate_field "$file" id)
  project=$(candidate_field "$file" project)
  tier=$(candidate_field "$file" tier)
  authority=$(candidate_field "$file" authority)
  status=$(candidate_field "$file" status)
  confidence=$(candidate_field "$file" confidence)
  target_kind=$(candidate_field "$file" target-kind)
  source_system=$(candidate_field "$file" source-system)
  source_session=$(candidate_field "$file" source-session)
  source_evidence=$(candidate_field "$file" source-evidence)

  [ "$schema" = "canuto-memory-candidate/v1" ] || candidate_fail "schema must be canuto-memory-candidate/v1"
  [ "$type" = "memory-candidate" ] || candidate_fail "type must be memory-candidate"
  case "$id" in
    ""|.|..|*[!A-Za-z0-9._-]*|*..*) candidate_fail "id must be a safe path segment" ;;
  esac
  [ "${#id}" -le 120 ] || candidate_fail "id exceeds 120 characters"
  [ "$project" = "$PROJECT_SLUG" ] || candidate_fail "project '$project' does not match '$PROJECT_SLUG'"
  [ "$tier" = "hypothesis" ] || candidate_fail "automatic staging accepts hypothesis tier only"
  [ "$authority" = "memory" ] || candidate_fail "authority must be memory"
  [ "$status" = "proposed" ] || candidate_fail "status must be proposed"
  [ "$confidence" = "low" ] || candidate_fail "confidence must be low"
  case "$target_kind" in
    instinct|session|pending|metric|audit) ;;
    *) candidate_fail "target-kind is not allowed for automatic staging" ;;
  esac
  [ -n "$source_system" ] || candidate_fail "source-system is required"
  [ -n "$source_session" ] || candidate_fail "source-session is required"
  [ -n "$source_evidence" ] || candidate_fail "source-evidence is required"

  if grep -Eiq '^[[:space:]]*(approved|promoted|approval-id|approved-by)[[:space:]]*:' "$file"; then
    candidate_fail "curation or approval fields are forbidden in a candidate"
  fi
  if grep -Eiq "(api[_-]?key|access[_-]?token|refresh[_-]?token|password|authorization|client[_-]?secret)[[:space:]]*[:=][[:space:]\"']*[A-Za-z0-9_./+=-]{12,}" "$file"; then
    candidate_fail "possible secret detected"
  fi
  if ! awk '
    BEGIN { separators = 0; body = 0 }
    $0 == "---" { separators++; next }
    separators >= 2 && $0 !~ /^[[:space:]]*$/ { body = 1 }
    END { exit body ? 0 : 1 }
  ' "$file"; then
    candidate_fail "candidate body is empty"
  fi

  printf '%s\n' "$id"
}

emit_candidate_event() {
  local candidate_id="$1"
  local target="$2"
  [ -x "$EVENT_LOG" ] || return 0
  bash "$EVENT_LOG" append MEMORY_CANDIDATE_STAGED \
    actor=vault-sync \
    project="$PROJECT_SLUG" \
    candidate_id="$candidate_id" \
    target="$target" >/dev/null 2>&1 || true
}

atomic_stage() {
  local source_file="$1"
  local target="$2"
  local target_dir="" temp_file=""
  target_dir=$(dirname "$target")
  mkdir -p "$target_dir"

  if [ -f "$target" ]; then
    if cmp -s "$source_file" "$target"; then
      echo "memory-candidate already staged: $target"
      return 0
    fi
    echo "memory-candidate conflict: $target already exists with different content" >&2
    return 1
  fi

  temp_file=$(mktemp "$target_dir/.candidate.XXXXXX")
  if ! cat "$source_file" > "$temp_file"; then
    rm -f "$temp_file"
    return 1
  fi
  mv "$temp_file" "$target"
}

stage_candidate() {
  local source_file="$1"
  local candidate_id="" target=""
  candidate_id=$(validate_candidate "$source_file") || return $?

  case "$BACKEND_KIND" in
    vault|legacy)
      target="$BACKEND_DIR/memory-candidates/$candidate_id.md"
      ;;
    none)
      mkdir -p "$PENDING_SYNC_DIR"
      target="$PENDING_SYNC_DIR/memory-candidate-$candidate_id.md"
      ;;
    *)
      echo "Unsupported memory backend: $BACKEND_KIND" >&2
      return 1
      ;;
  esac

  atomic_stage "$source_file" "$target" || return $?
  emit_candidate_event "$candidate_id" "$target"
  echo "memory-candidate staged: $target"
}

sync_to_vault() {
  local vault_dir="$1"
  local source_file="$2"
  local base_name
  base_name=$(basename "$source_file" .md)
  local target="$vault_dir/audit/${base_name}-OFFLINE-SYNC.md"

  mkdir -p "$vault_dir/audit"
  cat > "$target" <<EOF_AUDIT
---
type: audit-event
event: OFFLINE_SYNC
date: $(timestamp_now)
actor: System
provider: system
session: ""
impact: medium
task_id: ""
thread_id: ""
related-pending: []
tags:
  - audit
  - offline
  - sync
---

# OFFLINE_SYNC — $PROJECT_SLUG

Synced from:
\`$source_file\`

## Original Payload

$(cat "$source_file")
EOF_AUDIT
}

sync_to_legacy() {
  local legacy_dir="$1"
  local source_file="$2"
  local audit_log="$legacy_dir/audit-log.md"

  mkdir -p "$legacy_dir"
  {
    echo ""
    echo "## OFFLINE_SYNC — $(timestamp_now)"
    echo "- project: $PROJECT_SLUG"
    echo "- source: $source_file"
    echo ""
    cat "$source_file"
  } >> "$audit_log"
}

sync_pending() {
  local pending_file=""
  local synced=0 failed=0
  local -a pending_files=()

  if [ ! -d "$PENDING_SYNC_DIR" ]; then
    echo "No pending-sync directory found."
    return 0
  fi

  while IFS= read -r pending_file; do
    [ -n "$pending_file" ] || continue
    pending_files+=("$pending_file")
  done < <(find "$PENDING_SYNC_DIR" -maxdepth 1 -type f -name '*.md' | sort)
  if [ "${#pending_files[@]}" -eq 0 ]; then
    echo "No pending sync files to process."
    return 0
  fi

  if [ "$BACKEND_KIND" = "none" ]; then
    echo "No writable memory backend available. Create/repair the vault or legacy memory first." >&2
    return 1
  fi

  for pending_file in "${pending_files[@]}"; do
    if grep -q '^schema:[[:space:]]*canuto-memory-candidate/v1[[:space:]]*$' "$pending_file" 2>/dev/null; then
      if stage_candidate "$pending_file"; then
        rm -f "$pending_file"
        synced=$((synced + 1))
      else
        failed=$((failed + 1))
      fi
      continue
    fi

    if [ "$BACKEND_KIND" = "legacy" ]; then
      if sync_to_legacy "$BACKEND_DIR" "$pending_file"; then
        rm -f "$pending_file"
        synced=$((synced + 1))
      else
        failed=$((failed + 1))
      fi
      continue
    fi

    if sync_to_vault "$BACKEND_DIR" "$pending_file"; then
      rm -f "$pending_file"
      synced=$((synced + 1))
    else
      failed=$((failed + 1))
    fi
  done

  echo "vault-sync complete: $synced synced, $failed failed."
  [ "$failed" -eq 0 ]
}

case "$COMMAND" in
  sync)
    [ "$#" -le 1 ] || { usage >&2; exit 64; }
    sync_pending
    ;;
  validate-candidate)
    [ "$#" -eq 2 ] || { usage >&2; exit 64; }
    validate_candidate "$2" >/dev/null
    echo "memory-candidate valid: $2"
    ;;
  stage-candidate)
    [ "$#" -eq 2 ] || { usage >&2; exit 64; }
    stage_candidate "$2"
    ;;
  promote|approve|curate)
    echo "vault-sync never promotes curated memory. Use the human-approved promotion workflow." >&2
    exit 64
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac
