#!/usr/bin/env bash
# worktree-collision-check.sh
#
# What: warns if multiple Claude Code processes are likely operating on the
#       same git worktree (Conductor pattern shares .git across worktrees).
# Why:  Sessão 2026-04-18 perdeu ~20 Edits silenciosamente porque outra sessão
#       Claude (PID 4fa79590) commitou + branch-switched no mesmo worktree.
#       I-023 capturou o pattern. Este hook detecta e avisa antes de começar.
# When: SessionStart hook (matcher empty).
#
# Detection logic:
#   1. Count `claude` processes via ps
#   2. Read this session's PID (env CLAUDE_SESSION_ID se disponível)
#   3. If >1 process → check if any are in the same git worktree path
#   4. If colision → emit warning to stderr with PIDs to investigate
#
# Conservative: warns only, does not block. Worktree collisions are rare but
# expensive (silent edit reverts), so warning before work starts is high-value.

set -euo pipefail

project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Resolve git common dir (shared .git in worktrees)
git_common=$(git -C "$project_dir" rev-parse --git-common-dir 2>/dev/null || echo "")
[ -n "$git_common" ] || exit 0

# Resolve git common dir to absolute path
git_common_abs=$(cd "$(dirname "$git_common")" 2>/dev/null && pwd)/$(basename "$git_common")

# Count claude processes
claude_pids=$(pgrep -f 'claude(\b|$)' 2>/dev/null | sort -u || true)
claude_count=$(echo "$claude_pids" | grep -c . || true)

# If only one or zero, no collision possible
if [ "$claude_count" -le 1 ]; then
  exit 0
fi

# Find which of those processes have CWD inside a worktree sharing this .git
my_pid="${CLAUDE_PID:-$$}"
collisions=()

for pid in $claude_pids; do
  [ "$pid" = "$my_pid" ] && continue
  # Get cwd of process (macOS: lsof, Linux: /proc/PID/cwd)
  cwd=""
  if [[ "$(uname)" == "Darwin" ]]; then
    cwd=$(lsof -p "$pid" 2>/dev/null | awk '$4=="cwd"{print $9}' | head -1)
  elif [ -L "/proc/$pid/cwd" ]; then
    cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null || true)
  fi
  [ -n "$cwd" ] || continue

  # Check if cwd's git-common-dir matches ours
  other_common=$(git -C "$cwd" rev-parse --git-common-dir 2>/dev/null || echo "")
  [ -n "$other_common" ] || continue
  other_common_abs=$(cd "$(dirname "$other_common")" 2>/dev/null && pwd)/$(basename "$other_common")

  if [ "$other_common_abs" = "$git_common_abs" ]; then
    collisions+=("$pid:$cwd")
  fi
done

if [ "${#collisions[@]}" -eq 0 ]; then
  exit 0
fi

# Warn (non-blocking)
cat >&2 <<EOF
[worktree-collision-check] WARNING — another Claude session is operating on the same git repo.

Detected $((${#collisions[@]})) other Claude process(es) sharing this .git:
EOF

for entry in "${collisions[@]}"; do
  pid="${entry%%:*}"
  cwd="${entry#*:}"
  printf '  PID %s @ %s\n' "$pid" "$cwd" >&2
done

cat >&2 <<EOF

Risk (ref I-023 — sessão 2026-04-18): if the other session does git checkout /
commit / branch-switch, this worktree's working tree may silently revert mid-Edit.

Mitigations:
  - Confirm the other session is yours (intentional parallel work)
  - If unintentional: close one before continuing
  - Sinal de diagnóstico durante a sessão: Edit "sucede" mas \`git diff\` imediato
    mostra zero alterações + system-reminder "modified by user/linter"
EOF

exit 0  # warning only, do not block
