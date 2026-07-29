#!/usr/bin/env bash
# canuto-mcp.sh — liga/desliga os MCPs de back-delegação Codex→Claude.
#
# Por que existe: `claude-architect` e `claude-reviewer` sobem no arranque de
# TODA sessão Codex, e cada um custa alguns segundos — medido num MacBook Air,
# ~1,1s de `uv` (removido pelo venv fixo) mais ~2,6s de `import mcp`, que é
# pydantic e não tem como espremer. Quem usa back-delegação todo dia paga isso
# de bom grado; quem vai abrir o Codex para uma pergunta rápida, não.
#
# Isto NÃO desinstala nada. Só tira/põe o registro no `codex mcp`, que é o que
# determina se o Codex tenta subir os servidores no arranque. Os arquivos e o
# venv continuam no lugar, então voltar a ligar é instantâneo.
#
# Uso:
#   canuto-mcp.sh on       liga (registra os dois)
#   canuto-mcp.sh off      desliga (remove o registro)
#   canuto-mcp.sh status   mostra o estado declarado e o real
#
# O estado fica em ~/.claude/scripts/.mcp-enabled e o instalador o respeita:
# desligado por você, ele não volta sozinho no próximo `install.sh`.
set -euo pipefail

SCRIPTS_DIR="$HOME/.claude/scripts"
STATE_FILE="$SCRIPTS_DIR/.mcp-enabled"
SERVERS=(claude-architect claude-reviewer)

_state() {
  # Ausente = ligado. O padrão é a capacidade disponível; desligar é uma escolha
  # explícita, e escolha explícita fica gravada.
  [ -f "$STATE_FILE" ] || { printf 'on'; return; }
  local raw
  raw=$(tr -d '[:space:]' < "$STATE_FILE" 2>/dev/null || true)
  case "$raw" in
    off) printf 'off' ;;
    *)   printf 'on'  ;;
  esac
}

_registered() {
  # Best-effort, pelo mesmo motivo do instalador: o formato do `codex mcp` varia
  # entre versões, e chutar um formato só já produziu alarme falso antes.
  command -v codex >/dev/null 2>&1 || return 1
  codex mcp list 2>/dev/null | grep -q "$1"
}

_smoke() {
  # Não registrar servidor que não sobe: registro que falha custa arranque em
  # toda sessão. `--help` exercita o import (topo do módulo roda antes do
  # argparse) e sai 0 sem falar stdio.
  local venv_py="$SCRIPTS_DIR/.mcp-venv/bin/python"
  local script="$SCRIPTS_DIR/claude-agent-mcp.py" limit=""
  [ -f "$script" ] || return 1
  # ADR-0008: nada espera para sempre. macOS não traz o `timeout` do GNU.
  if   command -v timeout  >/dev/null 2>&1; then limit="timeout"
  elif command -v gtimeout >/dev/null 2>&1; then limit="gtimeout"
  fi
  local -a run
  if [ -x "$venv_py" ]; then
    run=("$venv_py" "$script" --help)
  elif command -v uv >/dev/null 2>&1; then
    run=(uv run --script "$script" --help)
  else
    return 1
  fi
  if [ -n "$limit" ]; then
    "$limit" 120 "${run[@]}" >/dev/null 2>&1
  else
    "${run[@]}" >/dev/null 2>&1
  fi
}

cmd="${1:-status}"

case "$cmd" in
  off)
    printf 'off\n' > "$STATE_FILE"
    for srv in "${SERVERS[@]}"; do
      codex mcp remove "$srv" >/dev/null 2>&1 || true
    done
    echo "🔌 back-delegation DESLIGADA — os dois MCPs saíram do registro."
    echo "   O arranque do Codex deixa de pagar por eles. Religue com: canuto-mcp.sh on"
    ;;

  on)
    for srv in "${SERVERS[@]}"; do
      if [ ! -x "$SCRIPTS_DIR/$srv.sh" ]; then
        echo "❌ $SCRIPTS_DIR/$srv.sh ausente ou não executável."
        echo "   Rode antes: bash .agents/hooks/install.sh"
        exit 1
      fi
    done
    if ! _smoke; then
      echo "❌ o servidor MCP não sobe — não vou registrar."
      echo "   Diagnóstico: $SCRIPTS_DIR/.mcp-venv/bin/python $SCRIPTS_DIR/claude-agent-mcp.py --help"
      echo "   Se o venv estiver quebrado, rode: bash .agents/hooks/install.sh"
      exit 1
    fi
    printf 'on\n' > "$STATE_FILE"
    for srv in "${SERVERS[@]}"; do
      codex mcp remove "$srv" >/dev/null 2>&1 || true
      codex mcp add "$srv" -- "$SCRIPTS_DIR/$srv.sh" >/dev/null 2>&1 || {
        echo "❌ falhei ao registrar $srv"; exit 1; }
    done
    echo "🔌 back-delegation LIGADA — claude-architect e claude-reviewer registrados."
    echo "   Custo: alguns segundos no arranque de cada sessão Codex."
    ;;

  status)
    echo "estado declarado: $(_state)   ($STATE_FILE)"
    for srv in "${SERVERS[@]}"; do
      if _registered "$srv"; then
        echo "  $srv: registrado no codex"
      else
        echo "  $srv: NÃO registrado"
      fi
    done
    if [ -x "$SCRIPTS_DIR/.mcp-venv/bin/python" ]; then
      echo "venv: $SCRIPTS_DIR/.mcp-venv (arranque rápido)"
    else
      echo "venv: ausente — os wrappers caem no 'uv run --script', ~1,1s a mais por servidor"
    fi
    ;;

  *)
    echo "uso: $(basename "$0") {on|off|status}" >&2
    exit 2
    ;;
esac
