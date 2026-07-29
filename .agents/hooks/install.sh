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
    # Guarda a versão anterior antes de sobrescrever: se a nova cópia não
    # parsear, dá para voltar.
    prev=""
    if [ -f "$HOOKS_DIR/$hook" ]; then
      prev="$HOOKS_DIR/$hook.prev.$$"
      cp "$HOOKS_DIR/$hook" "$prev" 2>/dev/null || prev=""
    fi

    cp "$SCRIPT_DIR/$hook" "$HOOKS_DIR/$hook"
    chmod +x "$HOOKS_DIR/$hook"

    # Verifica o DESTINO. Hook que não parseia dispara erro a cada invocação —
    # e posttooluse-universal.sh tem matcher ".*", ou seja, todo comando da
    # sessão. Visto em campo com o arquivo do repo íntegro: a cópia chegou
    # corrompida. A causa exata não importa aqui; o que importa é não deixar
    # em pé.
    if bash -n "$HOOKS_DIR/$hook" 2>/dev/null; then
      echo "   ✅ $hook"
      rm -f "$prev" 2>/dev/null || true
    else
      echo "   ❌ $hook: a cópia instalada não parseia (bash -n falhou)"
      bash -n "$HOOKS_DIR/$hook" 2>&1 | head -3 | sed 's/^/         /'
      if [ -n "$prev" ] && bash -n "$prev" 2>/dev/null; then
        mv "$prev" "$HOOKS_DIR/$hook"; chmod +x "$HOOKS_DIR/$hook"
        echo "      versão anterior íntegra restaurada"
      else
        rm -f "$HOOKS_DIR/$hook"
        echo "      removido — melhor sem hook que com hook quebrado em todo comando"
      fi
      rm -f "$prev" 2>/dev/null || true
    fi
  fi
done

