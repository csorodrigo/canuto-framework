#!/usr/bin/env bash

set -euo pipefail

HOOK_INPUT=$(cat 2>/dev/null || echo "")
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
ROOT_DIR="$(cd "$PROJECT_DIR" && git rev-parse --show-toplevel 2>/dev/null || pwd)"

if ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

COMMON_LIB="$ROOT_DIR/.agents/tools/codex-common.sh"
DIFF_SCRIPT="$ROOT_DIR/.agents/tools/codex-diff-context.sh"

if [ ! -f "$COMMON_LIB" ]; then
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

handle_codex_spawn() {
  local prompt_blob=""
  local prompt_count=0
  local context_hint=false
  local package_path=""
  local package_count=0

  if [ "$TOOL_NAME" = "mcp__codex-coder__spawn_agent" ]; then
    prompt_blob=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_input.prompt // ""')
    prompt_count=${#prompt_blob}
  else
    prompt_blob=$(printf '%s' "$HOOK_INPUT" | jq -r '[.tool_input.agents[].prompt // ""] | join("\n\n")')
    prompt_count=${#prompt_blob}
  fi

  if [ "$TOOL_NAME" = "mcp__codex-coder__spawn_agent" ]; then
    package_path=$(printf '%s' "$prompt_blob" | grep -oE '\.agents/tmp/context-package[^[:space:]]*\.md' | head -1 || true)
    if [ -n "$package_path" ] && codex_context_package_valid "$ROOT_DIR/$package_path"; then
      context_hint=true
    fi
  else
    # Check each agent's prompt individually to avoid one agent's package covering others.
    local total_agent_count=0
    while IFS= read -r agent_prompt; do
      total_agent_count=$((total_agent_count + 1))
      local agent_pkg
      agent_pkg=$(printf '%s' "$agent_prompt" | grep -oE '\.agents/tmp/context-package[^[:space:]]*\.md' | head -1 || true)
      if [ -n "$agent_pkg" ]; then
        package_count=$((package_count + 1))
        if ! codex_context_package_valid "$ROOT_DIR/$agent_pkg"; then
          block_with_message "Codex delegation blocked: agent $total_agent_count context package '$agent_pkg' is missing, stale, or invalid."
        fi
      fi
    done < <(printf '%s' "$HOOK_INPUT" | jq -r '.tool_input.agents[].prompt // ""')
    if [ "$package_count" -gt 0 ]; then
      context_hint=true
    fi
    # Block if some but not all agents have context packages (mixed batch).
    if [ "$total_agent_count" -gt 0 ] && [ "$package_count" -gt 0 ] && [ "$package_count" -lt "$total_agent_count" ]; then
      block_with_message "Codex delegation blocked: only $package_count of $total_agent_count agents have scoped context packages. Every agent in a parallel spawn must reference its own context package."
    fi
  fi

  if [ "$TOOL_NAME" = "mcp__codex-coder__spawn_agents_parallel" ] && [ "$context_hint" = false ]; then
    block_with_message "Codex delegation blocked: parallel spawn requires scoped context packages in .agents/tmp/. Generate them first with .agents/tools/codex-context-package.sh."
  fi

  if [ "$prompt_count" -gt 240 ] && [ "$context_hint" = false ]; then
    block_with_message "Codex delegation blocked: missing context package for a medium/large task. Generate .agents/tmp/context-package.md before calling spawn_agent."
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

  if ! printf '%s' "$command_text" | grep -Eq '(^|[[:space:]])git[[:space:]]+commit([[:space:]]|$)'; then
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

  diff_payload=$(bash "$DIFF_SCRIPT" --commit-candidate "$diff_mode")
  tmp_dir=$(codex_tmp_dir "$ROOT_DIR")
  review_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  prompt_file="$tmp_dir/pre-commit-$review_id.prompt.txt"
  schema_file="$tmp_dir/pre-commit-$review_id.schema.json"
  output_file="$tmp_dir/pre-commit-$review_id.json"
  used_file="$tmp_dir/pre-commit-$review_id.used"
  error_file="$tmp_dir/pre-commit-$review_id.err"
  review_markdown=$(codex_review_markdown_path "$ROOT_DIR" "latest-pre-commit-review")

  cat > "$schema_file" <<'EOF'
{
  "type": "object",
  "additionalProperties": false,
  "required": ["verdict", "summary", "score", "issues"],
  "properties": {
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

  if ! reviewer_cmd "$ROOT_DIR" "$schema_file" "$output_file" "$prompt_file" "$used_file" "$error_file" >/dev/null 2>&1; then
    event_json=$(jq -cn \
      --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg review_id "$review_id" \
      --arg review_kind "$review_kind" \
      --arg status "degraded" \
      --arg command "$command_text" \
      --arg error_file "$error_file" \
      --arg files "$staged_files" \
      '{timestamp:$timestamp,review_id:$review_id,review_type:$review_kind,status:$status,provider:"codex",model:"reviewer",command:$command,error_file:$error_file,files:($files | split("\n") | map(select(length > 0)))}')
    codex_append_event "$ROOT_DIR" "$event_json"
    return 0
  fi

  if [ ! -s "$output_file" ] || ! jq -e '
    (.verdict | type == "string")
    and (.summary | type == "string")
    and (.score | type == "number")
    and (.issues | type == "array")
  ' "$output_file" >/dev/null 2>&1; then
    event_json=$(jq -cn \
      --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg review_id "$review_id" \
      --arg review_kind "$review_kind" \
      --arg status "degraded" \
      --arg command "$command_text" \
      --arg error_file "$error_file" \
      --arg output_file "$output_file" \
      --arg files "$staged_files" \
      '{timestamp:$timestamp,review_id:$review_id,review_type:$review_kind,status:$status,provider:"codex",model:"reviewer",command:$command,error_file:$error_file,output_file:$output_file,files:($files | split("\n") | map(select(length > 0)))}')
    codex_append_event "$ROOT_DIR" "$event_json"
    return 0
  fi

  if [ -f "$used_file" ]; then
    used_candidate=$(cat "$used_file" 2>/dev/null || echo "model:unknown")
    case "$used_candidate" in
      profile:*) model_name="${used_candidate#profile:}" ;;
      model:*) model_name="${used_candidate#model:}" ;;
    esac
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
    echo "- model: $model_name"
    echo "- verdict: $verdict"
    echo "- score: $score"
    echo ""
    echo "## Summary"
    echo "$summary"
    echo ""
    echo "## Issues"
    jq -r '.issues[]? | "- [" + .severity + "] " + .file + ":" + ((.line // 0)|tostring) + " - " + .issue + " -> " + .fix' "$output_file"
  } > "$review_markdown"

  event_json=$(jq -cn \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg review_id "$review_id" \
    --arg review_kind "$review_kind" \
    --arg status "$event_status" \
    --arg command "$command_text" \
    --arg summary "$summary" \
    --arg model "$model_name" \
    --argjson score "$score" \
    --argjson issues "$issues_count" \
    --arg files "$staged_files" \
    '{timestamp:$timestamp,review_id:$review_id,review_type:$review_kind,status:$status,provider:"codex",model:$model,score:$score,issues_count:$issues,summary:$summary,command:$command,files:($files | split("\n") | map(select(length > 0)))}')
  codex_append_event "$ROOT_DIR" "$event_json"

  if [ "$verdict" = "HOLD" ]; then
    block_with_message "Codex blocked git commit: $summary See .agents/tmp/codex/latest-pre-commit-review.md for details."
  fi
}

case "$TOOL_NAME" in
  mcp__codex-coder__spawn_agent|mcp__codex-coder__spawn_agents_parallel)
    handle_codex_spawn
    ;;
  Bash)
    handle_commit_gate "$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_input.command // ""')"
    ;;
esac

exit 0
