#!/usr/bin/env bash
# codex-delegate.sh — wrapper canônico de delegação Codex (template versionado).
# Mantém snapshot da execução, preflight, roteamento central e resgate de parciais.
# Usage: codex-delegate.sh [--preflight-only] <role> <prompt-file|-|text> [output-file] [cwd]
canonical_script_path() {
  local path="$1"
  local dir base
  [[ -n "$path" ]] || return 1
  dir="$(dirname "$path")" || return 1
  base="$(basename "$path")" || return 1
  (cd "$dir" 2>/dev/null && printf '%s/%s\n' "$(pwd -P)" "$base")
}

self_snapshot_path="$(canonical_script_path "$0" 2>/dev/null || true)"
active_snapshot_path="$(canonical_script_path "${CODEX_DELEGATE_SNAPSHOT_ACTIVE:-}" 2>/dev/null || true)"

if [[ -z "$self_snapshot_path" || "$active_snapshot_path" != "$self_snapshot_path" ]]; then
  snapshot_template="${TMPDIR:-/tmp}/codex-delegate.snapshot.XXXXXX"
  snapshot_path="$(umask 077 && mktemp "$snapshot_template")" || {
    echo "CODEX_DELEGATE_FAILED role=unknown rc=4 reason=SNAPSHOT_FAILED" >&2
    exit 4
  }
  cleanup_snapshot() {
    rm -f -- "$snapshot_path"
  }
  trap cleanup_snapshot EXIT HUP INT TERM
  if ! cp -- "$0" "$snapshot_path" || ! chmod 500 "$snapshot_path"; then
    echo "CODEX_DELEGATE_FAILED role=unknown rc=4 reason=SNAPSHOT_FAILED" >&2
    exit 4
  fi
  snapshot_run_path="$(canonical_script_path "$snapshot_path" 2>/dev/null || true)"
  CODEX_DELEGATE_SNAPSHOT_ACTIVE="$snapshot_run_path" bash "$snapshot_path" "$@"
  snapshot_rc=$?
  exit "$snapshot_rc"
fi

set -uo pipefail

preflight_only=0
if [[ "${1:-}" == "--preflight-only" ]]; then
  preflight_only=1
  shift
fi

role="${1:-coder}"
src="${2:-}"
out="${3:-/tmp/codex-delegate-$$.md}"
requested_cwd="${4:-${CODEX_DELEGATE_CWD:-$PWD}}"
# NÃO resolver o modelo aqui: yaml_model só é lido ~68 linhas abaixo (:116).
# Até 2026-07-26 esta linha era
#   model="${CODEX_DELEGATE_MODEL:-${yaml_model:-gpt-5.5}}"
# e referenciava $yaml_model antes de ele existir -> string vazia -> TODO role
# caía em gpt-5.5, mesmo com models.yaml no formato correto. A resolução real
# ficou junto da leitura do yaml, mantendo a precedência env > yaml > default.
model="${CODEX_DELEGATE_MODEL:-}"

sanitize_field() {
  local value="${1:-unknown}"
  value="${value//$'\n'/;}"
  value="${value//$'\r'/;}"
  value="${value// /%20}"
  printf '%s' "$value"
}

