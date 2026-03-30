#!/usr/bin/env bash

set -euo pipefail

if ! command -v codex >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
  exit 0
fi

HOOK_INPUT=$(cat 2>/dev/null || echo "")
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
ROOT_DIR="$(cd "$PROJECT_DIR" && git rev-parse --show-toplevel 2>/dev/null || pwd)"
COMMON_LIB="$ROOT_DIR/.agents/tools/codex-common.sh"

if [ ! -f "$COMMON_LIB" ]; then
  exit 0
fi

# shellcheck source=/dev/null
source "$COMMON_LIB"

PLAN_FILE=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_response.plan_file_path // empty' 2>/dev/null || true)

if [ -z "$PLAN_FILE" ]; then
  PLAN_FILE=$(find "$ROOT_DIR" -maxdepth 2 \
    \( -name "PLAN.md" -o -name "plan.md" -o -name "PLAN.txt" \) \
    -not -path "*/node_modules/*" \
    2>/dev/null | head -1 || true)
fi

if [ -z "$PLAN_FILE" ]; then
  PLANS_DIR="$HOME/.claude/plans"
  if [ -d "$PLANS_DIR" ]; then
    PLAN_FILE=$(ls -t "$PLANS_DIR"/*.md 2>/dev/null | head -1 || true)
  fi
fi

if [ -z "$PLAN_FILE" ] || [ ! -f "$PLAN_FILE" ]; then
  exit 0
fi

PLAN_CONTENT=$(cat "$PLAN_FILE")
TMP_DIR=$(codex_tmp_dir "$ROOT_DIR")
REVIEW_ID="$(date -u +%Y%m%dT%H%M%SZ)-$$"
PROMPT_FILE="$TMP_DIR/plan-review-$REVIEW_ID.prompt.txt"
SCHEMA_FILE="$TMP_DIR/plan-review-$REVIEW_ID.schema.json"
OUTPUT_FILE="$TMP_DIR/plan-review-$REVIEW_ID.json"
USED_FILE="$TMP_DIR/plan-review-$REVIEW_ID.used"
MARKDOWN_FILE=$(codex_review_markdown_path "$ROOT_DIR" "latest-plan-review")

cat > "$SCHEMA_FILE" <<'EOF'
{
  "type": "object",
  "additionalProperties": false,
  "required": ["verdict", "summary", "score", "issues"],
  "properties": {
    "verdict": { "type": "string", "enum": ["LGTM", "CONCERNS"] },
    "summary": { "type": "string" },
    "score": { "type": "number" },
    "issues": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["severity", "issue", "fix"],
        "properties": {
          "severity": { "type": "string", "enum": ["high", "medium", "low"] },
          "issue": { "type": "string" },
          "fix": { "type": "string" }
        }
      }
    }
  }
}
EOF

{
  echo "You are reviewing an implementation plan before coding starts."
  echo "Return JSON only, matching the provided schema."
  echo "Use CONCERNS if you find hidden dependencies, missing test strategy, rollback gaps, unverified assumptions, or simpler alternatives."
  echo "Do not run shell commands, open files, or inspect the workspace."
  echo "Review only the plan content below and treat it as the full source of truth for this review."
  echo ""
  echo "Plan file: $PLAN_FILE"
  echo ""
  printf '%s\n' "$PLAN_CONTENT"
} > "$PROMPT_FILE"

REVIEW_DIR=$(codex_review_exec_dir "$ROOT_DIR")
if ! codex_run_reviewer "$REVIEW_DIR" "$SCHEMA_FILE" "$OUTPUT_FILE" "$PROMPT_FILE" "$USED_FILE"; then
  exit 0
fi

if [ ! -s "$OUTPUT_FILE" ] || ! jq -e '
  (.verdict | type == "string")
  and (.summary | type == "string")
  and (.score | type == "number")
  and (.issues | type == "array")
' "$OUTPUT_FILE" >/dev/null 2>&1; then
  exit 0
fi

VERDICT=$(jq -r '.verdict' "$OUTPUT_FILE" 2>/dev/null || echo "LGTM")
SUMMARY=$(jq -r '.summary' "$OUTPUT_FILE" 2>/dev/null || echo "Plan review completed.")
SCORE=$(jq -r '.score' "$OUTPUT_FILE" 2>/dev/null || echo "0")
ISSUES_COUNT=$(jq '.issues | length' "$OUTPUT_FILE" 2>/dev/null || echo "0")
USED_CANDIDATE=$(cat "$USED_FILE" 2>/dev/null || echo "model:unknown")
MODEL_NAME="${USED_CANDIDATE#*:}"

{
  echo "# Codex Plan Review"
  echo ""
  echo "- review_id: $REVIEW_ID"
  echo "- plan_file: $PLAN_FILE"
  echo "- model: $MODEL_NAME"
  echo "- verdict: $VERDICT"
  echo "- score: $SCORE"
  echo ""
  echo "## Summary"
  echo "$SUMMARY"
  echo ""
  echo "## Issues"
  jq -r '.issues[]? | "- [" + .severity + "] " + .issue + " -> " + .fix' "$OUTPUT_FILE"
} > "$MARKDOWN_FILE"

EVENT_JSON=$(jq -cn \
  --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg review_id "$REVIEW_ID" \
  --arg plan_file "$PLAN_FILE" \
  --arg verdict "$VERDICT" \
  --arg summary "$SUMMARY" \
  --arg model "$MODEL_NAME" \
  --argjson score "$SCORE" \
  --argjson issues "$ISSUES_COUNT" \
  '{timestamp:$timestamp,review_id:$review_id,review_type:"plan-review",status:$verdict,provider:"codex",model:$model,plan_file:$plan_file,score:$score,issues_count:$issues,summary:$summary}')
codex_append_event "$ROOT_DIR" "$EVENT_JSON"

echo ""
echo "════════════════════════════════"
echo "  Codex Plan Review"
echo "════════════════════════════════"
echo "$VERDICT ($SCORE/10) — $SUMMARY"
if [ "$ISSUES_COUNT" -gt 0 ]; then
  jq -r '.issues[] | "- [" + .severity + "] " + .issue + " -> " + .fix' "$OUTPUT_FILE"
fi
echo "Report saved to .agents/tmp/codex/latest-plan-review.md"
echo "════════════════════════════════"
echo ""
