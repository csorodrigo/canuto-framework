#!/usr/bin/env bash
# postdelegate-verify.sh — PostToolUse hook (matcher: Bash).
# Post-gate mecânico de delegações Codex, padrão edge-of-chaos
# assert_beat_produced: "exit 0 não prova nada" — o que prova é o artefato.
#
# Dois gates, nesta ordem:
#
# 1) GATE DE MÉTRICA (auditoria 2026-08-01: 42 falhas de delegação → só 3
#    declarações de fallback nos transcripts). Se o comando foi o wrapper
#    codex-delegate.sh, a ÚLTIMA linha de ~/.codex/delegate-metrics.jsonl é a
#    fonte de verdade (o wrapper a escreve ANTES de sair — emit_metric roda
#    dentro do processo do wrapper, que roda dentro do Bash tool call; este
#    hook só dispara depois). result != "OK" ⇒ additionalContext BLOQUEANTE:
#    o Maestro é obrigado a declarar qual executor real fez o trabalho.
#
# 2) GATE DE ARTEFATO (auditoria 2026-06-10: 17% das delegações com rc=124
#    sem o Maestro perceber): out-file existe e não está vazio. Vale também
#    para `codex exec --output-last-message` sem wrapper.
#
# Exit 2 (PostToolUse) = não desfaz nada, mas o stderr chega ao Claude como
# feedback imediato. O gate de métrica usa additionalContext (stdout JSON,
# exit 0) — canal que injeta contexto diretamente na conversa.

set -uo pipefail

# Sem payload num TTY: `cat` sem stdin fechado bloqueia para sempre e o
# runtime que espera o hook congela junto (regra de TTY/pipe do CLAUDE.md).
INPUT=""
[ -t 0 ] || INPUT=$(cat 2>/dev/null || true)

command -v jq >/dev/null 2>&1 || exit 0

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[ -n "$COMMAND" ] || exit 0

IS_DELEGATION=false
IS_WRAPPER=false
OUT_FILE=""

