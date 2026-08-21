#!/usr/bin/env bash
# session-start.sh — SessionStart hook
# 1) Health-check (codex-health-check.sh) com timeout REAL + linhas de sessão e
#    stale context, registrando SESSION_START em .agents/vault/audit/.
# 2) BRIEF compacto do vault global (~/.canuto/vault/projects/<slug>/) injetado
#    como contexto da sessão. Auditoria 2026-08-01: o briefing como instrução
#    em CLAUDE.md teve 0-8% de adesão em 350+ sessões — a memória do vault era
#    write-only. Hook é garantia, prompt é sugestão.
#
# Output: JSON {hookSpecificOutput:{hookEventName,additionalContext}} quando jq
# existe — contrato do SessionStart (PRs #65-67): o Claude aceita texto plano OU
# JSON, o Codex exige JSON; emitir JSON é estritamente mais compatível. Sem jq,
# texto plano (degradação aceita pelo Claude).
# Nunca bloqueia (exit 0 sempre). Bash 3.2 compatible.

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../tools/otel-emit.sh" ]; then
  . "$SCRIPT_DIR/../tools/otel-emit.sh"
elif [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "$CLAUDE_PROJECT_DIR/.agents/tools/otel-emit.sh" ]; then
  . "$CLAUDE_PROJECT_DIR/.agents/tools/otel-emit.sh"
else
  otel_emit_span() { return 0; }
  otel_emit_counter() { return 0; }
fi
export CANUTO_OTEL_HOOK_SOURCE="session-start"

# ── Event log: cascata repo → lib global → stub fail-loud ───────────────────
# O antigo stub `return 0` deixava o event log morto EM SILÊNCIO em ~90% dos
# repos consumidores (auditoria 2026-08-01). Agora: (1) lib do repo; (2) lib
# global instalada (~/.canuto/lib, populada pelo instalador); (3) stub que
# registra a ausência UMA vez por sessão (marker em /tmp) em
# ~/.canuto/vault/_health/missing-lib.jsonl. Best-effort: nunca falha.
# $2 = motivo (default: event-log-lib-missing). O motivo entra no marker de
# /tmp para que ausências DIFERENTES (event-log vs brief-compose) registrem
# cada uma a sua nota — um marker único faria a segunda ausência sumir.
_canuto_missing_lib_note() {
  local marker cwd_s reason
  reason="${2:-event-log-lib-missing}"
  marker="${TMPDIR:-/tmp}/canuto-missing-eventlib-${CLAUDE_SESSION_ID:-$PPID}-$1-$reason"
  [ -e "$marker" ] && return 0
  : >"$marker" 2>/dev/null || true
  mkdir -p "$HOME/.canuto/vault/_health" 2>/dev/null || return 0
  cwd_s=$(pwd 2>/dev/null || echo unknown)
  cwd_s=$(printf '%s' "$cwd_s" | tr -d '"\\' 2>/dev/null || echo unknown)
  printf '{"ts":"%s","hook":"%s","cwd":"%s","reason":"%s"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" "$1" "$cwd_s" "$reason" \
    >>"$HOME/.canuto/vault/_health/missing-lib.jsonl" 2>/dev/null || true
  return 0
}
if [ -f "$SCRIPT_DIR/../tools/event-log.sh" ]; then
  . "$SCRIPT_DIR/../tools/event-log.sh"
elif [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "$CLAUDE_PROJECT_DIR/.agents/tools/event-log.sh" ]; then
  . "$CLAUDE_PROJECT_DIR/.agents/tools/event-log.sh"
elif [ -f "$HOME/.canuto/lib/event-log.sh" ]; then
  . "$HOME/.canuto/lib/event-log.sh"
else
  canuto_event_append() { _canuto_missing_lib_note "session-start"; return 0; }
fi

emit_hook_otel() {
  {
    otel_emit_span "hook.session_start" "success" 0
    otel_emit_counter "hook.session_start" "success"
  } || true
}

