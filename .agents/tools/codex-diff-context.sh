#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
MODE="staged"
BASE_REF=""
OUTPUT_FILE=""
DIFF_TARGET="index"

# ── Orçamento de contexto do review ─────────────────────────────────────────
# Redesenho 2026-08-01 (auditoria mecesa/lucrando): o modelo anterior truncava
# ARQUIVO NO MEIO (teto de 400 linhas por arquivo, além de 1500 linhas/90KB no
# total) e o reviewer respondia HOLD exatamente por causa do truncamento
# ("migration and validator bodies are omitted") — ≥20 HOLDs em 4 sessões,
# todos pelo corte, nenhum por achado real. Resultado: CANUTO_ALLOW_COMMIT=1
# virou modus operandi (92 usos no mecesa, 53 no lucrando) e o gate virou ruído.
#
# Modelo novo (whole-file budgeting):
#   1. NENHUM arquivo é cortado no meio. Arquivo incluído = hunks COMPLETOS.
#   2. Arquivos security-sensitive (heurística canônica de codex-common.sh)
#      entram PRIMEIRO no orçamento, na ordem original do diff.
#   3. Estourou o orçamento? Caem ARQUIVOS INTEIROS de menor risco
#      (não-sensíveis; os menores entram antes para maximizar cobertura) e
#      cada omitido é listado em "## Omitted Files (not reviewed)".
#   4. Sensível que não coube também sai INTEIRO, e o cabeçalho marca
#      `sensitive_files_omitted: true` — o chamador (codex-pretool-guard.sh)
#      então instrui o reviewer que o veredicto SKIP-TRUNCATED é permitido
#      (tratado como advisory), nunca HOLD por falta de contexto.
#
# Calibração dos tetos (medida 2026-08-01 com migration sintética):
#   uma migration SQL de 1500 linhas gera ~1505 linhas / ~150KB de patch.
#   Antigo: 1500 linhas totais / 90KB / 400 por arquivo → a migration NUNCA
#   cabia inteira (chegavam 394 de 1500 linhas ao reviewer).
#   Novo: 8000 linhas / 400KB → a migration da auditoria ocupa ~19% do teto de
#   linhas ("com folga"); 400KB ≈ ~100k tokens, confortável para os modelos do
#   reviewer (janela ≥400k tokens) sem explodir custo/latência do hook.
#   O contexto de 3 linhas é o default do git e segue valendo (papiro#341).
DIFF_CONTEXT_LINES="${CODEX_DIFF_CONTEXT_LINES:-3}"
MAX_PATCH_BYTES="${CODEX_DIFF_MAX_BYTES:-400000}"
MAX_PATCH_LINES="${CODEX_DIFF_MAX_LINES:-8000}"
MAX_PATCH_FILES="${CODEX_DIFF_MAX_FILES:-40}"
# CODEX_DIFF_MAX_LINES_PER_FILE foi removido de propósito: truncar um arquivo
# no meio era o gerador dos HOLDs falsos. O corte agora é sempre por arquivo
# inteiro, com lista explícita do que ficou de fora.

# ── Heurística de risco (fonte canônica: codex-common.sh) ───────────────────
_SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || printf '%s' "$PWD")
if ! declare -F codex_is_security_sensitive_path >/dev/null 2>&1; then
  for _common_candidate in "$_SCRIPT_DIR/codex-common.sh" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/codex-common.sh"; do
    if [ -f "$_common_candidate" ]; then
      # shellcheck source=/dev/null
      source "$_common_candidate"
      break
    fi
  done
fi
if ! declare -F codex_is_security_sensitive_path >/dev/null 2>&1; then
  # Cópia de segurança, usada só quando codex-common.sh não está instalado ao
  # lado deste script nem em ~/.claude/scripts. Manter em sincronia manualmente.
  codex_is_security_sensitive_path() {
    local path="${1:-}"
    [[ "$path" =~ (^|/)(auth|middleware|crypto|payments?|billing|routes?|api|controllers?|schema|db|database|rls|supabase|env|config)(/|$) ]] \
      || [[ "$path" =~ (^|/)(package\.json|package-lock\.json|pnpm-lock\.yaml|yarn\.lock|go\.mod|go\.sum|requirements.*|poetry\.lock|Cargo\.toml|Cargo\.lock|Gemfile|Gemfile\.lock|composer\.json|composer\.lock|Dockerfile|docker-compose.*|\.env.*)$ ]]
  }
