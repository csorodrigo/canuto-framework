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

for hook in plan-review.sh codex-pretool-guard.sh session-save.sh session-load.sh pre-compact-save.sh protect-files.sh require-tests-for-pr.sh log-commands.sh; do
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
for script in codex-agent-mcp.py codex-coder.sh codex-reviewer.sh codex-maestro-mcp.sh codex-common.sh codex-diff-context.sh; do
  if [ -f "$TOOLS_DIR/$script" ]; then
    cp "$TOOLS_DIR/$script" "$SCRIPTS_DIR/$script"
    chmod +x "$SCRIPTS_DIR/$script"
    echo "   ✅ $script"
  fi
done

if [ -f "$SCRIPT_DIR/glm-agent-mcp.py" ]; then
  cp "$SCRIPT_DIR/glm-agent-mcp.py" "$SCRIPTS_DIR/glm-agent-mcp.py"
  chmod +x "$SCRIPTS_DIR/glm-agent-mcp.py"
  echo "   ✅ glm-agent-mcp.py"
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

if [ -f "$SETTINGS_FILE" ]; then
  MERGED=$(jq \
    --arg coder "$SCRIPTS_DIR/codex-coder.sh" \
    --arg reviewer "$SCRIPTS_DIR/codex-reviewer.sh" \
    --arg maestro "$SCRIPTS_DIR/codex-maestro-mcp.sh" \
    '
      .mcpServers = (.mcpServers // {})
      | .mcpServers["codex-coder"] = {"command": $coder, "type": "stdio"}
      | .mcpServers["codex-reviewer"] = {"command": $reviewer, "type": "stdio"}
      | .mcpServers["codex-maestro"] = {"command": $maestro, "type": "stdio"}
    ' "$SETTINGS_FILE")
  echo "$MERGED" > "$SETTINGS_FILE"
  echo "   ✅ codex-coder, codex-reviewer e codex-maestro apontando para wrappers compatíveis"
fi

# ── GLM fallback via Z.AI ─────────────────────────────────────────────────────
echo ""
echo "🧠 Instalando wrappers GLM em ~/.claude/scripts/..."

cat > "$SCRIPTS_DIR/glm-common.sh" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

ZAI_BASE_URL="https://api.z.ai/api/coding/paas/v4"
GLM_PRIMARY_MODEL="glm-5.1"
GLM_FALLBACK_MODEL="glm-4.7"

load_zai_api_key() {
  if [ -n "${ZAI_API_KEY:-}" ]; then
    return 0
  fi

  local env_file="$HOME/.config/canuto/zai.env"
  if [ -f "$env_file" ]; then
    local mode
    mode=$(stat -f '%Lp' "$env_file" 2>/dev/null || stat -c '%a' "$env_file" 2>/dev/null || true)
    if [ -n "$mode" ] && [ "$mode" != "600" ]; then
      echo "❌ $env_file deve estar com chmod 600 (atual: $mode). Rode: chmod 600 $env_file" >&2
      return 1
    fi

    local key
    key=$(awk -F= '
      $1 == "ZAI_API_KEY" {
        value = substr($0, index($0, "=") + 1)
        gsub(/^["'\'']|["'\'']$/, "", value)
        print value
        exit
      }
    ' "$env_file")
    if [ -n "$key" ]; then
      export ZAI_API_KEY="$key"
      return 0
    fi
  fi

  echo "❌ ZAI_API_KEY ausente. Exporte a variável ou crie ~/.config/canuto/zai.env com ZAI_API_KEY=sua-chave." >&2
  return 1
}

log_fallback() {
  local origin="${1:-unknown}"
  local destination="${2:-unknown}"
  local reason="${3:-unspecified}"
  local log_dir="$HOME/.claude/logs"

  mkdir -p "$log_dir"
  printf '%s origin=%s destination=%s reason=%s\n' \
    "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    "$origin" \
    "$destination" \
    "$reason" >> "$log_dir/glm-fallback.log"
}

zai_chat_completion() {
  local model="${1:?model required}"
  local messages_json="${2:?messages_json required}"
  local tools_json="${3:-null}"
  local allow_fallback="${4:-${ALLOW_GLM_FALLBACK:-0}}"
  local current_model="$model"
  local attempted_fallback=0
  local response_file

  load_zai_api_key || return 1

  response_file=$(mktemp)
  trap 'rm -f "$response_file"' RETURN

  while true; do
    local body
    body=$(jq -n \
      --arg model "$current_model" \
      --argjson messages "$messages_json" \
      --argjson tools "$tools_json" \
      '{
        model: $model,
        messages: $messages
      }
      + if $tools == null then {} else {tools: $tools} end')

    local headers_file
    headers_file=$(mktemp)
    chmod 600 "$headers_file"
    printf 'Authorization: Bearer %s\nContent-Type: application/json\n' "$ZAI_API_KEY" > "$headers_file"

    local status
    if ! status=$(curl -sS \
      -o "$response_file" \
      -w "%{http_code}" \
      -X POST "$ZAI_BASE_URL/chat/completions" \
      -H "@$headers_file" \
      -d "$body"); then
      rm -f "$headers_file"
      echo "❌ Z.AI chat completion falhou: erro de rede ao chamar $ZAI_BASE_URL/chat/completions." >&2
      return 1
    fi
    rm -f "$headers_file"

    if [[ "$status" =~ ^2[0-9][0-9]$ ]]; then
      cat "$response_file"
      return 0
    fi

    if [ "$status" = "429" ] && [ "$allow_fallback" = "1" ] && [ "$attempted_fallback" = "0" ]; then
      log_fallback "$current_model" "$GLM_FALLBACK_MODEL" "http_429_concurrency_limit"
      current_model="$GLM_FALLBACK_MODEL"
      attempted_fallback=1
      continue
    fi

    echo "❌ Z.AI chat completion falhou (HTTP $status, modelo $current_model)." >&2
    cat "$response_file" >&2
    return 1
  done
}
EOF

cat > "$SCRIPTS_DIR/glm-coder.sh" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail
ZAI_ENV="$HOME/.config/canuto/zai.env"
[ -f "$ZAI_ENV" ] && set -a && . "$ZAI_ENV" && set +a
exec uvx --from codex-as-mcp@latest --with openai \
  python "$HOME/.claude/scripts/glm-agent-mcp.py" \
  --server-name glm-coder \
  --mode coder \
  "$@"
EOF

cat > "$SCRIPTS_DIR/glm-reviewer.sh" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail
ZAI_ENV="$HOME/.config/canuto/zai.env"
[ -f "$ZAI_ENV" ] && set -a && . "$ZAI_ENV" && set +a
exec uvx --from codex-as-mcp@latest --with openai \
  python "$HOME/.claude/scripts/glm-agent-mcp.py" \
  --server-name glm-reviewer \
  --mode reviewer \
  "$@"
EOF

cat > "$SCRIPTS_DIR/glm-health-check.sh" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

source "$HOME/.claude/scripts/glm-common.sh"

load_zai_api_key

response_file=$(mktemp)
headers_file=$(mktemp)
trap 'rm -f "$response_file" "$headers_file"' EXIT

body=$(jq -n \
  --arg model "$GLM_PRIMARY_MODEL" \
  '{
    model: $model,
    messages: [{role: "user", content: "ping"}],
    max_tokens: 8
  }')

chmod 600 "$headers_file"
printf 'Authorization: Bearer %s\nContent-Type: application/json\n' "$ZAI_API_KEY" > "$headers_file"

start_ms=$(python3 -c 'import time; print(int(time.time() * 1000))')
status=$(curl -sS \
  -o "$response_file" \
  -w "%{http_code}" \
  -X POST "$ZAI_BASE_URL/chat/completions" \
  -H "@$headers_file" \
  -d "$body") || {
    echo "❌ GLM health check falhou: erro de rede ao chamar $ZAI_BASE_URL/chat/completions." >&2
    exit 1
  }
end_ms=$(python3 -c 'import time; print(int(time.time() * 1000))')
latency_ms=$((end_ms - start_ms))

preview=$(jq -r '
  (.choices[0].message.content // .error.message // .message // tostring)
' "$response_file" 2>/dev/null | tr '\n' ' ' | cut -c 1-60)

echo "   endpoint: $ZAI_BASE_URL/chat/completions"
echo "   modelo: $GLM_PRIMARY_MODEL"
echo "   status code: $status"
echo "   latency: ${latency_ms}ms"
echo "   resposta: $preview"

case "$status" in
  2??)
    exit 0
    ;;
  401|403)
    echo "❌ GLM health check falhou: autenticação recusada. Verifique ZAI_API_KEY." >&2
    exit 1
    ;;
  429)
    echo "❌ GLM health check falhou: limite de taxa ou concorrência atingido." >&2
    exit 1
    ;;
  000)
    echo "❌ GLM health check falhou: endpoint indisponível ou sem conexão." >&2
    exit 1
    ;;
  *)
    echo "❌ GLM health check falhou: HTTP $status." >&2
    cat "$response_file" >&2
    exit 1
    ;;