# ── Vault brief (a mudança de maior alavancagem da auditoria 2026-08-01) ────
# O compositor MOROU aqui (build_vault_brief) até a Fase 2. Saiu para
# .agents/tools/brief-compose.sh por um motivo mecânico, não estético: preso
# dentro do hook ele não podia ser PROVADO — um brief vazio por quebra era
# indistinguível de um brief vazio por não haver nada (a "lobotomia
# silenciosa" do edge-of-chaos). Agora o MESMO código atende hook, doctor e
# `brief-compose.sh check-identity`, que exercita as duas pernas do gate.
#
# Cascata idêntica à do event log: lib do repo → lib global instalada →
# sem lib, sem brief (com a ausência REGISTRADA em _health/missing-lib.jsonl,
# nunca em silêncio). Continua rodando em subshell ($(...)) na hora da
# chamada: o `set -euo pipefail` do canuto-memory.sh não vaza para o hook.
# Custo alvo <1s: só ls/sed/awk em ≤9 arquivos pequenos; nada recursivo.
if [ -f "$SCRIPT_DIR/../tools/brief-compose.sh" ]; then
  . "$SCRIPT_DIR/../tools/brief-compose.sh" 2>/dev/null || true
elif [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "$CLAUDE_PROJECT_DIR/.agents/tools/brief-compose.sh" ]; then
  . "$CLAUDE_PROJECT_DIR/.agents/tools/brief-compose.sh" 2>/dev/null || true
elif [ -f "$HOME/.canuto/lib/brief-compose.sh" ]; then
  . "$HOME/.canuto/lib/brief-compose.sh" 2>/dev/null || true
fi
# O source pode ter falhado (lib ausente OU lib que não parseia): a garantia é
# a FUNÇÃO existir, não o arquivo. Sem ela, brief vazio + nota de saúde.
if ! command -v canuto_compose_brief >/dev/null 2>&1; then
  canuto_compose_brief() {
    _canuto_missing_lib_note "session-start" "brief-compose-lib-missing"
    return 0
  }
fi

# --- Read hook input (ignore errors) --------------------------------------
# Sem payload num TTY: `cat` sem stdin fechado bloqueia para sempre e o
# runtime que espera o hook congela junto (regra de TTY/pipe do CLAUDE.md).
# Ausência de payload ≠ erro (PR #66): segue com os fallbacks de cwd.
INPUT=""
[ -t 0 ] || INPUT="$(cat 2>/dev/null || true)"
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$CWD" ] && CWD="${CLAUDE_PROJECT_DIR:-$(pwd)}"
# X1: session_id e source do payload — compact/resume ficam distinguíveis de
# startup no event log. CLAUDE_SESSION_ID exportado é o que event-log.sh já lê
# para preencher o campo `session` de todo evento gravado por este processo.
SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
SESSION_SOURCE=$(printf '%s' "$INPUT" | jq -r '.source // empty' 2>/dev/null)
if [ -n "$SESSION_ID" ]; then
  CLAUDE_SESSION_ID="$SESSION_ID"
  export CLAUDE_SESSION_ID
fi

# --- Resolve roots ---------------------------------------------------------
# GIT_ROOT: toplevel git do cwd — gate do BRIEF (probe fora de repo não paga
# ritual nenhum). ROOT: instalação do framework (.agents) — gate do health
# check e do audit local. São independentes: um repo git sem .agents ainda
# ganha brief se o slug tiver vault global.
GIT_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || GIT_ROOT=""
ROOT=""
if [ -d "$CWD/.agents" ]; then
  ROOT="$CWD"
elif [ -n "$GIT_ROOT" ] && [ -d "$GIT_ROOT/.agents" ]; then
  ROOT="$GIT_ROOT"
fi

if [ -z "$ROOT" ] && [ -z "$GIT_ROOT" ]; then
  # probe-gate: cwd sem repo e sem framework — silent exit
  emit_hook_otel
  exit 0
fi

