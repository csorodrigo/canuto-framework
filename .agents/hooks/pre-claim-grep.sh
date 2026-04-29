#!/usr/bin/env bash
# pre-claim-grep.sh
#
# What: detects when Claude is about to claim "X doesn't exist" / "isso é um
#       gap" / "vamos criar" without having grepped both .agents/skills/ AND
#       global-skills/ first. Warns if the claim tool input lacks evidence of
#       a prior search.
# Why:  Sessão 2026-04-18b: afirmei /co-plan --triple não existia, mas estava
#       em global-skills/co-plan/SKILL.md. Quase criei skill duplicada. I-027
#       capturou a regra; este hook torna garantia.
# When: PreToolUse — runs before any tool call. Checks if Claude is about to
#       use Edit/Write to create a NEW file that resembles a skill, OR if the
#       Bash command suggests creation work without prior search.
#
# Implementation philosophy:
#   - This is a soft hook (warns, does not block) because false positives are
#     costly to UX. The goal is to remind Claude to verify, not to police every
#     tool call.
#   - Specifically targets Write tool with paths matching known skill dirs.
#   - Looks at the conversation transcript (env: CLAUDE_TRANSCRIPT_PATH) for
#     recent grep/glob calls in the same dirs. If absent, warns.
#
# Override: CANUTO_SKIP_CLAIM_CHECK=1 bypasses for one tool call.

set -euo pipefail

if [ "${CANUTO_SKIP_CLAIM_CHECK:-0}" = "1" ]; then
  exit 0
fi

# Read tool input from stdin
input=$(cat)

# Parse tool name and target path
tool_name=$(printf '%s' "$input" | python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get("tool_name", ""))' 2>/dev/null || echo "")
file_path=$(printf '%s' "$input" | python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get("tool_input", {}).get("file_path", ""))' 2>/dev/null || echo "")

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

# Inspect transcript for recent Glob/Grep on skill dirs
transcript_path="${CLAUDE_TRANSCRIPT_PATH:-}"
if [ -n "$transcript_path" ] && [ -f "$transcript_path" ]; then
  # Look at the LAST 50 entries for Glob/Grep targeting skill dirs
  if tail -200 "$transcript_path" 2>/dev/null | grep -qE '"(Glob|Grep)"|global-skills|\.agents/skills|\.claude/skills'; then
    # Evidence of search exists; allow
    exit 0
  fi
fi

# No evidence of search → warn (non-blocking)
basename_target=$(basename "$(dirname "$file_path")")
slug=$(basename "$file_path" .md)

cat >&2 <<EOF
[pre-claim-grep] HEADS UP — about to create skill '$slug' at:
  $file_path

But no Glob/Grep in skill dirs was detected in recent transcript history.

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

# Soft warning: exit 0 (do not block). If you want strict mode, change to exit 2.
exit 0
