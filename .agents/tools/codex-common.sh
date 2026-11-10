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

# A política vem do mesmo resolvedor do wrapper, mesmo com cwd de execução externo.
codex_reviewer_policy() {
  local project_dir="${1:-$(codex_project_dir)}"
  local delegate="$project_dir/.agents/tools/codex-delegate.sh"
  [ -f "$delegate" ] || delegate="$HOME/.codex/bin/codex-delegate.sh"
  [ -f "$delegate" ] || { echo 'reviewer policy resolver unavailable' >&2; return 1; }
  bash "$delegate" --resolve-role reviewer "" "" "$project_dir"
}

codex_reviewer_args() {
  local policy
  policy=$(codex_reviewer_policy) || return 1
  printf '%s\n' '-m' "$(jq -r .model <<<"$policy")"
}

codex_reviewer_candidates() {
  local policy
  policy=$(codex_reviewer_policy) || return 1
  printf 'model:%s\n' "$(jq -r .model <<<"$policy")"
}

codex_reviewer_preferred_candidate() { codex_reviewer_candidates; }
codex_candidate_path_label() { printf '%s\n' "${1:-unavailable}"; }
codex_candidate_model_name() {
  case "${1:-}" in model:*) printf '%s\n' "${1#model:}" ;; *) printf '%s\n' unknown ;; esac
}
codex_candidate_fallback_occurred() { printf '%s\n' false; }

# Subconjunto explícito de JSON Schema usado pelos consumidores de review.
# Keyword desconhecida falha fechada; não depende de pacote Python instalado.
codex_validate_review_output() {
  python3 - "$1" "$2" <<'PY_SCHEMA'
import json, math, sys
allowed = {"type", "properties", "required", "additionalProperties", "items", "enum", "const"}
def reject_constant(value):
    raise ValueError("non-finite JSON number")
def unique_pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result: raise ValueError("duplicate JSON key")
        result[key] = value
    return result
def load(path):
    with open(path, encoding="utf-8") as handle:
        return json.load(handle, parse_constant=reject_constant, object_pairs_hook=unique_pairs)
def check_schema(schema):
    if not isinstance(schema, dict) or set(schema) - allowed:
        raise ValueError("unsupported review schema")
    for child in schema.get("properties", {}).values(): check_schema(child)
    if "items" in schema: check_schema(schema["items"])
def validate(value, schema):
    kinds = schema.get("type", [])
    kinds = [kinds] if isinstance(kinds, str) else kinds
    matches = {"object": isinstance(value, dict), "array": isinstance(value, list),
        "string": isinstance(value, str), "boolean": isinstance(value, bool),
        "null": value is None, "integer": type(value) is int,
        "number": type(value) in (float, int) and math.isfinite(value)}
    if kinds and not any(matches.get(kind, False) for kind in kinds): return False
    # bool não equivale a 0/1 no contrato JSON.
    equal = lambda a, b: type(a) is type(b) and a == b
    if "const" in schema and not equal(value, schema["const"]): return False
    if "enum" in schema and not any(equal(value, item) for item in schema["enum"]): return False
    if isinstance(value, dict):
        props = schema.get("properties", {})
        if set(schema.get("required", [])) - set(value): return False
        if schema.get("additionalProperties") is False and set(value) - set(props): return False
        return all(validate(item, props[key]) for key, item in value.items() if key in props)
    if isinstance(value, list) and "items" in schema:
        return all(validate(item, schema["items"]) for item in value)
    return True
try:
    schema, result = load(sys.argv[1]), load(sys.argv[2])
    check_schema(schema)
    raise SystemExit(0 if validate(result, schema) else 1)
except (ValueError, OSError, TypeError, OverflowError):
    raise SystemExit(1)
PY_SCHEMA
}

