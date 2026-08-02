#!/usr/bin/env bash
# event-log.sh — Append-only per-project event log (JSONL).
#
# Absorvido do edge-of-chaos (ADR-0001 do canuto): o log de eventos é escrito
# MECANICAMENTE pelos hooks — nunca depende do agente escolher registrar.
# Notas do vault (audit/, sessions/, metrics/) tornam-se PROJEÇÕES: derivadas
# do log, nunca a fonte de verdade dos eventos de sessão.
#
# Invariantes:
#   - Append-only: nada aqui edita ou remove linhas. Uma linha = um evento JSON.
#   - Nunca quebra o chamador: toda falha degrada em silêncio (exit 0).
#   - Fallback: sem vault resolvível, escreve em .agents/.cache/events/log.jsonl
#     (mesma filosofia do pending-sync; /vault-sync pode migrar depois).
#   - Concorrência SAME-HOST (multi-worktree): o append é protegido por lock de
#     diretório via mkdir — atômico em POSIX; flock NÃO existe no macOS, então
#     o branch antigo com flock era no-op exatamente onde o problema acontece.
#     Retry curto (~5×0.05s) e fail-open: se o lock não vier, o append acontece
#     mesmo assim — perder evento é pior que um interleaving raro. Lock órfão
#     (processo morto entre mkdir e rmdir, idade >10s) é quebrado.
#   - Conflitos ENTRE MÁQUINAS (Syncthing e afins) NÃO são resolvidos por lock
#     local: são conflitos de sync de arquivo, invisíveis a este processo.
#     Como o log é JSONL append-only, resolver um sync-conflict = concatenar as
#     duas versões e ordenar por ts (nenhuma linha é editada, só anexada).
#
# Uso como biblioteca (hooks):
#   source .agents/tools/event-log.sh
#   canuto_event_append SESSION_START actor=hook detail="briefing ok"
#
# Uso como CLI:
#   bash event-log.sh append <EVENT> [key=value ...]
#   bash event-log.sh path            # imprime o caminho resolvido do log
#   bash event-log.sh tail [N]        # últimos N eventos (default 10)
#
# Schema por linha (todos os valores são strings):
#   ts       ISO8601 UTC
#   event    SESSION_START|SESSION_END|PRE_COMPACT|TOOL_CALL|HANDOFF|GATE|
#            DELEGATION|REWORK|HEARTBEAT|INSTINCT|... (aberto; ver skill event-log)
#   project  slug do projeto
#   session  CLAUDE_SESSION_ID quando disponível
#   + pares key=value passados pelo chamador

_CANUTO_EVENT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v canuto_project_dir >/dev/null 2>&1; then
  # canuto-memory.sh liga `set -euo pipefail`; um source não pode mudar as
  # opções do hook chamador — captura e restaura.
  _canuto_prev_opts="$-"
  if [ -f "$_CANUTO_EVENT_LIB_DIR/canuto-memory.sh" ]; then
    # shellcheck source=canuto-memory.sh
    source "$_CANUTO_EVENT_LIB_DIR/canuto-memory.sh"
  elif [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "$CLAUDE_PROJECT_DIR/.agents/tools/canuto-memory.sh" ]; then
    # shellcheck source=/dev/null
    source "$CLAUDE_PROJECT_DIR/.agents/tools/canuto-memory.sh"
  fi
  case "$_canuto_prev_opts" in *e*) : ;; *) set +e ;; esac
  case "$_canuto_prev_opts" in *u*) : ;; *) set +u ;; esac
  unset _canuto_prev_opts
fi

# Resolve o caminho do log. Nunca imprime vazio: sempre há um destino.
canuto_event_log_path() {
  local project_dir="${1:-${CLAUDE_PROJECT_DIR:-$(pwd)}}"
  local backend_kind="" backend_dir=""

  if command -v canuto_resolve_memory_backend >/dev/null 2>&1; then
    project_dir=$(canuto_project_dir "$project_dir")
    IFS=$'\t' read -r backend_kind backend_dir < <(canuto_resolve_memory_backend "$project_dir") || true
  fi

  case "$backend_kind" in
    global|local)
      printf '%s/events/log.jsonl\n' "$backend_dir"
      ;;
    *)
      printf '%s/.agents/.cache/events/log.jsonl\n' "$project_dir"
      ;;
  esac
}

_canuto_json_escape() {
  # Escapa uma string para uso como valor JSON (sem jq): \ " e controles.
  printf '%s' "$1" | tr -d '\000-\010\013\014\016-\037' \
    | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e ':a;N;$!ba;s/\n/\\n/g' 2>/dev/null \
    || printf '%s' "$1" | tr -d '\000-\037"\\'
}

