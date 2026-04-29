#!/usr/bin/env bash
# pre-claim-grep.sh
#
# What: warns when about to create a NEW skill file in skill paths without
#       evidence of recent Glob/Grep in skill directories. Soft warn (does
#       not block) — goal is to remind, not police.
# Why:  Sessão 2026-04-18b: afirmei /co-plan --triple não existia, mas estava
#       em global-skills/co-plan/SKILL.md. Quase criei skill duplicada. I-027
#       capturou a regra; este hook torna garantia.
# When: PreToolUse matcher Write — runs before Write tool calls. Checks if the
#       target path is in a skill dir AND if the file does not exist yet.
#
# Implementation:
#   - Read tool name and target file_path from JSON stdin (Claude Code contract)
#   - Read transcript_path from same JSON (NOT env var — env contract differs)
#   - If creating skill in skill dir AND no Glob/Grep evidence in last ~200 lines
#     of transcript matching skill paths, emit a warning to stderr.
#   - Exit 0 always (soft warning).
#
# Override: CANUTO_SKIP_CLAIM_CHECK=1 bypasses for one tool call.

set -uo pipefail

if [ "${CANUTO_SKIP_CLAIM_CHECK:-0}" = "1" ]; then
  exit 0
fi

INPUT=$(cat)

tool_name=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null) || tool_name=""
file_path=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null) || file_path=""
transcript_path=$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null) || transcript_path=""

# Only check Write tool creating a NEW file in skill dirs
[ "$tool_name" = "Write" ] || exit 0
[ -n "$file_path" ] || exit 0

# Match skill paths
case "$file_path" in
  */global-skills/*|*/.agents/skills/*|*/.claude/skills/*)
    : # is a skill path, continue
    ;;
  *)
    exit 0  # not a skill, no check needed
    ;;
esac

# Skip if file already exists (Edit-like, not creation)
[ -f "$file_path" ] && exit 0

# Inspect transcript for recent Glob/Grep calls in skill dirs.
# Need both: tool used (Glob|Grep) AND a skill dir as target/pattern in same recent window.
if [ -n "$transcript_path" ] && [ -r "$transcript_path" ]; then
  # Tail more aggressively (500 lines) — long sessions need wider window.
  recent=$(tail -500 "$transcript_path" 2>/dev/null)
  # Require BOTH a tool_name of Glob/Grep AND a skill-dir reference in recent activity
  if echo "$recent" | grep -q '"tool_name":[[:space:]]*"\(Glob\|Grep\)"' && \
     echo "$recent" | grep -qE '(global-skills|\.agents/skills|\.claude/skills)'; then
    exit 0  # evidence found, allow
  fi
fi

# No evidence → warn (non-blocking)
slug=$(basename "$file_path" .md)

cat >&2 <<EOF
[pre-claim-grep] HEADS UP — about to create skill '$slug' at:
  $file_path

But no recent Glob/Grep targeting skill dirs was detected in transcript.

Risk (ref I-027 — sessão 2026-04-18b): claimed /co-plan --triple was a gap,
proposed to create from scratch. It already existed in global-skills/co-plan/SKILL.md.
The skill could have been duplicated.

Recommended check before proceeding (run if not done):
  ls .agents/skills/ | grep -i "$slug"
  ls global-skills/ 2>/dev/null | grep -i "$slug"
  git log --all --oneline --grep="$slug"

Override after verification:
  CANUTO_SKIP_CLAIM_CHECK=1 <retry tool>
EOF

# Soft warning: exit 0 (do not block).
exit 0