codex_run_reviewer() {
  local exec_dir="$1" schema_file="$2" output_file="$3" prompt_file="$4" used_file="$5"
  local error_file="${6:-${3}.err}"
  local policy candidate effort timeout_s attempt_dir rc=0 status
  # Nenhum artefato de chamada anterior é elegível como resultado desta chamada.
  rm -f -- "$output_file" "$used_file" "${output_file}.receipt.json"
  : > "$error_file"
  policy=$(codex_reviewer_policy 2>>"$error_file") || return 1
  candidate="model:$(jq -r .model <<<"$policy")"
  effort=$(jq -r .effort <<<"$policy")
  timeout_s="${CODEX_REVIEWER_TIMEOUT:-120}"
  if ! [[ "$timeout_s" =~ ^[1-9][0-9]*$ ]] || [ "$timeout_s" -gt 180 ]; then
    echo 'reviewer timeout must be 1..180 seconds (host hook budget: 240)' >> "$error_file"
    return 1
  fi
  if [ "$(wc -c < "$prompt_file")" -gt "${CODEX_REVIEW_MAX_PROMPT_BYTES:-450000}" ]; then
    echo 'review prompt exceeds complete payload budget' >> "$error_file"
    return 1
  fi
  attempt_dir=$(mktemp -d "${output_file}.attempt.XXXXXX") || return 1
  local -a cmd=(codex exec -C "$exec_dir" -s read-only --skip-git-repo-check --ephemeral
    -c features.multi_agent=false -c "model_reasoning_effort=\"$effort\""
    -m "${candidate#model:}" --output-schema "$schema_file" -o "$attempt_dir/result.json" -)
  codex_run_with_timeout "$timeout_s" "${cmd[@]}" < "$prompt_file" >"$attempt_dir/stdout.log" 2>"$error_file" || rc=$?
  if [ "$rc" -eq 124 ]; then status=TIMEOUT
  elif [ "$rc" -ne 0 ]; then status=EXECUTION_FAILED
  elif [ ! -s "$attempt_dir/result.json" ]; then status=EMPTY_OUTPUT
  elif ! codex_validate_review_output "$schema_file" "$attempt_dir/result.json"; then status=INVALID_OUTPUT
  else status=OK; fi
  python3 - "$attempt_dir/receipt.json" "$policy" "$status" "$rc" "$prompt_file" "$attempt_dir" <<'PY_RECEIPT'
import hashlib, json, pathlib, sys
path, policy, status, rc, prompt, attempt = sys.argv[1:]
receipt = dict(policy=json.loads(policy), status=status, exit_code=int(rc), attempt=attempt,
    requested_role="reviewer", effective_model=None, model_evidence="UNVERIFIED", fallback_occurred=False,
    prompt_sha256=hashlib.sha256(pathlib.Path(prompt).read_bytes()).hexdigest())
pathlib.Path(path).write_text(json.dumps(receipt) + "\n")
PY_RECEIPT
  cp "$attempt_dir/receipt.json" "${output_file}.receipt.json" || return 1
  if [ "$status" != OK ]; then
    printf '[reviewer status=%s attempt=%s] partial output is diagnostic only\n' "$status" "$attempt_dir" >> "$error_file"
    return 1
  fi
  mv "$attempt_dir/result.json" "$output_file" || return 1
  printf '%s\n' "$candidate" > "$used_file"
}

codex_is_security_sensitive_path() {
  local path="${1:-}"
  [[ "$path" =~ (^|/)(auth|middleware|crypto|payments?|billing|routes?|api|controllers?|schema|db|database|rls|supabase|env|config)(/|$) ]] \
    || [[ "$path" =~ (^|/)(package\.json|package-lock\.json|pnpm-lock\.yaml|yarn\.lock|go\.mod|go\.sum|requirements.*|poetry\.lock|Cargo\.toml|Cargo\.lock|Gemfile|Gemfile\.lock|composer\.json|composer\.lock|Dockerfile|docker-compose.*|\.env.*)$ ]]
}