fi

while [ $# -gt 0 ]; do
  case "$1" in
    --staged)
      MODE="staged"
      ;;
    --uncommitted)
      MODE="uncommitted"
      ;;
    --commit-candidate)
      MODE="commit-candidate"
      DIFF_TARGET="${2:-index}"
      shift
      ;;
    --base)
      MODE="base"
      BASE_REF="${2:-}"
      shift
      ;;
    --output)
      OUTPUT_FILE="${2:-}"
      shift
      ;;
    *)
      echo "Usage: $0 [--staged|--uncommitted|--commit-candidate <index|all-tracked>|--base <ref>] [--output <file>]" >&2
      exit 1
      ;;
  esac
  shift
done

cd "$PROJECT_DIR"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not a git repository." >&2
  exit 1
fi

case "$MODE" in
  staged)
    DIFF_CMD=(git diff --cached "-U$DIFF_CONTEXT_LINES" --no-color)
    STAT_CMD=(git diff --cached --stat=120 --compact-summary --no-color)
    FILE_CMD=(git diff --cached --name-only --diff-filter=ACMR)
    ;;
  uncommitted)
    DIFF_CMD=(git diff "-U$DIFF_CONTEXT_LINES" --no-color)
    STAT_CMD=(git diff --stat=120 --compact-summary --no-color)
    FILE_CMD=(git diff --name-only --diff-filter=ACMR)
    ;;
  commit-candidate)
    if [ "$DIFF_TARGET" = "all-tracked" ]; then
      if git rev-parse --verify HEAD >/dev/null 2>&1; then
        DIFF_CMD=(git diff HEAD "-U$DIFF_CONTEXT_LINES" --no-color)
        STAT_CMD=(git diff HEAD --stat=120 --compact-summary --no-color)
        FILE_CMD=(git diff HEAD --name-only --diff-filter=ACMR)
      else
        DIFF_CMD=(git diff --cached "-U$DIFF_CONTEXT_LINES" --no-color)
        STAT_CMD=(git diff --cached --stat=120 --compact-summary --no-color)
        FILE_CMD=(git diff --cached --name-only --diff-filter=ACMR)
      fi
    else
      DIFF_CMD=(git diff --cached "-U$DIFF_CONTEXT_LINES" --no-color)
      STAT_CMD=(git diff --cached --stat=120 --compact-summary --no-color)
      FILE_CMD=(git diff --cached --name-only --diff-filter=ACMR)
    fi
    ;;
  base)
    if [ -z "$BASE_REF" ]; then
      echo "--base requires a ref." >&2
      exit 1
    fi
    DIFF_CMD=(git diff "$BASE_REF"...HEAD "-U$DIFF_CONTEXT_LINES" --no-color)
    STAT_CMD=(git diff "$BASE_REF"...HEAD --stat=120 --compact-summary --no-color)
    FILE_CMD=(git diff "$BASE_REF"...HEAD --name-only --diff-filter=ACMR)
    ;;
esac

DIFF_OUTPUT="$("${DIFF_CMD[@]}")"
if [ -z "$DIFF_OUTPUT" ]; then
  DIFF_OUTPUT="No changes detected."
fi

