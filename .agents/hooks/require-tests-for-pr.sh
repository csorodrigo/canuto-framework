#!/usr/bin/env bash
# .agents/hooks/require-tests-for-pr.sh
# PreToolUse hook (matcher: mcp__github__create_pull_request) — blocks PR if tests fail.
# Exit 2 = block + send reason to Claude. Exit 0 = allow.

set -euo pipefail

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

# Typecheck é gate separado da suíte: vitest/jest NÃO rodam o typechecker.
# Em mecesa#88 a main ficou vermelha desde o merge do #86 com `apps/api`
# fechando 576/576 verde e o erro de tipo em pé — "só o tsc pega". Suíte verde
# não prova compilação, então o gate passa a exigir as duas coisas.
run_typecheck() {
  [[ -f "$PROJECT_DIR/package.json" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  local script
  for script in typecheck typecheck:ci tsc; do
    if jq -e --arg s "$script" '.scripts[$s] // empty' "$PROJECT_DIR/package.json" >/dev/null 2>&1; then
      echo "[require-tests-for-pr] rodando npm run $script" >&2
      (cd "$PROJECT_DIR" && npm run "$script" --silent 2>&1 | tail -20)
      return "${PIPESTATUS[0]}"
    fi
  done
  return 0
}

# Runner ausente ≠ teste falhando. Num clone fresco sem `npm install`, o script
# de teste morre com "vitest: not found" (rc 127) e o gate bloqueava o push com
# a mensagem "Tests are failing" — falso positivo que trava trabalho legítimo e,
# pior, ensina a usar o escape por reflexo. Só a ausência da FERRAMENTA é
# tolerada; teste que roda e falha continua bloqueando.
runner_missing() {
  local rc="$1" output="$2"
  [ "$rc" -eq 127 ] && return 0
  printf '%s' "$output" | grep -qiE '(command )?not found|No such file or directory|Missing script' && return 0
  return 1
}

run_tests() {
  if [[ -f "$PROJECT_DIR/test-framework.sh" ]]; then
    bash "$PROJECT_DIR/test-framework.sh" 2>&1 | tail -20
    return "${PIPESTATUS[0]}"
  elif [[ -f "$PROJECT_DIR/package.json" ]] && grep -q '"test"' "$PROJECT_DIR/package.json" 2>/dev/null; then
    cd "$PROJECT_DIR" && npm run test --silent 2>&1 | tail -20
    return "${PIPESTATUS[0]}"
  elif [[ -f "$PROJECT_DIR/Makefile" ]] && grep -q '^test:' "$PROJECT_DIR/Makefile" 2>/dev/null; then
    cd "$PROJECT_DIR" && make test 2>&1 | tail -20
    return "${PIPESTATUS[0]}"
  else
    echo "[require-tests-for-pr] No test runner detected, skipping gate." >&2
    return 0
  fi
}

# Quem chama declara a costura: mcp (default), gh-cli (pre-pr-bash-gate),
# pre-push (git hook runtime-agnóstico).
GATE_VIA="${CANUTO_GATE_VIA:-mcp}"

# Opt-in de gates POR PROJETO, versionado no repo. Um `export` no shell some ao
# trocar de terminal e não vale para o Codex nem para um push manual — o mesmo
# problema que o pre-push runtime-agnóstico veio resolver (ADR-0002).
# Variável de ambiente já definida tem precedência: dá para desligar pontualmente
# sem editar o arquivo.
GATES_ENV="$PROJECT_DIR/.agents/config/gates.env"
if [ -f "$GATES_ENV" ]; then
  while IFS='=' read -r key value; do
    case "$key" in
      ''|'#'*) continue ;;
      CANUTO_*) : ;;
      *) continue ;;
    esac
    value="${value%%#*}"; value="$(printf '%s' "$value" | tr -d '[:space:]')"
    [ -n "$value" ] || continue
    if [ -z "$(eval "printf '%s' \"\${$key:-}\"")" ]; then
      export "$key=$value"
    fi
  done < "$GATES_ENV"
fi

