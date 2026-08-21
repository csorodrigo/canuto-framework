#!/usr/bin/env bash
# codex-maestro.sh — porta de entrada do runtime Codex direto.
#
# Sessão Codex direta não tem os hooks do Claude Code (SessionStart/Stop),
# então ESTE wrapper é a costura mecânica (ADR-0002): registra SESSION_START
# e SESSION_END no event log e cobra o CLOSEOUT na saída — o mesmo gate do
# session-save.sh do lado Claude, sem depender de disciplina do agente.

set -euo pipefail

if ! command -v codex >/dev/null 2>&1; then
  echo "codex CLI not found. Install it first or run Canuto from Claude." >&2
  exit 1
fi

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
PROFILE="${CANUTO_CODEX_MAESTRO_PROFILE:-maestro}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVENT_LOG="$SCRIPT_DIR/event-log.sh"

if [ -f "$EVENT_LOG" ]; then
  bash "$EVENT_LOG" append SESSION_START actor=codex-maestro runtime=codex || true
fi

# ── Registro + aviso de versão (paridade com o hook SessionStart do Claude) ──
# Sessão Codex direta não roda os hooks do Claude: sem isto, um projeto usado
# só via Codex nunca entraria no registro do canuto-update-all.sh nem veria o
# aviso de framework desatualizado. Postura de escrita no slug (require);
# versão remota vem SÓ do cache (alimentado em background pelas sessões
# Claude) — nunca rede no caminho de abertura. Tudo best-effort sob o
# set -euo pipefail deste wrapper.
_REG_GITDIR=$(git -C "$PROJECT_DIR" rev-parse --git-dir 2>/dev/null) || _REG_GITDIR=""
_REG_GITCOMMON=$(git -C "$PROJECT_DIR" rev-parse --git-common-dir 2>/dev/null) || _REG_GITCOMMON=""
_REG_SLUG=""
# Worktree linkado não registra (git-dir != git-common-dir): last-write-wins
# redirecionaria o update-all para o branch de feature do worktree.
if [ "$_REG_GITDIR" = "$_REG_GITCOMMON" ]; then
  _REG_SLUG=$(CANUTO_TARGET_DIR="$PROJECT_DIR" bash -c '
    . "$0" 2>/dev/null || exit 1
    canuto_require_project_slug "$CANUTO_TARGET_DIR" 2>/dev/null
  ' "$SCRIPT_DIR/canuto-memory.sh" 2>/dev/null) || _REG_SLUG=""
fi
if [ -n "$_REG_SLUG" ]; then
  _REG_DIR="${CANUTO_VAULT_DIR:-$HOME/.canuto/vault}/projects/$_REG_SLUG"
  { mkdir -p "$_REG_DIR" 2>/dev/null \
      && printf '%s\n' "$PROJECT_DIR" > "$_REG_DIR/project-path" 2>/dev/null; } || true
fi
# Só avisa quando o remoto é MAIS NOVO (cache atrasado ou fork à frente não
# podem virar "DESATUALIZADO" mandando refazer update já feito).
_canuto_ver_gt() {
  [ "$1" = "$2" ] && return 1
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -t. -k1,1n -k2,2n -k3,3n 2>/dev/null | tail -1)" = "$1" ]
}
_LOCAL_FW_VER=$(head -1 "$PROJECT_DIR/.agents/VERSION" 2>/dev/null | tr -d '[:space:]') || _LOCAL_FW_VER=""
_REMOTE_FW_VER=$(head -1 "$HOME/.canuto/.cache/framework-remote-version" 2>/dev/null | tr -d '[:space:]') || _REMOTE_FW_VER=""
if [ -n "$_LOCAL_FW_VER" ] && [ -n "$_REMOTE_FW_VER" ] \
   && _canuto_ver_gt "$_REMOTE_FW_VER" "$_LOCAL_FW_VER"; then
  echo "⚠ Canuto Framework DESATUALIZADO (local v$_LOCAL_FW_VER, remoto v$_REMOTE_FW_VER) — rode 'bash install.sh --update' aqui, ou 'bash .agents/tools/canuto-update-all.sh' para todos os projetos." >&2
fi

_canuto_codex_session_end() {
  local rc=$?
  [ -f "$EVENT_LOG" ] || return 0
  bash "$EVENT_LOG" append SESSION_END actor=codex-maestro runtime=codex rc="$rc" || true

  local log_path today_closeouts
  log_path="$(bash "$EVENT_LOG" path 2>/dev/null || true)"
  today_closeouts=0
  if [ -n "$log_path" ] && [ -f "$log_path" ]; then
    today_closeouts=$(grep '"event":"CLOSEOUT"' "$log_path" 2>/dev/null \
      | grep -c "\"ts\":\"$(date -u +%Y-%m-%d)" 2>/dev/null) || today_closeouts=0
  fi
  if [ "${today_closeouts:-0}" = "0" ]; then
    echo "" >&2
    echo "⚠ GATE: nenhum evento CLOSEOUT registrado hoje${log_path:+ em $log_path}." >&2
    echo "  Rode o session-end-learning e registre antes de encerrar de verdade:" >&2
    echo "  bash .agents/tools/event-log.sh append CLOSEOUT actor=codex-maestro summary=\"...\"" >&2
  else
    echo "✓ CLOSEOUT registrado hoje ($today_closeouts evento(s)) — learning loop ok." >&2
  fi
}
trap _canuto_codex_session_end EXIT

# Sem exec: o trap EXIT precisa disparar depois que o codex retornar.
codex --profile "$PROFILE" -C "$PROJECT_DIR" "$@"
