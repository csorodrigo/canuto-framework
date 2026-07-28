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
for hook in codex-pretool-guard.sh session-save.sh pre-compact-save.sh protect-files.sh require-tests-for-pr.sh log-commands.sh session-start.sh validation-mark.sh validation-clear.sh retry-detect.sh fingerprint-gate.sh pre-finalize.sh posttooluse-universal.sh pre-commit-branch-check.sh worktree-collision-check.sh pre-claim-grep.sh screenshot-guard.sh pre-pr-bash-gate.sh postdelegate-verify.sh; do
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

# Cleanup: remove MCP entries que não pertencem ao settings.json do Claude.
# - codex-* (retired 2026-04-29): Maestro invoca Codex via `codex exec` direto.
# - claude-architect / claude-reviewer (2026-07-27): wrappers de back-delegation
#   Codex→Claude — só fazem sentido registrados NO CODEX. Numa sessão Claude
#   eram dois servidores MCP mortos subindo a cada startup.
# - openbrand / context-hub (2026-07-27): únicos consumidores são skills em
#   _archive/. Re-adicione com `claude mcp add` se voltar a usar.
if [ -f "$SETTINGS_FILE" ]; then
  CLEANED=$(jq '
    if .mcpServers then
      .mcpServers |= (
        del(.["codex-coder"])
        | del(.["codex-reviewer"])
        | del(.["codex-maestro"])
        | del(.["claude-architect"])
        | del(.["claude-reviewer"])
        | del(.["openbrand"])
        | del(.["context-hub"])
      )
    else . end
  ' "$SETTINGS_FILE")
  if [ -n "$CLEANED" ] && ! cmp -s <(echo "$CLEANED") "$SETTINGS_FILE"; then
    echo "$CLEANED" > "$SETTINGS_FILE"
    echo "   ✅ settings.json enxugado: removidos MCPs Codex-only e sem consumidor"
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

# claude-architect/claude-reviewer NÃO são registrados no settings.json do
# Claude: são wrappers de back-delegation usados apenas quando o Codex é o
# runtime ativo. Os arquivos ficam em ~/.claude/scripts/ (copiados acima) e o
# registro acontece só no `codex mcp` (seção seguinte).

echo "   ✅ MCP servers adicionais:"
echo "      - ast-grep (análise AST)"

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
  # Refresh idempotente: remove-then-add corrige entrada existente apontando
  # para caminho antigo/inexistente (causa do "MCP client failed to start:
  # No such file or directory" no startup do Codex).
  _codex_mcp_refresh() {
    local name="$1"; shift
    codex mcp remove "$name" >/dev/null 2>&1 || true
    if codex mcp add "$name" "$@" 2>/dev/null; then
      echo "   ✅ $name"
    else
      echo "   ⚠️  $name — codex mcp add falhou (diagnóstico: codex mcp list)"
    fi
  }

  # Codex sub-agents (codex-coder, codex-reviewer, codex-maestro) were retired
  # on 2026-04-29 — Maestro now invokes Codex via `codex exec --profile <name>` directly.
  # Cleanup any stale registrations.
  # codex-cli atual retorna 0 mesmo quando o servidor não existe ("No MCP
  # server named ..."), então o sucesso é detectado pela mensagem, não pelo rc.
  for legacy in codex-coder codex-reviewer codex-maestro; do
    LEGACY_OUT=$(codex mcp remove "$legacy" 2>/dev/null || true)
    case "$LEGACY_OUT" in
      ""|*"No MCP server"*) : ;;
      *) echo "   🧹 Removed legacy MCP: $legacy" ;;
    esac
  done

  # Claude MCPs (subscription-based, no API key required) — back-delegation
  # Codex→Claude, registrados SÓ aqui (nunca no settings.json do Claude).
  # Os wrappers executam via `uvx` (codex-as-mcp): sem uvx, o servidor morre
  # no startup com "No such file or directory" — pré-flight obrigatório.
  if ! command -v uvx &> /dev/null; then
    echo "   ⚠️  uvx não encontrado — removendo/pulando claude-architect e claude-reviewer."
    echo "      Instale com: brew install uv   (depois re-rode este script)"
    codex mcp remove claude-architect >/dev/null 2>&1 || true
    codex mcp remove claude-reviewer  >/dev/null 2>&1 || true
  elif [ ! -x "$SCRIPTS_DIR/claude-architect.sh" ] || [ ! -x "$SCRIPTS_DIR/claude-reviewer.sh" ]; then
    echo "   ⚠️  wrappers ausentes em $SCRIPTS_DIR — registro no Codex pulado."
  else
    _codex_mcp_refresh claude-architect -- "$SCRIPTS_DIR/claude-architect.sh"
    _codex_mcp_refresh claude-reviewer  -- "$SCRIPTS_DIR/claude-reviewer.sh"
  fi

  echo "   ℹ️  Verifique com: codex mcp list"
fi

# ── Codex hooks.json: normaliza timeouts de SessionEnd ──────────────────────
# codex-cli limita SessionEnd a 3s e emite "clamping SessionEnd hook timeout"
# no startup quando o valor configurado é maior. Normalizar aqui silencia o
# warning sem mudar comportamento (o clamp aconteceria de qualquer forma).
CODEX_HOOKS_JSON="$HOME/.codex/hooks.json"
if [ -f "$CODEX_HOOKS_JSON" ]; then
  NORMALIZED=$(jq '
    def clamp_se: walk(
      if type == "object" and ((.timeout? | type) == "number") and .timeout > 3
      then .timeout = 3 else . end);
    if .SessionEnd? then .SessionEnd |= clamp_se else . end
    | if ((.hooks? // {}) | has("SessionEnd")) then .hooks.SessionEnd |= clamp_se else . end
  ' "$CODEX_HOOKS_JSON" 2>/dev/null || true)
  if [ -n "$NORMALIZED" ] && ! cmp -s <(echo "$NORMALIZED") "$CODEX_HOOKS_JSON"; then
    cp "$CODEX_HOOKS_JSON" "$CODEX_HOOKS_JSON.bak.$(date +%s)"
    echo "$NORMALIZED" > "$CODEX_HOOKS_JSON"
    echo "   ✅ ~/.codex/hooks.json: timeout de SessionEnd normalizado para ≤3s"
  fi
fi
