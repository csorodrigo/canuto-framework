#!/usr/bin/env bash

set -euo pipefail

codex_project_dir() {
  local dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
  git -C "$dir" rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$dir"
}

codex_project_slug() {
  local project_dir="${1:-$(codex_project_dir)}"
  local slug=""
  if [ -f "$project_dir/CLAUDE.md" ]; then
    slug=$(grep -oE 'project-slug:[[:space:]]*[^[:space:]]+' "$project_dir/CLAUDE.md" 2>/dev/null | head -1 | awk -F': ' '{print $2}' || true)
  fi
  if [ -n "$slug" ]; then
    printf '%s\n' "$slug"
  else
    basename "$project_dir"
  fi
}

codex_vault_dir() {
  local project_dir="${1:-$(codex_project_dir)}"
  local slug
  slug=$(codex_project_slug "$project_dir")
  local global_vault="$HOME/.canuto/vault/projects/$slug"

  if [ -d "$global_vault" ]; then
    printf '%s\n' "$global_vault"
    return
  fi

  printf '%s\n' ""
}

codex_metrics_dir() {
  local project_dir="${1:-$(codex_project_dir)}"
  local vault_dir
  vault_dir=$(codex_vault_dir "$project_dir")

  if [ -n "$vault_dir" ]; then
    mkdir -p "$vault_dir/metrics"
    printf '%s\n' "$vault_dir/metrics"
    return
  fi

  mkdir -p "$project_dir/.agents/.cache/codex/metrics"
  printf '%s\n' "$project_dir/.agents/.cache/codex/metrics"
}

codex_sessions_dir() {
  local project_dir="${1:-$(codex_project_dir)}"
  local vault_dir
  vault_dir=$(codex_vault_dir "$project_dir")

  if [ -n "$vault_dir" ]; then
    mkdir -p "$vault_dir/sessions"
    printf '%s\n' "$vault_dir/sessions"
    return
  fi

  mkdir -p "$project_dir/.agents/.cache/codex/sessions"
  printf '%s\n' "$project_dir/.agents/.cache/codex/sessions"
}

codex_tmp_dir() {
  local project_dir="${1:-$(codex_project_dir)}"
  mkdir -p "$project_dir/.agents/tmp/codex"
  printf '%s\n' "$project_dir/.agents/tmp/codex"
}

codex_review_exec_dir() {
  local project_dir="${1:-$(codex_project_dir)}"
  local slug
  slug=$(codex_project_slug "$project_dir")
  local runner_dir="$HOME/.canuto/cache/codex-reviewer/$slug"
  mkdir -p "$runner_dir"
  printf '%s\n' "$runner_dir"
}

codex_event_log_path() {
  local metrics_dir
  metrics_dir=$(codex_metrics_dir "${1:-$(codex_project_dir)}")
  printf '%s\n' "$metrics_dir/codex-review-events.jsonl"
}

codex_append_event() {
  local project_dir="${1:-$(codex_project_dir)}"
  local event_json="${2:-}"
  local event_log
  event_log=$(codex_event_log_path "$project_dir")
  [ -n "$event_json" ] || return 0
  printf '%s\n' "$event_json" >> "$event_log"
}

codex_review_markdown_path() {
  local project_dir="${1:-$(codex_project_dir)}"
  local review_name="${2:-review}"
  local tmp_dir
  tmp_dir=$(codex_tmp_dir "$project_dir")
  printf '%s\n' "$tmp_dir/${review_name}.md"
}

codex_context_package_valid() {
  local package_path="${1:-}"
  local max_age_seconds="${2:-${CODEX_CONTEXT_MAX_AGE:-14400}}"

  [ -n "$package_path" ] || return 1
  [ -f "$package_path" ] || return 1
  [ -s "$package_path" ] || return 1
  grep -q '^# Context Package' "$package_path" 2>/dev/null || return 1

  local now_ts
  local file_ts
  now_ts=$(date +%s)
  if [[ "$(uname)" == "Darwin" ]]; then
    file_ts=$(stat -f %m "$package_path" 2>/dev/null || echo 0)
  else
    file_ts=$(stat -c %Y "$package_path" 2>/dev/null || echo 0)
  fi

  [ "$file_ts" -gt 0 ] || return 1
  [ $((now_ts - file_ts)) -le "$max_age_seconds" ] || return 1
}

codex_run_with_timeout() {
  local timeout_seconds="${1:-0}"
  shift

  if [ "${timeout_seconds:-0}" -le 0 ] 2>/dev/null; then
    "$@"
    return $?
  fi

  if command -v timeout >/dev/null 2>&1; then
    timeout "$timeout_seconds" "$@"
    return $?
  fi

  # macOS não traz GNU timeout; com coreutils do brew ele chega como `gtimeout`.
  # Sem este ramo, todo Mac sem coreutils caía no fallback python3 — que funciona,
  # mas é um processo a mais por chamada num caminho já síncrono e sensível.
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$timeout_seconds" "$@"
    return $?
  fi

  python3 -c '
import subprocess
import sys

timeout_seconds = float(sys.argv[1])
cmd = sys.argv[2:]

try:
    completed = subprocess.run(
        cmd,
        stdin=sys.stdin,
        stdout=sys.stdout,
        stderr=sys.stderr,
        timeout=timeout_seconds,
        check=False,
    )
except subprocess.TimeoutExpired:
    raise SystemExit(124)

raise SystemExit(completed.returncode)
' "$timeout_seconds" "$@"
}