# --- Run healthcheck com limite REAL de tempo -----------------------------
# Este hook roda no caminho de abertura da sessão: o runtime fica parado até ele
# voltar. E o health check não é barato — ele dispara `codex mcp list`,
# `codex mcp get` por servidor, `brew/npm/uvx/gh --version`. Nenhuma dessas
# chamadas tem limite próprio, e `codex mcp get` contra um servidor que não sobe
# é justamente a lenta. Resultado: abrir o Codex ficava "travado" por dezenas de
# segundos, com cara de deadlock.
#
# A versão anterior PARECIA protegida ("4s soft timeout via perl alarm"), mas o
# alarme só fazia o perl sair — o filho continuava vivo, e o close implícito do
# pipe no shutdown esperava por ele. Medido: 4s prometidos, 30s reais. Um
# timeout que não mata o filho não é timeout, é comentário.
#
# Ordem: timeout (GNU) → gtimeout (macOS/coreutils) → perl que mata o GRUPO do
# processo → desiste. macOS não traz `timeout` de fábrica, então sem o gtimeout
# o Mac caía direto no caminho sem limite nenhum — que é onde o problema aparecia.
# Se nada disso existe, o health check é PULADO: perder duas linhas de
# diagnóstico é barato, travar a abertura da sessão não é.
# X2 — default 2s (era 4): o hook tem ~5s de teto no harness; num host lento o brief morreria no kill — brief é a entrega prioritária, health é só diagnóstico.
HEALTH_TIMEOUT="${CANUTO_HEALTH_TIMEOUT:-2}"
HEALTH_JSON=""
VERDICT=""
if [ -n "$ROOT" ] && [ -x "$ROOT/.agents/tools/codex-health-check.sh" ]; then
  HEALTH_SCRIPT="$ROOT/.agents/tools/codex-health-check.sh"
  if command -v timeout >/dev/null 2>&1; then
    HEALTH_JSON=$(timeout "$HEALTH_TIMEOUT" bash "$HEALTH_SCRIPT" --json --smoke 2>/dev/null || true)
  elif command -v gtimeout >/dev/null 2>&1; then
    HEALTH_JSON=$(gtimeout "$HEALTH_TIMEOUT" bash "$HEALTH_SCRIPT" --json --smoke 2>/dev/null || true)
  elif command -v perl >/dev/null 2>&1; then
    HEALTH_JSON=$(perl -e '
      my $limit = shift @ARGV;
      my $pid = open(my $fh, "-|");
      exit 0 unless defined $pid;
      if ($pid == 0) { setpgrp(0, 0); exec(@ARGV); exit 127; }
      # mata o GRUPO: o filho é bash, mas quem demora são os netos (codex/brew).
      # Matar só o bash deixaria os netos segurando o pipe e o read bloqueado.
      $SIG{ALRM} = sub { kill("KILL", -$pid); exit 0 };
      alarm $limit;
      local $/;
      my $out = <$fh>;
      alarm 0;
      close $fh;
      print $out if defined $out;
    ' -- "$HEALTH_TIMEOUT" bash "$HEALTH_SCRIPT" --json --smoke 2>/dev/null || true)
  fi
fi

# --- Summarize health -----------------------------------------------------
HEALTH_LINE=""
if [ -n "$HEALTH_JSON" ]; then
  VERDICT=$(printf '%s' "$HEALTH_JSON" | jq -r '.verdict // "UNKNOWN"' 2>/dev/null)
  PASS=$(printf '%s' "$HEALTH_JSON" | jq -r '.counts.pass // 0' 2>/dev/null)
  WARN=$(printf '%s' "$HEALTH_JSON" | jq -r '.counts.warn // 0' 2>/dev/null)
  FAIL=$(printf '%s' "$HEALTH_JSON" | jq -r '.counts.fail // 0' 2>/dev/null)
  HEALTH_LINE="MCP Health: $VERDICT (pass=$PASS warn=$WARN fail=$FAIL)"
fi

# --- Session header -------------------------------------------------------
HDR_ROOT="${ROOT:-$GIT_ROOT}"
SLUG=$(basename "$HDR_ROOT")
# `rev-parse --abbrev-ref HEAD` num repo SEM commits imprime "HEAD" no stdout
# E falha — o antigo `|| echo "-"` concatenava os dois ("HEAD\n-"). head -1
# fica com a primeira linha; vazio de verdade vira "-".
BRANCH=$(git -C "$HDR_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null | head -1)
[ -n "$BRANCH" ] || BRANCH="-"
SESSION_LINE="Session: $SLUG @ $BRANCH"

# --- Stale context check --------------------------------------------------
STALE_LINE=""
LATEST_CONTEXT=""
CHANGED=""
if [ -n "$ROOT" ]; then
  # newest .context.md in the repo (excluding node_modules/.git)
  LATEST_CONTEXT=$(find "$ROOT" \( -path "*/node_modules" -o -path "*/.git" \) -prune -o -name ".context.md" -print 2>/dev/null | head -200 | xargs stat -f '%m %N' 2>/dev/null | sort -rn | head -1 | awk '{print $2}')
fi
if [ -n "$LATEST_CONTEXT" ] && [ -f "$LATEST_CONTEXT" ]; then
  CHANGED=$(git -C "$ROOT" diff --name-only HEAD 2>/dev/null | wc -l | tr -d ' ')
  if [ "$CHANGED" != "" ] && [ "$CHANGED" -gt 5 ]; then
    STALE_LINE="Stale contexts: $CHANGED files changed since latest .context.md"
  else
    STALE_LINE="Stale contexts: none"
  fi
fi

# --- Vault brief -----------------------------------------------------------
# Gates: cwd em repo git (probe-gate) e CANUTO_NO_BRIEF=1 desliga. Fail-open:
# qualquer falha interna vira brief vazio, nunca quebra a sessão.
# Diferença desde a Fase 2: o compositor NÃO devolve mais string vazia quando
# não acha vault. Ele devolve o estado honesto (fresco / declarado-e-ausente /
# identidade não resolvida) — a memória desligada precisa APARECER.
# CANUTO_BRIEF_STATUS_FILE é o canal lateral com o balanço estrutural da
# composição: alimenta o BRIEF_COMPOSED e o registro de uso, sem reparsear texto.
BRIEF=""
BRIEF_SLUG=""
BRIEF_VAULT_STATE=""
BRIEF_POP=""
BRIEF_EMPTY=""
BRIEF_BROKEN=""
BRIEF_REFS=""
BRIEF_STATUS_FILE=""
if [ -n "$GIT_ROOT" ] && [ "${CANUTO_NO_BRIEF:-0}" != "1" ]; then
  BRIEF_STATUS_FILE="${TMPDIR:-/tmp}/canuto-brief-status-$$"
  # Trunca ANTES de compor (redirect builtin, 0 forks): se o compositor não
  # escrever (lib ausente), o que se lê é vazio — nunca o resto de um PID
  # reciclado de outra sessão virando telemetria desta.
  : >"$BRIEF_STATUS_FILE" 2>/dev/null || true
  CANUTO_BRIEF_STATUS_FILE="$BRIEF_STATUS_FILE"
  export CANUTO_BRIEF_STATUS_FILE
  BRIEF=$(canuto_compose_brief "$GIT_ROOT" 2>/dev/null) || BRIEF=""
  unset CANUTO_BRIEF_STATUS_FILE
  if [ -f "$BRIEF_STATUS_FILE" ]; then
    while IFS='=' read -r _bk _bv; do
      case "$_bk" in
        slug) BRIEF_SLUG="$_bv" ;;
        vault_state) BRIEF_VAULT_STATE="$_bv" ;;
        sections_populated) BRIEF_POP="$_bv" ;;
        sections_empty) BRIEF_EMPTY="$_bv" ;;
        sections_broken) BRIEF_BROKEN="$_bv" ;;
        refs) BRIEF_REFS="$_bv" ;;
      esac
    done < "$BRIEF_STATUS_FILE"
    rm -f "$BRIEF_STATUS_FILE" 2>/dev/null || true
  fi