# Rede de segurança: hooks instalados em rodadas ANTERIORES podem ter corrompido
# depois. Varre tudo que está em ~/.claude/hooks/, não só o que acabou de ser
# copiado — foi exatamente assim que o posttooluse-universal.sh quebrado passou
# despercebido, disparando em toda a sessão sem ninguém reinstalar.
BROKEN_HOOKS=""
for installed in "$HOOKS_DIR"/*.sh; do
  [ -f "$installed" ] || continue
  bash -n "$installed" 2>/dev/null || BROKEN_HOOKS="$BROKEN_HOOKS $(basename "$installed")"
done
if [ -n "$BROKEN_HOOKS" ]; then
  echo ""
  echo "   ⚠️  hooks já instalados que NÃO parseiam:$BROKEN_HOOKS"
  echo "      Cada um deles falha a cada invocação. Se vieram do framework, o"
  echo "      passo acima já os substituiu; se persistirem, são locais."
fi

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
    # Registro apontando para wrapper que não existe é PIOR que não registrar:
    # o Codex tenta subir o servidor a cada abertura, falha com "No such file or
    # directory (os error 2)" e ainda paga a espera do startup. Sem wrapper,
    # tira o registro.
    echo "   ⚠️  wrappers ausentes em $SCRIPTS_DIR — removendo registro para não falhar no startup do Codex."
    codex mcp remove claude-architect >/dev/null 2>&1 || true
    codex mcp remove claude-reviewer  >/dev/null 2>&1 || true
  else
    # Aquece o cache do uv ANTES de registrar. Os wrappers rodam
    # `uvx --from codex-as-mcp` (sem `@latest`, de propósito — ver o comentário
    # neles). Sem `@latest` o uv usa o cache, mas na PRIMEIRA vez ainda precisa
    # baixar; e essa primeira vez cairia no startup do Codex, com 30s de teto
    # por servidor. Pagar aqui, uma vez, é melhor que pagar lá, em duas sessões.
    #
    # Não é fatal: se falhar (sem rede, PyPI fora), o registro segue e o wrapper
    # baixa sob demanda — só volta a arriscar o timeout na primeira abertura.
    if command -v uv >/dev/null 2>&1; then
      echo "   ⏳ aquecendo cache do codex-as-mcp (evita timeout de 30s no startup do Codex)..."
      if uv tool install --quiet codex-as-mcp >/dev/null 2>&1 \
         || uvx --from codex-as-mcp python -c "pass" >/dev/null 2>&1; then
        echo "   ✅ codex-as-mcp em cache"
      else
        echo "   ⚠️  não consegui baixar codex-as-mcp agora — a primeira sessão Codex vai pagar o download"
      fi
    fi

    _codex_mcp_refresh claude-architect -- "$SCRIPTS_DIR/claude-architect.sh"
    _codex_mcp_refresh claude-reviewer  -- "$SCRIPTS_DIR/claude-reviewer.sh"

    # Verificação: reler o registro e conferir que o comando existe em disco.
    # `codex mcp add` retorna 0 sem validar o caminho, então "adicionou" não é
    # o mesmo que "vai subir".
    #
    # A leitura de volta é BEST-EFFORT, e isso é deliberado. O formato de saída
    # do `codex mcp get` varia entre versões do codex-cli — assumir `--json` com
    # `.command` no topo produziu "registro não pôde ser lido de volta" logo
    # depois de um "Added global MCP server" bem-sucedido: alarme falso que
    # parecia defeito e não era. Aqui tentamos algumas formas e, se nenhuma
    # servir, dizemos que não deu para verificar em vez de acusar erro.
    #
    # O risco coberto pela leitura já está coberto antes: só chegamos aqui com
    # o wrapper confirmado executável, e registramos com exatamente esse caminho.
    _mcp_registered_cmd() {
      local srv="$1" out=""
      out=$(codex mcp get "$srv" --json 2>/dev/null | jq -r '
        [.. | objects | .command? // empty] | map(select(type=="string")) | first // empty
      ' 2>/dev/null) || true
      [ -n "$out" ] && { printf '%s' "$out"; return 0; }
      out=$(codex mcp list --json 2>/dev/null | jq -r --arg s "$srv" '
        [.. | objects | select((.name? // empty) == $s) | .command? // empty] | first // empty
      ' 2>/dev/null) || true
      [ -n "$out" ] && { printf '%s' "$out"; return 0; }
      # Última tentativa: saída em texto, pescando um caminho plausível.
      codex mcp get "$srv" 2>/dev/null | grep -oE '(/|~)[^[:space:]"]*claude-(architect|reviewer)\.sh' | head -1
    }

    for _srv in claude-architect claude-reviewer; do
      _cmd=$(_mcp_registered_cmd "$_srv")
      _cmd="${_cmd/#\~/$HOME}"
      if [ -z "$_cmd" ]; then
        echo "   ℹ️  $_srv registrado (esta versão do codex não expõe o caminho para conferência)"
      elif [ ! -x "$_cmd" ]; then
        echo "   ❌ $_srv aponta para '$_cmd', que não existe/não é executável —"
        echo "      é exatamente isso que vira 'MCP startup failed: No such file or directory'."
        codex mcp remove "$_srv" >/dev/null 2>&1 || true
        echo "      registro removido para o Codex parar de tentar no startup."
      else
        echo "   ✅ $_srv → $_cmd (verificado em disco)"
      fi
    done
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

  # ── SessionStart do Codex: exige JSON na saída ────────────────────────────
  # "SessionStart hook (failed) — hook returned invalid session start JSON
  # output" acontece quando um hook do CLAUDE CODE é ligado no SessionStart do
  # Codex. Os contratos são diferentes: o Claude aceita texto humano no stdout,
  # o Codex exige JSON. O hook roda, imprime as linhas de briefing, e o Codex
  # recusa — a cada abertura, pagando o tempo de execução para jogar fora.
  #
  # A checagem é empírica, não por nome de arquivo: roda o comando com payload
  # vazio e vê se o stdout parseia. Assim vale para qualquer hook ligado ali,
  # inclusive os que o usuário escreveu.
  _codex_sessionstart_cmds() {
    jq -r '
      [ (.SessionStart? // empty), (.hooks?.SessionStart? // empty) ]
      | flatten | .[]? | (.hooks? // [.]) | flatten | .[]?
      | (.command? // empty)
      | if type == "array" then join(" ") else tostring end
    ' "$CODEX_HOOKS_JSON" 2>/dev/null | sed '/^$/d'
  }

  # Com limite de tempo: este teste EXECUTA hook de terceiro. Um hook que trava
  # travaria o instalador junto — seria reintroduzir aqui a mesma classe de bug
  # que o ADR-0008 acabou de fechar. Sem timeout disponível, não testa: dar um
  # veredito sem poder limitar a execução é pior que não dar veredito.
  _emits_json() {
    local out limit=""
    if command -v timeout >/dev/null 2>&1; then limit="timeout 10"
    elif command -v gtimeout >/dev/null 2>&1; then limit="gtimeout 10"
    else return 0; fi   # sem limite seguro → trata como OK, não mexe
    out=$(printf '{}' | $limit bash -c "$1" 2>/dev/null) || true
    [ -n "$out" ] || return 1
    printf '%s' "$out" | jq -e type >/dev/null 2>&1
  }

  SS_BROKEN=""
  while IFS= read -r _ss_cmd; do
    [ -n "$_ss_cmd" ] || continue
    if ! _emits_json "$_ss_cmd"; then
      SS_BROKEN="$SS_BROKEN$_ss_cmd"$'\n'
    fi
  done <<< "$(_codex_sessionstart_cmds)"

  if [ -n "$SS_BROKEN" ]; then
    echo "   ⚠️  ~/.codex/hooks.json tem hook(s) de SessionStart que não emitem JSON:"
    printf '%s' "$SS_BROKEN" | sed 's/^/        /'
    echo "      É a causa de 'hook returned invalid session start JSON output'."
    # Desligar é estritamente melhor que deixar quebrado: o Codex descarta a
    # saída de qualquer jeito, então o hook só custa tempo de startup e um erro
    # por sessão. Backup antes; reversível.
    PRUNED=$(jq --arg broken "$SS_BROKEN" '
      # `// ""` e não `// empty`: em objeto SEM .command, `empty` produz stream
      # vazio, `select` sobre stream vazio não emite nada e o elemento é
      # descartado. Numa hooks.json aninhada ({hooks:[{hooks:[...]}]}) isso
      # apagava o GRUPO inteiro em vez do comando quebrado — testado.
      def cmd_of: (.command? // "") | if type == "array" then join(" ") else tostring end;
      def is_broken: (cmd_of) as $c
        | ($c | length > 0) and (($broken | split("\n")) | index($c) != null);
      def prune: walk(
        if type == "array" then map(select((type != "object") or (is_broken | not)))
        else . end);
      if .SessionStart? then .SessionStart |= prune else . end
      | if ((.hooks? // {}) | has("SessionStart")) then .hooks.SessionStart |= prune else . end
    ' "$CODEX_HOOKS_JSON" 2>/dev/null || true)
    if [ -n "$PRUNED" ] && ! cmp -s <(echo "$PRUNED") "$CODEX_HOOKS_JSON"; then
      cp "$CODEX_HOOKS_JSON" "$CODEX_HOOKS_JSON.bak.$(date +%s)"
      echo "$PRUNED" > "$CODEX_HOOKS_JSON"
      echo "      ✅ entrada(s) removida(s) do SessionStart (backup em ~/.codex/hooks.json.bak.*)"
      echo "      O briefing de sessão continua valendo no Claude Code, que aceita texto."
    else
      echo "      ⚠️  não consegui remover automaticamente — edite ~/.codex/hooks.json à mão."
    fi
  fi
fi

# ── Instruções globais: referências ao MCP Codex aposentado ─────────────────
# Os MCPs codex-coder/codex-reviewer/codex-maestro foram aposentados em
# 2026-04-29 — a delegação virou CLI. Instrução que ainda os cite faz o modelo
# tentar um servidor que não existe e ANUNCIAR fallback em toda sessão:
#
#   CODER FALLBACK: Codex direct (reason: codex-coder unavailable)
#
# O fallback é PARA o caminho correto. É ruído puro, e some quando a instrução
# para de tratar o MCP como primário. Os repositórios já foram corrigidos; o que
# sobra são os arquivos globais da máquina, que não estão em repo nenhum.
for GLOBAL_DOC in "$HOME/.claude/CLAUDE.md" "$HOME/.codex/AGENTS.md"; do
  [ -f "$GLOBAL_DOC" ] || continue
  grep -q 'mcp__codex-\(coder\|reviewer\|maestro\)' "$GLOBAL_DOC" 2>/dev/null || continue

  echo ""
  echo "🧹 $GLOBAL_DOC ainda cita o MCP Codex aposentado:"
  grep -n 'mcp__codex-\(coder\|reviewer\|maestro\)' "$GLOBAL_DOC" | head -5 | sed 's/^/      /'

  cp "$GLOBAL_DOC" "$GLOBAL_DOC.bak.$(date +%s)"
  # Substituição mínima: troca só o token do MCP pela invocação equivalente do
  # wrapper. Não reescreve a prosa em volta — o texto é do usuário, não meu.
  sed -i.tmp \
    -e 's|`mcp__codex-coder__spawn_agent`|`~/.codex/bin/codex-delegate.sh coder <task> <out>`|g' \
    -e 's|`mcp__codex-reviewer__spawn_agent`|`~/.codex/bin/codex-delegate.sh reviewer <task> <out>`|g' \
    -e 's|`mcp__codex-maestro__spawn_agent`|`~/.codex/bin/codex-delegate.sh maestro <task> <out>`|g' \
    -e 's|mcp__codex-coder__spawn_agent|~/.codex/bin/codex-delegate.sh coder|g' \
    -e 's|mcp__codex-reviewer__spawn_agent|~/.codex/bin/codex-delegate.sh reviewer|g' \
    -e 's|mcp__codex-maestro__spawn_agent|~/.codex/bin/codex-delegate.sh maestro|g' \
    "$GLOBAL_DOC" && rm -f "$GLOBAL_DOC.tmp"

  if grep -q 'mcp__codex-\(coder\|reviewer\|maestro\)' "$GLOBAL_DOC" 2>/dev/null; then
    echo "   ⚠️  sobraram referências em outra forma — revise à mão:"
    grep -n 'mcp__codex-' "$GLOBAL_DOC" | head -3 | sed 's/^/      /'
  else
    echo "   ✅ referências trocadas pelo wrapper CLI (backup em $(basename "$GLOBAL_DOC").bak.*)"
  fi
done

# ── stop-hook-git-check.sh: ignora commits já publicados ────────────────────
# Arquivo do harness (Claude Code remoto), não do framework — por isso é
# REPARADO no lugar, nunca substituído: assim continua recebendo as atualizações
# do harness e só a linha com o defeito muda.
#
# O defeito: o hook usa origin/<branch> como referência. Quando esse ref está
# defasado — branch mergeada e a local resetada para main, ou clone --depth 1,
# em que origin/<branch> não acompanha — o range "$upstream..HEAD" passa a
# conter o MERGE COMMIT que o próprio GitHub criou. Ele tem committer
# noreply@github.com e nunca poderá ser assinado por nós, então o hook manda
# fazer `--amend --reset-author` num commit já publicado, o que reescreveria
# história e faria a branch divergir do main.
STOP_HOOK="$HOME/.claude/stop-hook-git-check.sh"
if [ -f "$STOP_HOOK" ]; then
  if grep -q "exclude_published" "$STOP_HOOK" 2>/dev/null; then
    :  # já reparado
  elif ! grep -q 'upstream\.\.HEAD' "$STOP_HOOK" 2>/dev/null; then
    :  # versão do harness que não conhecemos — não mexer
  elif ! command -v python3 >/dev/null 2>&1; then
    echo "   ⚠️  ~/.claude/stop-hook-git-check.sh tem o bug de commit publicado, mas python3 não está disponível para reparar."
  else
    cp "$STOP_HOOK" "$STOP_HOOK.bak.$(date +%s)"
    if python3 - "$STOP_HOOK" <<'PATCH_STOP_HOOK'
import re, sys
path = sys.argv[1]
src = open(path).read()

block = '''
  # Commits já publicados no branch padrão remoto não são trabalho local: quando
  # o ref remoto do branch está defasado (branch mergeada e a local resetada para
  # main, ou clone --depth 1 cujo origin/<branch> não acompanha), o range
  # "$upstream..HEAD" passa a incluir o MERGE COMMIT que o próprio GitHub criou.
  # Ele tem committer noreply@github.com e nunca poderá ser assinado por nós —
  # seguir a instrução de --amend --reset-author reescreveria história publicada.
  # (reparo do Canuto Framework — ver .agents/hooks/install.sh)
  published_ref=""
  for candidate in origin/HEAD origin/main origin/master; do
    if git rev-parse --verify --quiet "$candidate" >/dev/null 2>&1; then
      published_ref="$candidate"
      break
    fi
  done
  exclude_published=()
  if [[ -n "$published_ref" ]]; then
    exclude_published=(--not "$published_ref")
  fi
'''

# Insere o bloco logo após a resolução do upstream.
anchor = re.search(r'^\s*upstream="origin/HEAD"\n\s*fi\n', src, re.M)
if not anchor:
    sys.exit(1)
src = src[:anchor.end()] + block + src[anchor.end():]

# Aplica a exclusão nas duas checagens que usam o range.
before = src
src = src.replace('"$upstream..HEAD" 2>/dev/null', '"$upstream..HEAD" "${exclude_published[@]}" 2>/dev/null')
src = src.replace('"$upstream..HEAD" --count 2>/dev/null', '"$upstream..HEAD" "${exclude_published[@]}" --count 2>/dev/null')
if src == before:
    sys.exit(1)

open(path, 'w').write(src)
PATCH_STOP_HOOK
    then
      if bash -n "$STOP_HOOK" 2>/dev/null; then
        echo "   ✅ ~/.claude/stop-hook-git-check.sh: commits já publicados deixam de ser sinalizados"
      else
        cp "$(ls -t "$STOP_HOOK".bak.* | head -1)" "$STOP_HOOK"
        echo "   ⚠️  reparo do stop-hook gerou script inválido — revertido, nada foi alterado."
      fi
    else
      cp "$(ls -t "$STOP_HOOK".bak.* | head -1)" "$STOP_HOOK"
      echo "   ⚠️  stop-hook-git-check.sh em formato inesperado — reparo pulado (backup restaurado)."
    fi
  fi
fi