# C7: Mask potential secrets/tokens in diff output
_mask_secrets="${CODEX_DIFF_MASK_SECRETS:-true}"
if [ "$_mask_secrets" != "false" ] && [ "$_mask_secrets" != "FALSE" ] && [ "$_mask_secrets" != "0" ]; then
  # Case-insensitive matching via piping through two passes (sed -E on macOS doesn't support /I)
  DIFF_OUTPUT=$(printf '%s' "$DIFF_OUTPUT" | \
    sed -E \
      -e 's/([Aa][Pp][Ii][_-]?[Kk][Ee][Yy]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Tt][Oo][Kk][Ee][Nn]|[Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Bb][Ee][Aa][Rr][Ee][Rr]|[Cc][Rr][Ee][Dd][Ee][Nn][Tt][Ii][Aa][Ll][Ss]?)[[:space:]]*[:=][[:space:]]*"?[A-Za-z0-9+\/_.~-]{8,}"?/\1=<REDACTED>/g' \
      -e 's/(sk_live_|pk_live_|sk_test_|pk_test_|xox[bpsar])-[A-Za-z0-9]{8,}/<REDACTED_KEY>/g' \
      -e 's/ghp_[A-Za-z0-9]{36,}/<REDACTED_GITHUB_PAT>/g' \
      -e 's/gho_[A-Za-z0-9]{36,}/<REDACTED_GITHUB_OAUTH>/g' \
      -e 's/github_pat_[A-Za-z0-9_]{20,}/<REDACTED_GITHUB_PAT>/g' \
      -e 's/eyJ[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{15,}/<REDACTED_JWT>/g' \
  )
fi

STAT_OUTPUT="$("${STAT_CMD[@]}" 2>/dev/null || true)"
if [ -z "$STAT_OUTPUT" ]; then
  STAT_OUTPUT="No file-level diff summary detected."
fi

declare -a CHANGED_FILES=()
while IFS= read -r changed_file; do
  [ -n "$changed_file" ] || continue
  CHANGED_FILES+=("$changed_file")
done < <("${FILE_CMD[@]}" 2>/dev/null | sed '/^$/d')

extract_identifiers() {
  local regex="$1"
  printf '%s\n' "$DIFF_OUTPUT" \
    | grep -E '^[+-][^+-]' \
    | grep -oE "$regex" \
    | sed 's/[(]$//' \
    | sort -u \
    | head -20 \
    || true
}

join_pattern() {
  local joined=""
  while IFS= read -r item; do
    [ -n "$item" ] || continue
    if [ -z "$joined" ]; then
      joined="$item"
    else
      joined="$joined|$item"
    fi
  done
  printf '%s\n' "$joined"
}

TYPE_PATTERN=$(extract_identifiers '\b[A-Z][A-Za-z0-9_]*\b' | join_pattern)
FUNC_PATTERN=$(extract_identifiers '\b[a-z][A-Za-z0-9_]*\(' | join_pattern)

render_signatures() {
  local file="$1"
  local rendered=false

  if [ -n "$TYPE_PATTERN" ]; then
    if rg -n "^[[:space:]]*(export[[:space:]]+)?(type|interface|enum|class)[[:space:]]+(${TYPE_PATTERN})\\b" "$file" 2>/dev/null | head -20; then
      rendered=true
    fi
  fi

  if [ -n "$FUNC_PATTERN" ]; then
    if rg -n "^[[:space:]]*(export[[:space:]]+)?(async[[:space:]]+)?function[[:space:]]+(${FUNC_PATTERN})\\b|^[[:space:]]*(export[[:space:]]+)?(const|let|var)[[:space:]]+(${FUNC_PATTERN})[[:space:]]*=" "$file" 2>/dev/null | head -20; then
      rendered=true
    fi
  fi

  [ "$rendered" = true ] || return 1
}

RESULT_FILE="${OUTPUT_FILE:-$(mktemp)}"
SPLIT_DIR=$(mktemp -d)
trap 'rm -rf "$SPLIT_DIR"' EXIT

