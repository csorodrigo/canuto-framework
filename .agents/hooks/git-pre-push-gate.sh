#!/usr/bin/env bash
# .agents/hooks/git-pre-push-gate.sh
# Gate de PR na costura RUNTIME-AGNÓSTICA: o git pre-push (ADR-0002).
#
# Os hooks PreToolUse são do Claude Code — sessão Codex direta (e push manual)
# passavam por fora do gate de testes. O pre-push do git dispara para QUALQUER
# runtime que faça push, então o contrato vale mecanicamente nos dois lados.
#
# Regras:
#   1. Push direto para main/master → BLOQUEADO (regra da casa: branch + PR).
#      Escape consciente: CANUTO_ALLOW_MAIN_PUSH=1 (registrado no event log).
#   2. Primeiro push de um branch (momento pré-PR) → roda require-tests-for-pr.sh;
#      teste falhando bloqueia o push.
#      Escape consciente: CANUTO_SKIP_PR_GATE=1 (registrado no event log).
#   3. Push subsequente de branch existente → passa direto (o gate pré-PR já
#      cumpriu o papel; o CI do PR cobre o resto).
#
# Instalado em .git/hooks/pre-push como shim por .agents/hooks/install.sh e
# pelo setup_hooks do install.sh (marker: canuto:git-pre-push-gate).
# stdin (protocolo do git): "<local_ref> <local_sha> <remote_ref> <remote_sha>"

set -uo pipefail

PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
HOOKS_DIR="$PROJECT_DIR/.agents/hooks"
TOOLS_DIR="$PROJECT_DIR/.agents/tools"

if [ -f "$TOOLS_DIR/event-log.sh" ]; then
  # shellcheck source=../tools/event-log.sh
  . "$TOOLS_DIR/event-log.sh"
else
  canuto_event_append() { return 0; }
fi

ZERO="0000000000000000000000000000000000000000"
new_branch=0
main_push=0

pushed_sha=""

while read -r _local_ref local_sha remote_ref remote_sha; do
  [ -z "${remote_ref:-}" ] && continue
  # Deleção de branch remoto (local_sha zerado) nunca é gated.
  [ "$local_sha" = "$ZERO" ] && continue
  case "$remote_ref" in
    refs/heads/main|refs/heads/master) main_push=1 ;;
  esac
  [ "$remote_sha" = "$ZERO" ] && new_branch=1
  pushed_sha="$local_sha"
done

# O sha entra no evento para que o gate de PR possa exigir prova de que ESTE
# commit passou pelo pre-push (CANUTO_REQUIRE_PREPUSH=1). Sem o sha, um evento
# GATE antigo de qualquer push serviria de álibi para um `--no-verify` novo.
export CANUTO_EVENT_SHA="$pushed_sha"

if [ "$main_push" = "1" ]; then
  if [ "${CANUTO_ALLOW_MAIN_PUSH:-0}" = "1" ]; then
    canuto_event_append GATE actor=git-hook gate=main-push verdict=skipped via=pre-push sha="$pushed_sha" || true
    echo "[canuto pre-push] push para main LIBERADO por CANUTO_ALLOW_MAIN_PUSH=1 (registrado no event log)." >&2
  else
    canuto_event_append GATE actor=git-hook gate=main-push verdict=blocked via=pre-push sha="$pushed_sha" || true
    echo "" >&2
    echo "✋ [canuto pre-push] Push direto para main bloqueado — regra da casa: feature branch + PR." >&2
    echo "   Urgência consciente: CANUTO_ALLOW_MAIN_PUSH=1 git push ... (fica registrado no event log)" >&2
    exit 1
  fi
fi

if [ "$new_branch" = "1" ]; then
  if [ "${CANUTO_SKIP_PR_GATE:-0}" = "1" ]; then
    canuto_event_append GATE actor=git-hook gate=pr-tests verdict=skipped via=pre-push sha="$pushed_sha" || true
    echo "[canuto pre-push] gate de testes PULADO por CANUTO_SKIP_PR_GATE=1 (registrado no event log)." >&2
    exit 0
  fi
  if [ -f "$HOOKS_DIR/require-tests-for-pr.sh" ]; then
    echo "[canuto pre-push] primeiro push do branch — gate pré-PR: rodando testes..." >&2
    if ! CANUTO_GATE_VIA=pre-push bash "$HOOKS_DIR/require-tests-for-pr.sh"; then
      echo "✋ [canuto pre-push] Testes falhando — push bloqueado." >&2
      echo "   Escape consciente: CANUTO_SKIP_PR_GATE=1 git push ... (fica registrado no event log)" >&2
      canuto_event_append GATE actor=git-hook gate=pr-tests verdict=fail via=pre-push sha="$pushed_sha" || true
      exit 1
    fi
    canuto_event_append GATE actor=git-hook gate=pr-tests verdict=pass via=pre-push sha="$pushed_sha" || true
  fi
fi

exit 0