# Out-of-band telemetry: transcripts quote these sentinel strings (docs, narration,
# edits to this very script), so the ONLY reliable failure-rate source is this file.
METRICS_FILE="${CODEX_DELEGATE_METRICS:-${CANUTO_METRICS_FILE:-$HOME/.codex/delegate-metrics.jsonl}}"
start_epoch="$(date +%s)"
metrics_emit() {
  local result="$1" rc="${2:-0}" reason="${3:-}" bytes="${4:-0}" dur
  dur=$(( $(date +%s) - start_epoch ))
  python3 - "$METRICS_FILE" "$role" "${model:-unknown}" "${original_model:-${model:-unknown}}" \
    "${eff:-unknown}" "$result" "$rc" "$reason" "$bytes" "$dur" \
    "${cwd:-$requested_cwd}" "${sandbox:-unknown}" "$out" <<'PY' 2>/dev/null || true
import json, sys
from datetime import datetime, timezone
from pathlib import Path
path, role, model, requested, effort, result, rc, reason, size, duration, cwd, sandbox, out = sys.argv[1:]
legacy_result = "OK" if result == "PREFLIGHT" else result
event = dict(ts=datetime.now(timezone.utc).isoformat(), role=role, model=model, configured_model=model,
             requested_model=requested, effective_model=None, model_evidence="UNVERIFIED",
             eff=effort, effort=effort, result=legacy_result, execution_status=result,
             phase="PREFLIGHT" if result == "PREFLIGHT" else "EXECUTION",
             rc=int(rc), reason=reason,
             bytes=int(size or 0), duration_s=int(duration), duration=int(duration),
             cwd=cwd, sandbox=sandbox, out=out)
target = Path(path)
target.parent.mkdir(parents=True, exist_ok=True)
with target.open("a", encoding="utf-8") as handle:
    handle.write(json.dumps(event) + "\n")
PY
  if [[ -f "${cwd:-$requested_cwd}/.agents/tools/event-log.sh" ]]; then
    bash "${cwd:-$requested_cwd}/.agents/tools/event-log.sh" append DELEGATION \
      actor=codex-delegate role="$role" model="${model:-unknown}" \
      effort="${eff:-unknown}" sandbox="${sandbox:-unknown}" verdict="$result" \
      rc="$rc" duration="$dur" out="$out" >/dev/null 2>&1 || true
  fi
}
machine_line() {
  printf 'CDXRES1 status=%s result=%s rc=%s role=%s out=%s\n' \
    "$1" "$2" "$3" "$(sanitize_field "${role:-unknown}")" "$(sanitize_field "${out:-none}")" >&2
}

cleanup_temps() {
  [[ -n "${tmp_out:-}" && -e "${tmp_out:-}" ]] && rm -f -- "$tmp_out"
  [[ -n "${tmp_log:-}" && -e "${tmp_log:-}" ]] && rm -f -- "$tmp_log"
}
trap cleanup_temps EXIT

emit_executor() {
  local result="$1" fallback="$2" reason="$3"
  printf 'EXECUTOR requested=%s resolved=%s effective=UNVERIFIED result=%s fallback=%s reason=%s cwd=%s\n' \
    "$(sanitize_field "$role")" \
    "$(sanitize_field "codex:${model}/${eff:-unknown}")" \
    "$result" "$fallback" "$(sanitize_field "$reason")" "$(sanitize_field "${cwd:-$requested_cwd}")"
}

legacy_failure() {
  local result="$1" rc="${2:-4}"
  echo "CODEX_DELEGATE_FAILED role=$role rc=$rc reason=$result" >&2
  metrics_emit "$result" "$rc" "${reason:-$result}" "${bytes:-0}"
  machine_line fail "$result" "$rc"
}

# ── models.yaml: config por role como DADO versionado ────────────────────────
# Le <cwd>/.agents/config/models.yaml quando existir. Formato plano de proposito
# (flow-style, uma linha por role) porque este script e bash e `yq` nao esta instalado.
# Precedencia: env var explicita > models.yaml > defaults embutidos abaixo.
# ESTE WRAPPER E GLOBAL: repo sem o arquivo tem de continuar funcionando, entao toda
# leitura aqui e best-effort e nunca aborta.
case "$role" in
  coder|fast|reviewer|architect|maestro|leaf) : ;;
  *)
    eff="invalid"
    emit_executor INVALID_ROLE false invalid_role >&2
    legacy_failure INVALID_ROLE 64
    exit 64
    ;;
