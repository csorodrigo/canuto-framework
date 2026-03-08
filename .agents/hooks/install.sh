#!/usr/bin/env bash
# install.sh — Instala o hook de segunda opinião (plan-review) no Claude Code
# Execute a partir da raiz do projeto:
#   bash .agents/hooks/install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$HOME/.claude/hooks"

echo "🔍 Verificando pré-requisitos..."

# Verificar se jq está disponível (usado no hook)
if ! command -v jq &> /dev/null; then
  echo "⚠️  jq não encontrado. Instale com: brew install jq"
  echo "Abortando — jq é necessário para o hook funcionar."
  exit 1
fi

echo "📁 Criando ~/.claude/hooks/..."
mkdir -p "$HOOKS_DIR"

echo "📋 Copiando plan-review.sh..."
cp "$SCRIPT_DIR/plan-review.sh" "$HOOKS_DIR/plan-review.sh"
chmod +x "$HOOKS_DIR/plan-review.sh"

echo ""
echo "✅ Instalação concluída!"
echo ""
echo "ℹ️  ExitPlanMode não é um evento de hook válido no Claude Code."
echo "   plan-review.sh foi instalado em ~/.claude/hooks/ para uso manual."
echo "   Execute: bash ~/.claude/hooks/plan-review.sh"