fi

# --- Audit event (só onde há framework instalado) --------------------------
if [ -n "$ROOT" ]; then
  AUDIT_DIR="$ROOT/.agents/vault/audit"
  if [ -d "$AUDIT_DIR" ] || mkdir -p "$AUDIT_DIR" 2>/dev/null; then
    DATE=$(date +%Y-%m-%d)
    TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
    AUDIT_FILE="$AUDIT_DIR/${DATE}-SESSION_START.md"
    # Existência decidida ANTES do bloco: o `>>` abre (cria) o arquivo antes de
    # o bloco rodar, então um `[ ! -f ]` interno nunca via a criação e o header
    # não saía. E `printf --`: formato começando com "-" sem o `--` é "invalid
    # option" no printf builtin — o audit ficava 0 bytes para sempre
    # (bug herdado do HEAD, achado na validação E2E 2026-08-01).
    AUDIT_NEW=1
    [ -f "$AUDIT_FILE" ] && AUDIT_NEW=0
    {
      if [ "$AUDIT_NEW" = 1 ]; then
        printf -- '---\ntype: SESSION_START\nproject: %s\ndate: %s\n---\n\n' "$SLUG" "$DATE"
      fi
      printf -- '- **%s** branch=%s health=%s stale=%s\n' \
        "$TS" "$BRANCH" "${VERDICT:-unknown}" "${CHANGED:-0}"
    } >> "$AUDIT_FILE" 2>/dev/null || true
  fi

  # --- Event log (fonte de verdade; a nota de audit acima é projeção) ------
  # Subshell com CLAUDE_PROJECT_DIR=$ROOT: canuto_event_append resolve o
  # projeto por env/pwd, e o pwd do processo do hook pode divergir do cwd do
  # payload (visto no harness: evento ia parar no vault de OUTRO projeto).
  # Subshell, não prefixo `VAR=x func`: no bash <4.4 o prefixo vaza pro caller.
  BRIEF_STATE=none
  [ -n "$BRIEF" ] && BRIEF_STATE=shown
  (
    CLAUDE_PROJECT_DIR="$ROOT"
    export CLAUDE_PROJECT_DIR
    canuto_event_append SESSION_START actor=hook \
      branch="${BRANCH:-}" health="${VERDICT:-unknown}" stale="${CHANGED:-0}" \
      brief="$BRIEF_STATE" source="${SESSION_SOURCE:-}"
  ) || true