esac
models_yaml_get() {
  local role_key="$1" field="$2" file="$3"
  [[ -f "$file" ]] || return 1
  local line
  line="$(awk '/^roles:/{section=1;next} /^[^[:space:]#]/{section=0} section' "$file" \
    | grep -E "^[[:space:]]{2}${role_key}:[[:space:]]*\{" | head -1)" || return 1
  [[ -n "$line" ]] || return 1
  local val
  val="$(printf '%s' "$line" | sed -nE "s/.*[{,][[:space:]]*${field}:[[:space:]]*([^,}[:space:]]+).*/\1/p")"
  [[ -n "$val" ]] || return 1
  printf '%s' "$val"
}

project_root="$(git -C "$requested_cwd" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$requested_cwd")"
models_yaml_file="${CODEX_DELEGATE_MODELS_YAML:-$project_root/.agents/config/models.yaml}"
if [[ -f "$models_yaml_file" ]]; then
  role_entries="$(awk '/^roles:/{section=1;next} /^[^[:space:]#]/{section=0} section' "$models_yaml_file" \
    | grep -E "^[[:space:]]+${role}:" || true)"
  if [[ -n "$role_entries" ]] && ! printf '%s\n' "$role_entries" \
      | grep -Eq "^[[:space:]]{2}${role}:[[:space:]]*\{[^}]+\}[[:space:]]*$"; then
    emit_executor SPAWN_FAILED false invalid_role_config >&2
    legacy_failure SPAWN_FAILED 64
    exit 64
  fi
  if [[ "$(printf '%s\n' "$role_entries" | grep -c ':')" -gt 1 ]]; then
    emit_executor SPAWN_FAILED false duplicate_role_config >&2
    legacy_failure SPAWN_FAILED 64
    exit 64
  fi
fi
yaml_model="$(models_yaml_get "$role" model "$models_yaml_file" 2>/dev/null || true)"
yaml_effort="$(models_yaml_get "$role" effort "$models_yaml_file" 2>/dev/null || true)"
yaml_timeout="$(models_yaml_get "$role" timeout "$models_yaml_file" 2>/dev/null || true)"
yaml_sandbox="$(models_yaml_get "$role" sandbox "$models_yaml_file" 2>/dev/null || true)"
yaml_fallback="$(models_yaml_get "$role" fallback "$models_yaml_file" 2>/dev/null || true)"

# Resolucao do modelo AQUI, e nao no topo do script: precisa vir depois de
# yaml_model existir. Precedencia: CODEX_DELEGATE_MODEL > models.yaml > default.
case "$role" in
  leaf|fast) default_model="gpt-6-luna" ;;
  maestro) default_model="session" ;;
  *) default_model="gpt-6.1-sol" ;;
esac
model="${model:-${yaml_model:-$default_model}}"
if [[ "$model" == "session" ]]; then
  emit_executor MODEL_UNAVAILABLE false session_model_required >&2
  legacy_failure MODEL_UNAVAILABLE 64
  exit 64
fi
original_model="$model"
configured_fallback="${CODEX_DELEGATE_FALLBACK_MODEL:-${yaml_fallback:-none}}"

# Nunca derivar um modelo alternativo pela troca de sufixo.
configured_model_fallback() {
  [[ "$configured_fallback" != "none" && "$configured_fallback" != "$1" ]] || return 1
  printf '%s' "$configured_fallback"
}

# Sandbox por role. O reviewer roda em read-only porque review nao deve escrever:
# ate 2026-07-25 o wrapper nunca passava -s, entao TODO role herdava
# sandbox_mode="danger-full-access" do config.toml — inclusive o reviewer, contrariando
# a propria doc (delegation-framework.md). Override: CODEX_DELEGATE_SANDBOX.
case "$role" in
  reviewer|architect|leaf) sandbox_default="read-only" ;;
  *)        sandbox_default="workspace-write" ;;
esac
sandbox="${CODEX_DELEGATE_SANDBOX:-${yaml_sandbox:-$sandbox_default}}"
case "$role" in
  reviewer|architect|leaf)
    if [[ "$sandbox" != "read-only" ]]; then
      emit_executor SPAWN_FAILED false read_only_required >&2
      legacy_failure SPAWN_FAILED 64
      exit 64
    fi
    ;;
esac
if [[ "$role" == "reviewer" && "$configured_fallback" != "none" ]]; then
  emit_executor SPAWN_FAILED false reviewer_fallback_forbidden >&2
  legacy_failure SPAWN_FAILED 64
  exit 64
fi
if [[ ! "$sandbox" =~ ^(read-only|workspace-write|danger-full-access)$ ]]; then
  emit_executor SPAWN_FAILED true invalid_sandbox >&2
  legacy_failure SPAWN_FAILED 64
  exit 64
fi

case "$role" in
  leaf|fast) eff="${yaml_effort:-low}" ;;
  coder) eff="${yaml_effort:-medium}" ;;
  reviewer|architect|maestro) eff="${yaml_effort:-high}" ;;
  *)
    eff="invalid"
    emit_executor MODEL_UNAVAILABLE true invalid_role >&2
    legacy_failure MODEL_UNAVAILABLE 64
    exit 64
    ;;
