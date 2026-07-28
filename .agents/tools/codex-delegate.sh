#!/usr/bin/env bash
# codex-delegate.sh — wrapper canônico de delegação Codex (template versionado).
#
# HISTÓRICO: até 2026-07-27 este wrapper existia SÓ em ~/.codex/bin/ de uma
# máquina — o caminho canônico de delegação não era distribuído (máquina nova
# = delegação quebrada). Este template implementa o contrato documentado em
# .agents/config/models.yaml e é instalado pelo install.sh em
# ~/.codex/bin/codex-delegate.sh SOMENTE QUANDO AUSENTE — nunca sobrescreve
# um wrapper já existente na máquina.
#
# Uso:    codex-delegate.sh <role> <task-file> <out-file>
# Roles:  coder | reviewer | architect | maestro | fast
#
# Contrato (fonte: models.yaml — manter os dois coerentes):
#   model:   CODEX_DELEGATE_MODEL   > models.yaml > gpt-5.5 (hardcoded)
#   effort:  (sem env var)          > models.yaml > xhigh (architect/maestro) | high
#   timeout: CODEX_DELEGATE_TIMEOUT > models.yaml > 1800 (coder/architect/maestro) | 900
#   sandbox: CODEX_DELEGATE_SANDBOX > models.yaml > read-only (reviewer) | workspace-write
#
# Garantias sobre a forma crua (`codex exec` direto):
#   - passa `-s` explícito (a forma crua herda danger-full-access + never)
#   - timeout com resgate de parcial (<out>.partial.md)
#   - checagem de 0-byte (result=EMPTY_OUTPUT — rc mente, ver models.yaml)
#   - pré-flight de auth
#   - métricas em ~/.codex/delegate-metrics.jsonl
#   - NUNCA usa -q (removido no codex-cli 0.135) nem --profile (morto no wrapper)

set -uo pipefail

usage() { echo "uso: codex-delegate.sh <role> <task-file> <out-file>" >&2; exit 64; }

ROLE="${1:-}"; TASK="${2:-}"; OUT="${3:-}"
[ -n "$ROLE" ] && [ -n "$TASK" ] && [ -n "$OUT" ] || usage
case "$ROLE" in coder|reviewer|architect|maestro|fast) : ;; *) echo "role inválido: $ROLE" >&2; usage ;; esac
[ -f "$TASK" ] || { echo "task-file não existe: $TASK" >&2; exit 66; }
command -v codex >/dev/null 2>&1 || { echo "codex CLI não encontrado" >&2; exit 69; }

# ── models.yaml (flow-style, 2 espaços — formato é load-bearing) ─────────────
PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
MODELS_YAML="${CODEX_DELEGATE_MODELS_YAML:-$PROJECT_DIR/.agents/config/models.yaml}"

models_yaml_get() {
  # $1=role $2=chave — só casa linhas `  <role>: { ... }` (ver models.yaml:1-23)
  [ -f "$MODELS_YAML" ] || return 0
  grep -E "^[[:space:]]{2}${1}:[[:space:]]*\{" "$MODELS_YAML" 2>/dev/null \
    | sed -nE "s/.*[{,][[:space:]]*${2}:[[:space:]]*([^,}[:space:]]+).*/\1/p" \
    | head -1
}

yaml_model=$(models_yaml_get "$ROLE" model)
yaml_effort=$(models_yaml_get "$ROLE" effort)
yaml_timeout=$(models_yaml_get "$ROLE" timeout)
yaml_sandbox=$(models_yaml_get "$ROLE" sandbox)

case "$ROLE" in
  architect|maestro) def_effort="xhigh" ;;
  *)                 def_effort="high" ;;
esac
case "$ROLE" in
  coder|architect|maestro) def_timeout=1800 ;;
  *)                       def_timeout=900 ;;
esac
case "$ROLE" in
  reviewer) def_sandbox="read-only" ;;
  *)        def_sandbox="workspace-write" ;;
esac

MODEL="${CODEX_DELEGATE_MODEL:-${yaml_model:-gpt-5.5}}"
EFFORT="${yaml_effort:-$def_effort}"
TIMEOUT_S="${CODEX_DELEGATE_TIMEOUT:-${yaml_timeout:-$def_timeout}}"
SANDBOX="${CODEX_DELEGATE_SANDBOX:-${yaml_sandbox:-$def_sandbox}}"

case "$EFFORT" in
  low|medium|high|xhigh|max) : ;;
  *) echo "effort inválido: $EFFORT (low|medium|high|xhigh|max)" >&2; exit 65 ;;
esac

# Event log do PROJETO — o delegate-metrics.jsonl mora em $HOME e é por máquina,
# então divergência entre models.yaml e execução real só aparecia em arqueologia
# de PR (papiro#339 registrou "effort medium" com o yaml pedindo xhigh). Gravar
# modelo/effort no evento DELEGATION torna isso um `jq` no log do projeto.
if [ -f "$(dirname "${BASH_SOURCE[0]}")/event-log.sh" ]; then
  # shellcheck source=event-log.sh
  . "$(dirname "${BASH_SOURCE[0]}")/event-log.sh"
