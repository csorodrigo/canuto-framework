#!/usr/bin/env bash
# delegation-ledger.sh — ledger de pendências de delegação (Fase 2, A2b).
#
# Absorvido do edge-of-chaos tools/voz.py (clone /tmp/eoc-1785628969) e dos
# ADRs 0017/0018 do mesmo repo: uma pendência é um FOLD sobre o log, nunca uma
# flag guardada. "recibo != resposta" (voz.py: um receipt_sent não fecha um
# comentário) vira aqui "registrar não resolve": só dead-letter (com razão) ou
# fallback declarado fecham. Um autônomo só pode PARKEAR, nunca fabricar um
# fechamento sem razão (ADR-0017: "an autonomous grill may only park, never
# fabricate acknowledged").
#
# Auditoria 2026-08-01: 42 falhas de delegação Codex geraram só 3 declarações
# de fallback nos transcripts — a regra "fallback nunca é silencioso" não se
# sustentava como prompt. Este ledger torna a pendência MECÂNICA: derivada a
# cada chamada do delegate-metrics.jsonl (fonte de verdade — ver
# .agents/tools/codex-delegate.sh:emit_metric) cruzado com o event log do
# projeto (.agents/tools/event-log.sh).
#
# ── Escolha de ID (documentada, não óbvia) ───────────────────────────────────
# delegate-metrics.jsonl não tem um id explícito por linha (é um NDJSON de
# métricas append-only, uma linha por chamada do wrapper). Este ledger usa
# `ts` (o timestamp ISO8601 UTC que emit_metric grava) COMO id. Trade-off
# aceito e documentado: duas delegações que caem no MESMO segundo colidem de
# id — dado o volume real (auditoria: unidades por sessão), o risco é baixo e
# preferível a inventar um id sintético que não sobrevive a re-leitura do
# arquivo. `delegation_dead_letter`/`delegation_declare_fallback` recebem esse
# mesmo `ts` como <id> (é o primeiro campo de cada linha impressa por
# delegation_ledger_pending).
#
# ── Regra de fechamento ───────────────────────────────────────────────────────
# Uma métrica com result != "OK" está PENDENTE até que o event log do projeto
# tenha, para o MESMO id (campo `id` do evento), um evento posterior:
#   - DELEGATION_DEAD_LETTER (via delegation_dead_letter)  — park, razão obrigatória
#   - FALLBACK_DECLARED      (via delegation_declare_fallback) — fallback declarado
#   - DELEGATION_RESOLVED    (reservado; qualquer emissor externo que feche o id)
# Nenhum outro evento fecha — em particular o evento genérico `DELEGATION` que
# codex-delegate.sh e postdelegate-verify.sh já emitem a cada chamada NÃO
# fecha nada aqui (é telemetria de execução, não disposição da pendência).
#
# ── Caps de leitura (padrão eoc tools/cortex_usage.py: USAGE_READ_CAP=5000,
# USAGE_READ_BYTES=8MB) ───────────────────────────────────────────────────────
# Nunca lê o arquivo inteiro: tail dos últimos 8MB, depois das últimas 5000
# linhas dentro disso. Um metrics.jsonl gigante NUNCA pode virar dependência
# bloqueante do Stop hook. Mesmo cap aplicado (defensivamente, além do que a
# spec exige) à leitura do event log.
#
# Linha malformada (não fecha em `{...}`, ou sem `ts`/`result` parseável) =
# skip silencioso — nunca aborta o fold (mesma postura de _read_tail_lines do
# eoc: um registro ruim não pode derrubar quem lê a cauda).
#
# ── Escopo de projeto (review cego 2026-08-02) ───────────────────────────────
# As métricas são GLOBAIS (~/.codex/delegate-metrics.jsonl, uma linha por
# chamada do wrapper em QUALQUER repo) mas o fechamento é POR PROJETO (o event
# log vive em <vault>/<slug>/events/log.jsonl). Sem recorte, dois defeitos
# reais: (a) todo projeto listava o backlog global inteiro no primeiro Stop;
# (b) um dead-letter feito no projeto B nunca fechava a mesma linha no projeto
# A — pendência imortal. Por default o fold só considera as linhas cujo campo
# `cwd` é o ROOT do projeto atual ou um subdiretório dele.
#   CANUTO_LEDGER_ALL=1  → desliga o filtro (backlog global, para auditoria).
#   CANUTO_LEDGER_ROOT   → força o root (testes / uso fora de repo git).
# LIMITAÇÃO CONHECIDA E ACEITA: linhas ANTIGAS (ou de wrappers que não gravam
# `cwd`) não têm o campo — são tratadas como FORA do projeto e somem do fold
# por default. É a escolha conservadora (nunca atribuir a este projeto uma
# falha que pode ser de outro); `CANUTO_LEDGER_ALL=1` recupera todas, e o
# número de linhas omitidas vai para stderr — o recorte nunca é silencioso.
#
# Bash 3.2 (macOS): sem arrays associativos, sem ${var,,}, sem mapfile.
# jq se existir (preferido); sem jq, fallback sed de melhor esforço (só
# valores string simples, sem escapes complexos — aceitável para este ledger).
# Nunca falha o chamador quando usado como biblioteca (nenhuma função aqui
# mata o processo; erros de uso retornam código != 0 para quem chamou decidir).
#
# Uso como biblioteca:
#   source .agents/tools/delegation-ledger.sh
#   delegation_ledger_pending [--since <iso8601>]
#   delegation_dead_letter <id> <razao>
#   delegation_declare_fallback <id> <executor-real>
#
# Uso como CLI:
#   bash delegation-ledger.sh pending [--since <iso8601>]
#   bash delegation-ledger.sh dead-letter <id> <razao>
#   bash delegation-ledger.sh declare-fallback <id> <executor-real>
#   bash delegation-ledger.sh metrics-path        # debug: caminho resolvido do metrics