esac

if [[ ! "$model" =~ ^[A-Za-z0-9._:-]+$ ]] || [[ ! "$eff" =~ ^(low|medium|high|xhigh|max)$ ]]; then
  emit_executor MODEL_UNAVAILABLE true invalid_model_or_effort >&2
  legacy_failure MODEL_UNAVAILABLE 64
  exit 64
fi
if [[ "$configured_fallback" != "none" && ! "$configured_fallback" =~ ^[A-Za-z0-9._:-]+$ ]]; then
  emit_executor MODEL_UNAVAILABLE false invalid_fallback >&2
  legacy_failure MODEL_UNAVAILABLE 64
  exit 64
fi
models_cache="${CODEX_DELEGATE_MODELS_CACHE:-$HOME/.codex/models_cache.json}"
if [[ -r "$models_cache" ]]; then
  if ! python3 - "$models_cache" "$model" "$configured_fallback" "$eff" <<'PY'
import json, sys
with open(sys.argv[1], encoding="utf-8") as handle:
    registry = {item["slug"]: item for item in json.load(handle).get("models", [])}
for index, slug in enumerate(sys.argv[2:4]):
    if slug == "none":
        continue
    item = registry.get(slug)
    if item is None:
        if index == 1:
            raise SystemExit("fallback ausente do registro de capacidades")
        continue  # ausência no cache não comprova indisponibilidade do primário
    efforts = {entry["effort"] for entry in item.get("supported_reasoning_levels", [])}
    if sys.argv[4] not in efforts:
        raise SystemExit("effort incompatível com o modelo configurado")
PY
  then
    emit_executor MODEL_UNAVAILABLE false incompatible_model_effort >&2
    legacy_failure MODEL_UNAVAILABLE 64
    exit 64
  fi
elif [[ "$configured_fallback" != "none" ]]; then
  emit_executor MODEL_UNAVAILABLE false fallback_capabilities_unknown >&2
  legacy_failure MODEL_UNAVAILABLE 64
  exit 64
fi

if [[ $preflight_only -eq 0 && -z "$src" ]]; then
  emit_executor SPAWN_FAILED true missing_prompt_source >&2
  legacy_failure SPAWN_FAILED 64
  echo "usage: codex-delegate.sh [--preflight-only] <role> <prompt-file|-|text> [out] [cwd]" >&2
  exit 64
fi

# ── Preflight barato de spawn (<2s, sem API) ─────────────────────────────────
# Cobre "arquivo de task legivel e nao-vazio": ate aqui um $EDITOR que salva
# vazio (ou um path sem permissao de leitura) so era descoberto no
# "empty_prompt" tardio (mais abaixo), depois de pagar JWT check + `codex
# login status` + `codex exec --help` -- a mesma classe de espera que gerou os
# SPAWN_FAILED caros medidos na auditoria. So entra em jogo quando $src aponta
# pra um path que EXISTE; texto literal ou "-" (stdin) continuam intocados.
if [[ "$src" != "-" && -e "$src" ]]; then
  if [[ ! -f "$src" ]]; then
    emit_executor SPAWN_FAILED true preflight_task_not_regular_file >&2
    legacy_failure SPAWN_FAILED 64
    exit 4
  fi
  if [[ ! -r "$src" ]]; then
    emit_executor SPAWN_FAILED true preflight_task_file_unreadable >&2
    legacy_failure SPAWN_FAILED 64
    exit 4
  fi
  if [[ ! -s "$src" ]]; then
    emit_executor SPAWN_FAILED true preflight_task_file_empty >&2
    legacy_failure SPAWN_FAILED 64
    exit 4
  fi
fi

