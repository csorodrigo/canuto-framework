#!/usr/bin/env bash
# install.sh — Instala o hook de segunda opinião (plan-review) no Claude Code
# Execute a partir da raiz do projeto:
#   bash .agents/hooks/install.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$HOME/.claude/hooks"
SETTINGS_FILE="$HOME/.claude/settings.json"

echo "🔍 Verificando pré-requisitos..."

# Verificar se codex está instalado
if ! command -v codex &> /dev/null; then
  echo "⚠️  Codex CLI não encontrado. Instale com:"
  echo "    npm install -g @openai/codex"
  echo ""
  echo "Continuando instalação do hook (a revisão falhará silenciosamente até o Codex ser instalado)."
fi

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

echo "⚙️  Atualizando ~/.claude/settings.json..."

# Novo entry para o hook
NEW_HOOK=$(cat <<'EOF'
{
  "type": "command",
  "command": "~/.claude/hooks/plan-review.sh",
  "timeout": 120
}
EOF
)

# Verificar se o hook já existe
if grep -q "plan-review.sh" "$SETTINGS_FILE" 2>/dev/null; then
  echo "✓ Hook ExitPlanMode já presente em settings.json — pulando."
else
  UPDATED=$(jq --argjson hook "$NEW_HOOK" '
    if .hooks.ExitPlanMode then
      .hooks.ExitPlanMode += [$hook]
    else
      .hooks.ExitPlanMode = [$hook]
    end
  ' "$SETTINGS_FILE")
  if [[ -n "$UPDATED" ]]; then
    echo "$UPDATED" > "$SETTINGS_FILE"
    echo "✓ Hook adicionado ao settings.json."
  else
    echo "⚠️  jq falhou — settings.json não foi modificado." >&2
    exit 1
  fi
fi

echo ""
echo "✅ Instalação concluída!"
echo ""
echo "O hook dispara automaticamente após qualquer ExitPlanMode."
echo "Para tasks M/L, o Maestro aguarda o resultado antes de rotear ao Coder."
