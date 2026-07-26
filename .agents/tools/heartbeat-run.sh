#!/usr/bin/env bash
# heartbeat-run.sh — Heartbeat v1: ativação autônoma single-shot com post-gate.
#
# Absorvido do edge-of-chaos (ADR-0003 de lá): o loop autônomo mínimo é
# pequeno — cron/launchd → uma invocação single-shot do CLI → post-gate
# mecânico ("exit 0 não prova nada; o artefato prova") → evento no log.
# SEM envelope, SEM retry, SEM estado próprio: falhou, fica registrado e o
# próximo tick tenta de novo.
#
# Tasks são arquivos markdown em .agents/heartbeats/<name>.md:
#   ---
#   timeout: 600                # segundos (default 600)
#   cli: claude                 # claude | codex (default claude)
#   permission_mode: acceptEdits # p/ claude -p (default acceptEdits)
#   expect_output: .agents/vault/digests/heartbeat-<name>.md
#   ---
#   <prompt em texto livre>
#
# Uso:
#   bash .agents/tools/heartbeat-run.sh <task-name>        # roda agora
#   bash .agents/tools/heartbeat-run.sh --list             # lista tasks
#   bash .agents/tools/heartbeat-run.sh --dry-run <task>   # mostra sem rodar
#   bash .agents/tools/heartbeat-run.sh --install-cron "0 9 * * 1" <task>
#   bash .agents/tools/heartbeat-run.sh --install-launchd 604800 <task>  # macOS
#   bash .agents/tools/heartbeat-run.sh --uninstall <task>
#
# Instalar agendamento é SEMPRE opt-in explícito (gate de governança:
# nunca instalado automaticamente pelo install.sh).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
HEARTBEATS_DIR="$PROJECT_DIR/.agents/heartbeats"
LOG_DIR="$PROJECT_DIR/.agents/.cache"

if [ -f "$SCRIPT_DIR/event-log.sh" ]; then
  # shellcheck source=event-log.sh
  . "$SCRIPT_DIR/event-log.sh"
else
  canuto_event_append() { return 0; }
fi

usage() { sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

frontmatter_get() {
  # frontmatter_get <file> <key> — valor de `key: value` entre os --- iniciais
  awk -v key="$2" '
    NR==1 && $0=="---" { inside=1; next }
    inside && $0=="---" { exit }
    inside && $0 ~ "^"key":" { sub("^"key":[[:space:]]*",""); print; exit }
  ' "$1"
}

prompt_body() {
  # tudo depois do segundo ---; sem frontmatter, o arquivo inteiro
  awk 'NR==1 && $0=="---" { skip=1; next }
       skip && $0=="---" { skip=0; body=1; next }
       skip { next }
       { print }' "$1"
}

run_task() {
  local task="$1" dry="${2:-false}"
  local task_file="$HEARTBEATS_DIR/$task.md"
  if [ ! -f "$task_file" ]; then
    echo "heartbeat: task '$task' não existe em $HEARTBEATS_DIR/" >&2
    canuto_event_append HEARTBEAT actor=heartbeat task="$task" verdict=no-task || true
    return 1
  fi

  local timeout_s cli perm expect prompt started_at rc verdict reason
  timeout_s=$(frontmatter_get "$task_file" timeout); timeout_s="${timeout_s:-600}"
  cli=$(frontmatter_get "$task_file" cli); cli="${cli:-claude}"
  perm=$(frontmatter_get "$task_file" permission_mode); perm="${perm:-acceptEdits}"
  expect=$(frontmatter_get "$task_file" expect_output)
  prompt=$(prompt_body "$task_file")

  if [ "$dry" = true ]; then
    echo "task: $task"
    echo "cli: $cli | timeout: ${timeout_s}s | permission_mode: $perm"
    echo "expect_output: ${expect:-"(nenhum — só rc)"}"
    echo "--- prompt ---"
    printf '%s\n' "$prompt"
    return 0
  fi

  mkdir -p "$LOG_DIR"
  started_at=$(date +%s)
  local run_log="$LOG_DIR/heartbeat-$task.log"
  {
    echo "═══ heartbeat $task @ $(date -u +%Y-%m-%dT%H:%M:%SZ) ═══"
  } >> "$run_log"

  # Single-shot, foreground, sem retry (lei do turno headless: nada em background)
  case "$cli" in
    codex)
      local out_file="$LOG_DIR/heartbeat-$task-last.md"
      ( cd "$PROJECT_DIR" && timeout "$timeout_s" codex exec --color never \
          --skip-git-repo-check --output-last-message "$out_file" \
          "$prompt" < /dev/null ) >> "$run_log" 2>&1
      rc=$?
      ;;
    claude|*)
      ( cd "$PROJECT_DIR" && printf '%s' "$prompt" | timeout "$timeout_s" \
          claude -p --permission-mode "$perm" ) >> "$run_log" 2>&1
      rc=$?
      ;;
  esac

  # ── Post-gate mecânico: exit 0 não prova nada — o artefato prova ─────────
  verdict=ok; reason=""
  if [ "$rc" = "124" ]; then
    verdict=timeout; reason="timeout ${timeout_s}s"
  elif [ "$rc" != "0" ]; then
    verdict=error; reason="rc=$rc"
  elif [ -n "$expect" ]; then
    local expect_path="$PROJECT_DIR/$expect"
    [ "${expect:0:1}" = "/" ] && expect_path="$expect"
    if [ ! -f "$expect_path" ]; then
      verdict=missing-output; reason="esperado e ausente: $expect"
    elif [ ! -s "$expect_path" ]; then
      verdict=empty-output; reason="esperado e vazio: $expect"
    else
      local mtime
      mtime=$(stat -c %Y "$expect_path" 2>/dev/null || stat -f %m "$expect_path" 2>/dev/null || echo 0)
      if [ "$mtime" -lt "$started_at" ]; then
        verdict=stale-output; reason="$expect não foi tocado nesta execução"
      fi
    fi
  fi

  canuto_event_append HEARTBEAT actor=heartbeat task="$task" cli="$cli" \
    rc="$rc" verdict="$verdict" reason="$reason" || true
  {
    echo "── post-gate: verdict=$verdict rc=$rc ${reason:+($reason)}"
  } >> "$run_log"

  if [ "$verdict" = "ok" ]; then
    echo "heartbeat $task: ok"
    return 0
  else
    echo "heartbeat $task: $verdict ${reason:+— $reason} (log: $run_log)" >&2
    return 1
  fi
}

