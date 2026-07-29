#!/usr/bin/env bash
# pre-commit-branch-check.sh
#
# What: blocks `git checkout -b <new>` (and equivalent forms) from a polluted
#       branch (commits ahead of main not related to the new work).
# Why:  PR #35 (sessão 2026-04-18) ficou DIRTY com 32 commits gemini misturados
#       porque criei branch da feat atual em vez de origin/main. Custo: PR teve
#       que ser fechado e recriado limpo. I-026 capturou a regra em prompt;
#       este hook a transforma em garantia.
# When: PreToolUse matcher Bash, com input contendo branch-creation pattern.
#
# Invocation forms covered (all of these match):
#   git checkout -b NEW
#   git switch -c NEW
#   git -C /path checkout -b NEW
#   git -c key=val checkout -b NEW
#   rtk git checkout -b NEW          (rtk passthrough)
#   sudo git checkout -b NEW         (just in case)
#
# Decision logic:
#   1. Detect: command contains a branch-creation flag (-b for checkout, -c for switch)
#   2. Skip: if user already specified an explicit base (origin/main, main, etc)
#   3. Skip: if current branch is main/master/develop (no risk)
#   4. Read commits ahead of origin/main
#   5. If 0-3 commits → allow (likely related)
#   6. If 4+ commits → block + suggest `git checkout -b NEW origin/main`
#
# Override: set CANUTO_SKIP_BRANCH_CHECK=1 to bypass for one command.
# Environment: receives JSON on stdin (Claude Code hook contract).

set -uo pipefail

# Bypass switch
if [ "${CANUTO_SKIP_BRANCH_CHECK:-0}" = "1" ]; then
  exit 0
fi

# Read tool input from stdin (Claude Code hook contract)
# Sem payload num TTY: `cat` sem stdin fechado bloqueia para sempre e o
# runtime que espera o hook congela junto (regra de TTY/pipe do CLAUDE.md).
input=""
[ -t 0 ] || input=$(cat)
command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || command=""
[ -n "$command" ] || exit 0

# Detect branch-creation pattern. Robust to optional flags (-C, -c, -P) and
# wrapper prefixes (rtk, sudo). Match anywhere in the command line.
# Patterns:
#   `... git ... checkout ... -b ...` OR
#   `... git ... switch ... -c ...`
if ! echo "$command" | grep -qE '\bgit\b([[:space:]]+(-[CcP][[:space:]]*[^[:space:]]+|--[a-zA-Z0-9_-]+(=[^[:space:]]+)?))*[[:space:]]+(checkout[[:space:]]+(-[a-zA-Z]*b|--branch)|switch[[:space:]]+(-[a-zA-Z]*c|--create))[[:space:]]+[^[:space:]]+'; then
  exit 0
fi

# Skip if user already specified an explicit base (whitespace-bounded match)
if echo "$command" | grep -qE '(\s|/)(origin/main|origin/master|origin/develop)(\s|$)'; then
  exit 0
fi
# Also skip if `main` appears as standalone word right before/after the new branch name
# (heuristic: explicit base passed as positional arg)
if echo "$command" | grep -qE '[[:space:]](main|master|develop)([[:space:]]|$)'; then
  exit 0
fi

# Get current branch
project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
current_branch=$(git -C "$project_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
[ -n "$current_branch" ] || exit 0

# If already on main/master/develop, no risk
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
