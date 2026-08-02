#!/usr/bin/env bash
# session-save.sh — Auto-save session state on Stop
# Dispara via hooks.Stop
#
# What it does:
#   1. Creates a timestamped backup of memory files
#   2. Outputs a reminder for the Maestro to finalize session state
#   3. Ensures no session data is lost on unexpected exits
#
# INSTALLATION:
#   cp .agents/hooks/session-save.sh ~/.claude/hooks/session-save.sh
#   chmod +x ~/.claude/hooks/session-save.sh

set -euo pipefail

# ── Locate vault ──────────────────────────────────────────────────────────
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
ROOT_DIR="$(cd "$PROJECT_DIR" && git rev-parse --show-toplevel 2>/dev/null || pwd)"
MEMORY_LIB="$ROOT_DIR/.agents/tools/canuto-memory.sh"

if [ -f "$MEMORY_LIB" ]; then
  # shellcheck source=/dev/null
  source "$MEMORY_LIB"
else
  canuto_project_dir()  { echo "${1:-.}"; }
  canuto_project_slug() { basename "${1:-.}"; }
  canuto_cache_dir()    { echo "${1:-.}/.agents/.cache"; }
  canuto_resolve_memory_backend() { printf 'none\t\n'; }
fi

# ── Event log: cascata repo → lib global → stub fail-loud ───────────────────
# O antigo stub `return 0` deixava o event log morto EM SILÊNCIO em ~90% dos
# repos consumidores (auditoria 2026-08-01). Sem lib no repo nem em
# ~/.canuto/lib, o stub registra a ausência UMA vez por sessão (marker em
# /tmp) em ~/.canuto/vault/_health/missing-lib.jsonl. Best-effort: nunca falha.
_canuto_missing_lib_note() {
  local marker cwd_s
  marker="${TMPDIR:-/tmp}/canuto-missing-eventlib-${CLAUDE_SESSION_ID:-$PPID}-$1"
  [ -e "$marker" ] && return 0
  : >"$marker" 2>/dev/null || true
  mkdir -p "$HOME/.canuto/vault/_health" 2>/dev/null || return 0
  cwd_s=$(pwd 2>/dev/null || echo unknown)
  cwd_s=$(printf '%s' "$cwd_s" | tr -d '"\\' 2>/dev/null || echo unknown)
  printf '{"ts":"%s","hook":"%s","cwd":"%s","reason":"event-log-lib-missing"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" "$1" "$cwd_s" \
    >>"$HOME/.canuto/vault/_health/missing-lib.jsonl" 2>/dev/null || true
  return 0
}
EVENT_LIB="$ROOT_DIR/.agents/tools/event-log.sh"
if [ -f "$EVENT_LIB" ]; then
  # shellcheck source=/dev/null
  source "$EVENT_LIB"
elif [ -f "$HOME/.canuto/lib/event-log.sh" ]; then
  # shellcheck source=/dev/null
  source "$HOME/.canuto/lib/event-log.sh"
else
  canuto_event_append() { _canuto_missing_lib_note "session-save"; return 0; }
fi

PROJECT_DIR=$(canuto_project_dir "$PROJECT_DIR")
PROJECT_SLUG=$(canuto_project_slug "$PROJECT_DIR")
CACHE_DIR=$(canuto_cache_dir "$PROJECT_DIR")
BACKEND_KIND=""
BACKEND_DIR=""

# `|| true`: read returns 1 on EOF-without-newline, which under `set -e` killed
# the whole hook (29% failure rate in projects without canuto-memory.sh).
IFS=$'\t' read -r BACKEND_KIND BACKEND_DIR < <(canuto_resolve_memory_backend "$PROJECT_DIR") || true
[ -n "$BACKEND_KIND" ] || BACKEND_KIND="none"

VAULT_AVAILABLE=false
if [ "$BACKEND_KIND" = "global" ] || [ "$BACKEND_KIND" = "local" ]; then
  VAULT_AVAILABLE=true
  VAULT_DIR="$BACKEND_DIR"
fi

# ── Event log: SESSION_END é mecânico, nunca depende do agente ─────────────
canuto_event_append SESSION_END actor=hook backend="$BACKEND_KIND" || true