_CANUTO_LEDGER_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}" 2>/dev/null)" 2>/dev/null && pwd)"

# ── Lib de event log: mesma cascata fail-loud dos hooks (Track A/D 2026-08-01):
# repo (relativo a este arquivo) → repo (projeto atual) → lib global ~/.canuto/lib
# → stub que REGISTRA a ausência em vez de silenciar (canuto_event_append vira
# um no-op que anota em ~/.canuto/vault/_health/missing-lib.jsonl).
if [ -n "$_CANUTO_LEDGER_LIB_DIR" ] && [ -f "$_CANUTO_LEDGER_LIB_DIR/event-log.sh" ]; then
  # shellcheck source=event-log.sh
  . "$_CANUTO_LEDGER_LIB_DIR/event-log.sh" 2>/dev/null || true
elif [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -f "$CLAUDE_PROJECT_DIR/.agents/tools/event-log.sh" ]; then
  # shellcheck source=/dev/null
  . "$CLAUDE_PROJECT_DIR/.agents/tools/event-log.sh" 2>/dev/null || true
elif [ -f "$HOME/.canuto/lib/event-log.sh" ]; then
  # shellcheck source=/dev/null
  . "$HOME/.canuto/lib/event-log.sh" 2>/dev/null || true
fi
if ! type canuto_event_append >/dev/null 2>&1; then
  canuto_event_append() {
    mkdir -p "$HOME/.canuto/vault/_health" 2>/dev/null || return 0
    printf '{"ts":"%s","missing":"event-log.sh","consumer":"delegation-ledger.sh","project":"%s"}\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${CLAUDE_PROJECT_DIR:-$(pwd)}" \
      >> "$HOME/.canuto/vault/_health/missing-lib.jsonl" 2>/dev/null || true
    return 0
  }
fi
if ! type canuto_event_log_path >/dev/null 2>&1; then
  canuto_event_log_path() {
    printf '%s/.agents/.cache/events/log.jsonl\n' "${CLAUDE_PROJECT_DIR:-$(pwd)}"
  }
fi

# ── Caps de leitura ───────────────────────────────────────────────────────────
_DELEGATION_LEDGER_READ_CAP_LINES=5000
_DELEGATION_LEDGER_READ_CAP_BYTES=$((8 * 1024 * 1024))

# _delegation_ledger_read_capped <arquivo>
# Tail duplo (bytes, depois linhas) — nunca carrega o arquivo inteiro. Arquivo
# ausente = fold vazio, nunca erro.
_delegation_ledger_read_capped() {
  local file="$1"
  [ -n "$file" ] && [ -f "$file" ] || return 0
  tail -c "$_DELEGATION_LEDGER_READ_CAP_BYTES" "$file" 2>/dev/null \
    | tail -n "$_DELEGATION_LEDGER_READ_CAP_LINES" 2>/dev/null
}

# _delegation_ledger_json_field <linha> <chave>
# Valor (string) de um campo top-level, ou vazio. jq quando disponível; sem
# jq, sed de melhor esforço (só valores string simples, sem \" internos).
_delegation_ledger_json_field() {
  local line="$1" key="$2"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$line" | jq -r --arg k "$key" '.[$k] // empty' 2>/dev/null
    return 0
  fi
  printf '%s' "$line" | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" | head -1
}