fi

# --- Uso das notas + evento do brief ---------------------------------------
# A ORDEM É INVARIANTE (edge-of-chaos cortex_usage, N3): o compositor JÁ
# ranqueou usando o store anterior; só agora gravamos o uso desta sessão.
# Inverter faria o briefing reforçar a própria ordem — o que foi mostrado
# subiria por ter sido mostrado, e a telemetria viraria profecia auto-realizável.
# Best-effort e fora do caminho crítico: nada aqui pode atrasar ou quebrar a
# abertura da sessão.
if [ -n "$BRIEF_SLUG" ] && [ -n "$BRIEF_REFS" ] \
   && command -v canuto_usage_record >/dev/null 2>&1; then
  # set -f: as refs vão para "$@" por word-splitting em vírgula; sem noglob um
  # nome de nota com `*` viraria expansão de path.
  set -f
  _BRIEF_OLD_IFS="$IFS"
  IFS=','
  set -- $BRIEF_REFS
  IFS="$_BRIEF_OLD_IFS"
  set +f
  canuto_usage_record "$BRIEF_SLUG" "$@" || true
fi

# BRIEF_COMPOSED é o que permite calibrar depois: quantas sessões abriram com
# seção quebrada, quantas com vault fresco, quais seções vivem vazias.
# Gate de escrita: só onde já existe destino legítimo (framework instalado ou
# vault do projeto presente) — senão o append criaria .agents/.cache num repo
# de terceiro só para registrar telemetria.
# BRIEF_VAULT_STATE só existe se o compositor REALMENTE rodou (ele o preenche
# nos quatro desfechos). Sem ele, não há o que reportar — a ausência da lib já
# virou nota em _health/missing-lib.jsonl, e um evento de campos vazios seria
# pior que evento nenhum.
if [ -n "$BRIEF_VAULT_STATE" ] \
   && { [ -n "$ROOT" ] || [ "$BRIEF_VAULT_STATE" = "present" ]; }; then
  (
    CLAUDE_PROJECT_DIR="${ROOT:-$GIT_ROOT}"
    export CLAUDE_PROJECT_DIR
    canuto_event_append BRIEF_COMPOSED actor=hook \
      slug="${BRIEF_SLUG:-}" vault_state="${BRIEF_VAULT_STATE:-}" \
      sections_populated="${BRIEF_POP:-}" sections_empty="${BRIEF_EMPTY:-}" \
      sections_broken="${BRIEF_BROKEN:-}"
  ) || true
fi

# --- Registro do path do projeto (para canuto-update-all.sh) ---------------
# O vault global conhece SLUGS, não paths — e o update-all precisa dos paths
# para varrer os projetos. Cada sessão registra (last-write-wins) o toplevel em
# <vault>/projects/<slug>/project-path. Postura de ESCRITA: só com
# canuto_require_project_slug (identidade confiável); slug degradado criaria
# ilha nova no vault — aí é melhor não registrar. Best-effort: nunca quebra a
# abertura da sessão.
if [ -n "$ROOT" ] && command -v canuto_require_project_slug >/dev/null 2>&1; then
  REG_SLUG=$(canuto_require_project_slug "$ROOT" 2>/dev/null) || REG_SLUG=""
  if [ -n "$REG_SLUG" ]; then
    REG_DIR="${CANUTO_VAULT_DIR:-$HOME/.canuto/vault}/projects/$REG_SLUG"
    mkdir -p "$REG_DIR" 2>/dev/null \
      && printf '%s\n' "$ROOT" > "$REG_DIR/project-path" 2>/dev/null || true
  fi