# Tokenizador do comando do wrapper, ciente de ASPAS (review cego 2026-08-02).
# O padrão anterior era `[^[:space:]"']+` por argumento: com um caminho entre
# aspas — `codex-delegate.sh coder "/tmp/my task.md" /tmp/out.md` — ele
# simplesmente NÃO CASAVA, OUT_FILE saía vazio e a delegação escapava inteira
# dos dois gates (nem o de métrica, nem o de artefato). Aqui o awk varre o
# texto DEPOIS de "codex-delegate.sh" e devolve o 3º argumento (out-file) já
# sem aspas, honrando '..', ".." e barra invertida, e parando em ; | & fora de
# aspas (fim do comando).
_pdv_wrapper_out_file() {
  printf '%s' "$1" | awk '
    {
      i = index($0, "codex-delegate.sh")
      if (i == 0) next   # awk lê LINHA a linha: comando multi-linha (heredoc)
                         # pode ter o wrapper na 2ª linha — `exit` aqui cegaria
                         # o hook para esse caso.
      s = substr($0, i + length("codex-delegate.sh"))
      n = length(s); tok = ""; argc = 0; q = ""; started = 0
      for (k = 1; k <= n; k++) {
        c = substr(s, k, 1)
        if (q != "") {
          if (c == q) { q = "" } else { tok = tok c }
          continue
        }
        if (c == "\"" || c == "'"'"'") { q = c; started = 1; continue }
        if (c == "\\" && k < n) { k++; tok = tok substr(s, k, 1); started = 1; continue }
        if (c == " " || c == "\t") {
          if (tok != "" || started) {
            argc++
            if (argc == 3) { print tok; exit }
            tok = ""; started = 0
          }
          continue
        }
        if (c == ";" || c == "|" || c == "&") {
          if ((tok != "" || started) && argc == 2) print tok
          exit
        }
        tok = tok c
      }
      if ((tok != "" || started) && argc == 2) print tok
    }' 2>/dev/null
}

if printf '%s' "$COMMAND" | grep -q 'codex-delegate\.sh'; then
  IS_DELEGATION=true
  IS_WRAPPER=true
  # forma canônica: codex-delegate.sh <persona> <task-file> <out-file>
  OUT_FILE=$(_pdv_wrapper_out_file "$COMMAND" | head -1)
  # Tocar no ARQUIVO do wrapper ou CITÁ-LO em prosa não é delegar: bash -n,
  # cp, chmod, git commit -m "...codex-delegate.sh..." produzem "out-file"
  # que é flag (-n), palavra solta (template) ou vazio. Delegação real tem
  # out-file com cara de caminho (2026-07-27: 2 falsos positivos em sequência
  # — syntax check e mensagem de commit).
  case "$OUT_FILE" in
    ""|-*) IS_DELEGATION=false; IS_WRAPPER=false ;;
    */*|*.md|*.txt|*.json|*.log) : ;;
    *) IS_DELEGATION=false; IS_WRAPPER=false ;;
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

# ── Lib de event log: cascata fail-loud (contrato Track A/D 2026-08-01) ──────
# repo (relativo ao hook) → repo (projeto atual) → lib global ~/.canuto/lib →
# stub que REGISTRA a ausência em ~/.canuto/vault/_health/missing-lib.jsonl.
# O event log morreu em ~90% dos projetos porque repos com install desatualizado
# não têm .agents/tools/event-log.sh e o stub antigo silenciava (return 0 puro).
if [ -f "$SCRIPT_DIR/../tools/event-log.sh" ]; then
  # shellcheck source=../tools/event-log.sh
  . "$SCRIPT_DIR/../tools/event-log.sh" 2>/dev/null || true
elif [ -f "$PROJECT_DIR/.agents/tools/event-log.sh" ]; then
  # shellcheck source=/dev/null
  . "$PROJECT_DIR/.agents/tools/event-log.sh" 2>/dev/null || true
elif [ -f "$HOME/.canuto/lib/event-log.sh" ]; then
  # shellcheck source=/dev/null
  . "$HOME/.canuto/lib/event-log.sh" 2>/dev/null || true
fi
if ! type canuto_event_append >/dev/null 2>&1; then
  canuto_event_append() {
    mkdir -p "$HOME/.canuto/vault/_health" 2>/dev/null || return 0
    printf '{"ts":"%s","missing":"event-log.sh","consumer":"postdelegate-verify.sh","project":"%s"}\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$PROJECT_DIR" \
      >> "$HOME/.canuto/vault/_health/missing-lib.jsonl" 2>/dev/null || true
    return 0
  }
fi

# expande ~ e $$ não são resolvidos aqui; só validamos caminhos absolutos/relativos simples
OUT_FILE_EXPANDED="${OUT_FILE/#\~/$HOME}"

# ── Gate 1: métrica do wrapper (fallback nunca é silencioso — mecânico) ──────
if [ "$IS_WRAPPER" = true ]; then
  METRICS_FILE="${CANUTO_METRICS_FILE:-$HOME/.codex/delegate-metrics.jsonl}"
  if [ -f "$METRICS_FILE" ]; then
    LAST_METRIC=$(tail -n 1 "$METRICS_FILE" 2>/dev/null || true)
    if [ -n "$LAST_METRIC" ]; then
      M_RESULT=$(printf '%s' "$LAST_METRIC" | jq -r '.result // empty' 2>/dev/null) || M_RESULT=""
      M_ROLE=$(printf '%s' "$LAST_METRIC" | jq -r '.role // "?"' 2>/dev/null) || M_ROLE="?"
      M_REASON=$(printf '%s' "$LAST_METRIC" | jq -r '.reason // empty' 2>/dev/null) || M_REASON=""
      M_OUT=$(printf '%s' "$LAST_METRIC" | jq -r '.out // empty' 2>/dev/null) || M_OUT=""
      M_PARTIAL=$(printf '%s' "$LAST_METRIC" | jq -r '.partial // empty' 2>/dev/null) || M_PARTIAL=""

      # Staleness: o wrapper pode sair ANTES de emitir métrica (task-file
      # inexistente, codex CLI ausente) — aí a última linha é de outra
      # delegação. O campo "out" da métrica identifica a chamada; se não
      # bate com o out-file deste comando, a linha é velha: pula o gate de
      # métrica (o gate de artefato abaixo continua valendo).
      STALE=false
      if [ -n "$M_OUT" ] && [ "$M_OUT" != "$OUT_FILE" ] && [ "$M_OUT" != "$OUT_FILE_EXPANDED" ]; then
        STALE=true
      fi

      if [ "$STALE" = false ] && [ -n "$M_RESULT" ] && [ "$M_RESULT" != "OK" ]; then
        VERDICT=$(printf '%s' "$M_RESULT" | tr '[:upper:]' '[:lower:]')
        canuto_event_append DELEGATION actor=hook provider=codex rc="$RC" \
          role="$M_ROLE" out_file="$OUT_FILE" verdict="$VERDICT" \
          reason="${M_REASON:-$M_RESULT}" || true

        PARTIAL_HINT="$OUT_FILE_EXPANDED.partial.md"
        [ -n "$M_PARTIAL" ] && PARTIAL_HINT="$M_PARTIAL (E $OUT_FILE_EXPANDED.partial.md)"
        CTX="DELEGACAO CODEX FALHOU — AVISO BLOQUEANTE (postdelegate-verify). \
ROLE=$M_ROLE RESULT=$M_RESULT REASON=${M_REASON:-n/d}. \
E OBRIGATORIO DECLARAR NO OUTPUT FINAL QUAL EXECUTOR REAL FEZ O TRABALHO \
(EX.: 'codex-delegate falhou — Claude implementando direto'). NUNCA AFIRMAR QUE O CODEX RODOU. \
ANTES DE RE-DELEGAR: CHEQUE O PARCIAL RESGATADO EM $PARTIAL_HINT E O GIT DIFF — \
PODE HAVER TRABALHO APROVEITAVEL. NAO USE O CONTEUDO DE $OUT_FILE COMO RESULTADO VALIDO."
        jq -cn --arg ctx "$CTX" \
          '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}' 2>/dev/null \
          || printf '%s\n' "$CTX" >&2
        exit 0
      fi
    fi
  fi
fi

# ── Gate 2: artefato (vale para wrapper com métrica OK/stale e codex exec) ───
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
      echo "declare o executor real no output final e re-delegue ou trate a falha"
      echo "(fallback chain em multi-provider.md)."
    } >&2
    exit 2
    ;;
esac