# _delegation_ledger_metrics_path
_delegation_ledger_metrics_path() {
  printf '%s\n' "${CANUTO_METRICS_FILE:-$HOME/.codex/delegate-metrics.jsonl}"
}

# _delegation_ledger_project_root
# Root do projeto atual, nas DUAS formas (lógica e resolvida com pwd -P),
# separadas por tab. Duas porque o `cwd` gravado na métrica é o $PWD cru do
# wrapper: pode ser o caminho com symlink (/var/...) enquanto o root resolve
# para o real (/private/var/...) — comparar só uma das formas perderia
# pendência legítima. Ausência de git/CLAUDE_PROJECT_DIR cai em pwd.
_delegation_ledger_project_root() {
  local root real
  root="${CANUTO_LEDGER_ROOT:-${CLAUDE_PROJECT_DIR:-}}"
  if [ -z "$root" ]; then
    root="$(git rev-parse --show-toplevel 2>/dev/null)" || root=""
  fi
  [ -n "$root" ] || root="$(pwd 2>/dev/null)" || root=""
  real="$( (cd "$root" 2>/dev/null && pwd -P) 2>/dev/null )" || real=""
  [ -n "$real" ] || real="$root"
  printf '%s\t%s\n' "$root" "$real"
}

# _delegation_ledger_closed_ids
# Imprime, delimitado por "|" (formato "|id1|id2|"), os ids já FECHADOS —
# eventos DELEGATION_DEAD_LETTER, FALLBACK_DECLARED ou DELEGATION_RESOLVED
# encontrados no event log do projeto, cada um com campo `id`. String vazia
# vira "|" (nenhum id fechado); o teste de pertencimento em
# delegation_ledger_pending usa `case "$closed" in *"|$ts|"*)`.
_delegation_ledger_closed_ids() {
  local log_path ids line ev id
  log_path="$(canuto_event_log_path 2>/dev/null)" || log_path=""
  ids="|"
  if [ -n "$log_path" ] && [ -f "$log_path" ]; then
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      case "$line" in \{*\}) : ;; *) continue ;; esac
      ev=$(_delegation_ledger_json_field "$line" event)
      case "$ev" in
        DELEGATION_DEAD_LETTER|FALLBACK_DECLARED|DELEGATION_RESOLVED) : ;;
        *) continue ;;
      esac
      id=$(_delegation_ledger_json_field "$line" id)
      [ -n "$id" ] || continue
      ids="${ids}${id}|"
    done < <(_delegation_ledger_read_capped "$log_path")
  fi
  printf '%s' "$ids"
}