# ── Gate de closeout (fail-closed informativo, padrão edge "verify at exit"):
# se o agente não registrou CLOSEOUT hoje, o aviso sai com evidência concreta.
EVENT_LOG_PATH=""
command -v canuto_event_log_path >/dev/null 2>&1 && EVENT_LOG_PATH=$(canuto_event_log_path "$PROJECT_DIR") || true
CLOSEOUT_TODAY=0
if [ -n "$EVENT_LOG_PATH" ] && [ -f "$EVENT_LOG_PATH" ]; then
  CLOSEOUT_TODAY=$(grep '"event":"CLOSEOUT"' "$EVENT_LOG_PATH" 2>/dev/null \
    | grep -c "\"ts\":\"$(date -u +%Y-%m-%d)" 2>/dev/null) || CLOSEOUT_TODAY=0
fi

# ── Fallback: save to pending-sync if vault unavailable ───────────────────
if [ "$BACKEND_KIND" = "none" ]; then
  PENDING_SYNC="$CACHE_DIR/pending-sync"
  mkdir -p "$PENDING_SYNC"
  TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
  cat > "$PENDING_SYNC/$TIMESTAMP-session-marker.md" <<EOF
---
type: pending-sync-marker
status: pending
timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)
project: $PROJECT_SLUG
source: session-save
tags:
  - pending-sync
  - offline
---

# Offline Session Marker

- recorded_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)
- project: $PROJECT_SLUG
- note: No vault or legacy memory backend was available when session-save ran.
EOF
  echo ""
  echo "════════════════════════════════════════"
  echo "  Canuto — OFFLINE Save"
  echo "════════════════════════════════════════"
  echo "  Vault unavailable. State saved to:"
  echo "  $PENDING_SYNC/"
  echo ""
  echo "  On next session with vault available,"
  echo "  run /vault-sync or bash .agents/tools/vault-sync.sh."
  echo "════════════════════════════════════════"
  echo ""
  exit 0
fi

if [ "$BACKEND_KIND" = "legacy" ]; then
  SNAPSHOT_DIR="$BACKEND_DIR/.snapshots"
  TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)_$$
  SNAPSHOT_PATH="$SNAPSHOT_DIR/$TIMESTAMP"

  mkdir -p "$SNAPSHOT_PATH"
  for file in last-session.md decisions.md instincts.md pending.md metrics.md audit-log.md design-profile.md component-inventory.md; do
    if [ -f "$BACKEND_DIR/$file" ]; then
      cp "$BACKEND_DIR/$file" "$SNAPSHOT_PATH/$file"
    fi
  done

  echo "$TIMESTAMP" > "$BACKEND_DIR/.last-save-timestamp"

  echo ""
  echo "════════════════════════════════════════"
  echo "  Canuto — Legacy Session State Saved"
  echo "════════════════════════════════════════"
  echo "  Snapshot: $SNAPSHOT_PATH"
  echo ""
  echo "  Legacy .agents/memory backend detected."
  echo "  Upgrade when ready, but current compatibility state was preserved."
  echo "════════════════════════════════════════"
  echo ""
  exit 0
fi

# ── Create backup snapshot ──────────────────────────────────────────────────
SNAPSHOT_DIR="$VAULT_DIR/.snapshots"
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)_$$
SNAPSHOT_PATH="$SNAPSHOT_DIR/$TIMESTAMP"

mkdir -p "$SNAPSHOT_PATH"

# Copy current vault state (key directories only)
for dir in sessions decisions instincts pending metrics audit; do
  if [ -d "$VAULT_DIR/$dir" ]; then
    mkdir -p "$SNAPSHOT_PATH/$dir"
    cp "$VAULT_DIR/$dir"/*.md "$SNAPSHOT_PATH/$dir/" 2>/dev/null || true
  fi
done

# ── Prune old snapshots (keep last 10) ──────────────────────────────────────
if [ -d "$SNAPSHOT_DIR" ]; then
  ls -dt "$SNAPSHOT_DIR"/*/ 2>/dev/null | tail -n +11 | while IFS= read -r dir; do rm -rf "$dir"; done 2>/dev/null || true
fi

# ── Write session marker ────────────────────────────────────────────────────
echo "$TIMESTAMP" > "$VAULT_DIR/.last-save-timestamp"