# canuto_event_append <EVENT> [key=value ...]
# Sempre retorna 0 — hooks nunca podem morrer por causa de telemetria.
canuto_event_append() {
  local event="${1:-UNKNOWN}"; shift 2>/dev/null || true
  local project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
  local log_path slug ts session line kv key value

  log_path=$(canuto_event_log_path "$project_dir") || return 0
  mkdir -p "$(dirname "$log_path")" 2>/dev/null || return 0

  if command -v canuto_project_slug >/dev/null 2>&1; then
    slug=$(canuto_project_slug 2>/dev/null || basename "$project_dir")
  else
    slug=$(basename "$project_dir")
  fi
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)
  session="${CLAUDE_SESSION_ID:-}"

  if command -v jq >/dev/null 2>&1; then
    # UMA invocação de jq para o evento inteiro. A versão anterior pagava um
    # spawn de jq POR par key=value (5-7 forks por evento): num host de 16GB em
    # swap-thrash o fork custa dezenas de ms, e este append roda em TODO tool
    # call. Os kvs entram como args posicionais; o split no primeiro "=" e o
    # descarte de pares sem "=" ou com key vazia reproduzem o comportamento do
    # loop antigo (último kv duplicado vence via add).
    line=$(jq -cn --arg ts "$ts" --arg event "$event" --arg project "$slug" --arg session "$session" \
      '{ts:$ts,event:$event,project:$project,session:$session}
       + ([$ARGS.positional[] | index("=") as $i | select($i != null and $i > 0)
          | {(.[0:$i]): .[$i+1:]}] | add // {})' \
      --args "$@" 2>/dev/null) || line=""
  fi

  if [ -z "${line:-}" ]; then
    line=$(printf '{"ts":"%s","event":"%s","project":"%s","session":"%s"' \
      "$(_canuto_json_escape "$ts")" "$(_canuto_json_escape "$event")" \
      "$(_canuto_json_escape "$slug")" "$(_canuto_json_escape "$session")")
    for kv in "$@"; do
      key="${kv%%=*}"; value="${kv#*=}"
      [ -n "$key" ] && [ "$key" != "$kv" ] || continue
      line="$line,\"$(_canuto_json_escape "$key")\":\"$(_canuto_json_escape "$value")\""
    done
    line="$line}"
  fi

  # Lock same-host por diretório (mkdir é atômico; flock não existe no macOS).
  # Ver invariante de concorrência no header: retry curto, fail-open, e locks
  # entre máquinas (Syncthing) estão fora do alcance deste mecanismo.
  local lock_dir have_lock attempt lock_mtime now_epoch
  lock_dir="${log_path}.lock"
  have_lock=0
  for attempt in 1 2 3 4 5; do
    if mkdir "$lock_dir" 2>/dev/null; then have_lock=1; break; fi
    sleep 0.05 2>/dev/null || true
  done
  if [ "$have_lock" != "1" ]; then
    # Lock órfão (dono morreu entre mkdir e rmdir): quebra se idade >10s.
    lock_mtime=$(stat -f %m "$lock_dir" 2>/dev/null || stat -c %Y "$lock_dir" 2>/dev/null || echo "")
    now_epoch=$(date +%s 2>/dev/null || echo "")
    case "$lock_mtime$now_epoch" in *[!0-9]*|"") : ;; *)
      if [ $((now_epoch - lock_mtime)) -gt 10 ]; then
        rmdir "$lock_dir" 2>/dev/null || true
        # R6: quebrar o lock órfão NÃO dá posse — só o mkdir atômico dá.
        # Volta ao loop de aquisição: outro processo pode vencer a corrida
        # pós-rmdir; quem perder segue fail-open (append sem lock), como antes.
        for attempt in 1 2 3; do
          if mkdir "$lock_dir" 2>/dev/null; then have_lock=1; break; fi
          sleep 0.05 2>/dev/null || true
        done
      fi
    ;; esac
  fi
  printf '%s\n' "$line" >> "$log_path" 2>/dev/null || true
  if [ "$have_lock" = "1" ]; then rmdir "$lock_dir" 2>/dev/null || true; fi
  return 0
}

# ── CLI ─────────────────────────────────────────────────────────────────────
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  cmd="${1:-}"
  case "$cmd" in
    append)
      shift
      canuto_event_append "$@"
      ;;
    path)
      canuto_event_log_path
      ;;
    tail)
      n="${2:-10}"
      p=$(canuto_event_log_path)
      [ -f "$p" ] && tail -n "$n" "$p" || echo "(log vazio: $p)"
      ;;
    *)
      echo "uso: event-log.sh append <EVENT> [key=value ...] | path | tail [N]" >&2
      exit 1
      ;;
  esac
fi