fi

# --- Aviso de framework desatualizado ---------------------------------------
# Compara .agents/VERSION local com o VERSION remoto do main. A busca remota
# NUNCA roda no caminho crítico: o valor usado é o do cache
# (~/.canuto/.cache/framework-remote-version) e o refresh dispara em
# BACKGROUND quando o cache tem >6h — a primeira sessão não avisa, a próxima
# sim. Offline: curl falha em silêncio, cache antigo continua valendo.
# CANUTO_NO_VERSION_CHECK=1 desliga.
UPDATE_LINE=""
if [ -n "$ROOT" ] && [ "${CANUTO_NO_VERSION_CHECK:-0}" != "1" ] \
   && [ -f "$ROOT/.agents/VERSION" ]; then
  LOCAL_FW_VER=$(head -1 "$ROOT/.agents/VERSION" 2>/dev/null | tr -d '[:space:]')
  VER_CACHE_DIR="$HOME/.canuto/.cache"
  VER_CACHE="$VER_CACHE_DIR/framework-remote-version"
  CACHE_MTIME=$(stat -c %Y "$VER_CACHE" 2>/dev/null || stat -f %m "$VER_CACHE" 2>/dev/null || echo 0)
  NOW_EPOCH=$(date +%s 2>/dev/null || echo 0)
  if [ $((NOW_EPOCH - CACHE_MTIME)) -gt 21600 ] && command -v curl >/dev/null 2>&1; then
    mkdir -p "$VER_CACHE_DIR" 2>/dev/null || true
    (
      RAW=$(curl -fsSL -m 5 "${CANUTO_REPO_URL:-https://raw.githubusercontent.com/csorodrigo/canuto-framework/main}/.agents/VERSION" 2>/dev/null | head -1 | tr -d '[:space:]')
      # Só versão com cara de versão entra no cache — 404 HTML ou lixo de
      # proxy viraria um "desatualizado" fantasma em toda sessão.
      case "$RAW" in
        [0-9]*.[0-9]*) printf '%s\n' "$RAW" > "$VER_CACHE.tmp" 2>/dev/null \
          && mv "$VER_CACHE.tmp" "$VER_CACHE" 2>/dev/null ;;
      esac
    ) >/dev/null 2>&1 &
  fi
  REMOTE_FW_VER=$(head -1 "$VER_CACHE" 2>/dev/null | tr -d '[:space:]')
  if [ -n "$LOCAL_FW_VER" ] && [ -n "$REMOTE_FW_VER" ] \
     && [ "$LOCAL_FW_VER" != "$REMOTE_FW_VER" ]; then
    UPDATE_LINE="Framework: DESATUALIZADO (local v$LOCAL_FW_VER, remoto v$REMOTE_FW_VER) — rode 'bash install.sh --update' aqui, ou 'bash .agents/tools/canuto-update-all.sh' para atualizar todos os projetos"
  fi
fi

# --- Emit ------------------------------------------------------------------
CONTEXT=""
if [ -n "$HEALTH_LINE" ]; then
  CONTEXT="$HEALTH_LINE
"
fi
CONTEXT="${CONTEXT}${SESSION_LINE}"
if [ -n "$UPDATE_LINE" ]; then
  CONTEXT="$CONTEXT
$UPDATE_LINE"
fi
if [ -n "$STALE_LINE" ]; then
  CONTEXT="$CONTEXT
$STALE_LINE"
fi
if [ -n "$BRIEF" ]; then
  CONTEXT="$CONTEXT

$BRIEF"
fi

if command -v jq >/dev/null 2>&1; then
  # -M: nunca colorizar — jq detecta tty e injetaria escapes ANSI no JSON.
  printf '%s' "$CONTEXT" \
    | jq -M -Rs '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:.}}' 2>/dev/null \
    || printf '%s\n' "$CONTEXT"
else
  printf '%s\n' "$CONTEXT"
fi

emit_hook_otel
exit 0