# ── Nota canônica + intent kernel (eoc ADR-0009/0012, P2 #9 da auditoria) ──
# O closeout só conta como PUBLICADO se a nota canônica da sessão (a mais
# recente em $VAULT_DIR/sessions/) carregar prova de intenção: o kernel de
# 3 linhas intent:/porque:/proximo:, OU o contrato Summary/Proof/Next
# Entrypoint que `canuto-brain closeout` já escreve hoje (mesma prova, forma
# antiga — nenhum dos dois formatos é penalizado). Sem os dois, a nota
# existe mas é write-only: prosa sem índice de retrieval (ADR-0009).
# Isto ACRESCENTA ao gate de CLOSEOUT_TODAY acima — mesmo ato, não um
# segundo gate (spec A5 / convenções Fase 2).

_a5_slugify() {
  # bash 3.2: sem ${var,,}. Produz um id estável (ADR-0007: item endereçável).
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[^a-z0-9]/-/g' -e 's/-\{2,\}/-/g' -e 's/^-//' -e 's/-$//' \
    | cut -c1-60
}

_a5_redact_secrets() {
  # CHOKE POINT ÚNICO de redação (review cego 2026-08-02). Todo texto extraído
  # da nota que vá para (a) nome de arquivo, (b) corpo de nota nova, (c) evento
  # no log.jsonl ou (d) stdout do hook passa por aqui ANTES. Redige o lado
  # direito de qualquer atribuição NOME=valor: o NOME sobrevive (é o que o
  # humano precisa para rotacionar), o VALOR nunca sai da nota original.
  # Idempotente: `TOKEN=<redigido>` redigido de novo continua igual.
  # `|| true` porque o hook roda sob `set -euo pipefail` — falha do sed nunca
  # pode matar o Stop hook.
  printf '%s' "${1:-}" | sed 's/=[^[:space:]]*/=<redigido>/g' 2>/dev/null || true
}

