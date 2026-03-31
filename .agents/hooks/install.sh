#!/usr/bin/env bash
# .agents/hooks/install.sh
# Installs local hooks and MCP servers for this project.
#
# NOTE: For full framework install/update (including gstack and global skills),
# use the main installer instead:
#   curl -fsSL https://raw.githubusercontent.com/csorodrigo/canuto-framework/main/install.sh | bash -s -- --update
#
# Use this script only when working on the framework repo locally.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$HOME/.claude/hooks"
SETTINGS_FILE="$HOME/.claude/settings.json"
SCRIPTS_DIR="$HOME/.claude/scripts"

echo "🔍 Verificando pré-requisitos..."

if ! command -v jq &> /dev/null; then
  echo "⚠️  jq não encontrado. Instale com: brew install jq"
  echo "Abortando — jq é necessário para hooks e MCP."
  exit 1
fi

# ── Hooks ───────────────────────────────────────────────────────────────────
echo ""
echo "📁 Instalando hooks em ~/.claude/hooks/..."
mkdir -p "$HOOKS_DIR"

for hook in plan-review.sh codex-pretool-guard.sh session-save.sh session-load.sh pre-compact-save.sh; do
  if [ -f "$SCRIPT_DIR/$hook" ]; then
    cp "$SCRIPT_DIR/$hook" "$HOOKS_DIR/$hook"
    chmod +x "$HOOKS_DIR/$hook"
    echo "   ✅ $hook"
  fi
done

echo ""
echo "🧠 Instalando wrappers do Codex em ~/.claude/scripts/..."
mkdir -p "$SCRIPTS_DIR"

TOOLS_DIR="$(cd "$SCRIPT_DIR/../tools" && pwd)"
for script in codex-agent-mcp.py codex-coder.sh codex-reviewer.sh codex-common.sh codex-diff-context.sh; do
  if [ -f "$TOOLS_DIR/$script" ]; then
    cp "$TOOLS_DIR/$script" "$SCRIPTS_DIR/$script"
    chmod +x "$SCRIPTS_DIR/$script"
    echo "   ✅ $script"
  fi
done

# ── MCP Servers ─────────────────────────────────────────────────────────────
echo ""
echo "🔌 Configurando MCP servers em settings.json..."

SNIPPET="$SCRIPT_DIR/settings-snippet.json"

if [ -f "$SETTINGS_FILE" ] && [ -f "$SNIPPET" ]; then
  MERGED=$(jq -s '
    def hook_key:
      (.type // "") + "|" + (.command // "");

    def group_key:
      (.matcher // "") + "|" + (((.hooks // []) | map(hook_key) | sort) | join(","));

    def merge_hook_list(current; incoming):
      reduce (incoming // [])[] as $hook (current // [];
        if any(.[]; hook_key == ($hook | hook_key)) then
          map(if hook_key == ($hook | hook_key) then $hook + . else . end)
        else
          . + [$hook]
        end
      );

    def merge_hook_group(current; incoming):
      (current + incoming)
      | .matcher = (current.matcher // incoming.matcher // "")
      | .hooks = merge_hook_list((current.hooks // []); (incoming.hooks // []));

    def merge_event_groups(current; incoming):
      reduce (incoming // [])[] as $group (current // [];
        ($group | group_key) as $target
        | (map(group_key) | index($target)) as $existing_index
        | if $existing_index != null then
            . as $current_groups
            | .[$existing_index] = merge_hook_group($current_groups[$existing_index]; $group)
        else
          . + [$group]
        end
      );

    def merge_hooks(current; incoming):
      reduce (incoming | keys_unsorted[]) as $event (current;
        .[$event] = merge_event_groups((.[ $event ] // []); (incoming[$event] // []))
      );

    .[0] as $base
    | .[1] as $snippet
    | $base
    | .mcpServers = (($base.mcpServers // {}) * ($snippet.mcpServers // {}))
    | .hooks = merge_hooks(($base.hooks // {}); ($snippet.hooks // {}))
  ' \
    "$SETTINGS_FILE" "$SNIPPET")
  echo "$MERGED" > "$SETTINGS_FILE"
  echo "   ✅ Hooks e MCP servers mesclados no settings.json existente"
elif [ -f "$SNIPPET" ]; then
  mkdir -p "$HOME/.claude"
  cp "$SNIPPET" "$SETTINGS_FILE"
  echo "   ✅ settings.json criado com hooks e MCP servers"
else
  echo "   ⚠️  settings-snippet.json não encontrado — pulando MCP setup."
fi

if [ -f "$SETTINGS_FILE" ]; then
  MERGED=$(jq \
    --arg coder "$SCRIPTS_DIR/codex-coder.sh" \
    --arg reviewer "$SCRIPTS_DIR/codex-reviewer.sh" \
    '
      .mcpServers = (.mcpServers // {})
      | .mcpServers["codex-coder"] = {"command": $coder, "type": "stdio"}
      | .mcpServers["codex-reviewer"] = {"command": $reviewer, "type": "stdio"}
    ' "$SETTINGS_FILE")
  echo "$MERGED" > "$SETTINGS_FILE"
  echo "   ✅ codex-coder e codex-reviewer apontando para wrappers compatíveis"
fi

echo "      - ast-grep (análise AST)"
echo "      - openbrand (extração de assets de marca)"
echo "      - context-hub (docs de API atualizadas)"

echo ""
echo "✅ Hooks e MCP instalados."
echo ""
echo "ℹ️  Codex hooks instalados: pretool guard + plan review + session hooks"
