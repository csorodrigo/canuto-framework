#!/usr/bin/env bash
# instinct-aging.sh — Aging por escassez do tier hipótese (nunca deleta).
#
# Absorvido do edge-of-chaos: "decay is caused by SCARCITY, never by time"
# na teoria; na prática do Canuto v1, o proxy mecânico disponível é
# last-seen + confidence. Regra:
#
#   instinct com confidence: low  E  last-seen há mais de N dias (default 30)
#   → status: archived   (frontmatter editado; o arquivo NUNCA é apagado)
#
# Instincts medium/high (tier curado pela regra de dois tiers) são EXENTOS —
# aging só toca o tier hipótese. Promoção/prune de curados é decisão humana
# (continuous-learning/references/instinct-promotion.md).
#
# Uso:
#   bash .agents/tools/instinct-aging.sh --dry-run   # lista candidatos (default)
#   bash .agents/tools/instinct-aging.sh --apply     # arquiva e registra no event log
#   CANUTO_AGING_DAYS=45 bash .agents/tools/instinct-aging.sh --apply

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$SCRIPT_DIR/canuto-memory.sh" ]; then
  # shellcheck source=canuto-memory.sh
  source "$SCRIPT_DIR/canuto-memory.sh"
  set +e
fi
if [ -f "$SCRIPT_DIR/event-log.sh" ]; then
  # shellcheck source=event-log.sh
  . "$SCRIPT_DIR/event-log.sh"
else
  canuto_event_append() { return 0; }
fi

MODE="${1:---dry-run}"
DAYS="${CANUTO_AGING_DAYS:-30}"
NOW_EPOCH=$(date +%s)
CUTOFF=$((NOW_EPOCH - DAYS * 86400))

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
INSTINCTS_DIR=""
if command -v canuto_resolve_vault_dir >/dev/null 2>&1; then
  VAULT_DIR=$(canuto_resolve_vault_dir "$PROJECT_DIR")
  [ -n "$VAULT_DIR" ] && [ -d "$VAULT_DIR/instincts" ] && INSTINCTS_DIR="$VAULT_DIR/instincts"
fi
if [ -z "$INSTINCTS_DIR" ]; then
  echo "instinct-aging: nenhum vault com instincts/ resolvido — nada a fazer."
  exit 0
fi

fm_get() { awk -v key="$2" 'NR==1&&$0=="---"{i=1;next} i&&$0=="---"{exit} i&&$0~"^"key":"{sub("^"key":[[:space:]]*","");print;exit}' "$1"; }

to_epoch() {
  # aceita YYYY-MM-DD; devolve epoch ou vazio
  date -d "$1" +%s 2>/dev/null || date -j -f %Y-%m-%d "$1" +%s 2>/dev/null || true
}

ARCHIVED=0
CANDIDATES=0

for f in "$INSTINCTS_DIR"/*.md; do
  [ -f "$f" ] || continue
  status=$(fm_get "$f" status)
  case "$status" in archived|pruned|promoted) continue ;; esac
  confidence=$(fm_get "$f" confidence)
  [ "$confidence" = "low" ] || continue
  last_seen=$(fm_get "$f" last-seen)
  [ -n "$last_seen" ] || last_seen=$(fm_get "$f" date)
  [ -n "$last_seen" ] || continue
  seen_epoch=$(to_epoch "$last_seen")
  [ -n "$seen_epoch" ] || continue
  if [ "$seen_epoch" -lt "$CUTOFF" ]; then
    CANDIDATES=$((CANDIDATES + 1))
    id=$(fm_get "$f" id); [ -n "$id" ] || id=$(basename "$f" .md)
    if [ "$MODE" = "--apply" ]; then
      if grep -q '^status:' "$f"; then
        # posix-safe in-place: tmp + mv (preserva o arquivo — nunca deleta)
        awk 'NR==1&&$0=="---"{i=1} i&&/^status:/{print "status: archived"; next} /^---$/&&NR>1{i=0} {print}' "$f" > "$f.tmp" \
          && mv "$f.tmp" "$f"
      else
        awk 'NR==1&&$0=="---"{print; print "status: archived"; next} {print}' "$f" > "$f.tmp" \
          && mv "$f.tmp" "$f"
      fi
      canuto_event_append INSTINCT_ARCHIVED actor=aging id="$id" \
        reason="confidence=low sem uso há >${DAYS}d (last-seen: $last_seen)" || true
      ARCHIVED=$((ARCHIVED + 1))
      echo "arquivado: $id (last-seen: $last_seen)"
    else
      echo "candidato a arquivamento: $id (confidence: low, last-seen: $last_seen)"
    fi
  fi
done

if [ "$MODE" = "--apply" ]; then
  echo "instinct-aging: $ARCHIVED arquivado(s) de $CANDIDATES candidato(s) (cutoff ${DAYS}d)."
else
  echo "instinct-aging: $CANDIDATES candidato(s) — rode com --apply para arquivar (status: archived; nada é deletado)."
fi