# delegation_ledger_pending [--since <iso8601>]
# Fold puro: uma linha por delegação PENDENTE (result != "OK" na métrica E sem
# fechamento posterior no event log). Formato de saída (tab-separated):
#   <id=ts>\trole=<role>\tresult=<result>\treason=<reason>\tout=<out-file>
# Nunca mantém estado/cursor próprio — recalculado a cada chamada.
delegation_ledger_pending() {
  local since="" arg
  while [ $# -gt 0 ]; do
    arg="$1"
    case "$arg" in
      --since)
        since="${2:-}"
        shift 2 2>/dev/null || shift $#
        ;;
      --since=*)
        since="${arg#--since=}"
        shift
        ;;
      *)
        shift
        ;;
    esac
  done

  local metrics_file closed line ts result role reason out
  local root_logical="" root_real="" cwd="" off_project=0
  metrics_file="$(_delegation_ledger_metrics_path)"
  [ -f "$metrics_file" ] || return 0

  # Recorte por projeto (ver cabeçalho). CANUTO_LEDGER_ALL=1 deixa os dois
  # roots vazios, o que desliga o filtro no loop abaixo.
  if [ "${CANUTO_LEDGER_ALL:-0}" != "1" ]; then
    IFS=$'\t' read -r root_logical root_real < <(_delegation_ledger_project_root) || true
    # Nunca deixar UM dos dois vazio: um padrão vazio no `case` casaria com
    # cwd vazio e reabriria justamente o buraco do "cwd ausente".
    [ -n "$root_logical" ] || root_logical="$root_real"
    [ -n "$root_real" ] || root_real="$root_logical"
  fi

  closed="$(_delegation_ledger_closed_ids)"

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in \{*\}) : ;; *) continue ;; esac
    ts=$(_delegation_ledger_json_field "$line" ts)
    result=$(_delegation_ledger_json_field "$line" result)
    [ -n "$ts" ] && [ -n "$result" ] || continue
    [ "$result" = "OK" ] && continue
    if [ -n "$since" ] && [[ "$ts" < "$since" ]]; then
      continue
    fi
    if [ -n "$root_logical" ] || [ -n "$root_real" ]; then
      # `cwd` ausente = linha antiga/de wrapper sem o campo: fora do projeto
      # (escolha conservadora documentada no cabeçalho), mas CONTADA para o
      # aviso de stderr — omissão silenciosa é o que a Fase 2 proíbe.
      cwd=$(_delegation_ledger_json_field "$line" cwd)
      case "$cwd" in
        "$root_logical"|"$root_logical"/*|"$root_real"|"$root_real"/*) : ;;
        *) off_project=$((off_project + 1)); continue ;;
      esac
    fi
    case "$closed" in
      *"|$ts|"*) continue ;;
    esac
    role=$(_delegation_ledger_json_field "$line" role)
    reason=$(_delegation_ledger_json_field "$line" reason)
    out=$(_delegation_ledger_json_field "$line" out)
    printf '%s\trole=%s\tresult=%s\treason=%s\tout=%s\n' \
      "$ts" "${role:-?}" "$result" "${reason:-n/d}" "${out:-n/d}"
  done < <(_delegation_ledger_read_capped "$metrics_file")

  # O recorte por projeto nunca é silencioso: stdout continua sendo SÓ
  # pendências (uma por linha — o pre-finalize parseia linha a linha), então o
  # aviso vai por stderr.
  if [ "$off_project" -gt 0 ]; then
    printf '[delegation-ledger] %s falha(s) de delegação omitida(s) por serem de outro cwd (ou sem campo cwd). CANUTO_LEDGER_ALL=1 lista todas.\n' \
      "$off_project" >&2
  fi

  return 0
}

# delegation_dead_letter <id> <razao>
# PARK. Razão obrigatória e não-vazia (só espaço não conta) — senão exit 1 com
# mensagem em stderr (ADR-0017: "an autonomous grill may only park, never
# fabricate acknowledged" — sem razão, não há park válido). Emite
# DELEGATION_DEAD_LETTER; a próxima chamada de delegation_ledger_pending já
# não lista mais este id.
delegation_dead_letter() {
  local id="${1:-}" reason="${2:-}" trimmed

  if [ -z "$id" ]; then
    echo "uso: delegation_dead_letter <id> <razao>" >&2
    return 64
  fi
  trimmed="$(printf '%s' "$reason" | tr -d '[:space:]')"
  if [ -z "$trimmed" ]; then
    echo "delegation_dead_letter: razao obrigatoria e nao-vazia (id=$id)" >&2
    return 1
  fi

  canuto_event_append DELEGATION_DEAD_LETTER actor="${CANUTO_LEDGER_ACTOR:-cli}" \
    id="$id" reason="$reason"
  return 0
}

# delegation_declare_fallback <id> <executor-real>
# FALLBACK declarado (o ato mecânico que fecha "fallback nunca é silencioso").
# Executor obrigatório e não-vazio — sem ele a declaração não diz quem
# realmente fez o trabalho, que é o ponto inteiro da regra.
delegation_declare_fallback() {
  local id="${1:-}" executor="${2:-}"

  if [ -z "$id" ] || [ -z "$executor" ]; then
    echo "uso: delegation_declare_fallback <id> <executor-real>" >&2
    return 64
  fi

  canuto_event_append FALLBACK_DECLARED actor="${CANUTO_LEDGER_ACTOR:-cli}" \
    id="$id" executor="$executor"
  return 0
}

# ── CLI ─────────────────────────────────────────────────────────────────────
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  _cmd="${1:-}"
  shift 2>/dev/null || true
  case "$_cmd" in
    pending)
      delegation_ledger_pending "$@"
      exit $?
      ;;
    dead-letter)
      delegation_dead_letter "$@"
      exit $?
      ;;
    declare-fallback)
      delegation_declare_fallback "$@"
      exit $?
      ;;
    metrics-path)
      _delegation_ledger_metrics_path
      exit 0
      ;;
    *)
      echo "uso: delegation-ledger.sh pending [--since <iso8601>] | dead-letter <id> <razao> | declare-fallback <id> <executor-real> | metrics-path" >&2
      exit 64
      ;;
  esac
fi