esac
EOF

chmod +x \
  "$SCRIPTS_DIR/glm-agent-mcp.py" \
  "$SCRIPTS_DIR/glm-common.sh" \
  "$SCRIPTS_DIR/glm-coder.sh" \
  "$SCRIPTS_DIR/glm-reviewer.sh" \
  "$SCRIPTS_DIR/glm-health-check.sh"

echo "   ✅ glm-common.sh"
echo "   ✅ glm-agent-mcp.py"
echo "   ✅ glm-coder.sh"
echo "   ✅ glm-reviewer.sh"
echo "   ✅ glm-health-check.sh"

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

GLM_ENABLED=0
if [ -n "${ZAI_API_KEY:-}" ] || { [ -f "$HOME/.config/canuto/zai.env" ] && grep -q '^ZAI_API_KEY=' "$HOME/.config/canuto/zai.env"; }; then
  GLM_ENABLED=1
else
  printf '   \033[33m⚠️ ZAI_API_KEY ausente — MCPs glm-coder/glm-reviewer serão pulados. Para habilitar fallback GLM, crie ~/.config/canuto/zai.env (chmod 600) com `ZAI_API_KEY=sua-chave`.\033[0m\n'
fi

if [ "$GLM_ENABLED" = "1" ] && [ -f "$SETTINGS_FILE" ]; then
  MERGED=$(jq \
    --arg glm_coder "$SCRIPTS_DIR/glm-coder.sh" \
    --arg glm_reviewer "$SCRIPTS_DIR/glm-reviewer.sh" \
    '
      .mcpServers = (.mcpServers // {})
      | .mcpServers["glm-coder"] = {"command": $glm_coder, "type": "stdio"}
      | .mcpServers["glm-reviewer"] = {"command": $glm_reviewer, "type": "stdio"}
    ' "$SETTINGS_FILE")
  echo "$MERGED" > "$SETTINGS_FILE"
  echo "   ✅ glm-coder, glm-reviewer registrados (fallback via Z.AI)"
fi

if [ "$GLM_ENABLED" = "1" ] && [ "${CANUTO_GLM_HEALTH_CHECK:-0}" = "1" ]; then
  bash "$SCRIPTS_DIR/glm-health-check.sh" || echo "   ⚠️ GLM health check falhou — verifique chave"
elif [ "$GLM_ENABLED" = "1" ]; then
  echo "   ℹ️ Pular health check. Para validar conexão: bash ~/.claude/scripts/glm-health-check.sh"
fi

# Mantemos a ordem existente e adicionamos cabeçalho para separar estes MCPs
# adicionais da seção experimental GLM acima.
echo "   ✅ MCP servers adicionais:"
echo "      - ast-grep (análise AST)"
echo "      - openbrand (extração de assets de marca)"
echo "      - context-hub (docs de API atualizadas)"

echo ""
echo "✅ Hooks e MCP instalados."
echo ""
echo "ℹ️  Codex hooks instalados: pretool guard + plan review + session hooks"

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

  # Codex sub-agents
  _codex_mcp_add codex-coder    -- "$SCRIPTS_DIR/codex-coder.sh"
  _codex_mcp_add codex-reviewer -- "$SCRIPTS_DIR/codex-reviewer.sh"
  _codex_mcp_add codex-maestro  -- "$SCRIPTS_DIR/codex-maestro-mcp.sh"

  # GLM fallback
  if [ "$GLM_ENABLED" = "1" ]; then
    _codex_mcp_add glm-coder    -- "$SCRIPTS_DIR/glm-coder.sh"
    _codex_mcp_add glm-reviewer -- "$SCRIPTS_DIR/glm-reviewer.sh"
  fi

  # Gemini — use wrapper script if npx form is not supported by codex mcp add
  if command -v gemini &> /dev/null; then
    _codex_mcp_add gemini -- "$(which gemini)"
  elif command -v npx &> /dev/null; then
    # Create a thin wrapper so codex mcp add receives a single command arg
    cat > "$SCRIPTS_DIR/gemini-mcp.sh" <<'GEMINI_EOF'
#!/usr/bin/env bash
set -euo pipefail
exec npx -y gemini-mcp-tool "$@"
GEMINI_EOF
    chmod +x "$SCRIPTS_DIR/gemini-mcp.sh"
    _codex_mcp_add gemini -- "$SCRIPTS_DIR/gemini-mcp.sh"
  else
    echo "   ⚠️  gemini-mcp-tool não disponível — pulando gemini no Codex MCP"
  fi

  # Claude MCPs (subscription-based, no API key required)
  _codex_mcp_add claude-architect -- "$SCRIPTS_DIR/claude-architect.sh"
  _codex_mcp_add claude-reviewer  -- "$SCRIPTS_DIR/claude-reviewer.sh"

  echo "   ℹ️  Verifique com: codex mcp list"
fi
