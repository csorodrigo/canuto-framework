#!/usr/bin/env bash

set -euo pipefail

# Sem payload num TTY: `cat` sem stdin fechado bloqueia para sempre e o
# runtime que espera o hook congela junto (regra de TTY/pipe do CLAUDE.md).
HOOK_INPUT=""
[ -t 0 ] || HOOK_INPUT=$(cat 2>/dev/null || echo "")
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
ROOT_DIR="$(cd "$PROJECT_DIR" && git rev-parse --show-toplevel 2>/dev/null || pwd)"

_degraded_flag() {
  local flag_dir="$ROOT_DIR/.agents/tmp/codex"
  mkdir -p "$flag_dir" 2>/dev/null || true
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$flag_dir/degraded-mode.flag"
  printf '[codex-pretool-guard] DEGRADED: %s\n' "$1" >&2
}

if ! command -v jq >/dev/null 2>&1; then
  _degraded_flag "jq not found — all Codex validation skipped"
  exit 0
fi

COMMON_LIB="$ROOT_DIR/.agents/tools/codex-common.sh"
DIFF_SCRIPT="$ROOT_DIR/.agents/tools/codex-diff-context.sh"

# Projects without a local .agents/ checkout fall back to the globally
# installed copies (install.sh ships them to ~/.claude/scripts/).
GLOBAL_SCRIPTS_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts"
[ -f "$COMMON_LIB" ] || COMMON_LIB="$GLOBAL_SCRIPTS_DIR/codex-common.sh"
[ -f "$DIFF_SCRIPT" ] || DIFF_SCRIPT="$GLOBAL_SCRIPTS_DIR/codex-diff-context.sh"

if [ ! -f "$COMMON_LIB" ]; then
  _degraded_flag "codex-common.sh not found — all Codex validation skipped"
  exit 0
fi

# shellcheck source=/dev/null
source "$COMMON_LIB"

TOOL_NAME=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)

block_with_message() {
  printf '%s\n' "$1" >&2
  exit 2
}

reviewer_cmd() {
  local project_dir="$1"
  local schema_file="$2"
  local output_file="$3"
  local prompt_file="$4"
  local used_file="$5"
  local error_file="${6:-}"

  local review_dir
  review_dir=$(codex_review_exec_dir "$project_dir")
  codex_run_reviewer "$review_dir" "$schema_file" "$output_file" "$prompt_file" "$used_file" "$error_file"
}