_a5_note_exists() {
  # $1=dir $2=id — anti-duplicata: nome de arquivo OU frontmatter `id:`.
  # Loop em vez de `dir/*.md` num grep direto: glob sem match não pode virar
  # "arquivo não encontrado" bagunçando o retorno (regra de busca do CLAUDE.md).
  local dir="$1" id="$2" f
  [ -d "$dir" ] || return 1
  for f in "$dir"/*.md; do
    [ -e "$f" ] || continue
    case "$(basename "$f")" in
      *"-$id.md") return 0 ;;
    esac
    grep -q "^id: $id\$" "$f" 2>/dev/null && return 0
  done
  return 1
}

_a5_create_pending() {
  # $1=vault $2=texto-do-next-entrypoint $3=nota-de-origem
  # Cria <vault>/pending/<data>-<id>.md com status: proposed (ADR-0007:
  # entrada permissiva; curadoria promove a set). Idempotente via
  # _a5_note_exists — rodar o hook 2x não duplica.
  local vdir="$1" text="$2" note="$3" id date_s file title
  # O next-entrypoint pode carregar uma atribuição de segredo ("proximo:
  # rotacionar TOKEN=abc123") — e daqui o texto CRU virava id, nome de arquivo
  # E corpo da nota (review cego 2026-08-02). Redigir ANTES do slugify é o que
  # impede o valor de aterrissar em pending/<data>-...-abc123.md.
  text=$(_a5_redact_secrets "$text")
  [ -n "$text" ] || text="(next-entrypoint redigido)"
  id=$(_a5_slugify "$text") || id=""
  [ -n "$id" ] || id="next-entrypoint"
  _a5_note_exists "$vdir/pending" "$id" && return 1
  mkdir -p "$vdir/pending" 2>/dev/null || return 1
  date_s=$(date +%Y-%m-%d 2>/dev/null) || date_s="unknown-date"
  file="$vdir/pending/${date_s}-${id}.md"
  [ -e "$file" ] && return 1
  title=$(printf '%s' "$text" | cut -c1-120 2>/dev/null) || title="$text"
  {
    printf -- '---\n'
    printf 'id: %s\n' "$id"
    printf 'status: proposed\n'
    printf 'created: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
    printf 'source: session-save\n'
    printf 'source-note: %s\n' "$(basename "$note" 2>/dev/null || printf '%s' "$note")"
    printf -- 'tags:\n  - pending\n  - auto-distilled\n---\n\n'
    printf '# %s\n\n' "$title"
    printf 'Next-entrypoint destilado automaticamente da nota de sessão `%s` no closeout (P2 #9, eoc ADR-0007 — thread persiste até `status: dropped` com `dropped-reason:` explícito; nunca evapora por omissão).\n\n' "$(basename "$note" 2>/dev/null || printf '%s' "$note")"
    printf '**Texto original:** %s\n' "$text"
  } > "$file" 2>/dev/null || return 1
  printf '%s\n' "$id"
  return 0
}

_a5_create_rework() {
  # $1=vault $2=linha-evidencia $3=nota-de-origem
  # Mesmo formato do pending (id/status/created), em <vault>/rework/.
  local vdir="$1" evidence="$2" note="$3" id date_s file title
  # A MESMA linha pode conter a admissão de retrabalho E uma atribuição
  # NOME=valor de segredo (gap do recibo A5). Redigir o lado direito de todo
  # "=" ANTES de slugificar/titular/embutir — valor nunca chega ao arquivo.
  # (mesma sed de antes, agora no choke point compartilhado _a5_redact_secrets)
  evidence=$(_a5_redact_secrets "$evidence")
  [ -n "$evidence" ] || evidence="(evidencia redigida)"
  id=$(_a5_slugify "$evidence") || id=""
  [ -n "$id" ] || id="retrabalho"
  _a5_note_exists "$vdir/rework" "$id" && return 1
  mkdir -p "$vdir/rework" 2>/dev/null || return 1
  date_s=$(date +%Y-%m-%d 2>/dev/null) || date_s="unknown-date"
  file="$vdir/rework/${date_s}-${id}.md"
  [ -e "$file" ] && return 1
  title=$(printf '%s' "$evidence" | cut -c1-120 2>/dev/null) || title="$evidence"
  {
    printf -- '---\n'
    printf 'id: %s\n' "$id"
    printf 'status: proposed\n'
    printf 'created: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
    printf 'source: session-save\n'
    printf 'source-note: %s\n' "$(basename "$note" 2>/dev/null || printf '%s' "$note")"
    printf -- 'tags:\n  - rework\n  - auto-distilled\n---\n\n'
    printf '# Retrabalho: %s\n\n' "$title"
    printf 'Admissão de retrabalho detectada automaticamente na nota de sessão `%s` (padrões: "redescobri"/"de novo"/"já estava na memória"/"refiz" — P2 #9, eoc ADR-0007/0012).\n\n' "$(basename "$note" 2>/dev/null || printf '%s' "$note")"
    printf '**Evidência:** %s\n' "$evidence"
  } > "$file" 2>/dev/null || return 1
  printf '%s\n' "$id"
  return 0
}

_a5_secret_evidence() {
  grep -inE 'rotacionar|token vazou|api_key|secret leak' "$1" 2>/dev/null
}

_a5_secret_count() {
  # Quantas linhas-gatilho a nota tem. wc consome tudo — sem head, sem SIGPIPE.
  _a5_secret_evidence "$1" | wc -l | tr -d '[:space:]'
}

_a5_secret_lines() {
  # S4: NUNCA imprimir o token. O extrator antigo de "nomes" ([A-Z][A-Z0-9_]{2,})
  # capturava a própria CHAVE (ex.: AKIA...) e a colava no transcript — o
  # oposto do que o alerta promete. Sai só a lista de números de linha do
  # gatilho; quem lê abre a nota, o log não vaza nada. sed '1,5p' em vez de
  # head: consome o input inteiro (sem SIGPIPE sob pipefail).
  _a5_secret_evidence "$1" | cut -d: -f1 | sed -n '1,5p' | tr '\n' ' ' | sed 's/[[:space:]]*$//'
}

_a5_rework_evidence() {
  grep -inE 'redescobri|de novo|ja estava na memoria|já estava na memória|refiz' "$1" 2>/dev/null \
    | cut -d: -f2-
}

_a5_note_is_fresh() {
  # S3: gate de frescor da nota canônica. `ls -t | head -1` acha a nota MAIS
  # RECENTE do vault, não uma nota DESTA sessão — sem este gate, sessão sem
  # closeout achava nota velha e declarava "PUBLICADO", contradizendo o
  # CLOSEOUT_TODAY=0 calculado acima. Fresca = datada de HOJE (mesma janela
  # UTC do gate CLOSEOUT_TODAY, via prefixo YYYY-MM-DD do nome) OU mtime <12h.
  local note="${1:-}" today="" base="" mtime="" now=""
  [ -n "$note" ] || return 1
  today=$(date -u +%Y-%m-%d 2>/dev/null) || today=""
  base=$(basename "$note" 2>/dev/null) || base=""
  if [ -n "$today" ]; then
    case "$base" in "$today"*) return 0 ;; esac
  fi
  mtime=$(stat -f %m "$note" 2>/dev/null || stat -c %Y "$note" 2>/dev/null || echo "")
  now=$(date +%s 2>/dev/null || echo "")
  case "$mtime$now" in ''|*[!0-9]*) return 1 ;; esac
  [ $((now - mtime)) -lt 43200 ]
}

SESSION_NOTE=""
KERNEL_INTENT=""
KERNEL_PORQUE=""
KERNEL_PROXIMO=""
KERNEL_PRESENT=0
CLOSEOUT_STATUS="none_note"
PENDINGS_CREATED=""
REWORKS_CREATED=0
SECRET_EVIDENCE=""
SECRET_COUNT=0
SECRET_LINES=""

if [ -d "$VAULT_DIR/sessions" ]; then
  SESSION_NOTE=$(ls -t "$VAULT_DIR/sessions" 2>/dev/null | grep '\.md$' | head -1) || SESSION_NOTE=""
  [ -n "$SESSION_NOTE" ] && SESSION_NOTE="$VAULT_DIR/sessions/$SESSION_NOTE"
  [ -n "$SESSION_NOTE" ] && [ -f "$SESSION_NOTE" ] || SESSION_NOTE=""
fi

if [ -n "$SESSION_NOTE" ] && ! _a5_note_is_fresh "$SESSION_NOTE"; then
  # S3: nota canônica existe mas é VELHA — esta sessão fechou sem nota própria.
  # Não parseia kernel nem re-destila pending/rework/segredo de nota antiga
  # (a destilação dela já rodou quando era fresca).
  CLOSEOUT_STATUS="note_stale"
elif [ -n "$SESSION_NOTE" ]; then
  KERNEL_INTENT=$(sed -n 's/^intent:[[:space:]]*//p' "$SESSION_NOTE" 2>/dev/null | head -1) || KERNEL_INTENT=""
  KERNEL_PORQUE=$(sed -n 's/^porque:[[:space:]]*//p' "$SESSION_NOTE" 2>/dev/null | head -1) || KERNEL_PORQUE=""
  KERNEL_PROXIMO=$(sed -n 's/^proximo:[[:space:]]*//p' "$SESSION_NOTE" 2>/dev/null | head -1) || KERNEL_PROXIMO=""

  if [ -n "$KERNEL_INTENT" ] && [ -n "$KERNEL_PORQUE" ] && [ -n "$KERNEL_PROXIMO" ]; then
    KERNEL_PRESENT=1
  else
    # Fallback: contrato Summary/Proof/Next Entrypoint (canuto-brain closeout).
    LEGACY_SUMMARY=$(awk '/^## Summary/{f=1;next} f&&/^#/{exit} f&&NF{print;exit}' "$SESSION_NOTE" 2>/dev/null) || LEGACY_SUMMARY=""
    LEGACY_PROOF=$(awk '/^## Proof/{f=1;next} f&&/^#/{exit} f&&NF{print;exit}' "$SESSION_NOTE" 2>/dev/null) || LEGACY_PROOF=""
    LEGACY_NEXT=$(sed -n 's/^next-entrypoint:[[:space:]]*//p' "$SESSION_NOTE" 2>/dev/null | head -1) || LEGACY_NEXT=""
    LEGACY_NEXT="${LEGACY_NEXT%\"}"; LEGACY_NEXT="${LEGACY_NEXT#\"}"
    if [ -z "$LEGACY_NEXT" ]; then
      LEGACY_NEXT=$(awk '/^## Next Entrypoint/{f=1;next} f&&/^#/{exit} f&&NF{print;exit}' "$SESSION_NOTE" 2>/dev/null) || LEGACY_NEXT=""
    fi
    if [ -n "$LEGACY_SUMMARY" ] && [ -n "$LEGACY_PROOF" ] && [ -n "$LEGACY_NEXT" ]; then
      KERNEL_PRESENT=1
      KERNEL_INTENT="$LEGACY_SUMMARY"
      KERNEL_PORQUE="$LEGACY_PROOF"
      KERNEL_PROXIMO="$LEGACY_NEXT"
    fi
  fi

  # ── Redação dos 3 campos do kernel (review cego 2026-08-02) ───────────────
  # Os campos iam VERBATIM para o evento CLOSEOUT_PUBLISHED e para o stdout do
  # hook: uma nota com "proximo: rotacionar TOKEN=abc123" publicava o valor no
  # events/log.jsonl E no transcript. Redigir AQUI (depois de resolver kernel
  # novo vs. contrato legado, antes de qualquer consumo) cobre os dois braços
  # e também o NEXT_TEXT derivado logo abaixo. A presença do kernel já foi
  # decidida acima com os valores crus — redigir nunca esvazia um campo.
  KERNEL_INTENT=$(_a5_redact_secrets "$KERNEL_INTENT")
  KERNEL_PORQUE=$(_a5_redact_secrets "$KERNEL_PORQUE")
  KERNEL_PROXIMO=$(_a5_redact_secrets "$KERNEL_PROXIMO")

  if [ "$KERNEL_PRESENT" = "1" ]; then
    CLOSEOUT_STATUS="published"
  else
    CLOSEOUT_STATUS="note_no_kernel"
  fi

  # ── Destilação mecânica no mesmo ato (P2 #9) ──────────────────────────────
  NEXT_TEXT="$KERNEL_PROXIMO"
  if [ -z "$NEXT_TEXT" ]; then
    NEXT_TEXT=$(sed -n 's/^next-entrypoint:[[:space:]]*//p' "$SESSION_NOTE" 2>/dev/null | head -1) || NEXT_TEXT=""
    NEXT_TEXT="${NEXT_TEXT%\"}"; NEXT_TEXT="${NEXT_TEXT#\"}"
  fi
  if [ -z "$NEXT_TEXT" ]; then
    NEXT_TEXT=$(awk '/^## Next Entrypoint/{f=1;next} f&&/^#/{exit} f&&NF{print;exit}' "$SESSION_NOTE" 2>/dev/null) || NEXT_TEXT=""
  fi
  NEXT_TEXT_LC=$(printf '%s' "$NEXT_TEXT" | tr '[:upper:]' '[:lower:]')
  case "$NEXT_TEXT_LC" in
    ""|"-"|"none recorded."|"none recorded"|"n/a"|"tbd") NEXT_TEXT="" ;;
  esac
  if [ -n "$NEXT_TEXT" ]; then
    NEW_PENDING_ID=$(_a5_create_pending "$VAULT_DIR" "$NEXT_TEXT" "$SESSION_NOTE" 2>/dev/null) \
      && PENDINGS_CREATED="$NEW_PENDING_ID" || true
  fi

  REWORK_EVIDENCE=$(_a5_rework_evidence "$SESSION_NOTE" 2>/dev/null | head -1) || REWORK_EVIDENCE=""
  if [ -n "$REWORK_EVIDENCE" ]; then
    _a5_create_rework "$VAULT_DIR" "$REWORK_EVIDENCE" "$SESSION_NOTE" >/dev/null 2>&1 \
      && REWORKS_CREATED=1 || true
  fi

  # sed '1,5p' (não head): consome tudo — sem SIGPIPE sob o pipefail do topo.
  SECRET_EVIDENCE=$(_a5_secret_evidence "$SESSION_NOTE" 2>/dev/null | sed -n '1,5p') || SECRET_EVIDENCE=""
  if [ -n "$SECRET_EVIDENCE" ]; then
    SECRET_COUNT=$(_a5_secret_count "$SESSION_NOTE" 2>/dev/null) || SECRET_COUNT=0
    case "$SECRET_COUNT" in ''|*[!0-9]*) SECRET_COUNT=0 ;; esac
    SECRET_LINES=$(_a5_secret_lines "$SESSION_NOTE" 2>/dev/null) || SECRET_LINES=""
  fi