elif [ -f "$PROJECT_DIR/.agents/tools/event-log.sh" ]; then
  # shellcheck source=/dev/null
  . "$PROJECT_DIR/.agents/tools/event-log.sh"
else
  canuto_event_append() { return 0; }
fi

METRICS="$HOME/.codex/delegate-metrics.jsonl"
mkdir -p "$HOME/.codex" "$(dirname "$OUT")" 2>/dev/null || true
EXEC_LOG="$OUT.exec.log"

emit_metric() {
  # $1=rc $2=result $3=bytes $4=duration $5=reason
  local ts; ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg ts "$ts" --arg role "$ROLE" --arg model "$MODEL" --arg effort "$EFFORT" \
      --arg sandbox "$SANDBOX" --argjson timeout "$TIMEOUT_S" --argjson rc "$1" \
      --arg result "$2" --argjson bytes "$3" --argjson duration "$4" \
      --arg reason "$5" --arg task "$TASK" --arg out "$OUT" \
      '{ts:$ts,role:$role,model:$model,effort:$effort,sandbox:$sandbox,timeout:$timeout,
        rc:$rc,result:$result,bytes:$bytes,duration:$duration,task:$task,out:$out}
       + (if $reason != "" then {reason:$reason} else {} end)' >> "$METRICS" 2>/dev/null || true
  else
    printf '{"ts":"%s","role":"%s","model":"%s","effort":"%s","sandbox":"%s","timeout":%s,"rc":%s,"result":"%s","bytes":%s,"duration":%s,"reason":"%s"}\n' \
      "$ts" "$ROLE" "$MODEL" "$EFFORT" "$SANDBOX" "$TIMEOUT_S" "$1" "$2" "$3" "$4" "$5" >> "$METRICS" 2>/dev/null || true
  fi

  # Mesma informação no event log do projeto: é lá que a auditoria olha, e o
  # que importa é a CONFIGURAÇÃO REALMENTE USADA, não a declarada no yaml.
  canuto_event_append DELEGATION actor=codex-delegate role="$ROLE" \
    model="$MODEL" effort="$EFFORT" sandbox="$SANDBOX" \
    verdict="$2" rc="$1" duration="$4" out="$OUT" || true
}

# ── Pré-flight de auth (falha rápida em vez de queimar o timeout) ────────────
if ! codex login status >/dev/null 2>&1; then
  emit_metric 1 AUTH_ERROR 0 0 "codex login status falhou"
  echo "[codex-delegate] auth ausente — rode: codex login" >&2
  exit 77
fi

# ── Execução ─────────────────────────────────────────────────────────────────
start=$SECONDS
if command -v timeout >/dev/null 2>&1; then
  timeout "$TIMEOUT_S" codex exec \
    -s "$SANDBOX" -m "$MODEL" -c "model_reasoning_effort=\"$EFFORT\"" \
    --output-last-message "$OUT" - < "$TASK" > "$EXEC_LOG" 2>&1
  rc=$?
else
  codex exec \
    -s "$SANDBOX" -m "$MODEL" -c "model_reasoning_effort=\"$EFFORT\"" \
    --output-last-message "$OUT" - < "$TASK" > "$EXEC_LOG" 2>&1
  rc=$?
fi
duration=$(( SECONDS - start ))
bytes=0
[ -f "$OUT" ] && bytes=$(wc -c < "$OUT" 2>/dev/null | tr -d ' ') && : "${bytes:=0}"

# ── Classificação (ver models.yaml failure-detection: rc E result mentem) ────
result="OK"; reason=""
if [ "$rc" -eq 124 ]; then
  result="TIMEOUT"
  if [ "$bytes" -eq 0 ] && [ -s "$EXEC_LOG" ]; then
    tail -c 20000 "$EXEC_LOG" > "$OUT.partial.md" 2>/dev/null || true
    reason="deadline_exceeded_partial_rescued"
  else
    reason="deadline_exceeded"
  fi
elif grep -Eqi "model[^\"]{0,40}(unavailable|not (found|available))" "$EXEC_LOG" 2>/dev/null; then
  # match na MESMA linha e adjacente — o classificador antigo por substring
  # solta ("model" E "unavailable" em qualquer lugar) gerava falsos positivos
  # (6 casos, 2 com rc=0 — ver models.yaml:56-63).
  result="MODEL_UNAVAILABLE"
elif [ "$rc" -ne 0 ]; then
  result="ERROR"
elif [ "$bytes" -eq 0 ]; then
  result="EMPTY_OUTPUT"
fi

emit_metric "$rc" "$result" "$bytes" "$duration" "$reason"

if [ "$result" = "OK" ]; then
  exit 0
fi
echo "[codex-delegate] $ROLE → $result (rc=$rc, ${bytes}B, ${duration}s) — log: $EXEC_LOG" >&2
[ "$result" = "TIMEOUT" ] && [ -f "$OUT.partial.md" ] \
  && echo "[codex-delegate] parcial resgatado: $OUT.partial.md — cheque git status antes de re-delegar" >&2
exit 1
