#!/usr/bin/env bash
# codex-pretool-guard.sh — PreToolUse (Bash) hook.
#
# Duas classes de gate (ADR-0002 do edge-of-chaos; ver .context/fase2/spec-A1-guard.md
# item 6). Um fato mora numa classe só:
# - CONFIABILIDADE (este arquivo): calibrável, degradável, overridável COM
#   REGISTRO. Cobre a checagem estática de delegação Codex arriscada
#   (handle_codex_cli_command: context package, prompt injection, C6) e o
#   review de pre-commit (handle_commit_gate). SÓ a perna de review/veredito do
#   commit gate responde à escada CANUTO_GUARD_MODE (0=off/1=observe/2=gate,
#   ver abaixo) — os checks estáticos de handle_codex_cli_command continuam
#   sempre ativos em qualquer modo; não são "review calibrável".
# - IDENTIDADE (protect-files.sh, protect-env-read.sh, hooks de keychain):
#   binário, nunca calibrável, NÃO pertence a esta escada e NÃO ganha modo
#   observe. Este arquivo não os altera nem os invoca.

set -euo pipefail

# Sem payload num TTY: `cat` sem stdin fechado bloqueia para sempre e o
# runtime que espera o hook congela junto (regra de TTY/pipe do CLAUDE.md).
HOOK_INPUT=""
[ -t 0 ] || HOOK_INPUT=$(cat 2>/dev/null || echo "")
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
ROOT_DIR="$(cd "$PROJECT_DIR" && git rev-parse --show-toplevel 2>/dev/null || pwd)"

_degraded_flag() {
  local flag_dir="$ROOT_DIR/.agents/tmp/codex"
  mkdir -p "$flag_dir" 2>/dev/null || true
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" >> "$flag_dir/degraded-mode.flag"
  printf '[codex-pretool-guard] DEGRADED: %s\n' "$1" >&2
}

if ! command -v jq >/dev/null 2>&1; then
  _degraded_flag "jq not found — all Codex validation skipped"
  exit 0
fi

COMMON_LIB="$ROOT_DIR/.agents/tools/codex-common.sh"
DIFF_SCRIPT="$ROOT_DIR/.agents/tools/codex-diff-context.sh"

# Projects without a local .agents/ checkout fall back to the globally
# installed copies (install.sh ships them to ~/.claude/scripts/).
GLOBAL_SCRIPTS_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts"
[ -f "$COMMON_LIB" ] || COMMON_LIB="$GLOBAL_SCRIPTS_DIR/codex-common.sh"
[ -f "$DIFF_SCRIPT" ] || DIFF_SCRIPT="$GLOBAL_SCRIPTS_DIR/codex-diff-context.sh"

if [ ! -f "$COMMON_LIB" ]; then
  _degraded_flag "codex-common.sh not found — all Codex validation skipped"
  exit 0
fi

# shellcheck source=/dev/null
source "$COMMON_LIB"

TOOL_NAME=$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)

# ── Escada CANUTO_GUARD_MODE (spec A1 item 2) ───────────────────────────────
# 0=off (guard não roda) / 1=observe (roda o review inteiro, registra o que
# teria feito, nunca bloqueia) / 2=gate (comportamento atual — bloqueia em
# HOLD). Default 2: manter enforcement; a des/re-escalada é decisão futura POR
# EVIDÊNCIA (eventos type=guard-verdict/guard-dark), não um default silencioso.
# Valor fora de {0,1,2} cai em 2 (fail-safe = o mais estrito, não o mais frouxo).
GUARD_MODE="${CANUTO_GUARD_MODE:-2}"
case "$GUARD_MODE" in
  0|1|2) ;;
  *) GUARD_MODE=2 ;;
esac

block_with_message() {
  printf '%s\n' "$1" >&2
  exit 2
}

reviewer_cmd() {
  local project_dir="$1"
  local schema_file="$2"
  local output_file="$3"
  local prompt_file="$4"
  local used_file="$5"
  local error_file="${6:-}"

  local review_dir
  review_dir=$(codex_review_exec_dir "$project_dir")
  codex_run_reviewer "$review_dir" "$schema_file" "$output_file" "$prompt_file" "$used_file" "$error_file"
}