handle_codex_cli_command() {
  local command_text="$1"
  local command_size=${#command_text}
  local context_hint=false
  local package_path=""
  local codex_exec_count=0

  if ! printf '%s' "$command_text" | grep -Eq 'codex[[:space:]]+exec'; then
    return 0
  fi

  if ! printf '%s' "$command_text" | grep -Eq -- '--profile(=|[[:space:]]+)(coder|fast)'; then
    return 0
  fi

  while IFS= read -r package_path; do
    [ -n "$package_path" ] || continue
    if codex_context_package_valid "$ROOT_DIR/$package_path"; then
      context_hint=true
    else
      block_with_message "Codex delegation blocked: context package '$package_path' is missing, stale, or invalid."
    fi
  done < <(printf '%s' "$command_text" | grep -oE '\.agents/tmp/context-package[^[:space:]]*\.md' || true)

  codex_exec_count=$(printf '%s' "$command_text" | grep -oE 'codex[[:space:]]+exec' | wc -l | tr -d '[:space:]')
  if [ "${codex_exec_count:-0}" -gt 1 ] && [ "$context_hint" = false ]; then
    block_with_message "Codex delegation blocked: parallel codex exec requires scoped context packages in .agents/tmp/. Generate them first with .agents/tools/codex-context-package.sh."
  fi

  # C6: Basic prompt injection guard
  if printf '%s' "$command_text" | grep -qiE '(ignore (previous|all|above) instructions|you are now|system prompt override|disregard.*instructions|new persona|forget everything)'; then
    block_with_message "Codex delegation blocked: prompt contains patterns resembling injection. Review the prompt content before delegating."
  fi

  if [ "$command_size" -gt 240 ] && [ "$context_hint" = false ]; then
    block_with_message "Codex delegation blocked: missing context package for a medium/large task. Generate .agents/tmp/context-package.md before calling codex exec --profile coder."
  fi
}

handle_commit_gate() {
  local command_text="$1"
  local staged_files
  local sensitive=false
  local review_kind="pre-commit"
  local diff_mode="index"
  local event_status="skipped"
  local event_json=""
  local hook_start_ts
  hook_start_ts=$(date +%s)
  local review_id
  local tmp_dir
  local prompt_file
  local schema_file
  local output_file
  local review_markdown
  local diff_payload
  local verdict
  local summary
  local score
  local issues_count
  local used_file
  local error_file
  local used_candidate="model:unknown"
  local model_name="unknown"
  local reviewer_path="unavailable"
  local preferred_candidate
  local preferred_path
  local preferred_model
  local fallback_occurred="true"

  if ! printf '%s' "$command_text" | grep -Eq '(^|[[:space:]])git[[:space:]]+commit([[:space:]]|$)'; then
    return 0
  fi

  # Deliberate override (mirrors CANUTO_ALLOW_PROTECTED / CANUTO_ALLOW_ENV_READ).
  if [ "${CANUTO_ALLOW_COMMIT:-}" = "1" ] || printf '%s' "$command_text" | grep -q 'CANUTO_ALLOW_COMMIT=1'; then
    printf '%s\n' "[codex-pretool-guard] commit review skipped (CANUTO_ALLOW_COMMIT=1)." >&2
    return 0
  fi

  cd "$ROOT_DIR"
  if printf '%s' "$command_text" | grep -Eq '(^|[[:space:]])(--all|-a)([[:space:]]|$)|(^|[[:space:]])-[A-Za-z]*a[A-Za-z]*([[:space:]]|$)'; then
    diff_mode="all-tracked"
    if git rev-parse --verify HEAD >/dev/null 2>&1; then
      if git diff HEAD --quiet --exit-code; then
        return 0
      fi
    elif git diff --cached --quiet --exit-code && git diff --quiet --exit-code; then
      return 0
    fi
  else
    if git diff --cached --quiet --exit-code; then
      return 0
    fi
  fi

  if [ ! -x "$DIFF_SCRIPT" ]; then
    return 0
  fi

  if ! command -v codex >/dev/null 2>&1; then
    return 0
  fi

  declare -a staged_array=()
  while IFS= read -r staged_path; do
    [ -n "$staged_path" ] || continue
    staged_array+=("$staged_path")
  done < <(
    if [ "$diff_mode" = "all-tracked" ] && git rev-parse --verify HEAD >/dev/null 2>&1; then
      git diff HEAD --name-only --diff-filter=ACMR 2>/dev/null
    else
      git diff --cached --name-only --diff-filter=ACMR 2>/dev/null
    fi | sed '/^$/d'
  )
  staged_files=$(printf '%s\n' "${staged_array[@]}")

  for path in "${staged_array[@]}"; do
    if codex_is_security_sensitive_path "$path"; then
      sensitive=true
      review_kind="pre-commit-security"
      break
    fi
  done

  # ── Threshold: skip or downgrade review by diff size ──────────────────
  local diff_line_count=0
  local _shortstat=""
  if [ "$diff_mode" = "all-tracked" ] && git rev-parse --verify HEAD >/dev/null 2>&1; then
    _shortstat=$(git diff HEAD --shortstat 2>/dev/null)
  else
    _shortstat=$(git diff --cached --shortstat 2>/dev/null)
  fi
  if [ -n "$_shortstat" ]; then
    diff_line_count=$(printf '%s' "$_shortstat" | grep -oE '[0-9]+ (insertion|deletion)' | awk '{s+=$1} END{print s+0}')
  fi

  local review_tier="full"
  if [ "$sensitive" = true ]; then
    review_tier="full"
  elif [ "$diff_line_count" -lt 20 ]; then
    return 0
  elif [ "$diff_line_count" -le 100 ]; then
    review_tier="fast"
  fi

  diff_payload=$(bash "$DIFF_SCRIPT" --commit-candidate "$diff_mode")
  tmp_dir=$(codex_tmp_dir "$ROOT_DIR")
  review_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  prompt_file="$tmp_dir/pre-commit-$review_id.prompt.txt"
  schema_file="$tmp_dir/pre-commit-$review_id.schema.json"
  output_file="$tmp_dir/pre-commit-$review_id.json"
  used_file="$tmp_dir/pre-commit-$review_id.used"
  error_file="$tmp_dir/pre-commit-$review_id.err"
  review_markdown=$(codex_review_markdown_path "$ROOT_DIR" "latest-pre-commit-review")
  preferred_candidate=$(codex_reviewer_preferred_candidate 2>/dev/null || true)
  preferred_path=$(codex_candidate_path_label "$preferred_candidate")
  preferred_model=$(codex_candidate_model_name "$preferred_candidate")

  cat > "$schema_file" <<'EOF'
{
  "type": "object",
  "additionalProperties": false,
  "required": ["schema_version", "verdict", "summary", "score", "issues"],
  "properties": {
    "schema_version": { "type": "string", "const": "1.0" },
    "verdict": { "type": "string", "enum": ["COMMIT", "HOLD"] },
    "summary": { "type": "string" },
    "score": { "type": "number" },
    "issues": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["severity", "file", "line", "issue", "fix"],
        "properties": {
          "severity": { "type": "string", "enum": ["high", "medium", "low"] },
          "file": { "type": "string" },
          "line": { "type": ["integer", "null"] },
          "issue": { "type": "string" },
          "fix": { "type": "string" }
        }
      }
    }
  }
}
EOF

  {
    echo "You are reviewing staged changes before git commit."
    echo "Return JSON only, matching the provided schema."
    echo "Use HOLD if you find bugs, security risks, missing edge cases, or convention regressions that should block the commit."
    echo "Do not run shell commands, open files, or inspect the workspace."
    echo "Review only the diff context below and treat it as the full source of truth for this review."
    echo "If context is insufficient, say so in an issue instead of using tools."
    if [ "$sensitive" = true ]; then
      echo "These files are security-sensitive. Treat auth, secrets, injection, access control, RLS, and race conditions as release-blocking."
    fi
    echo ""
    echo "Changed files:"
    printf '%s\n' "$staged_files"
    echo ""
    cat <<'EOF'
Focus on:
- correctness and regressions
- security and access control
- performance footguns
- missing test coverage for the happy path
- violations of existing project patterns
EOF
    echo ""
    printf '%s\n' "$diff_payload"
  } > "$prompt_file"

  local review_ok=false
  if [ "$review_tier" = "fast" ]; then
    # Tier fast: perfil `fast` com reasoning baixo (o modelo sai de models.yaml
    # via perfil — não citar versão aqui, vira defasagem silenciosa).
    #
    # O timeout NÃO é opcional. Este hook roda SÍNCRONO dentro do Codex: o
    # processo pai fica parado até o hook retornar, e aqui o hook sobe um SEGUNDO
    # `codex exec` completo (config, auth, startup de MCP). Sem limite, qualquer
    # travada do filho — MCP que não sobe, uvx buscando pacote na rede, auth
    # expirada esperando input — congela a UI inteira sem log e sem saída. Foi
    # exatamente esse o sintoma relatado ("codex todo travado, parece deadlock").
    # O caminho `full` já era limitado por codex_run_with_timeout desde sempre;
    # só o tier fast — o que deveria ser o mais barato — ficou sem rédea.
    # Limite menor que o do full de propósito: um review "rápido" que passa de
    # ~45s já falhou no que prometia; melhor degradar para advisory que travar.
    local fast_timeout="${CODEX_FAST_REVIEW_TIMEOUT:-45}"
    local fast_cmd=(codex exec -C "$ROOT_DIR" -s read-only --skip-git-repo-check --ephemeral --profile fast -c 'model_reasoning_effort="low"' --output-schema "$schema_file" -o "$output_file" -)
    if codex_run_with_timeout "$fast_timeout" "${fast_cmd[@]}" < "$prompt_file" >/dev/null 2>&1; then
      review_ok=true
      printf '%s\n' "profile:fast" > "$used_file"
    fi
  else
    if reviewer_cmd "$ROOT_DIR" "$schema_file" "$output_file" "$prompt_file" "$used_file" "$error_file" >/dev/null 2>&1; then
      review_ok=true
    fi
  fi

  if [ "$review_ok" = false ]; then
    {
      echo "# Codex Pre-Commit Review"
      echo ""
      echo "- review_id: $review_id"
      echo "- kind: $review_kind"
      echo "- preferred_reviewer_path: $preferred_path"
      echo "- preferred_model: $preferred_model"
      echo "- reviewer_path: unavailable"
      echo "- model: none"
      echo "- verdict: DEGRADED"
      echo "- fallback_occurred: true"
      echo ""
      echo "## Summary"
      echo "Reviewer path unavailable. Commit review ran in degraded advisory mode."
      if [ -s "$error_file" ]; then
        echo ""
        echo "## Reviewer Errors"
        sed 's/^/    /' "$error_file"
      fi
    } > "$review_markdown"
    event_json=$(jq -cn \
      --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg review_id "$review_id" \
      --arg review_kind "$review_kind" \
      --arg status "degraded" \
      --arg command "$command_text" \
      --arg error_file "$error_file" \
      --arg preferred_path "$preferred_path" \
      --arg preferred_model "$preferred_model" \
      --arg files "$staged_files" \
      '{timestamp:$timestamp,review_id:$review_id,review_type:$review_kind,status:$status,provider:"codex",preferred_reviewer_path:$preferred_path,preferred_model:$preferred_model,reviewer_path:"unavailable",model:"none",fallback_occurred:true,summary:"Reviewer path unavailable. Commit review ran in degraded advisory mode.",command:$command,error_file:$error_file,files:($files | split("\n") | map(select(length > 0)))}')
    codex_append_event "$ROOT_DIR" "$event_json"
    printf '%s\n' "Codex commit review degraded: reviewer path unavailable. See .agents/tmp/codex/latest-pre-commit-review.md for details." >&2
    return 0
  fi

  if [ ! -s "$output_file" ] || ! jq -e '
    (.verdict | type == "string")
    and (.summary | type == "string")
    and (.score | type == "number")
    and (.issues | type == "array")
  ' "$output_file" >/dev/null 2>&1; then
    used_candidate=$(cat "$used_file" 2>/dev/null || true)
    reviewer_path=$(codex_candidate_path_label "$used_candidate")
    model_name=$(codex_candidate_model_name "$used_candidate")
    event_json=$(jq -cn \
      --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg review_id "$review_id" \
      --arg review_kind "$review_kind" \
      --arg status "degraded" \
      --arg command "$command_text" \
      --arg error_file "$error_file" \
      --arg output_file "$output_file" \
      --arg preferred_path "$preferred_path" \
      --arg preferred_model "$preferred_model" \
      --arg reviewer_path "$reviewer_path" \
      --arg model "$model_name" \
      --arg files "$staged_files" \
      '{timestamp:$timestamp,review_id:$review_id,review_type:$review_kind,status:$status,provider:"codex",preferred_reviewer_path:$preferred_path,preferred_model:$preferred_model,reviewer_path:$reviewer_path,model:$model,fallback_occurred:true,summary:"Reviewer returned invalid output. Commit review ran in degraded advisory mode.",command:$command,error_file:$error_file,output_file:$output_file,files:($files | split("\n") | map(select(length > 0)))}')
    codex_append_event "$ROOT_DIR" "$event_json"
    {
      echo "# Codex Pre-Commit Review"
      echo ""
      echo "- review_id: $review_id"
      echo "- kind: $review_kind"
      echo "- preferred_reviewer_path: $preferred_path"
      echo "- preferred_model: $preferred_model"
      echo "- reviewer_path: $reviewer_path"
      echo "- model: $model_name"
      echo "- verdict: DEGRADED"
      echo "- fallback_occurred: true"
      echo ""
      echo "## Summary"
      echo "Reviewer returned invalid output. Commit review ran in degraded advisory mode."
      if [ -s "$error_file" ]; then
        echo ""
        echo "## Reviewer Errors"
        sed 's/^/    /' "$error_file"
      fi
    } > "$review_markdown"
    printf '%s\n' "Codex commit review degraded: reviewer returned invalid output. See .agents/tmp/codex/latest-pre-commit-review.md for details." >&2
    return 0
  fi

  if [ -f "$used_file" ]; then
    used_candidate=$(cat "$used_file" 2>/dev/null || echo "model:unknown")
    reviewer_path=$(codex_candidate_path_label "$used_candidate")
    model_name=$(codex_candidate_model_name "$used_candidate")
    fallback_occurred=$(codex_candidate_fallback_occurred "$used_candidate")
  fi

  verdict=$(jq -r '.verdict' "$output_file" 2>/dev/null || echo "COMMIT")
  summary=$(jq -r '.summary' "$output_file" 2>/dev/null || echo "Review completed.")
  score=$(jq -r '.score' "$output_file" 2>/dev/null || echo "0")
  issues_count=$(jq '.issues | length' "$output_file" 2>/dev/null || echo "0")
  event_status="$verdict"

  {
    echo "# Codex Pre-Commit Review"
    echo ""
    echo "- review_id: $review_id"
    echo "- kind: $review_kind"
    echo "- preferred_reviewer_path: $preferred_path"
    echo "- preferred_model: $preferred_model"
    echo "- reviewer_path: $reviewer_path"
    echo "- model: $model_name"
    echo "- fallback_occurred: $fallback_occurred"
    echo "- verdict: $verdict"
    echo "- score: $score"
    echo ""
    echo "## Summary"
    echo "$summary"
    echo ""
    echo "## Issues"
    jq -r '.issues[]? | "- [" + .severity + "] " + .file + ":" + ((.line // 0)|tostring) + " - " + .issue + " -> " + .fix' "$output_file"
  } > "$review_markdown"

  local hook_end_ts
  hook_end_ts=$(date +%s)
  local hook_duration_s=$((hook_end_ts - hook_start_ts))

  event_json=$(jq -cn \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg review_id "$review_id" \
    --arg review_kind "$review_kind" \
    --arg status "$event_status" \
    --arg command "$command_text" \
    --arg summary "$summary" \
    --arg preferred_path "$preferred_path" \
    --arg preferred_model "$preferred_model" \
    --arg reviewer_path "$reviewer_path" \
    --arg model "$model_name" \
    --argjson fallback_occurred "$fallback_occurred" \
    --argjson score "$score" \
    --argjson issues "$issues_count" \
    --argjson hook_duration_s "$hook_duration_s" \
    --arg review_tier "$review_tier" \
    --arg files "$staged_files" \
    '{timestamp:$timestamp,review_id:$review_id,review_type:$review_kind,status:$status,provider:"codex",preferred_reviewer_path:$preferred_path,preferred_model:$preferred_model,reviewer_path:$reviewer_path,model:$model,fallback_occurred:$fallback_occurred,score:$score,issues_count:$issues,hook_duration_s:$hook_duration_s,review_tier:$review_tier,summary:$summary,command:$command,files:($files | split("\n") | map(select(length > 0)))}')
  codex_append_event "$ROOT_DIR" "$event_json"

  # Loop-breaker: an agent retrying the same blocked commit burns tokens
  # (observed: 29 HOLD blocks in a single session). After 3 HOLDs in the same
  # session the gate degrades to advisory instead of blocking forever.
  local session_id hold_count_file prev_holds hold_count
  session_id=$(printf '%s' "$HOOK_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
  [ -n "$session_id" ] || session_id="nosession"
  hold_count_file="$tmp_dir/commit-hold-count-$session_id"
  prev_holds=$(cat "$hold_count_file" 2>/dev/null || printf '0')
  case "$prev_holds" in ''|*[!0-9]*) prev_holds=0 ;; esac

  if [ "$verdict" = "HOLD" ]; then
    hold_count=$((prev_holds + 1))
    printf '%s\n' "$hold_count" > "$hold_count_file" 2>/dev/null || true
    if [ "$hold_count" -ge 3 ]; then
      printf '%s\n' "Codex review HOLD #$hold_count nesta sessão — gate degradado para advisory; commit liberado. Corrija os issues em .agents/tmp/codex/latest-pre-commit-review.md ou divida o commit." >&2
      return 0
    fi
    block_with_message "Codex blocked git commit (HOLD $hold_count/3): $summary Fix the issues or split the commit — do NOT retry the same commit unchanged (after 3 HOLDs the gate turns advisory). See .agents/tmp/codex/latest-pre-commit-review.md for details."
  fi
  rm -f "$hold_count_file" 2>/dev/null || true
}

case "$TOOL_NAME" in
  Bash)
    command_text="$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_input.command // ""')"
    handle_codex_cli_command "$command_text"
    handle_commit_gate "$command_text"
    ;;
esac

exit 0
