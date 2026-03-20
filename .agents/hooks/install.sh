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

# ──────────────────────────────────────────────────────
# MCP Servers — merge into ~/.claude/settings.json
# ──────────────────────────────────────────────────────
SETTINGS_FILE="$HOME/.claude/settings.json"

echo ""
echo "🔌 Configurando MCP servers..."

if [ -f "$SETTINGS_FILE" ]; then
  # Merge mcpServers from snippet into existing settings
  SNIPPET="$SCRIPT_DIR/settings-snippet.json"
  if [ -f "$SNIPPET" ] && command -v jq &> /dev/null; then
    # Extract mcpServers from snippet and merge with existing
    MERGED=$(jq -s '.[0] * { mcpServers: (.[0].mcpServers // {} ) * .[1].mcpServers }' "$SETTINGS_FILE" "$SNIPPET")
    echo "$MERGED" > "$SETTINGS_FILE"
    echo "   ✅ MCP servers adicionados ao settings.json existente:"
  else
    echo "   ⚠️  Não foi possível fazer merge. Adicione manualmente de settings-snippet.json."
  fi
else
  # Create settings.json from snippet
  mkdir -p "$HOME/.claude"
  cp "$SCRIPT_DIR/settings-snippet.json" "$SETTINGS_FILE"
  echo "   ✅ settings.json criado com MCP servers:"
fi

echo "      - ast-grep (análise AST)"
echo "      - openbrand (extração de assets de marca)"
echo "      - context-hub (docs de API atualizadas)"

echo ""
echo "✅ Instalação concluída!"
echo ""
echo "ℹ️  ExitPlanMode não é um evento de hook válido no Claude Code."
echo "   plan-review.sh foi instalado em ~/.claude/hooks/ para uso manual."
echo "   Execute: bash ~/.claude/hooks/plan-review.sh"