cron_marker() { printf '# canuto-heartbeat:%s:%s' "$1" "$PROJECT_DIR"; }

install_cron() {
  local schedule="$1" task="$2"
  command -v crontab >/dev/null 2>&1 || { echo "crontab indisponível (use --install-launchd no macOS)" >&2; return 1; }
  local marker line current
  marker=$(cron_marker "$task")
  line="$schedule cd $PROJECT_DIR && bash .agents/tools/heartbeat-run.sh $task >> .agents/.cache/heartbeat-cron.log 2>&1 $marker"
  current=$(crontab -l 2>/dev/null || true)
  if printf '%s' "$current" | grep -qF "$marker"; then
    current=$(printf '%s\n' "$current" | grep -vF "$marker")
  fi
  printf '%s\n%s\n' "$current" "$line" | sed '/^$/d' | crontab -
  canuto_event_append HEARTBEAT actor=heartbeat task="$task" verdict=installed schedule="$schedule" via=cron || true
  echo "cron instalado: [$schedule] $task (remova com --uninstall $task)"
}

install_launchd() {
  local interval="$1" task="$2"
  local label="com.canuto.heartbeat.$task"
  local plist="$HOME/Library/LaunchAgents/$label.plist"
  [ -d "$HOME/Library/LaunchAgents" ] || { echo "launchd indisponível (use --install-cron no Linux)" >&2; return 1; }
  cat > "$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$label</string>
  <key>ProgramArguments</key><array>
    <string>/bin/bash</string>
    <string>$PROJECT_DIR/.agents/tools/heartbeat-run.sh</string>
    <string>$task</string>
  </array>
  <key>WorkingDirectory</key><string>$PROJECT_DIR</string>
  <key>StartInterval</key><integer>$interval</integer>
  <key>StandardOutPath</key><string>$PROJECT_DIR/.agents/.cache/heartbeat-cron.log</string>
  <key>StandardErrorPath</key><string>$PROJECT_DIR/.agents/.cache/heartbeat-cron.log</string>
</dict></plist>
PLIST
  launchctl unload "$plist" 2>/dev/null || true
  launchctl load "$plist"
  canuto_event_append HEARTBEAT actor=heartbeat task="$task" verdict=installed interval="$interval" via=launchd || true
  echo "launchd instalado: $label a cada ${interval}s (remova com --uninstall $task)"
}

uninstall_task() {
  local task="$1" marker
  marker=$(cron_marker "$task")
  if command -v crontab >/dev/null 2>&1; then
    (crontab -l 2>/dev/null | grep -vF "$marker" | crontab -) 2>/dev/null || true
  fi
  local plist="$HOME/Library/LaunchAgents/com.canuto.heartbeat.$task.plist"
  if [ -f "$plist" ]; then
    launchctl unload "$plist" 2>/dev/null || true
    rm -f "$plist"
  fi
  canuto_event_append HEARTBEAT actor=heartbeat task="$task" verdict=uninstalled || true
  echo "agendamentos de '$task' removidos (cron + launchd)"
}

case "${1:-}" in
  --list)
    if [ -d "$HEARTBEATS_DIR" ]; then
      find "$HEARTBEATS_DIR" -name '*.md' -exec basename {} .md \;
    else
      echo "(nenhuma task — crie .agents/heartbeats/<name>.md)"
    fi
    ;;
  --dry-run)
    [ -n "${2:-}" ] || { usage; exit 1; }
    run_task "$2" true
    ;;
  --install-cron)
    [ -n "${2:-}" ] && [ -n "${3:-}" ] || { usage; exit 1; }
    install_cron "$2" "$3"
    ;;
  --install-launchd)
    [ -n "${2:-}" ] && [ -n "${3:-}" ] || { usage; exit 1; }
    install_launchd "$2" "$3"
    ;;
  --uninstall)
    [ -n "${2:-}" ] || { usage; exit 1; }
    uninstall_task "$2"
    ;;
  ""|--help|-h)
    usage
    ;;
  *)
    run_task "$1" false
    ;;
esac
