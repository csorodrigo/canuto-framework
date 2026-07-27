#!/usr/bin/env bash
# postdelegate-verify.sh — PostToolUse hook (matcher: Bash).
# Post-gate mecânico de delegações Codex, padrão edge-of-chaos
# assert_beat_produced: "exit 0 não prova nada" — o que prova é o artefato.
#
# A auditoria 2026-06-10 mediu 17% das delegações falhando com rc=124
# (timeout) sem que o Maestro percebesse. Este hook verifica, após QUALQUER
# comando de delegação (codex-delegate.sh ou codex exec --output-last-message),
# que o arquivo de saída existe e não está vazio, e registra DELEGATION no
# event log com veredito.
#
# Exit 2 (PostToolUse) = não desfaz nada, mas o stderr chega ao Claude como
# feedback imediato — o Maestro fica sabendo ANTES de usar um resultado oco.

set -uo pipefail

INPUT=$(cat 2>/dev/null || true)

command -v jq >/dev/null 2>&1 || exit 0

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$COMMAND" ] || exit 0

IS_DELEGATION=false
OUT_FILE=""

if printf '%s' "$COMMAND" | grep -q 'codex-delegate\.sh'; then
  IS_DELEGATION=true
  # forma canônica: codex-delegate.sh <persona> <task-file> <out-file>
  OUT_FILE=$(printf '%s' "$COMMAND" | grep -o 'codex-delegate\.sh[[:space:]]\+[^[:space:]]\+[[:space:]]\+[^[:space:]]\+[[:space:]]\+[^[:space:];|&]\+' | awk '{print $4}' | head -1)
  # Tocar no ARQUIVO do wrapper não é delegar: bash -n, shellcheck, cp, chmod,
  # git add etc. produzem "out-file" começando com "-" ou nem casam a forma
  # canônica (2026-07-27: falso positivo em `bash -n codex-delegate.sh`).
  case "$OUT_FILE" in
    ""|-*) IS_DELEGATION=false ;;
  esac
elif printf '%s' "$COMMAND" | grep -q 'codex[[:space:]]\+exec' && printf '%s' "$COMMAND" | grep -q -- '--output-last-message'; then
  IS_DELEGATION=true
  OUT_FILE=$(printf '%s' "$COMMAND" | sed -n 's/.*--output-last-message[= ]\([^[:space:];|&]*\).*/\1/p' | head -1)
fi

[ "$IS_DELEGATION" = true ] || exit 0

RC=$(printf '%s' "$INPUT" | jq -r '(.tool_response // .tool_output // {}) | (.exitCode // .exit_code // .code // 0) | tostring' 2>/dev/null) || RC="unknown"
case "$RC" in ''|null) RC=0 ;; esac

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/../tools/event-log.sh" ]; then
  # shellcheck source=../tools/event-log.sh
  . "$SCRIPT_DIR/../tools/event-log.sh"
elif [ -f "$PROJECT_DIR/.agents/tools/event-log.sh" ]; then
  # shellcheck source=/dev/null
  . "$PROJECT_DIR/.agents/tools/event-log.sh"
else
  canuto_event_append() { return 0; }
fi

# expande ~ e $$ não são resolvidos aqui; só validamos caminhos absolutos/relativos simples
OUT_FILE_EXPANDED="${OUT_FILE/#\~/$HOME}"

VERDICT="ok"
REASON=""
if [ "$RC" = "124" ]; then
  VERDICT="timeout"
  REASON="rc=124 (timeout do codex — resultado NÃO confiável)"
elif [ "$RC" != "0" ]; then
  VERDICT="error"
  REASON="rc=$RC"
elif [ -z "$OUT_FILE_EXPANDED" ]; then
  VERDICT="no-outfile"
  REASON="comando de delegação sem --output-last-message parseável"
elif printf '%s' "$OUT_FILE_EXPANDED" | grep -q '[$*?]'; then
  # caminho com expansão de shell não resolvida — não dá para verificar daqui
  VERDICT="unverifiable"
  REASON="out-file com variável de shell ($OUT_FILE)"
elif [ ! -f "$OUT_FILE_EXPANDED" ]; then
  VERDICT="missing"
  REASON="out-file não existe: $OUT_FILE_EXPANDED"
elif [ ! -s "$OUT_FILE_EXPANDED" ]; then
  VERDICT="empty"
  REASON="out-file vazio: $OUT_FILE_EXPANDED"
fi

canuto_event_append DELEGATION actor=hook provider=codex rc="$RC" \
  out_file="$OUT_FILE" verdict="$VERDICT" reason="$REASON" || true

case "$VERDICT" in
  ok|unverifiable|no-outfile)
    exit 0
    ;;
  *)
    {
      echo "⚠ [postdelegate-verify] Delegação Codex FALHOU no post-gate mecânico: $REASON."
      echo "Exit code do processo não prova entrega — o artefato prova. NÃO use este resultado;"
      echo "re-delegue ou trate a falha (fallback chain em multi-provider.md)."
    } >&2
    exit 2
    ;;
esac
