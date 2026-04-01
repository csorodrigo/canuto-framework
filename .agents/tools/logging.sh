#!/usr/bin/env bash
# logging.sh — Centralized logging for Canuto Framework hooks and tools.
# Source this file: source "$ROOT_DIR/.agents/tools/logging.sh"
#
# Functions:
#   log_debug "message"
#   log_info  "message"
#   log_warn  "message"
#   log_error "message"
#   log_json  "level" "component" "message" [extra_json_fields]
#
# Env vars:
#   CANUTO_LOG_LEVEL  — debug|info|warn|error (default: info)
#   CANUTO_LOG_JSON   — true|false (default: false)
#   CANUTO_LOG_FILE   — path to append structured logs (optional)

_CANUTO_LOG_LEVEL="${CANUTO_LOG_LEVEL:-info}"
_CANUTO_LOG_JSON="${CANUTO_LOG_JSON:-false}"
_CANUTO_LOG_FILE="${CANUTO_LOG_FILE:-}"
_CANUTO_COMPONENT="${CANUTO_COMPONENT:-canuto}"

# ANSI colors (only when stderr is a TTY)
if [ -t 2 ]; then
  _C_RESET='\033[0m'
  _C_DIM='\033[2m'
  _C_YELLOW='\033[33m'
  _C_RED='\033[31m'
  _C_CYAN='\033[36m'
else
  _C_RESET='' _C_DIM='' _C_YELLOW='' _C_RED='' _C_CYAN=''
fi

_log_level_num() {
  case "$1" in
    debug) echo 0 ;; info) echo 1 ;; warn) echo 2 ;; error) echo 3 ;; *) echo 1 ;;
  esac
}

_should_log() {
  local msg_level=$(_log_level_num "$1")
  local min_level=$(_log_level_num "$_CANUTO_LOG_LEVEL")
  [ "$msg_level" -ge "$min_level" ]
}

_log_text() {
  local level="$1" color="$2" msg="$3"
  _should_log "$level" || return 0
  local ts
  ts=$(date -u +%H:%M:%S)
  printf "${color}[%s][%s][%s]${_C_RESET} %s\n" "$ts" "$_CANUTO_COMPONENT" "$level" "$msg" >&2
}

log_json() {
  local level="$1" component="${2:-$_CANUTO_COMPONENT}" msg="$3" extra="${4:-}"
  _should_log "$level" || return 0

  local entry
  if command -v jq >/dev/null 2>&1; then
    entry=$(jq -cn \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg level "$level" \
      --arg component "$component" \
      --arg msg "$msg" \
      '{timestamp:$ts,level:$level,component:$component,message:$msg}')
    if [ -n "$extra" ]; then
      entry=$(printf '%s' "$entry" | jq -c --argjson extra "$extra" '. + $extra')
    fi
  else
    local _msg _level_e _comp_e
    _msg="$(printf '%s' "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    _level_e="$(printf '%s' "$level" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    _comp_e="$(printf '%s' "$component" | sed 's/\\/\\\\/g; s/"/\\"/g')"
    entry="{\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",\"level\":\"$_level_e\",\"component\":\"$_comp_e\",\"message\":\"$_msg\"}"
  fi

  if [ -n "$_CANUTO_LOG_FILE" ]; then
    printf '%s\n' "$entry" >> "$_CANUTO_LOG_FILE" 2>/dev/null || true
  fi

  if [ "$_CANUTO_LOG_JSON" = "true" ]; then
    printf '%s\n' "$entry" >&2
  fi
}

log_debug() {
  _log_text "debug" "$_C_DIM" "$1"
  if [ "$_CANUTO_LOG_JSON" = "true" ] || [ -n "$_CANUTO_LOG_FILE" ]; then
    log_json "debug" "$_CANUTO_COMPONENT" "$1"
  fi
}

log_info() {
  _log_text "info" "$_C_CYAN" "$1"
  if [ "$_CANUTO_LOG_JSON" = "true" ] || [ -n "$_CANUTO_LOG_FILE" ]; then
    log_json "info" "$_CANUTO_COMPONENT" "$1"
  fi
}

log_warn() {
  _log_text "warn" "$_C_YELLOW" "$1"
  if [ "$_CANUTO_LOG_JSON" = "true" ] || [ -n "$_CANUTO_LOG_FILE" ]; then
    log_json "warn" "$_CANUTO_COMPONENT" "$1"
  fi
}

log_error() {
  _log_text "error" "$_C_RED" "$1"
  if [ "$_CANUTO_LOG_JSON" = "true" ] || [ -n "$_CANUTO_LOG_FILE" ]; then
    log_json "error" "$_CANUTO_COMPONENT" "$1"
  fi
}