fi

# ── Evento atômico: nota + kernel + destilação são UM ato (ADR-0012) ───────
case "$CLOSEOUT_STATUS" in
  published)
    canuto_event_append CLOSEOUT_PUBLISHED status=published \
      note="$SESSION_NOTE" kernel_intent="$KERNEL_INTENT" \
      kernel_porque="$KERNEL_PORQUE" kernel_proximo="$KERNEL_PROXIMO" \
      pendings_created="$PENDINGS_CREATED" reworks_created="$REWORKS_CREATED" \
      secret_alert="$([ -n "$SECRET_EVIDENCE" ] && echo yes || echo no)" || true
    ;;
  note_no_kernel)
    canuto_event_append CLOSEOUT_PUBLISHED status=incomplete reason=no_kernel \
      note="$SESSION_NOTE" \
      pendings_created="$PENDINGS_CREATED" reworks_created="$REWORKS_CREATED" \
      secret_alert="$([ -n "$SECRET_EVIDENCE" ] && echo yes || echo no)" || true
    ;;
  note_stale)
    # S3: nota mais recente não é desta sessão — closeout AUSENTE, não publicado.
    # `distilled=skipped` é explícito de propósito (review cego 2026-08-02): os
    # campos pendings_created/reworks_created/secret_alert dos outros braços
    # NÃO aparecem aqui porque a destilação nem rodou — a ausência é uma
    # decisão registrada, não um campo esquecido (nada de "0" que se leria como
    # "rodou e não achou nada").
    canuto_event_append CLOSEOUT_PUBLISHED status=stale reason=note_not_fresh \
      distilled=skipped note="$SESSION_NOTE" || true
    ;;
