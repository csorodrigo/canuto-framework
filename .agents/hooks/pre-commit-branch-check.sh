#!/usr/bin/env bash
# pre-commit-branch-check.sh
#
# What: blocks `git checkout -b <new>` from a polluted branch (commits ahead of
#       main not related to the new work).
# Why:  PR #35 (sessão 2026-04-18) ficou DIRTY com 32 commits gemini misturados
#       porque criei branch da feat atual em vez de origin/main. Custo: PR teve
#       que ser fechado e recriado limpo. I-026 capturou a regra em prompt;
#       este hook a transforma em garantia.
# When: PreToolUse matcher Bash, com input contendo "git checkout -b" ou
#       "git switch -c".
#
# Decision logic:
#   1. Detect: command starts with `git checkout -b NEW` or `git switch -c NEW`
#   2. Read current branch + commits ahead of origin/main
#   3. If 0 commits ahead → allow (clean)
#   4. If 1-3 commits → warn but allow (likely related work)
#   5. If 4+ commits → block + suggest `git checkout -b NEW origin/main`
#
# Override: set CANUTO_SKIP_BRANCH_CHECK=1 to bypass for one command.
# Environment: receives JSON on stdin (Claude Code hook contract).

set -euo pipefail

# Bypass switch
if [ "${CANUTO_SKIP_BRANCH_CHECK:-0}" = "1" ]; then
  exit 0
fi

# Read tool input from stdin (Claude Code hook contract)
input=$(cat)
command=$(printf '%s' "$input" | python3 -c 'import json,sys; data=json.load(sys.stdin); print(data.get("tool_input", {}).get("command", ""))' 2>/dev/null || echo "")

# Quick exit if no command or not a branch-creation pattern
[ -n "$command" ] || exit 0

# Match `git checkout -b NAME` or `git switch -c NAME` (allow optional flags before/after NAME)
if ! echo "$command" | grep -qE '^[[:space:]]*git[[:space:]]+(checkout[[:space:]]+-b|switch[[:space:]]+-c)[[:space:]]+[^[:space:]]+'; then
  exit 0
fi

# Skip if user already specified an explicit base (origin/main, main, etc) — that's the safe pattern
if echo "$command" | grep -qE '(origin/main|origin/master|origin/develop|main$| main )'; then
  exit 0
fi

# Get current branch
project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
current_branch=$(git -C "$project_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
[ -n "$current_branch" ] || exit 0

# If already on main/master, no risk
case "$current_branch" in
  main|master|develop) exit 0 ;;
esac

# Count commits ahead of origin/main
ahead=$(git -C "$project_dir" rev-list --count "origin/main..HEAD" 2>/dev/null || echo "0")

if [ "$ahead" -lt 4 ]; then
  exit 0
fi

# Block + advise
cat >&2 <<EOF
[pre-commit-branch-check] BLOCKED — current branch '$current_branch' has $ahead commits ahead of origin/main.

Risk: creating a new branch from here will inherit those commits. If they
are unrelated to the new task, the resulting PR will be DIRTY (ref I-026 —
sessão 2026-04-18, PR #35 fechado por exatamente esse motivo).

Recommended:
  git stash push -u -m "WIP $current_branch"
  git checkout -b <new-branch> origin/main
  # do work, commit, push
  git checkout $current_branch && git stash pop

Override (only if the commits ARE related to the new work):
  CANUTO_SKIP_BRANCH_CHECK=1 $command
EOF
exit 2