if [[ "$out" != /* ]]; then
  out="$PWD/$out"
fi

central_routing=0
codex_executable="codex"
if [[ -x "$HOME/.local/bin/codex-central" && -r "$HOME/.config/r2p-ai-availability/developers-execute-token" ]]; then
  central_routing=1
  codex_executable="$HOME/.local/bin/codex-central"
fi
if ! command -v "$codex_executable" >/dev/null 2>&1; then
  emit_executor EXECUTOR_NOT_FOUND true codex_not_in_path >&2
  legacy_failure EXECUTOR_NOT_FOUND 127
  exit 4
fi
if ! command -v timeout >/dev/null 2>&1; then
  emit_executor SPAWN_FAILED true timeout_not_in_path >&2
  legacy_failure SPAWN_FAILED 127
  exit 4
fi
if [[ ! -d "$requested_cwd" ]]; then
  emit_executor CWD_NOT_FOUND true cwd_does_not_exist >&2
  legacy_failure CWD_NOT_FOUND 66
  exit 4
fi
cwd="$(cd "$requested_cwd" 2>/dev/null && pwd -P)" || {
  emit_executor CWD_NOT_FOUND true cwd_not_accessible >&2
  legacy_failure CWD_NOT_FOUND 66
  exit 4
}

if [[ "${CODEX_DELEGATE_REQUIRE_REPO:-0}" == "1" ]] && ! git -C "$cwd" rev-parse --show-toplevel >/dev/null 2>&1; then
  emit_executor CWD_NOT_REPO true repo_required >&2
  legacy_failure CWD_NOT_REPO 69
  exit 4
fi

out_parent="$(dirname "$out")"
if [[ ! -d "$out_parent" || ! -w "$out_parent" ]]; then
  emit_executor SPAWN_FAILED true preflight_output_parent_not_writable >&2
  legacy_failure SPAWN_FAILED 73
  exit 4
fi
log="${out}.log"
for target in "$out" "$log"; do
  if [[ -L "$target" ]]; then
    emit_executor SPAWN_FAILED true output_target_symlink >&2
    legacy_failure SPAWN_FAILED 73
    exit 4
  fi
  if [[ -e "$target" && ! -f "$target" ]]; then
    emit_executor SPAWN_FAILED true output_target_not_regular >&2
    legacy_failure SPAWN_FAILED 73
    exit 4
  fi
done

check_capacity() {
BACKPRESSURE_FILE="$HOME/.codex/guard/backpressure.json"
if [[ -r "$BACKPRESSURE_FILE" ]]; then
  bp_decision="$(python3 - "$BACKPRESSURE_FILE" "$role" <<'PY' 2>/dev/null || true
import json
import sys
from datetime import datetime, timezone

path, role = sys.argv[1], sys.argv[2]
try:
    with open(path, encoding="utf-8") as handle:
        data = json.load(handle)
except Exception:
    print("BLOCK invalid-backpressure")
    raise SystemExit
if not isinstance(data, dict) or not isinstance(data.get("active"), bool):
    print("BLOCK invalid-backpressure")
    raise SystemExit
if not data.get("active"):
    print("CLEAR")
    raise SystemExit
severity = data.get("severity", "unknown")
reasons = ",".join(map(str, data.get("reasons", []))) or "unknown"
print(f"BLOCK severity={severity} reasons={reasons}; refresh capacity before spawning")
PY
)"
  case "$bp_decision" in
    BLOCK*)
      echo "CODEX_DELEGATE_BACKPRESSURE $bp_decision" >&2
      emit_executor BACKPRESSURE false backpressure_active >&2
      metrics_emit BACKPRESSURE 75 backpressure_active 0
      machine_line fail BACKPRESSURE 75
      exit 75
      ;;
    WARN*) echo "CODEX_DELEGATE_BACKPRESSURE $bp_decision" >&2 ;;
  esac
fi
}
check_capacity

# Deadlines calibrados pelo p90 real medido (auditoria de falha de delegacao,
# 2026-08-11: coder p90=1548s era o maior contribuinte de deadline_exceeded).
# CODEX_DELEGATE_TIMEOUT (env) e yaml_timeout (models.yaml) continuam com
# precedencia sobre este default -- nenhuma variavel nova foi criada, a que
# ja existia so ganhou defaults por role mais folgados que o p90.
case "$role" in
  coder)     timeout_default=1800 ;;
  architect) timeout_default=1500 ;;
  reviewer)  timeout_default=900  ;;
  maestro)   timeout_default=900  ;;
  fast)      timeout_default=300  ;;
  *)         timeout_default=900  ;;
esac
timeout_s="${CODEX_DELEGATE_TIMEOUT:-${yaml_timeout:-$timeout_default}}"
if ! [[ "$timeout_s" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  emit_executor SPAWN_FAILED true invalid_timeout >&2
  legacy_failure SPAWN_FAILED 64
  exit 64
fi
if ! python3 - "$timeout_s" <<'PY' >/dev/null 2>&1
import sys
raise SystemExit(0 if float(sys.argv[1]) > 0 else 1)
PY
then
  emit_executor SPAWN_FAILED true invalid_timeout >&2
  legacy_failure SPAWN_FAILED 64
  exit 64
fi

JWT_CHECK="${CODEX_DELEGATE_JWT_CHECK:-$HOME/.claude/scripts/codex-jwt-check.sh}"
if [[ $central_routing -eq 0 && -x "$JWT_CHECK" ]]; then
  jwt_out="$("$JWT_CHECK" 2>/dev/null)" || true
  case "$jwt_out" in
    CODEX_AUTH_EXPIRED*)
      echo "CODEX_DELEGATE_FALLBACK auth-expired" >&2
      emit_executor AUTH_FAILED true jwt_expired >&2
      legacy_failure AUTH_FAILED 5
      exit 5
      ;;
  esac
fi

if [[ $central_routing -eq 0 ]] && codex login status --help >/dev/null 2>&1; then
  if ! codex login status >/dev/null 2>&1; then
    echo "CODEX_DELEGATE_FALLBACK auth-failed" >&2
    emit_executor AUTH_FAILED true login_status_auth_failed >&2
    legacy_failure AUTH_FAILED 5
    exit 5
  fi
fi

help_out="$("$codex_executable" exec --help 2>&1)"
help_rc=$?
if [[ $help_rc -ne 0 ]]; then
  if [[ "$help_out" == *"model"* && "$help_out" == *"unavailable"* ]]; then
    result="MODEL_UNAVAILABLE"
    reason="exec_help_model_unavailable"
  else
    result="SPAWN_FAILED"
    reason="exec_help_failed"
  fi
  emit_executor "$result" true "$reason" >&2
  legacy_failure "$result" "$help_rc"
  exit 4
fi
if [[ "$help_out" != *"--sandbox"* || "$help_out" != *"--output-last-message"* ]]; then
  emit_executor SPAWN_FAILED false missing_executor_capabilities >&2
  legacy_failure SPAWN_FAILED 64
  exit 64
fi


if [[ $preflight_only -eq 1 ]]; then
  emit_executor PREFLIGHT false preflight_ok
  metrics_emit PREFLIGHT 0 preflight_ok 0
  machine_line ok PREFLIGHT 0
  echo "CODEX_DELEGATE_OK role=$role preflight-only cwd=$cwd"
  exit 0
fi

if [[ "$src" == "-" ]]; then
  prompt="$(</dev/stdin)"
elif [[ -f "$src" ]]; then
  prompt="$(<"$src")"
else
  prompt="$src"
fi
if [[ -z "$prompt" ]]; then
  emit_executor SPAWN_FAILED true empty_prompt >&2
  legacy_failure SPAWN_FAILED 64
  exit 64
fi

tmp_out="$(mktemp "$out_parent/.codex-delegate.$(basename "$out").XXXXXX")" || {
  emit_executor SPAWN_FAILED true output_temp_create_failed >&2
  legacy_failure SPAWN_FAILED 73
  exit 4
}
tmp_log="$(mktemp "$out_parent/.codex-delegate.$(basename "$out").log.XXXXXX")" || {
  emit_executor SPAWN_FAILED true log_temp_create_failed >&2
  legacy_failure SPAWN_FAILED 73
  exit 4
}

# A configuração e o modelo pedido permanecem separados da identidade efetiva.
if [[ $central_routing -eq 1 ]]; then
  availability_context="$("$HOME/.local/bin/ai-availability" --url https://ai.papiro-cart.cloud/central --token-file "$HOME/.config/r2p-ai-availability/agents-read-token" --model "$model" --context 2>/dev/null)"
  prompt="Shared AI availability (operational data; preserve requested model and effort): ${availability_context:-unknown}

$prompt"
fi
read_only_config=()
case "$role" in
  leaf|reviewer|architect)
    read_only_config=(-c features.multi_agent=false)
    prompt="Read-only bounded task. Do not mutate files or delegate. Return one evidence artifact to the parent.

$prompt"
    ;;
esac
model_fallback_used=0

# M3(r3): deteccao de MODEL_UNAVAILABLE no log de execucao. Padroes com fonte:
#   - "unknown model": string real do binario codex CLI 0.147.0 ("Unknown model `slug`").
#   - "model_not_found": codigo de erro da API OpenAI para modelo inexistente/sem acesso.
#   - clausula generica: exige o slug ENTRE aspas/backticks logo apos "model " — a versao
#     antiga ("model" a <=40 chars do indicador, sem aspas) dava falso positivo reproduzido
#     em prosa/erro generico: "loading model config: file not found" e "the model weights
#     were not found on disk" NAO podem casar; "model \`gpt-x\` does not exist" casa.
# "503 service unavailable" e "model context window exceeded" tambem nao casam.
MODEL_ERR_RE="unknown model|model_not_found|The [\"'\`][^\"'\`]+[\"'\`] model is not supported|model [\"'\`][^\"'\`]{1,64}[\"'\`].{0,20}(not found|does not exist|is unavailable|not supported)"

while :; do
  check_capacity
  rc=0
  (
    cd "$cwd" &&
    timeout "$timeout_s" "$codex_executable" exec --color never --skip-git-repo-check -s "$sandbox" \
      -c model="$model" -c model_reasoning_effort="$eff" "${read_only_config[@]}" -o "$tmp_out" "$prompt" < /dev/null > "$tmp_log" 2>&1
  ) || rc=$?

  if [[ $rc -eq 0 ]] && LC_ALL=C grep -q '[^[:space:]]' "$tmp_out"; then
    break
  fi

  bytes="$(wc -c < "$tmp_out" 2>/dev/null | tr -d ' ')"
  partial_lines="$(wc -l < "$tmp_log" 2>/dev/null | tr -d ' ')"
  if [[ $rc -eq 124 ]]; then
    result="TIMEOUT"
    reason="deadline_exceeded"
  elif [[ $rc -ne 0 && -s "$tmp_log" ]] && grep -Eiq "$MODEL_ERR_RE" "$tmp_log"; then
    # A-A3 + M3(r3): regex definida em MODEL_ERR_RE (ver comentario na definicao, acima do
    # loop). A clausula generica agora exige o slug entre aspas/backticks — "not found"
    # solto perto da palavra "model" (prosa do agente, erro de arquivo) nao dispara mais.
    result="MODEL_UNAVAILABLE"
    reason="runtime_model_unavailable"
  elif [[ $rc -ne 0 ]]; then
    result="SPAWN_FAILED"
    reason="codex_exec_nonzero"
  else
    result="EMPTY_OUTPUT"
    reason="zero_byte_result"
  fi

  # Alternativa explícita: apenas indisponibilidade, sem parcial e no máximo uma vez.
  # Sem loop -- model_fallback_used trava a segunda tentativa de retentar.
  if [[ $central_routing -eq 0 && "$result" == "MODEL_UNAVAILABLE" && $model_fallback_used -eq 0
        && ! -s "$tmp_out" ]]; then
    fallback_model="$(configured_model_fallback "$model")"
    if [[ -n "$fallback_model" ]]; then
      echo "CODEX_DELEGATE_FALLBACK model-unavailable $model -> $fallback_model" >&2
      # A-M4: o `continue` pulava o bloco de resgate abaixo e a 2a tentativa truncava
      # tmp_log/tmp_out — a evidencia da 1a falha sumia. Rotaciona antes de retentar.
      # M1(r3): truncagem SO quando o mv confirmou (rc 0). Antes, `mv || true` seguido de
      # truncagem incondicional apagava a evidencia mesmo com o mv falho. mv falho agora
      # preserva o original, avisa, e a 2a tentativa escreve num temp NOVO.
      # M2(r3): sufixo $$ no attempt1 — `mv -f` sobrescrevia o attempt1 de um run anterior
      # com o mesmo $out. O marcador stderr cita o nome real.
      if [[ -s "$tmp_log" ]]; then
        attempt1_log="${log}.attempt1.$$"
        if mv -f -- "$tmp_log" "$attempt1_log" 2>/dev/null; then
          echo "CODEX_DELEGATE_ATTEMPT1_LOG $attempt1_log" >&2
          : > "$tmp_log" 2>/dev/null || true
        else
          echo "CODEX_DELEGATE_ATTEMPT1_LOG_MOVE_FAILED preserved=$tmp_log" >&2
          new_tmp_log="$(mktemp "$out_parent/.codex-delegate.$(basename "$out").log.XXXXXX" 2>/dev/null)" \
            && tmp_log="$new_tmp_log" \
            || echo "CODEX_DELEGATE_ATTEMPT1_LOG_AT_RISK attempt2 vai sobrescrever $tmp_log" >&2
        fi
      fi
      if [[ -s "$tmp_out" ]]; then
        attempt1_out="${out}.attempt1.$$.partial.md"
        if mv -f -- "$tmp_out" "$attempt1_out" 2>/dev/null; then
          echo "CODEX_DELEGATE_ATTEMPT1_PARTIAL $attempt1_out" >&2
          : > "$tmp_out" 2>/dev/null || true
        else
          echo "CODEX_DELEGATE_ATTEMPT1_PARTIAL_MOVE_FAILED preserved=$tmp_out" >&2
          new_tmp_out="$(mktemp "$out_parent/.codex-delegate.$(basename "$out").XXXXXX" 2>/dev/null)" \
            && tmp_out="$new_tmp_out" \
            || echo "CODEX_DELEGATE_ATTEMPT1_PARTIAL_AT_RISK attempt2 vai sobrescrever $tmp_out" >&2
        fi
      fi
      model_fallback_used=1
      model="$fallback_model"
      continue
    fi
  fi

  # Rescue: publish whatever was produced BEFORE the EXIT trap can delete it
  # (a timed-out run once produced a 79k-line log that was silently discarded).
  if [[ -s "$tmp_log" ]]; then
    mv -f -- "$tmp_log" "$log" 2>/dev/null && tmp_log="" || true
  fi
  if [[ -s "$tmp_out" ]]; then
    mv -f -- "$tmp_out" "${out}.partial.md" 2>/dev/null && tmp_out="" || true
  fi
  if [[ "$result" == "TIMEOUT" ]]; then
    partial_keep="$HOME/.codex/delegate-partials/$(date -u +%Y%m%dT%H%M%SZ)-$role-$$.partial.md"
    if [[ ! -s "${out}.partial.md" && -s "$log" ]]; then
      tail -c 20000 "$log" > "${out}.partial.md" 2>/dev/null || true
    fi
    if [[ -s "${out}.partial.md" ]]; then
      mkdir -p "$(dirname "$partial_keep")" 2>/dev/null &&
        cp "${out}.partial.md" "$partial_keep" 2>/dev/null || true
    fi
  fi
  if [[ "$result" == "TIMEOUT" ]]; then
    if [[ "${partial_lines:-0}" -gt 1000 ]]; then
      reason="deadline_exceeded_partial_rescued"
    fi
    echo "CODEX_DELEGATE_PARTIAL $log lines=${partial_lines:-0}" >&2
  fi
  if [[ $model_fallback_used -eq 1 ]]; then
    reason="fallback_from_${original_model}_${reason}"
  fi
  legacy_failure "$result" "$rc"
  echo "CODEX_DELEGATE_FAILED role=$role rc=$rc bytes=${bytes:-0}" >&2
  emit_executor "$result" true "$reason" >&2
  exit 4
done

mv -f -- "$tmp_out" "$out" || {
  emit_executor SPAWN_FAILED true output_publish_failed >&2
  legacy_failure SPAWN_FAILED 73
  exit 4
}
tmp_out=""
mv -f -- "$tmp_log" "$log" || {
  emit_executor SPAWN_FAILED true log_publish_failed >&2
  legacy_failure SPAWN_FAILED 73
  exit 4
}
tmp_log=""

success_reason="completed"
if [[ $model_fallback_used -eq 1 ]]; then
  success_reason="fallback_from_${original_model}"
fi
emit_executor OK false "$success_reason"
final_bytes="$(wc -c < "$out" | tr -d ' ')"
metrics_emit OK 0 "$success_reason" "$final_bytes"
machine_line ok OK 0
echo "CODEX_DELEGATE_OK role=$role -> $out ($final_bytes bytes)"
