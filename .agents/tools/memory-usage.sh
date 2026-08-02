#!/usr/bin/env bash
# memory-usage.sh — telemetria IMPLÍCITA de uso das notas do vault (Fase 2, A4).
#
# Absorvido do edge-of-chaos `tools/cortex_usage.py` (REQUISITES F7/N3/N4).
# Responde a uma pergunta que o vault não sabia responder: das notas que o
# briefing mostra, QUAIS o agente de fato usou? Sem isso, "pending" e
# "instincts" só sabem ordenar por mtime — e mtime mede quando alguém ESCREVEU,
# nunca o que se provou útil.
#
# INVARIANTES DE GOVERNANÇA (eoc N4 — este store NÃO é self-state):
#   - Store SEPARADO: <vault>/projects/<slug>/_usage/usage.jsonl. NUNCA o event
#     log (<vault>/projects/<slug>/events/log.jsonl), que é a fonte de verdade
#     append-only. Telemetria não pode virar evento nem reescrever a memória.
#   - Fora do caminho crítico: `canuto_usage_record` é best-effort e NUNCA falha
#     o chamador. Por isso NÃO usa o mkdir-lock do event-log.sh: perder uma
#     linha de telemetria numa corrida é aceitável (o sinal é estatístico e
#     reconciliável a zero); perder um EVENTO não é. Lock aqui só compraria
#     latência no caminho de abertura da sessão.
#   - RANQUEIA-ANTES-DE-GRAVAR (eoc N3): quem chama ordena com
#     `canuto_usage_rerank` PRIMEIRO e só então grava com `canuto_usage_record`.
#     A leitura de agora nunca reforça a própria ordem — senão o briefing
#     viraria uma profecia auto-realizável (o que foi mostrado sobe porque foi
#     mostrado). session-start.sh respeita essa ordem: compõe (que ranqueia) e
#     grava depois.
#   - Store frio/corrompido == sem sinal == ordem de entrada. Nunca erro.
#
# Uso como biblioteca:
#   source .agents/tools/memory-usage.sh
#   printf '%s\n' pending:a.md pending:b.md | canuto_usage_rerank meu-slug
#   canuto_usage_record meu-slug pending:a.md instinct:x.md
#
# Uso como CLI:
#   bash memory-usage.sh record <slug> <ref...>
#   bash memory-usage.sh rerank <slug>   # refs por stdin, uma por linha
#   bash memory-usage.sh path <slug>
#
# Bash 3.2 compatible (macOS): sem arrays associativos, sem mapfile.

# ── Caps duros (eoc Slice-3: nenhum caminho pode virar dependência bloqueante) ─
CANUTO_USAGE_MAX_REFS=64            # refs por linha gravada
CANUTO_USAGE_MAX_REF_LEN=256        # chars por ref (truncagem, não descarte)
CANUTO_USAGE_READ_LINES=2000        # cauda lida no rerank
CANUTO_USAGE_READ_BYTES=4194304     # 4MB — teto de bytes lidos da cauda
CANUTO_USAGE_FUTURE_SKEW_S=300      # ts no futuro além disso = relógio torto
CANUTO_USAGE_HALFLIFE_DEFAULT_S=604800  # 7 dias (eoc R5: recência é 1ª classe)

_canuto_usage_halflife() {
  # Meia-vida em segundos. Valor não-inteiro/zero/negativo NÃO é honrado: uma
  # meia-vida negativa inverteria a recência (o velho pontuaria mais que o
  # novo), então cai no default seguro em vez de obedecer.
  local raw="${CANUTO_USAGE_HALFLIFE_S:-}"
  case "$raw" in
    ''|*[!0-9]*) printf '%s\n' "$CANUTO_USAGE_HALFLIFE_DEFAULT_S"; return 0 ;;
  esac
  if [ "$raw" -gt 0 ] 2>/dev/null; then
    printf '%s\n' "$raw"
  else
    printf '%s\n' "$CANUTO_USAGE_HALFLIFE_DEFAULT_S"
  fi
}

_canuto_usage_store_compute() {
  # Seta _CANUTO_USAGE_STORE SEM subshell de captura — o caminho de abertura de
  # sessão paga ~30-50ms por fork num Mac sob pressão, e este valor é
  # consultado antes de qualquer decisão. Vazio = slug inutilizável.
  # Slug com qualquer caractere fora de [A-Za-z0-9._-] (barra, "..", espaço) é
  # REJEITADO: o único jeito de este módulo escrever fora do próprio diretório
  # seria travessia no slug.
  local slug="${1:-}"
  _CANUTO_USAGE_STORE=""
  [ -n "$slug" ] || return 0
  case "$slug" in
    .|..|*[!A-Za-z0-9._-]*) return 0 ;;
  esac
  _CANUTO_USAGE_STORE="${CANUTO_VAULT_DIR:-$HOME/.canuto/vault}/projects/$slug/_usage/usage.jsonl"
  return 0
}

