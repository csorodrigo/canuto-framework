#!/usr/bin/env bash

set -euo pipefail

canuto_project_dir() {
  local dir="${1:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"
  printf '%s\n' "$dir"
}

canuto_project_slug() {
  local project_dir="${1:-$(canuto_project_dir)}"
  local override=""

  if [ -f "$project_dir/CLAUDE.md" ]; then
    override=$(grep -oE 'project-slug:[[:space:]]*[^[:space:]]+' "$project_dir/CLAUDE.md" 2>/dev/null | head -1 | awk -F': ' '{print $2}' || true)
  fi

  if [ -n "$override" ]; then
    printf '%s\n' "$override"
  else
    basename "$project_dir"
  fi
}

canuto_global_vault_dir() {
  local project_dir="${1:-$(canuto_project_dir)}"
  local slug
  slug=$(canuto_project_slug "$project_dir")
  local dir="$HOME/.canuto/vault/projects/$slug"

  if [ -d "$dir" ]; then
    printf '%s\n' "$dir"
  else
    printf '\n'
  fi
}

canuto_local_vault_dir() {
  local project_dir="${1:-$(canuto_project_dir)}"
  local dir="$project_dir/.agents/vault"

  if [ -d "$dir" ]; then
    printf '%s\n' "$dir"
  else
    printf '\n'
  fi
}

canuto_legacy_memory_dir() {
  local project_dir="${1:-$(canuto_project_dir)}"
  local dir="$project_dir/.agents/memory"

  if [ -d "$dir" ]; then
    printf '%s\n' "$dir"
  else
    printf '\n'
  fi
}

canuto_cache_dir() {
  local project_dir="${1:-$(canuto_project_dir)}"
  printf '%s\n' "$project_dir/.agents/.cache"
}

canuto_pending_sync_dir() {
  local project_dir="${1:-$(canuto_project_dir)}"
  printf '%s\n' "$(canuto_cache_dir "$project_dir")/pending-sync"
}

canuto_resolve_memory_backend() {
  local project_dir="${1:-$(canuto_project_dir)}"
  local global_vault=""
  local local_vault=""
  local legacy_memory=""

  global_vault=$(canuto_global_vault_dir "$project_dir")
  if [ -n "$global_vault" ]; then
    printf 'global\t%s\n' "$global_vault"
    return 0
  fi

  local_vault=$(canuto_local_vault_dir "$project_dir")
  if [ -n "$local_vault" ]; then
    printf 'local\t%s\n' "$local_vault"
    return 0
  fi

  legacy_memory=$(canuto_legacy_memory_dir "$project_dir")
  if [ -n "$legacy_memory" ]; then
    printf 'legacy\t%s\n' "$legacy_memory"
    return 0
  fi

  printf 'none\t\n'
}

canuto_resolve_vault_dir() {
  local project_dir="${1:-$(canuto_project_dir)}"
  local backend_kind=""
  local backend_dir=""

  IFS=$'\t' read -r backend_kind backend_dir < <(canuto_resolve_memory_backend "$project_dir")
  case "$backend_kind" in
    global|local)
      printf '%s\n' "$backend_dir"
      ;;
    *)
      printf '\n'
      ;;
  esac
}
