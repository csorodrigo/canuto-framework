#!/usr/bin/env bash
# =============================================================================
# vault-bridge.sh — Obsidian REST API wrapper for Codex agents
# Usage:
#   vault-bridge.sh read <note-path>         Read a vault note
#   vault-bridge.sh write <note-path> <body>  Create/update a note
#   vault-bridge.sh search <query>            Full-text search
#   vault-bridge.sh list <directory>           List notes in directory
#
# Requires: OBSIDIAN_API_KEY env var or key in ~/.claude/settings.json
# Requires: Obsidian running with Local REST API plugin
# =============================================================================

set -euo pipefail

BASE_URL="${OBSIDIAN_BASE_URL:-https://127.0.0.1:27124}"
API_KEY="${OBSIDIAN_API_KEY:-}"

# Try to read API key from settings.json if not in env
if [ -z "$API_KEY" ]; then
  SETTINGS="$HOME/.claude/settings.json"
  if [ -f "$SETTINGS" ] && command -v jq &>/dev/null; then
    API_KEY=$(jq -r '.mcpServers["obsidian-mcp-server"].env.OBSIDIAN_API_KEY // empty' "$SETTINGS" 2>/dev/null)
  fi
fi

if [ -z "$API_KEY" ]; then
  echo "ERROR: OBSIDIAN_API_KEY not found. Set it in env or configure obsidian-mcp-server in settings.json." >&2
  exit 1
fi

# -k is required: the Obsidian Local REST API plugin uses a self-signed cert on localhost.
# The API key is written to a temp file to avoid exposing it in the process list (ps aux).
_AUTH_FILE=$(mktemp)
trap 'rm -f "$_AUTH_FILE"' EXIT
printf 'Authorization: Bearer %s' "$API_KEY" > "$_AUTH_FILE"
CURL_OPTS=(-s -k --header "@$_AUTH_FILE" -H "Content-Type: application/json")

usage() {
  echo "Usage:"
  echo "  vault-bridge.sh read <note-path>           Read a vault note"
  echo "  vault-bridge.sh write <note-path> <body>    Create/update a note"
  echo "  vault-bridge.sh search <query>              Full-text search"
  echo "  vault-bridge.sh list [directory]             List notes in directory"
  exit 1
}

cmd_read() {
  local path="$1"
  curl "${CURL_OPTS[@]}" -H "Accept: text/markdown" "$BASE_URL/vault/$path" 2>/dev/null
  local status=$?
  if [ $status -ne 0 ]; then
    echo "ERROR: Failed to read $path (is Obsidian running?)" >&2
    exit 1
  fi
}

cmd_write() {
  local path="$1"
  local body="$2"
  local http_code
  http_code=$(printf '%s' "$body" | curl "${CURL_OPTS[@]}" -X PUT \
    -H "Content-Type: text/markdown" \
    --data-binary @- \
    -o /dev/null -w '%{http_code}' \
    "$BASE_URL/vault/$path" 2>/dev/null)
  local curl_status=$?
  if [ $curl_status -ne 0 ]; then
    echo "ERROR: Failed to write $path (curl error $curl_status)" >&2
    exit 1
  fi
  case "$http_code" in
    200|201|204)
      echo "OK: Written to $path (HTTP $http_code)"
      ;;
    *)
      echo "ERROR: Failed to write $path (HTTP $http_code)" >&2
      exit 1
      ;;
  esac
}

cmd_search() {
  local query="$1"
  local body
  body=$(jq -n --arg q "$query" '{query: $q}')
  curl "${CURL_OPTS[@]}" -X POST \
    -d "$body" \
    "$BASE_URL/search/simple/" 2>/dev/null
}

cmd_list() {
  local dir="${1:-/}"
  curl "${CURL_OPTS[@]}" "$BASE_URL/vault/?dir=$dir" 2>/dev/null
}

# ── Main ─────────────────────────────────────────────────────────────────────
if [ $# -lt 1 ]; then
  usage
fi

case "$1" in
  read)
    [ $# -lt 2 ] && usage
    cmd_read "$2"
    ;;
  write)
    [ $# -lt 3 ] && usage
    cmd_write "$2" "$3"
    ;;
  search)
    [ $# -lt 2 ] && usage
    cmd_search "$2"
    ;;
  list)
    cmd_list "${2:-/}"
    ;;
  *)
    usage
    ;;
esac