esac

# ── ALERTA DE SEGREDO no topo da saída (S4: nem nome nem valor no log — só
# contagem + arquivo:linha; o extrator antigo de "nomes" imprimia a chave) ──
if [ -n "$SECRET_EVIDENCE" ]; then
  echo ""
  echo "🚨 ALERTA — nota de sessão menciona rotação/vazamento de segredo."
  echo "   ${SECRET_COUNT:-1} possível(is) referência(s) a segredo — ver a nota (nada é copiado para este log)."
  echo "   Nota: $SESSION_NOTE${SECRET_LINES:+ (linha(s): $SECRET_LINES)}"
  echo "   NUNCA cole o valor do segredo aqui. Rotacione e confirme direto na nota."
fi

# ── Output reminder (visible to user) ───────────────────────────────────────
echo ""
echo "════════════════════════════════════════"
echo "  Canuto — Session State Saved"
echo "════════════════════════════════════════"
echo "  Snapshot: $VAULT_DIR/.snapshots/$TIMESTAMP"
echo ""
if [ "${CLOSEOUT_TODAY:-0}" = "0" ] || [ -z "${CLOSEOUT_TODAY:-}" ]; then
  echo "  ⚠ GATE: nenhum evento CLOSEOUT registrado hoje em"
  echo "  ${EVENT_LOG_PATH:-events/log.jsonl}."
  echo "  A sessão está fechando SEM closeout do learning loop."
  echo "  Rode canuto-session-end-learning e registre com:"
  echo "  bash .agents/tools/event-log.sh append CLOSEOUT actor=maestro"