codex_reviewer_args() {
  local config_toml="$HOME/.codex/config.toml"
  if [ -f "$config_toml" ] && grep -q '\[profiles\.reviewer\]' "$config_toml" 2>/dev/null; then
    printf '%s\n' "--profile" "reviewer"
  else
    printf '%s\n' "-m" "gpt-5.5"
  fi
}

codex_profile_model() {
  local profile="${1:-}"
  local config_toml="$HOME/.codex/config.toml"

  [ -n "$profile" ] || return 1
  [ -f "$config_toml" ] || return 1

  awk -v profile="$profile" '
    $0 ~ "^\\[profiles\\." profile "\\]$" { in_profile=1; next }
    /^\[.*\]$/ && in_profile { exit }
    in_profile && $1 == "model" {
      value = $3
      gsub(/"/, "", value)
      print value
      exit
    }
  ' "$config_toml"
}

codex_reviewer_candidates() {
  local config_toml="$HOME/.codex/config.toml"
  if [ -f "$config_toml" ] && grep -q '\[profiles\.reviewer\]' "$config_toml" 2>/dev/null; then
    printf '%s\n' "profile:reviewer"
  else
    printf '%s\n' "model:gpt-5.5"
  fi
  printf '%s\n' "profile:maestro"
  printf '%s\n' "profile:architect"
}

codex_reviewer_preferred_candidate() {
  codex_reviewer_candidates | head -1
}

codex_candidate_path_label() {
  local candidate="${1:-}"
  if [ -z "$candidate" ]; then
    printf '%s\n' "unavailable"
  else
    printf '%s\n' "$candidate"
  fi
}

codex_candidate_model_name() {
  local candidate="${1:-}"
  case "$candidate" in
    profile:*)
      codex_profile_model "${candidate#profile:}" 2>/dev/null || printf '%s\n' "${candidate#profile:}"
      ;;
    model:*)
      printf '%s\n' "${candidate#model:}"
      ;;
    *)
      printf '%s\n' "unknown"
      ;;
  esac
}

codex_candidate_fallback_occurred() {
  local candidate="${1:-}"
  local preferred
  preferred=$(codex_reviewer_preferred_candidate 2>/dev/null || true)

  if [ -z "$candidate" ] || [ -z "$preferred" ]; then
    printf '%s\n' "true"
    return
  fi

  if [ "$candidate" = "$preferred" ]; then
    printf '%s\n' "false"
  else
    printf '%s\n' "true"
  fi
}

codex_run_reviewer() {
  local exec_dir="$1"
  local schema_file="$2"
  local output_file="$3"
  local prompt_file="$4"
  local used_file="$5"
  local error_file="${6:-}"

  local candidate=""
  local local_error_file=""
  local -a cmd=()
  local candidate_error_file=""

  if [ -n "$error_file" ]; then
    : > "$error_file"
  else
    local_error_file=$(mktemp)
    error_file="$local_error_file"
  fi

  while IFS= read -r candidate; do
    [ -n "$candidate" ] || continue
    candidate_error_file=$(mktemp)
    local reviewer_timeout="${CODEX_REVIEWER_TIMEOUT:-120}"
    cmd=(codex exec -C "$exec_dir" -s read-only --skip-git-repo-check --ephemeral -c 'model_reasoning_effort="high"')
    case "$candidate" in
      profile:*)
        cmd+=(--profile "${candidate#profile:}")
        ;;
      model:*)
        cmd+=(-m "${candidate#model:}")
        ;;
    esac
    cmd+=(--output-schema "$schema_file" -o "$output_file" -)

    if codex_run_with_timeout "$reviewer_timeout" "${cmd[@]}" < "$prompt_file" >/dev/null 2>"$candidate_error_file"; then
      printf '%s\n' "$candidate" > "$used_file"
      if [ -s "$candidate_error_file" ]; then
        cat "$candidate_error_file" > "$error_file"
      else
        : > "$error_file"
      fi
      # C9: notify user when fallback occurred
      local preferred
      preferred=$(codex_reviewer_preferred_candidate 2>/dev/null || true)
      if [ -n "$preferred" ] && [ "$candidate" != "$preferred" ]; then
        printf '[codex-reviewer] FALLBACK: preferred %s unavailable, used %s instead\n' "$preferred" "$candidate" >&2
      fi
      rm -f "$candidate_error_file"
      [ -n "$local_error_file" ] && rm -f "$local_error_file"
      return 0
    fi

    {
      printf '[candidate=%s]\n' "$candidate"
      cat "$candidate_error_file"
      printf '\n'
    } >> "$error_file"
    rm -f "$candidate_error_file"
  done < <(codex_reviewer_candidates)

  [ -n "$local_error_file" ] && rm -f "$local_error_file"
  return 1
}

codex_is_security_sensitive_path() {
  local path="${1:-}"
  [[ "$path" =~ (^|/)(auth|middleware|crypto|payments?|billing|routes?|api|controllers?|schema|db|database|rls|supabase|env|config)(/|$) ]] \
    || [[ "$path" =~ (^|/)(package\.json|package-lock\.json|pnpm-lock\.yaml|yarn\.lock|go\.mod|go\.sum|requirements.*|poetry\.lock|Cargo\.toml|Cargo\.lock|Gemfile|Gemfile\.lock|composer\.json|composer\.lock|Dockerfile|docker-compose.*|\.env.*)$ ]]
}