canuto_usage_store() {
  _canuto_usage_store_compute "${1:-}"
  printf '%s\n' "${_CANUTO_USAGE_STORE:-}"
}

_canuto_usage_escape() {
  # Trunca (expansão pura — multibyte-safe, sem fork de cut) e escapa para
  # valor JSON: remove controles, escapa \ e ".
  local v="${1:-}"
  v="${v:0:${CANUTO_USAGE_MAX_REF_LEN}}"
  printf '%s' "$v" | tr -d '\000-\037' | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' 2>/dev/null || true
}

# canuto_usage_record <slug> <ref...>
# Append de UMA linha {"ts":<epoch>,"refs":[...]}. Sempre retorna 0.
canuto_usage_record() {
  local slug="${1:-}"
  shift 2>/dev/null || true
  local store="" ts="" refs_json="" ref="" esc="" n=0

  _canuto_usage_store_compute "$slug"
  store="${_CANUTO_USAGE_STORE:-}"
  [ -n "$store" ] || return 0
  # Cinto de segurança do invariante N4: o store jamais mora no diretório do
  # event log. Estruturalmente impossível (o path é fixo em _usage/), mas a
  # checagem documenta a fronteira em código, não só em comentário.
  case "$store" in */events/*) return 0 ;; esac
  [ "$#" -gt 0 ] || return 0

  ts=$(date +%s 2>/dev/null || true)
  case "$ts" in ''|*[!0-9]*) return 0 ;; esac

  for ref in "$@"; do
    [ -n "$ref" ] || continue
    [ "$n" -lt "$CANUTO_USAGE_MAX_REFS" ] || break
    esc=$(_canuto_usage_escape "$ref")
    [ -n "$esc" ] || continue
    if [ "$n" -eq 0 ]; then
      refs_json="\"$esc\""
    else
      refs_json="$refs_json,\"$esc\""
    fi
    n=$((n + 1))
  done
  [ "$n" -gt 0 ] || return 0

  mkdir -p "$(dirname "$store")" 2>/dev/null || return 0
  printf '{"ts":%s,"refs":[%s]}\n' "$ts" "$refs_json" >> "$store" 2>/dev/null || true
  return 0
}

# canuto_usage_rerank <slug>
# stdin: uma ref por linha (ordem de entrada = ordem base).
# stdout: as MESMAS refs reordenadas por score de uso (recência+frequência,
# meia-vida 7d), decrescente. SORT ESTÁVEL: ref sem uso mantém a posição
# relativa de entrada (score 0 desempata pelo índice de entrada), então store
# frio == ordem de entrada, exatamente como o eoc rerank().
# Nunca perde nem inventa linha: qualquer anomalia devolve a entrada intacta.
canuto_usage_rerank() {
  local slug="${1:-}"
  local store="" tmp_in="" tmp_store="" now="" hl="" ranked="" n_in=0 n_out=0

  # Store frio ANTES de qualquer fork: sem sinal, o rerank é um `cat` e não
  # deve custar mktemp/date/rm no caminho de abertura da sessão.
  _canuto_usage_store_compute "$slug"
  store="${_CANUTO_USAGE_STORE:-}"
  if [ -z "$store" ] || [ ! -s "$store" ]; then
    cat 2>/dev/null || true
    return 0
  fi

  tmp_in=$(mktemp "${TMPDIR:-/tmp}/canuto-usage-in.XXXXXX" 2>/dev/null || true)
  if [ -z "$tmp_in" ] || [ ! -f "$tmp_in" ]; then
    # Sem tmp não dá para reler a entrada: passa adiante sem reordenar.
    cat 2>/dev/null || true
    return 0
  fi
  cat > "$tmp_in" 2>/dev/null || true

  now=$(date +%s 2>/dev/null || true)
  hl=$(_canuto_usage_halflife)
  case "$now" in ''|*[!0-9]*) now="" ;; esac

  if [ -z "$now" ] || ! command -v awk >/dev/null 2>&1; then
    cat "$tmp_in" 2>/dev/null || true
    rm -f "$tmp_in" 2>/dev/null || true
    return 0
  fi

  tmp_store=$(mktemp "${TMPDIR:-/tmp}/canuto-usage-tail.XXXXXX" 2>/dev/null || true)
  if [ -z "$tmp_store" ] || [ ! -f "$tmp_store" ]; then
    cat "$tmp_in" 2>/dev/null || true
    rm -f "$tmp_in" 2>/dev/null || true
    return 0
  fi
  # Cauda dupla: teto de BYTES antes do teto de LINHAS — uma linha corrompida
  # gigante (sem \n) nunca é lida inteira. O primeiro registro pode sair
  # cortado ao meio; ele simplesmente não casa o regex e é descartado.
  tail -c "$CANUTO_USAGE_READ_BYTES" "$store" 2>/dev/null \
    | tail -n "$CANUTO_USAGE_READ_LINES" > "$tmp_store" 2>/dev/null || true

  # score(ref) = Σ exp(-idade/meia-vida * ln2) sobre os registros anteriores.
  # Linha malformada / ts não-numérico / ts no futuro (>skew) = SKIP: relógio
  # torto não é sinal fresco (eoc USAGE_FUTURE_SKEW_S).
  # Saída: "<score*1e5>\t<índice de entrada>\t<ref>" — o sort numérico
  # decrescente por score com desempate crescente por índice É a estabilidade.
  ranked=$(awk -v now="$now" -v hl="$hl" -v skew="$CANUTO_USAGE_FUTURE_SKEW_S" \
               -v store="$tmp_store" '
    BEGIN {
      ln2 = log(2)
      while ((getline line < store) > 0) {
        if (line !~ /^\{"ts":/) continue
        if (line !~ /\]\}[ \t]*$/) continue
        ts = line
        sub(/^\{"ts":/, "", ts)
        sub(/[,}].*$/, "", ts)
        if (ts !~ /^[0-9]+(\.[0-9]+)?$/) continue
        t = ts + 0
        if (t > now + skew) continue
        age = now - t
        if (age < 0) age = 0
        decay = exp(-age / hl * ln2)
        r = line
        sub(/^.*"refs":\[/, "", r)
        sub(/\]\}[ \t]*$/, "", r)
        if (r == "") continue
        m = split(r, arr, "\",\"")
        for (i = 1; i <= m; i++) {
          s = arr[i]
          sub(/^"/, "", s)
          sub(/"$/, "", s)
          gsub(/\\"/, "\"", s)
          gsub(/\\\\/, "\\", s)
          if (s != "") score[s] += decay
        }
      }
      close(store)
    }
    {
      idx++
      sc = ($0 in score) ? score[$0] : 0
      printf "%.0f\t%d\t%s\n", sc * 100000, idx, $0
    }
  ' "$tmp_in" 2>/dev/null | sort -t "$(printf '\t')" -k1,1nr -k2,2n 2>/dev/null | cut -f3- 2>/dev/null || true)

  n_in=$(wc -l < "$tmp_in" 2>/dev/null | tr -d ' ' || true)
  case "$n_in" in ''|*[!0-9]*) n_in=0 ;; esac
  if [ -n "$ranked" ]; then
    n_out=$(printf '%s\n' "$ranked" | wc -l | tr -d ' ' || true)
    case "$n_out" in ''|*[!0-9]*) n_out=0 ;; esac
  fi
  # Só entrega o reordenado se ele tiver EXATAMENTE as mesmas linhas de saída.
  # Telemetria pode não ajudar; não pode sumir com item do briefing.
  if [ -n "$ranked" ] && [ "$n_out" = "$n_in" ]; then
    printf '%s\n' "$ranked"
  else
    cat "$tmp_in" 2>/dev/null || true
  fi
  rm -f "$tmp_in" "$tmp_store" 2>/dev/null || true
  return 0
}

# ── CLI ─────────────────────────────────────────────────────────────────────
# `:-` em BASH_SOURCE: sob `zsh -u` a variável não existe e o teste abortaria o
# source (o framework roda em bash, mas hooks são lidos por ferramentas zsh).
if [ "${BASH_SOURCE[0]:-}" = "${0:-}" ]; then
  case "${1:-}" in
    record)
      shift
      canuto_usage_record "$@"
      ;;
    rerank)
      shift
      canuto_usage_rerank "${1:-}"
      ;;
    path)
      shift
      canuto_usage_store "${1:-}"
      ;;
    *)
      echo "uso: memory-usage.sh record <slug> <ref...> | rerank <slug> (refs por stdin) | path <slug>" >&2
      exit 1
      ;;
  esac
fi