# ── Split do diff em um bloco por arquivo ───────────────────────────────────
# LC_ALL=C: length() conta bytes (é o que o orçamento mede) e o parsing fica
# estável para conteúdo binário/UTF-8. Cada bloco `diff --git` vira um arquivo
# NNNNNN.patch e o index.tsv registra: bloco, linhas, bytes, path.
printf '%s\n' "$DIFF_OUTPUT" | LC_ALL=C awk -v dir="$SPLIT_DIR" '
  BEGIN { n = 0; out = "" }
  /^diff --git / {
    if (out != "") close(out)
    n++
    out = sprintf("%s/%06d.patch", dir, n)
    p = $0
    sub(/^diff --git [^ ]+ b\//, "", p)
    gsub(/^"|"$/, "", p)
    hdrpath[n] = p
  }
  n > 0 {
    if ($0 ~ /^\+\+\+ / && pluspath[n] == "") {
      p = $0
      sub(/^\+\+\+ /, "", p)
      if (p != "/dev/null") {
        gsub(/^"|"$/, "", p)
        sub(/^b\//, "", p)
        sub(/\t.*$/, "", p)
        pluspath[n] = p
      }
    }
    print > out
    lc[n]++
    bc[n] += length($0) + 1
  }
  END {
    if (out != "") close(out)
    idx = dir "/index.tsv"
    for (i = 1; i <= n; i++) {
      p = (pluspath[i] != "" ? pluspath[i] : hdrpath[i])
      printf "%06d\t%d\t%d\t%s\n", i, lc[i], bc[i], p > idx
    }
    close(idx)
  }
'

BLOCK_COUNT=0
declare -a block_lines=()
declare -a block_bytes=()
declare -a block_path=()
declare -a block_sens=()
if [ -s "$SPLIT_DIR/index.tsv" ]; then
  while IFS=$'\t' read -r blk blines bbytes bpath; do
    [ -n "$blk" ] || continue
    idx=$((10#$blk))
    block_lines[$idx]=$blines
    block_bytes[$idx]=$bbytes
    block_path[$idx]=$bpath
    if codex_is_security_sensitive_path "$bpath"; then
      block_sens[$idx]=1
    else
      block_sens[$idx]=0
    fi
    if [ "$idx" -gt "$BLOCK_COUNT" ]; then
      BLOCK_COUNT=$idx
    fi
  done < "$SPLIT_DIR/index.tsv"
fi

# ── Ordem de inclusão no orçamento ──────────────────────────────────────────
#   prioridade 0: arquivos sensíveis, na ordem original do diff
#   prioridade 1: não-sensíveis, do menor para o maior (maximiza cobertura)
TAB=$(printf '\t')
PRIORITY_FILE="$SPLIT_DIR/priority.tsv"
: > "$PRIORITY_FILE"
i=1
while [ "$i" -le "$BLOCK_COUNT" ]; do
  if [ "${block_sens[$i]}" = "1" ]; then
    printf '0\t%s\t%s\t%s\n' "$i" "$i" "$i" >> "$PRIORITY_FILE"
  else
    printf '1\t%s\t%s\t%s\n' "${block_lines[$i]}" "$i" "$i" >> "$PRIORITY_FILE"
  fi
  i=$((i + 1))
done

declare -a included=()
INCLUDED_COUNT=0
OMITTED_COUNT=0
SENSITIVE_OMITTED=false
OMITTED_FILE="$SPLIT_DIR/omitted.tsv"
: > "$OMITTED_FILE"
tot_lines=0
tot_bytes=0
if [ "$BLOCK_COUNT" -gt 0 ]; then
  while IFS=$'\t' read -r _prio _key _seq idx; do
    [ -n "$idx" ] || continue
    blines=${block_lines[$idx]}
    bbytes=${block_bytes[$idx]}
    if [ "$INCLUDED_COUNT" -ge "$MAX_PATCH_FILES" ] \
      || [ $((tot_lines + blines)) -gt "$MAX_PATCH_LINES" ] \
      || [ $((tot_bytes + bbytes)) -gt "$MAX_PATCH_BYTES" ]; then
      OMITTED_COUNT=$((OMITTED_COUNT + 1))
      if [ "${block_sens[$idx]}" = "1" ]; then
        SENSITIVE_OMITTED=true
      fi
      printf '%s\t%s\t%s\n' "${block_sens[$idx]}" "$blines" "${block_path[$idx]}" >> "$OMITTED_FILE"
      continue
    fi
    included[$idx]=1
    INCLUDED_COUNT=$((INCLUDED_COUNT + 1))
    tot_lines=$((tot_lines + blines))
    tot_bytes=$((tot_bytes + bbytes))
  done < <(sort -t "$TAB" -k1,1n -k2,2n -k3,3n "$PRIORITY_FILE")
fi

# Render do excerpt na ordem ORIGINAL do diff (mais legível para o reviewer).
PATCH_EXCERPT_FILE="$SPLIT_DIR/excerpt.patch"
: > "$PATCH_EXCERPT_FILE"
if [ "$BLOCK_COUNT" -gt 0 ]; then
  i=1
  while [ "$i" -le "$BLOCK_COUNT" ]; do
    if [ "${included[$i]:-0}" = "1" ]; then
      cat "$SPLIT_DIR/$(printf '%06d' "$i").patch" >> "$PATCH_EXCERPT_FILE"
    fi
    i=$((i + 1))
  done
else
  # Diff sem headers `diff --git` (ex.: "No changes detected.") passa cru.
  printf '%s\n' "$DIFF_OUTPUT" > "$PATCH_EXCERPT_FILE"
fi

{
  echo "# Compressed Diff Context"
  echo ""
  echo "## Review Scope"
  echo "- mode: $MODE"
  if [ "$MODE" = "commit-candidate" ]; then
    echo "- commit_target: $DIFF_TARGET"
  fi
  if [ -n "$BASE_REF" ]; then
    echo "- base: $BASE_REF"
  fi
  echo "- files: ${#CHANGED_FILES[@]}"
  echo "- files_in_patch: $BLOCK_COUNT"
  echo "- files_included_full: $INCLUDED_COUNT"
  echo "- files_omitted: $OMITTED_COUNT"
  echo "- sensitive_files_omitted: $SENSITIVE_OMITTED"
  echo "- budget: $MAX_PATCH_FILES files / $MAX_PATCH_LINES patch lines / $MAX_PATCH_BYTES bytes"
  echo ""
  echo "## Diff Summary"
  echo '```text'
  printf '%s\n' "$STAT_OUTPUT"
  echo '```'
  echo ""
  echo "## Patch Excerpt"
  if [ "$OMITTED_COUNT" -gt 0 ]; then
    echo "_Context budget applied: $INCLUDED_COUNT of $BLOCK_COUNT changed files included with COMPLETE hunks; $OMITTED_COUNT file(s) omitted IN FULL and listed under \"Omitted Files (not reviewed)\". No file is ever cut mid-way._"
  elif [ "$BLOCK_COUNT" -gt 0 ]; then
    echo "_All $BLOCK_COUNT changed files included with complete hunks (nothing omitted)._"
  fi
  echo '```diff'
  cat "$PATCH_EXCERPT_FILE"
  echo '```'
  echo ""

  if [ "$OMITTED_COUNT" -gt 0 ]; then
    echo "## Omitted Files (not reviewed)"
    echo "_These files exceeded the review context budget and were omitted IN FULL (never cut mid-file). They were NOT reviewed:_"
    while IFS=$'\t' read -r osens olines opath; do
      [ -n "$opath" ] || continue
      if [ "$osens" = "1" ]; then
        echo "- $opath ($olines diff lines) [SECURITY-SENSITIVE]"
      else
        echo "- $opath ($olines diff lines)"
      fi
    done < <(sort -t "$TAB" -k1,1nr -k2,2n "$OMITTED_FILE")
    echo ""
  fi

  if [ ${#CHANGED_FILES[@]} -gt 0 ]; then
    echo "## Referenced Signatures"
    sig_tmp=$(mktemp)
    for file in "${CHANGED_FILES[@]}"; do
      [ -f "$file" ] || continue
      : > "$sig_tmp"
      if ! render_signatures "$file" >"$sig_tmp" 2>/dev/null; then
        continue
      fi
      if [ -s "$sig_tmp" ]; then
        echo "### $file"
        echo '```text'
        cat "$sig_tmp"
        echo '```'
        echo ""
      fi
    done
    rm -f "$sig_tmp"
  fi
} > "$RESULT_FILE"

cat "$RESULT_FILE"

if [ -z "$OUTPUT_FILE" ]; then
  rm -f "$RESULT_FILE"
fi
