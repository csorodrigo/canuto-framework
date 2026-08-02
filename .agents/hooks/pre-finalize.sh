#!/usr/bin/env bash
# Stop hook - report files still waiting for validation.

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
export CANUTO_OTEL_HOOK_SOURCE="pre-finalize"

# ── Ledger de delegação (Fase 2, A2b): mesma cascata fail-loud dos demais
# hooks. Ausência da lib nunca bloqueia o Stop — só significa "sem
# visibilidade de pendência de delegação" (delegation_ledger_pending vira
# no-op). Ver .agents/tools/delegation-ledger.sh para o fold e o porquê de
# "recibo != resposta" (voz.py / ADR-0017 / ADR-0018 do edge-of-chaos).
#
# Faltava o degrau GLOBAL (~/.canuto/lib) — o mesmo que install.sh popula
# (install_global_fallback_libs) para repo consumidor com install antigo:
# sem ele a cascata pulava direto para o stub e o Stop hook perdia o ledger
# EM SILÊNCIO em qualquer projeto sem a lib no repo (review cego 2026-08-02;
# é o buraco que deixou o event log morto em ~90% dos consumidores).
_canuto_missing_lib_note() {
  # Degradação nunca silenciosa (convenções Fase 2): registra a ausência UMA
  # vez por sessão (marker em TMPDIR) em ~/.canuto/vault/_health/. Best-effort
  # em cada passo — nada aqui pode falhar o Stop.
  local marker cwd_s
  marker="${TMPDIR:-/tmp}/canuto-missing-ledgerlib-${CLAUDE_SESSION_ID:-$PPID}-$1"
  [ -e "$marker" ] && return 0
  : >"$marker" 2>/dev/null || true
  mkdir -p "$HOME/.canuto/vault/_health" 2>/dev/null || return 0
  cwd_s=$(pwd 2>/dev/null || echo unknown)
  cwd_s=$(printf '%s' "$cwd_s" | tr -d '"\\' 2>/dev/null || echo unknown)
  printf '{"ts":"%s","hook":"%s","cwd":"%s","reason":"delegation-ledger-lib-missing"}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" "$1" "$cwd_s" \
    >>"$HOME/.canuto/vault/_health/missing-lib.jsonl" 2>/dev/null || true
  return 0
}
if [ -f "$SCRIPT_DIR/../tools/delegation-ledger.sh" ]; then
  # shellcheck source=../tools/delegation-ledger.sh
  . "$SCRIPT_DIR/../tools/delegation-ledger.sh" 2>/dev/null || true
elif [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "$CLAUDE_PROJECT_DIR/.agents/tools/delegation-ledger.sh" ]; then
  # shellcheck source=/dev/null
  . "$CLAUDE_PROJECT_DIR/.agents/tools/delegation-ledger.sh" 2>/dev/null || true
elif [ -f "$HOME/.canuto/lib/delegation-ledger.sh" ]; then
  # shellcheck source=/dev/null
  . "$HOME/.canuto/lib/delegation-ledger.sh" 2>/dev/null || true
fi
if ! type delegation_ledger_pending >/dev/null 2>&1; then
  delegation_ledger_pending() { _canuto_missing_lib_note "pre-finalize"; return 0; }
fi

emit_hook_otel() {
  local outcome="$1"
  local pending_count="${2:-0}"
  {
    CANUTO_OTEL_PENDING_COUNT="$pending_count" otel_emit_span "hook.pre_finalize" "$outcome" 0
    otel_emit_counter "hook.pre_finalize" "$outcome"
  } || true
}

# Sem payload num TTY: `cat` sem stdin fechado bloqueia para sempre e o
# runtime que espera o hook congela junto (regra de TTY/pipe do CLAUDE.md).
INPUT=""
[ -t 0 ] || INPUT=$(cat)
stop_active=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null); [ "$stop_active" = "true" ] && { emit_hook_otel "success"; exit 0; }

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd -P || pwd)"
AUDIT_DIR="$PROJECT_DIR/.agents/vault/audit"
PENDING_FILE="$AUDIT_DIR/validation-pending.json"
RETRY_FILE="$AUDIT_DIR/retry-counter.json"

init_storage() {
  mkdir -p "$AUDIT_DIR" 2>/dev/null || return 1
  for f in "$PENDING_FILE" "$RETRY_FILE"; do
    if [ ! -f "$f" ] || ! jq -e type "$f" >/dev/null 2>&1; then
      (printf '{}\n' > "$f") 2>/dev/null || return 1
    fi
  done
}

validation_pending_count=0
if init_storage && jq -e 'length > 0' "$PENDING_FILE" >/dev/null 2>&1; then
  files=$(jq -r 'keys[:5] | join(", ")' "$PENDING_FILE" 2>/dev/null) || files=""
  [ -n "$files" ] && printf '[pre-finalize] pending validation for: %s\n' "$files"
  validation_pending_count=$(jq -r 'length' "$PENDING_FILE" 2>/dev/null) || validation_pending_count=0
fi

# ── Pendências de delegação (fold sobre delegate-metrics.jsonl + event log —
# ver delegation-ledger.sh). "recibo != resposta": um aviso do
# postdelegate-verify.sh NÃO resolve a pendência, só dead-letter (com razão)
# ou fallback declarado resolvem — por isso cada id pendente é listado aqui
# com as DUAS opções legais (nunca um "há pendências" genérico).
#
# ESCOPO: as métricas são GLOBAIS (~/.codex/delegate-metrics.jsonl) mas o
# fechamento é por projeto (event log do projeto). Sem filtro, todo projeto
# listava o backlog global inteiro no primeiro Stop e um dead-letter feito no
# projeto B nunca fechava a linha no projeto A (review cego 2026-08-02). O
# ledger filtra por `cwd` da métrica; o cabeçalho abaixo DIZ isso, para que o
# recorte não seja uma omissão silenciosa.
delegation_pending_count=0
delegation_lines=$(delegation_ledger_pending 2>/dev/null) || delegation_lines=""
if [ -n "$delegation_lines" ]; then
  printf '[pre-finalize] delegações pendentes DESTE projeto (sem dead-letter nem fallback declarado; CANUTO_LEDGER_ALL=1 lista todos os projetos):\n'
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    delegation_pending_count=$((delegation_pending_count + 1))
    id="${line%%$'\t'*}"
    printf '  - %s\n' "$line"
    printf '      PARK:     delegation_dead_letter %s "<razao>"\n' "$id"
    printf '      FALLBACK: delegation_declare_fallback %s claude-direct\n' "$id"
  done < <(printf '%s\n' "$delegation_lines")
fi

pending_count=$((validation_pending_count + delegation_pending_count))
if [ "$pending_count" -gt 0 ]; then
  emit_hook_otel "pending" "$pending_count"
else
  emit_hook_otel "success"
fi

exit 0