else
  echo "  ✓ CLOSEOUT registrado hoje ($CLOSEOUT_TODAY evento(s)) — learning loop ok."
fi
echo ""
case "$CLOSEOUT_STATUS" in
  published)
    echo "  ✓ CLOSEOUT PUBLICADO — kernel de intenção presente na nota canônica:"
    echo "    nota:    $SESSION_NOTE"
    echo "    intent:  $KERNEL_INTENT"
    echo "    porque:  $KERNEL_PORQUE"
    echo "    proximo: $KERNEL_PROXIMO"
    ;;
  note_no_kernel)
    echo "  ⚠ closeout sem intent kernel — memória write-only."
    echo "    nota: $SESSION_NOTE"
    echo "    Adicione intent:/porque:/proximo: (ou Summary/Proof/Next Entrypoint completos)."
    ;;
  note_stale)
    echo "  ⚠ nota canônica mais recente é ANTIGA (não é de hoje/12h) — closeout DESTA sessão ausente."
    echo "    nota antiga: $SESSION_NOTE"
    echo "    Rode: canuto-brain closeout --project <slug> --title <t> --summary <s> --next <proximo>"
    ;;
  none_note)
    echo "  ⚠ nenhuma nota canônica de sessão encontrada em $VAULT_DIR/sessions/."
    echo "    Rode: canuto-brain closeout --project <slug> --title <t> --summary <s> --next <proximo>"
    ;;
esac
[ -n "$PENDINGS_CREATED" ] && echo "  + pending auto-criado (status: proposed): $PENDINGS_CREATED"
[ "$REWORKS_CREATED" != "0" ] && echo "  + retrabalho detectado e registrado em $VAULT_DIR/rework/ (status: proposed)"
echo "════════════════════════════════════════"
echo ""