# CANUTO_GUARD_MODE=0: nota UMA vez por sessão de que o commit gate está
# desligado (marker em $TMPDIR — padrão _canuto_missing_lib_note de
# session-start.sh — para não floodar o event log a cada `git commit` na
# mesma sessão). Best-effort: nunca falha o caller.
_guard_mode_disabled_note() {
  local command_text="${1:-}"
  local session_id marker event_json
  session_id=$(printf '%s' "$HOOK_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
  [ -n "$session_id" ] || session_id="nosession"
  marker="${TMPDIR:-/tmp}/canuto-guard-mode0-${session_id}"
  if [ -e "$marker" ]; then
    return 0
  fi
  : > "$marker" 2>/dev/null || true
  event_json=$(jq -cn \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg command "$command_text" \
    '{timestamp:$timestamp,type:"guard-dark",reason:"disabled",mode:0,enforced:false,status:"dark",provider:"codex",summary:"CANUTO_GUARD_MODE=0 — commit review guard disabled for this session.",command:$command}' 2>/dev/null) || event_json=""
  if [ -n "$event_json" ]; then
    codex_append_event "$ROOT_DIR" "$event_json" 2>/dev/null || true
  fi
  printf '%s\n' "[codex-pretool-guard] CANUTO_GUARD_MODE=0 — commit review guard disabled for this session (evento type=guard-dark reason=disabled registrado uma vez por sessão em metrics)." >&2
  return 0
}

# Infra ≠ veredito (ADR/issue #55 do eoc, spec A1 item 5): quando o reviewer
# Codex (fast ou full — ambos convergem em review_ok=false, ou devolve saída
# que não valida contra o schema) falha por transporte/timeout/auth, isso
# NUNCA vira HOLD nem PASS fabricado. Este evento formaliza o que o caminho
# fail-open já fazia silenciosamente: o commit segue, mas a ausência de review
# fica registrada e visível, não escondida atrás de um veredicto qualquer.
_guard_dark_event() {
  local reason="${1:-unknown}"
  local review_id_arg="${2:-}"
  local event_json
  event_json=$(jq -cn \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg reason "$reason" \
    --arg review_id "$review_id_arg" \
    --argjson mode "$GUARD_MODE" \
    '{timestamp:$timestamp,type:"guard-dark",reason:$reason,review_id:$review_id,mode:$mode,enforced:false,status:"dark",provider:"codex",summary:"review indisponível — commit segue SEM review (dark)."}' 2>/dev/null) || event_json=""
  if [ -n "$event_json" ]; then
    codex_append_event "$ROOT_DIR" "$event_json" 2>/dev/null || true
  fi
  printf '%s\n' "[codex-pretool-guard] review indisponível — commit segue SEM review (dark). reason=$reason (evento type=guard-dark registrado em metrics)." >&2
}

handle_codex_cli_command() {
  local command_text="$1"
  local command_size=${#command_text}
  local context_hint=false
  local package_path=""
  local codex_exec_count=0

  # Herestring, nunca `printf "$var" | grep` (S1): sob pipefail, grep -q saindo
  # no primeiro match dava SIGPIPE no printf (rc 141) em payload grande e a
  # condição virava FALSA com o match presente. <<< alimenta por arquivo
  # temporário — sem pipe, sem SIGPIPE. Padrão vale para o arquivo inteiro.
  if ! grep -Eq 'codex[[:space:]]+exec' <<<"$command_text"; then
    return 0
  fi

  if ! grep -Eq -- '--profile(=|[[:space:]]+)(coder|fast)' <<<"$command_text"; then
    return 0
  fi

  while IFS= read -r package_path; do
    [ -n "$package_path" ] || continue
    if codex_context_package_valid "$ROOT_DIR/$package_path"; then
      context_hint=true
    else
      block_with_message "Codex delegation blocked: context package '$package_path' is missing, stale, or invalid."
    fi
  done < <(grep -oE '\.agents/tmp/context-package[^[:space:]]*\.md' <<<"$command_text" || true)

  codex_exec_count=$(grep -oE 'codex[[:space:]]+exec' <<<"$command_text" | wc -l | tr -d '[:space:]')
  if [ "${codex_exec_count:-0}" -gt 1 ] && [ "$context_hint" = false ]; then
    block_with_message "Codex delegation blocked: parallel codex exec requires scoped context packages in .agents/tmp/. Generate them first with .agents/tools/codex-context-package.sh."
  fi

  # C6: Basic prompt injection guard
  if grep -qiE '(ignore (previous|all|above) instructions|you are now|system prompt override|disregard.*instructions|new persona|forget everything)' <<<"$command_text"; then
    block_with_message "Codex delegation blocked: prompt contains patterns resembling injection. Review the prompt content before delegating."
  fi

  if [ "$command_size" -gt 240 ] && [ "$context_hint" = false ]; then
    block_with_message "Codex delegation blocked: missing context package for a medium/large task. Generate .agents/tmp/context-package.md before calling codex exec --profile coder."
  fi
}

handle_commit_gate() {
  local command_text="$1"
  local staged_files
  local sensitive=false
  local review_kind="pre-commit"
  local diff_mode="index"
  local event_status="skipped"
  local event_json=""
  local hook_start_ts
  hook_start_ts=$(date +%s)
  local review_id
  local tmp_dir
  local prompt_file
  local schema_file
  local output_file
  local review_markdown
  local diff_payload
  local verdict
  local summary
  local event_summary
  local score
  local issues_count
  local used_file
  local error_file
  local used_candidate="model:unknown"
  local model_name="unknown"
  local reviewer_path="unavailable"
  local preferred_candidate
  local preferred_path
  local preferred_model
  local fallback_occurred="true"
  local override_files=""
  local sensitive_omitted=false
  local omitted_count=0
  local guard_enforced="false"
  if [ "$GUARD_MODE" = "2" ]; then
    guard_enforced="true"
  fi

  if ! grep -Eq '(^|[[:space:]])git[[:space:]]+commit([[:space:]]|$)' <<<"$command_text"; then
    return 0
  fi

  # CANUTO_GUARD_MODE=0: guard não roda — nem override, nem diff, nem review.
  # Sai cedo e registra a ausência (uma vez por sessão). (spec A1 item 2)
  if [ "$GUARD_MODE" = "0" ]; then
    _guard_mode_disabled_note "$command_text"
    return 0
  fi

  # Deliberate override (mirrors CANUTO_ALLOW_PROTECTED / CANUTO_ALLOW_ENV_READ).
  if [ "${CANUTO_ALLOW_COMMIT:-}" = "1" ] || grep -q 'CANUTO_ALLOW_COMMIT=1' <<<"$command_text"; then
    # Telemetria do override (auditoria 2026-08-01: 92 usos no mecesa, 53 no
    # lucrando — sem evento, a próxima auditoria não mede se o número caiu).
    # Fail-open: telemetria NUNCA pode impedir o commit.
    override_files=$(git -C "$ROOT_DIR" diff --cached --name-only --diff-filter=ACMR 2>/dev/null || true)
    if [ -z "$override_files" ]; then
      override_files=$(git -C "$ROOT_DIR" diff HEAD --name-only --diff-filter=ACMR 2>/dev/null || true)
    fi
    # O veto ganha caneta (eoc ADR-0024): a razão do override vira dado de
    # calibração. Não é exigida — só registrada; a catraca vem por evidência.
    event_json=$(jq -cn \
      --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg command "$command_text" \
      --arg files "$override_files" \
      --arg reason "${CANUTO_ALLOW_REASON:-unstated}" \
      --argjson mode "$GUARD_MODE" \
      --argjson enforced "$guard_enforced" \
      '{timestamp:$timestamp,type:"override-commit",review_type:"pre-commit",status:"override",provider:"codex",mode:$mode,enforced:$enforced,reason:$reason,summary:"Commit review skipped via CANUTO_ALLOW_COMMIT=1.",command:$command,files:($files | split("\n") | map(select(length > 0)))}' 2>/dev/null) || event_json=""
    if [ -n "$event_json" ]; then
      codex_append_event "$ROOT_DIR" "$event_json" 2>/dev/null || true
    fi
    printf '%s\n' "[codex-pretool-guard] commit review skipped (CANUTO_ALLOW_COMMIT=1) — override registrado em metrics (type=override-commit). Dica: CANUTO_ALLOW_REASON=\"...\" documenta o porquê." >&2
    return 0
  fi

  cd "$ROOT_DIR"
  if grep -Eq '(^|[[:space:]])(--all|-a)([[:space:]]|$)|(^|[[:space:]])-[A-Za-z]*a[A-Za-z]*([[:space:]]|$)' <<<"$command_text"; then
    diff_mode="all-tracked"
    if git rev-parse --verify HEAD >/dev/null 2>&1; then
      if git diff HEAD --quiet --exit-code; then
        return 0
      fi
    elif git diff --cached --quiet --exit-code && git diff --quiet --exit-code; then
      return 0
    fi
  else
    if git diff --cached --quiet --exit-code; then
      return 0
    fi
  fi

  if [ ! -x "$DIFF_SCRIPT" ]; then
    return 0
  fi

  if ! command -v codex >/dev/null 2>&1; then
    return 0
  fi

  declare -a staged_array=()
  while IFS= read -r staged_path; do
    [ -n "$staged_path" ] || continue
    staged_array+=("$staged_path")
  done < <(
    if [ "$diff_mode" = "all-tracked" ] && git rev-parse --verify HEAD >/dev/null 2>&1; then
      git diff HEAD --name-only --diff-filter=ACMR 2>/dev/null
    else
      git diff --cached --name-only --diff-filter=ACMR 2>/dev/null
    fi | sed '/^$/d'
  )
  staged_files=$(printf '%s\n' "${staged_array[@]}")

  for path in "${staged_array[@]}"; do
    if codex_is_security_sensitive_path "$path"; then
      sensitive=true
      review_kind="pre-commit-security"
      break
    fi
  done

  # ── Threshold: skip or downgrade review by diff size ──────────────────
  local diff_line_count=0
  local _shortstat=""
  if [ "$diff_mode" = "all-tracked" ] && git rev-parse --verify HEAD >/dev/null 2>&1; then
    _shortstat=$(git diff HEAD --shortstat 2>/dev/null)
  else
    _shortstat=$(git diff --cached --shortstat 2>/dev/null)
  fi
  if [ -n "$_shortstat" ]; then
    # `|| diff_line_count=0`: shortstat sem insertions/deletions (ex.: só
    # chmod) faz o grep sair 1 e, sob pipefail+set -e, matava o hook aqui.
    diff_line_count=$(grep -oE '[0-9]+ (insertion|deletion)' <<<"$_shortstat" | awk '{s+=$1} END{print s+0}') || diff_line_count=0
  fi

  local review_tier="full"
  if [ "$sensitive" = true ]; then
    review_tier="full"
  elif [ "$diff_line_count" -lt 20 ]; then
    return 0
  elif [ "$diff_line_count" -le 100 ]; then
    review_tier="fast"
  fi

  # Fail-open: uma falha interna do gerador de contexto nunca pode quebrar o
  # commit — sem payload não há review, e o gate avisa em vez de bloquear.
  if ! diff_payload=$(bash "$DIFF_SCRIPT" --commit-candidate "$diff_mode" 2>/dev/null) || [ -z "$diff_payload" ]; then
    printf '%s\n' "[codex-pretool-guard] codex-diff-context.sh failed — commit review skipped (fail-open)." >&2
    return 0
  fi

  # O budgeter do diff-context nunca corta arquivo no meio: ou o arquivo entra
  # com hunks completos, ou sai INTEIRO e aparece em "Omitted Files (not
  # reviewed)". Estas flags dizem ao prompt como instruir o reviewer.
  # S1: herestring, nunca `printf | grep -q` — payload >64KB com match no
  # header fazia o grep sair cedo, o printf levar SIGPIPE (rc 141) e o
  # pipefail declarar FALSO exatamente no commit grande (o caso-alvo).
  if grep -q '^- sensitive_files_omitted: true$' <<<"$diff_payload"; then
    sensitive_omitted=true
  fi
  # R10: `q` no sed substitui o `| head -1` (head saindo cedo = mesmo SIGPIPE).
  omitted_count=$(sed -n '/^- files_omitted: [0-9][0-9]*$/{s/^- files_omitted: //p;q;}' <<<"$diff_payload")
  case "$omitted_count" in ''|*[!0-9]*) omitted_count=0 ;; esac

  tmp_dir=$(codex_tmp_dir "$ROOT_DIR")
  review_id="$(date -u +%Y%m%dT%H%M%SZ)-$$"
  prompt_file="$tmp_dir/pre-commit-$review_id.prompt.txt"
  schema_file="$tmp_dir/pre-commit-$review_id.schema.json"
  output_file="$tmp_dir/pre-commit-$review_id.json"
  used_file="$tmp_dir/pre-commit-$review_id.used"
  error_file="$tmp_dir/pre-commit-$review_id.err"
  review_markdown=$(codex_review_markdown_path "$ROOT_DIR" "latest-pre-commit-review")
  preferred_candidate=$(codex_reviewer_preferred_candidate 2>/dev/null || true)
  preferred_path=$(codex_candidate_path_label "$preferred_candidate")
  preferred_model=$(codex_candidate_model_name "$preferred_candidate")

  cat > "$schema_file" <<'EOF'
{
  "type": "object",
  "additionalProperties": false,
  "required": ["schema_version", "verdict", "summary", "score", "issues"],
  "properties": {
    "schema_version": { "type": "string", "const": "1.0" },
    "verdict": { "type": "string", "enum": ["COMMIT", "HOLD", "SKIP-TRUNCATED"] },
    "summary": { "type": "string" },
    "score": { "type": "number" },
    "issues": {
      "type": "array",
      "items": {
        "type": "object",
        "additionalProperties": false,
        "required": ["severity", "file", "line", "issue", "fix"],
        "properties": {
          "severity": { "type": "string", "enum": ["high", "medium", "low"] },
          "file": { "type": "string" },
          "line": { "type": ["integer", "null"] },
          "issue": { "type": "string" },
          "fix": { "type": "string" }
        }
      }
    }
  }
}
EOF

  {
    echo "You are reviewing staged changes before git commit."
    echo "Return JSON only, matching the provided schema."
    echo "Use HOLD only for real findings in the reviewed hunks: bugs, security risks, missing edge cases, or convention regressions that should block the commit."
    echo "Do not run shell commands, open files, or inspect the workspace."
    echo ""
    echo "How this diff context was assembled (context budgeter contract):"
    echo "- Every file present in the Patch Excerpt is shown with COMPLETE hunks — files are never cut mid-file."
    echo "- Files that did not fit the context budget were omitted IN FULL and are listed under 'Omitted Files (not reviewed)'."
    echo "- NEVER return HOLD because context is missing, omitted, or truncated. Omission is a deliberate budgeting decision, not an author error."
    if [ "$sensitive_omitted" = true ]; then
      echo "- At least one SECURITY-SENSITIVE file was omitted from this context. If you cannot vouch for this commit without reviewing the omitted file(s), return verdict SKIP-TRUNCATED. SKIP-TRUNCATED is allowed and expected in that case — the gate treats it as an advisory pass, never as a block or a failure."
    else
      echo "- No security-sensitive file was omitted from this context. Verdict SKIP-TRUNCATED does not apply to this review; answer COMMIT or HOLD."
    fi
    echo "If something inside an included hunk is unclear, record it as an issue instead of using tools."
    if [ "$sensitive" = true ]; then
      echo "These files are security-sensitive. Treat auth, secrets, injection, access control, RLS, and race conditions as release-blocking."
    fi
    echo ""
    echo "Changed files:"
    printf '%s\n' "$staged_files"
    echo ""
    cat <<'EOF'
Focus on:
- correctness and regressions
- security and access control
- performance footguns
- missing test coverage for the happy path
- violations of existing project patterns
EOF
    echo ""
    printf '%s\n' "$diff_payload"
  } > "$prompt_file"

  local review_ok=false
  if [ "$review_tier" = "fast" ]; then
    # Tier fast: perfil `fast` com reasoning baixo (o modelo sai de models.yaml
    # via perfil — não citar versão aqui, vira defasagem silenciosa).
    #
    # O timeout NÃO é opcional. Este hook roda SÍNCRONO dentro do Codex: o
    # processo pai fica parado até o hook retornar, e aqui o hook sobe um SEGUNDO
    # `codex exec` completo (config, auth, startup de MCP). Sem limite, qualquer
    # travada do filho — MCP que não sobe, uvx buscando pacote na rede, auth
    # expirada esperando input — congela a UI inteira sem log e sem saída. Foi
    # exatamente esse o sintoma relatado ("codex todo travado, parece deadlock").
    # O caminho `full` já era limitado por codex_run_with_timeout desde sempre;
    # só o tier fast — o que deveria ser o mais barato — ficou sem rédea.
    # Limite menor que o do full de propósito: um review "rápido" que passa de
    # ~45s já falhou no que prometia; melhor degradar para advisory que travar.
    local fast_timeout="${CODEX_FAST_REVIEW_TIMEOUT:-45}"
    local fast_cmd=(codex exec -C "$ROOT_DIR" -s read-only --skip-git-repo-check --ephemeral --profile fast -c 'model_reasoning_effort="low"' --output-schema "$schema_file" -o "$output_file" -)
    if codex_run_with_timeout "$fast_timeout" "${fast_cmd[@]}" < "$prompt_file" >/dev/null 2>&1; then
      review_ok=true
      printf '%s\n' "profile:fast" > "$used_file"
    fi
  else
    if reviewer_cmd "$ROOT_DIR" "$schema_file" "$output_file" "$prompt_file" "$used_file" "$error_file" >/dev/null 2>&1; then
      review_ok=true
    fi
  fi

  if [ "$review_ok" = false ]; then
    {
      echo "# Codex Pre-Commit Review"
      echo ""
      echo "- review_id: $review_id"
      echo "- kind: $review_kind"
      echo "- preferred_reviewer_path: $preferred_path"
      echo "- preferred_model: $preferred_model"
      echo "- reviewer_path: unavailable"
      echo "- model: none"
      echo "- verdict: DEGRADED"
      echo "- fallback_occurred: true"
      echo ""
      echo "## Summary"
      echo "Reviewer path unavailable. Commit review ran in degraded advisory mode."
      if [ -s "$error_file" ]; then
        echo ""
        echo "## Reviewer Errors"
        sed 's/^/    /' "$error_file"
      fi
    } > "$review_markdown"
    event_json=$(jq -cn \
      --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg review_id "$review_id" \
      --arg review_kind "$review_kind" \
      --arg status "degraded" \
      --arg command "$command_text" \
      --arg error_file "$error_file" \
      --arg preferred_path "$preferred_path" \
      --arg preferred_model "$preferred_model" \
      --argjson mode "$GUARD_MODE" \
      --argjson enforced "$guard_enforced" \
      --arg files "$staged_files" \
      '{timestamp:$timestamp,review_id:$review_id,review_type:$review_kind,status:$status,provider:"codex",preferred_reviewer_path:$preferred_path,preferred_model:$preferred_model,reviewer_path:"unavailable",model:"none",fallback_occurred:true,mode:$mode,enforced:$enforced,summary:"Reviewer path unavailable. Commit review ran in degraded advisory mode.",command:$command,error_file:$error_file,files:($files | split("\n") | map(select(length > 0)))}')
    codex_append_event "$ROOT_DIR" "$event_json"
    # Infra ≠ veredito (spec A1 item 5): o reviewer (fast ou full) falhou por
    # transporte/timeout/auth — nunca vira HOLD nem PASS fabricado.
    _guard_dark_event "reviewer-unavailable" "$review_id"
    printf '%s\n' "Codex commit review degraded: reviewer path unavailable. See .agents/tmp/codex/latest-pre-commit-review.md for details." >&2
    return 0
  fi

  if [ ! -s "$output_file" ] || ! jq -e '
    (.verdict | type == "string")
    and (.summary | type == "string")
    and (.score | type == "number")
    and (.issues | type == "array")
  ' "$output_file" >/dev/null 2>&1; then
    used_candidate=$(cat "$used_file" 2>/dev/null || true)
    reviewer_path=$(codex_candidate_path_label "$used_candidate")
    model_name=$(codex_candidate_model_name "$used_candidate")
    event_json=$(jq -cn \
      --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg review_id "$review_id" \
      --arg review_kind "$review_kind" \
      --arg status "degraded" \
      --arg command "$command_text" \
      --arg error_file "$error_file" \
      --arg output_file "$output_file" \
      --arg preferred_path "$preferred_path" \
      --arg preferred_model "$preferred_model" \
      --arg reviewer_path "$reviewer_path" \
      --arg model "$model_name" \
      --argjson mode "$GUARD_MODE" \
      --argjson enforced "$guard_enforced" \
      --arg files "$staged_files" \
      '{timestamp:$timestamp,review_id:$review_id,review_type:$review_kind,status:$status,provider:"codex",preferred_reviewer_path:$preferred_path,preferred_model:$preferred_model,reviewer_path:$reviewer_path,model:$model,fallback_occurred:true,mode:$mode,enforced:$enforced,summary:"Reviewer returned invalid output. Commit review ran in degraded advisory mode.",command:$command,error_file:$error_file,output_file:$output_file,files:($files | split("\n") | map(select(length > 0)))}')
    codex_append_event "$ROOT_DIR" "$event_json"
    # Infra ≠ veredito (spec A1 item 5): a saída do reviewer não validou contra
    # o schema — trate como falha de infra, não como um veredicto qualquer.
    _guard_dark_event "invalid-output" "$review_id"
    {
      echo "# Codex Pre-Commit Review"
      echo ""
      echo "- review_id: $review_id"
      echo "- kind: $review_kind"
      echo "- preferred_reviewer_path: $preferred_path"
      echo "- preferred_model: $preferred_model"
      echo "- reviewer_path: $reviewer_path"
      echo "- model: $model_name"
      echo "- verdict: DEGRADED"
      echo "- fallback_occurred: true"
      echo ""
      echo "## Summary"
      echo "Reviewer returned invalid output. Commit review ran in degraded advisory mode."
      if [ -s "$error_file" ]; then
        echo ""
        echo "## Reviewer Errors"
        sed 's/^/    /' "$error_file"
      fi
    } > "$review_markdown"
    printf '%s\n' "Codex commit review degraded: reviewer returned invalid output. See .agents/tmp/codex/latest-pre-commit-review.md for details." >&2
    return 0
  fi

  if [ -f "$used_file" ]; then
    used_candidate=$(cat "$used_file" 2>/dev/null || echo "model:unknown")
    reviewer_path=$(codex_candidate_path_label "$used_candidate")
    model_name=$(codex_candidate_model_name "$used_candidate")
    fallback_occurred=$(codex_candidate_fallback_occurred "$used_candidate")
  fi

  verdict=$(jq -r '.verdict' "$output_file" 2>/dev/null || echo "COMMIT")
  summary=$(jq -r '.summary' "$output_file" 2>/dev/null || echo "Review completed.")
  score=$(jq -r '.score' "$output_file" 2>/dev/null || echo "0")
  issues_count=$(jq '.issues | length' "$output_file" 2>/dev/null || echo "0")
  event_status="$verdict"
  # X3: o PORQUÊ viaja junto do veredito no evento — summary sanitizado (sem
  # aspas/quebras) e truncado a 160 chars. A próxima auditoria classifica
  # HOLDs por causa direto do JSONL, sem abrir o markdown de cada review.
  event_summary=$(tr -d "\r\n\"'" <<<"$summary" | cut -c1-160) || event_summary=""

  {
    echo "# Codex Pre-Commit Review"
    echo ""
    echo "- review_id: $review_id"
    echo "- kind: $review_kind"
    echo "- preferred_reviewer_path: $preferred_path"
    echo "- preferred_model: $preferred_model"
    echo "- reviewer_path: $reviewer_path"
    echo "- model: $model_name"
    echo "- fallback_occurred: $fallback_occurred"
    echo "- verdict: $verdict"
    echo "- score: $score"
    echo ""
    echo "## Summary"
    echo "$summary"
    echo ""
    echo "## Issues"
    jq -r '.issues[]? | "- [" + .severity + "] " + .file + ":" + ((.line // 0)|tostring) + " - " + .issue + " -> " + .fix' "$output_file"
  } > "$review_markdown"

  local hook_end_ts
  hook_end_ts=$(date +%s)
  local hook_duration_s=$((hook_end_ts - hook_start_ts))

  event_json=$(jq -cn \
    --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg review_id "$review_id" \
    --arg review_kind "$review_kind" \
    --arg status "$event_status" \
    --arg command "$command_text" \
    --arg summary "$event_summary" \
    --arg preferred_path "$preferred_path" \
    --arg preferred_model "$preferred_model" \
    --arg reviewer_path "$reviewer_path" \
    --arg model "$model_name" \
    --argjson fallback_occurred "$fallback_occurred" \
    --argjson score "$score" \
    --argjson issues "$issues_count" \
    --argjson hook_duration_s "$hook_duration_s" \
    --arg review_tier "$review_tier" \
    --argjson files_omitted "$omitted_count" \
    --argjson sensitive_omitted "$sensitive_omitted" \
    --argjson mode "$GUARD_MODE" \
    --argjson enforced "$guard_enforced" \
    --arg files "$staged_files" \
    '{timestamp:$timestamp,review_id:$review_id,review_type:$review_kind,status:$status,provider:"codex",preferred_reviewer_path:$preferred_path,preferred_model:$preferred_model,reviewer_path:$reviewer_path,model:$model,fallback_occurred:$fallback_occurred,score:$score,issues_count:$issues,hook_duration_s:$hook_duration_s,review_tier:$review_tier,files_omitted:$files_omitted,sensitive_omitted:$sensitive_omitted,mode:$mode,enforced:$enforced,summary:$summary,command:$command,files:($files | split("\n") | map(select(length > 0)))}')
  codex_append_event "$ROOT_DIR" "$event_json"

  # Loop-breaker: an agent retrying the same blocked commit burns tokens
  # (observed: 29 HOLD blocks in a single session). After 3 HOLDs in the same
  # session the gate degrades to advisory instead of blocking forever.
  local session_id hold_count_file prev_holds hold_count
  session_id=$(printf '%s' "$HOOK_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)
  [ -n "$session_id" ] || session_id="nosession"
  hold_count_file="$tmp_dir/commit-hold-count-$session_id"
  prev_holds=$(cat "$hold_count_file" 2>/dev/null || printf '0')
  case "$prev_holds" in ''|*[!0-9]*) prev_holds=0 ;; esac

  # SKIP-TRUNCATED: o reviewer declarou que não consegue avaliar um arquivo
  # sensível omitido pelo orçamento de contexto. Isso NUNCA vira HOLD (HOLD
  # por truncamento foi o que matou a credibilidade do gate — auditoria
  # 2026-08-01): o commit passa em modo advisory, com aviso explícito e evento
  # mensurável para a próxima auditoria.
  if [ "$verdict" = "SKIP-TRUNCATED" ]; then
    # S2 (mantido e ENDURECIDO pelo review cego 2026-08-02): SKIP-TRUNCATED só
    # é veredito legítimo quando um arquivo SENSÍVEL ficou fora do contexto —
    # é a única situação que o prompt do reviewer autoriza. A tolerância
    # anterior (aceitar files_omitted>0 como evidência mínima) liberava o
    # commit imprimindo "arquivo(s) sensível(is) ficaram fora do contexto"
    # mesmo quando NENHUM sensível foi omitido: mensagem falsa sobre o que
    # aconteceu, que é pior que não avisar. Com sensitive_omitted != true a
    # saída do reviewer não se sustenta ⇒ mesma classe do invalid-output
    # acima: fail-open (NUNCA HOLD), evento guard-dark reason=invalid-output,
    # e nenhuma afirmação de truncamento. O detalhe (com ou sem arquivos
    # omitidos) fica na mensagem para a próxima auditoria.
    if [ "$sensitive_omitted" != "true" ]; then
      local skip_detail
      if [ "${omitted_count:-0}" -eq 0 ]; then
        skip_detail="sem nenhum arquivo omitido do contexto"
      else
        skip_detail="com ${omitted_count} arquivo(s) omitido(s) por orçamento, mas NENHUM classificado como sensível"
      fi
      _guard_dark_event "invalid-output" "$review_id"
      printf '%s\n' "Codex commit review degraded: reviewer devolveu SKIP-TRUNCATED $skip_detail (saída inválida — o veredito só vale com arquivo sensível fora do contexto). Commit segue SEM review, sem HOLD. See .agents/tmp/codex/latest-pre-commit-review.md for details." >&2
      return 0
    fi
    event_json=$(jq -cn \
      --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg review_id "$review_id" \
      --arg review_kind "$review_kind" \
      --arg summary "$event_summary" \
      --argjson score "$score" \
      --argjson files_omitted "$omitted_count" \
      --argjson sensitive_omitted "$sensitive_omitted" \
      --argjson mode "$GUARD_MODE" \
      --argjson enforced "$guard_enforced" \
      --arg files "$staged_files" \
      '{timestamp:$timestamp,type:"skip-truncated",review_id:$review_id,review_type:$review_kind,status:"advisory",provider:"codex",score:$score,files_omitted:$files_omitted,sensitive_omitted:$sensitive_omitted,mode:$mode,enforced:$enforced,summary:$summary,files:($files | split("\n") | map(select(length > 0)))}' 2>/dev/null) || event_json=""
    if [ -n "$event_json" ]; then
      codex_append_event "$ROOT_DIR" "$event_json" 2>/dev/null || true
    fi
    rm -f "$hold_count_file" 2>/dev/null || true
    printf '%s\n' "Codex review: SKIP-TRUNCATED — arquivo(s) sensível(is) ficaram fora do contexto por orçamento; commit LIBERADO em modo advisory (nunca bloqueia). Detalhes: .agents/tmp/codex/latest-pre-commit-review.md (evento type=skip-truncated registrado em metrics)." >&2
    return 0
  fi

  if [ "$verdict" = "HOLD" ]; then
    # CANUTO_GUARD_MODE=1 (observe): o veredicto HOLD já foi registrado no
    # evento principal acima com enforced=false — o modo observe existe
    # exatamente para nunca bloquear, então nem entra na contagem de streak
    # (spec A1 item 2: "HOLD vira aviso").
    if [ "$GUARD_MODE" != "2" ]; then
      rm -f "$hold_count_file" 2>/dev/null || true
      printf '%s\n' "Codex review: HOLD (mode=$GUARD_MODE observe — não bloqueia): $summary Detalhes: .agents/tmp/codex/latest-pre-commit-review.md (evento já registrado com enforced=false)." >&2
      return 0
    fi
    hold_count=$((prev_holds + 1))
    printf '%s\n' "$hold_count" > "$hold_count_file" 2>/dev/null || true
    if [ "$hold_count" -ge 3 ]; then
      printf '%s\n' "Codex review HOLD #$hold_count nesta sessão — gate degradado para advisory; commit liberado. Corrija os issues em .agents/tmp/codex/latest-pre-commit-review.md ou divida o commit." >&2
      return 0
    fi
    block_with_message "Codex blocked git commit (HOLD $hold_count/3): $summary Fix the issues or split the commit — do NOT retry the same commit unchanged (after 3 HOLDs the gate turns advisory). See .agents/tmp/codex/latest-pre-commit-review.md for details."
  fi
  rm -f "$hold_count_file" 2>/dev/null || true
}

case "$TOOL_NAME" in
  Bash)
    command_text="$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_input.command // ""')"
    handle_codex_cli_command "$command_text"
    handle_commit_gate "$command_text"
    ;;
esac

exit 0
