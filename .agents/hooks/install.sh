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

# plan-review.sh retired 2026-06-11 (0 firings in the 200-session audit) — see _retired/.
for hook in codex-pretool-guard.sh session-save.sh session-load.sh pre-compact-save.sh protect-files.sh require-tests-for-pr.sh log-commands.sh session-start.sh validation-mark.sh validation-clear.sh retry-detect.sh fingerprint-gate.sh pre-finalize.sh posttooluse-universal.sh pre-commit-branch-check.sh worktree-collision-check.sh pre-claim-grep.sh screenshot-guard.sh pre-pr-bash-gate.sh postdelegate-verify.sh; do
  if [ -f "$SCRIPT_DIR/$hook" ]; then
    cp "$SCRIPT_DIR/$hook" "$HOOKS_DIR/$hook"
    chmod +x "$HOOKS_DIR/$hook"
    echo "   ✅ $hook"
  fi
done

echo ""
echo "🧠 Instalando libs compartilhadas do Codex em ~/.claude/scripts/..."
mkdir -p "$SCRIPTS_DIR"

# Codex MCP wrappers (codex-coder.sh, codex-reviewer.sh, codex-agent-mcp.py,
# codex-maestro-mcp.sh) were retired on 2026-04-29 — Maestro now invokes Codex
# via `codex exec --profile <name>` directly (10-35% lower token overhead).
TOOLS_DIR="$(cd "$SCRIPT_DIR/../tools" && pwd)"
for script in codex-common.sh codex-diff-context.sh; do
  if [ -f "$TOOLS_DIR/$script" ]; then
    cp "$TOOLS_DIR/$script" "$SCRIPTS_DIR/$script"
    chmod +x "$SCRIPTS_DIR/$script"
    echo "   ✅ $script"
  fi
done

# ── Git pre-push gate (runtime-agnóstico: Claude, Codex ou humano) ─────────
echo ""
echo "🔒 Instalando git pre-push gate..."
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GIT_HOOKS_PATH="$(git -C "$PROJECT_ROOT" rev-parse --git-path hooks 2>/dev/null || true)"
if [ -n "$GIT_HOOKS_PATH" ]; then
  case "$GIT_HOOKS_PATH" in
    /*) : ;;
    *) GIT_HOOKS_PATH="$PROJECT_ROOT/$GIT_HOOKS_PATH" ;;
  esac
  mkdir -p "$GIT_HOOKS_PATH"
  PREPUSH="$GIT_HOOKS_PATH/pre-push"
  if [ -f "$PREPUSH" ] && ! grep -q "canuto:git-pre-push-gate" "$PREPUSH" 2>/dev/null; then
    echo "   ⚠️  pre-push existente (não-canuto) em $PREPUSH — preservado."
    echo "      Encadeie manualmente: bash .agents/hooks/git-pre-push-gate.sh"
  else
    cat > "$PREPUSH" <<'PREPUSH_SHIM'
#!/usr/bin/env bash
# canuto:git-pre-push-gate — shim gerado por .agents/hooks/install.sh (não editar).
GATE="$(git rev-parse --show-toplevel)/.agents/hooks/git-pre-push-gate.sh"
[ -f "$GATE" ] && exec bash "$GATE" "$@"
exit 0
PREPUSH_SHIM
    chmod +x "$PREPUSH"
    echo "   ✅ git pre-push gate → $PREPUSH"
  fi
else
  echo "   ⚠️  não é um repositório git — pre-push gate pulado."
fi

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

# Cleanup: remove legacy codex-* MCP entries (retired on 2026-04-29).
# Maestro now invokes Codex via `codex exec --profile <name>` directly.
if [ -f "$SETTINGS_FILE" ]; then
  CLEANED=$(jq '
    if .mcpServers then
      .mcpServers |= (
        del(.["codex-coder"])
        | del(.["codex-reviewer"])
        | del(.["codex-maestro"])
      )
    else . end
  ' "$SETTINGS_FILE")
  if [ -n "$CLEANED" ] && ! cmp -s <(echo "$CLEANED") "$SETTINGS_FILE"; then
    echo "$CLEANED" > "$SETTINGS_FILE"
    echo "   ✅ Removidas entradas legacy codex-* do settings.json (Codex agora via CLI)"
  fi
fi

# ── Claude MCPs ──────────────────────────────────────────────────────────────
echo ""
echo "🧠 Instalando wrappers Claude em ~/.claude/scripts/..."

for script in claude-agent-mcp.py claude-architect.sh claude-reviewer.sh; do
  if [ -f "$TOOLS_DIR/$script" ]; then
    cp "$TOOLS_DIR/$script" "$SCRIPTS_DIR/$script"
    chmod +x "$SCRIPTS_DIR/$script"
    echo "   ✅ $script"
  fi
done

if [ -f "$SETTINGS_FILE" ]; then
  MERGED=$(jq \
    --arg arch "$SCRIPTS_DIR/claude-architect.sh" \
    --arg rev "$SCRIPTS_DIR/claude-reviewer.sh" \
    '
      .mcpServers["claude-architect"] = {"command": $arch, "type": "stdio"}
      | .mcpServers["claude-reviewer"] = {"command": $rev, "type": "stdio"}
    ' "$SETTINGS_FILE")
  echo "$MERGED" > "$SETTINGS_FILE"
  echo "   ✅ claude-architect, claude-reviewer → ~/.claude/settings.json"
fi

echo "   ✅ MCP servers adicionais:"
echo "      - ast-grep (análise AST)"
echo "      - openbrand (extração de assets de marca)"
echo "      - context-hub (docs de API atualizadas)"

echo ""
echo "✅ Hooks e MCP instalados."
echo ""
echo "ℹ️  Codex hooks instalados: pretool guard + screenshot guard + session hooks"

# ── Sync todos os MCPs no Codex CLI ─────────────────────────────────────────
echo ""
echo "🔄 Sincronizando MCPs no Codex CLI..."

if ! command -v codex &> /dev/null; then
  echo "   ⚠️  codex CLI não encontrado — pulando sync. Re-rode após instalar codex."
else
  _codex_mcp_add() {
    local name="$1"; shift
    if codex mcp add "$name" "$@" 2>/dev/null; then
      echo "   ✅ $name"
    else
      echo "   ↩️  $name (já existia ou falhou — ignore se já configurado)"
    fi
  }

  # Codex sub-agents (codex-coder, codex-reviewer, codex-maestro) were retired
  # on 2026-04-29 — Maestro now invokes Codex via `codex exec --profile <name>` directly.
  # Cleanup any stale registrations.
  for legacy in codex-coder codex-reviewer codex-maestro; do
    if codex mcp remove "$legacy" 2>/dev/null; then
      echo "   🧹 Removed legacy MCP: $legacy"
    fi
  done

  # Claude MCPs (subscription-based, no API key required) — useful when Codex is
  # the active runtime and needs to back-delegate to Claude.
  _codex_mcp_add claude-architect -- "$SCRIPTS_DIR/claude-architect.sh"
  _codex_mcp_add claude-reviewer  -- "$SCRIPTS_DIR/claude-reviewer.sh"

  echo "   ℹ️  Verifique com: codex mcp list"
fi