# CANUTO_REQUIRE_PREPUSH=1 — fecha o `git push --no-verify`.
# O pre-push é hook do git, e `--no-verify` o pula sem deixar rastro: em
# lucrando-ai#2369 o push saiu com --no-verify num repo onde "o pre-push é o
# único CI". Aqui exigimos prova POSITIVA de que o commit que está indo para o
# PR cruzou o gate: um evento GATE com o sha do HEAD. Sem evento, sem PR.
require_prepush_evidence() {
  [ "${CANUTO_REQUIRE_PREPUSH:-0}" = "1" ] || return 0
  [ "$GATE_VIA" = "pre-push" ] && return 0   # é o próprio pre-push rodando agora

  local head_sha log_path
  head_sha=$(git -C "$PROJECT_DIR" rev-parse HEAD 2>/dev/null || echo "")
  [ -n "$head_sha" ] || return 0

  if ! command -v canuto_event_log_path >/dev/null 2>&1; then
    echo "[require-tests-for-pr] CANUTO_REQUIRE_PREPUSH=1 mas o event log não está disponível — não dá para provar o pre-push." >&2
    return 1
  fi
  log_path=$(canuto_event_log_path "$PROJECT_DIR" 2>/dev/null || echo "")
  if [ -z "$log_path" ] || [ ! -f "$log_path" ]; then
    echo "[require-tests-for-pr] CANUTO_REQUIRE_PREPUSH=1 mas não há event log em $PROJECT_DIR — nenhum push registrado." >&2
    return 1
  fi

  if grep -q "\"sha\":\"$head_sha\"" "$log_path" 2>/dev/null; then
    return 0
  fi

  echo "" >&2
  echo "✋ CANUTO_REQUIRE_PREPUSH=1 — nenhum evento de pre-push para o HEAD ($head_sha)." >&2
  echo "   O commit que vai para o PR não tem prova de ter cruzado o gate." >&2
  echo "   Causa comum: \`git push --no-verify\`, que pula o hook sem deixar rastro." >&2
  echo "   Corrija com um push normal (sem --no-verify), ou declare o escape:" >&2
  echo "       CANUTO_SKIP_PR_GATE=1 git push ...   (fica registrado no event log)" >&2
  return 1
}

TEST_RC=0
TEST_OUTPUT=$(run_tests 2>&1) || TEST_RC=$?
printf '%s\n' "$TEST_OUTPUT" >&2
if [ "$TEST_RC" -ne 0 ]; then
  if runner_missing "$TEST_RC" "$TEST_OUTPUT"; then
    canuto_event_append GATE actor=hook gate=pr-tests verdict=unavailable via="$GATE_VIA" reason=runner-missing || true
    echo "[require-tests-for-pr] runner de teste indisponível (dependências não instaladas?) — gate não pôde rodar." >&2
    echo "   Isto NÃO é aprovação: rode 'npm install' e valide antes de confiar no PR." >&2
  else
    canuto_event_append GATE actor=hook gate=pr-tests verdict=fail via="$GATE_VIA" || true
    echo "Tests are failing. Fix all test failures before creating a PR." >&2
    exit 2
  fi
fi

TC_RC=0
TC_OUTPUT=$(run_typecheck 2>&1) || TC_RC=$?
printf '%s\n' "$TC_OUTPUT" >&2
if [ "$TC_RC" -ne 0 ]; then
  if runner_missing "$TC_RC" "$TC_OUTPUT"; then
    canuto_event_append GATE actor=hook gate=pr-typecheck verdict=unavailable via="$GATE_VIA" reason=runner-missing || true
    echo "[require-tests-for-pr] typecheck indisponível (dependências não instaladas?) — gate não pôde rodar." >&2
  else
    canuto_event_append GATE actor=hook gate=pr-typecheck verdict=fail via="$GATE_VIA" || true
    echo "Typecheck is failing. Suíte verde não prova compilação — corrija os erros de tipo antes de abrir o PR." >&2
    exit 2
  fi
fi

if ! require_prepush_evidence; then
  canuto_event_append GATE actor=hook gate=pr-prepush verdict=fail via="$GATE_VIA" || true
  exit 2
fi

canuto_event_append GATE actor=hook gate=pr-tests verdict=pass via="$GATE_VIA" || true
exit 0
