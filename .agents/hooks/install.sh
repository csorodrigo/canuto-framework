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

canuto_managed_hooks() {
  node "$SCRIPT_DIR/reconcile-hooks.mjs" "$@" \
    --manifest "$SCRIPT_DIR/managed-hooks.json"
}

CANUTO_CODEX_PLUGIN_DIR="$SCRIPT_DIR/../plugins/canuto"

canuto_codex_plugin_hooks() {
  local state="$1"
  shift
  local manifest="$CANUTO_CODEX_PLUGIN_DIR/managed-hooks.codex.json"
  if [ "$state" = "disabled" ]; then
    manifest="$CANUTO_CODEX_PLUGIN_DIR/managed-hooks.codex.disabled.json"
  fi
  node "$CANUTO_CODEX_PLUGIN_DIR/codex-plugin-reconcile.mjs" "$@" --manifest "$manifest"
}

# Modos restritos: nunca copiam hooks nem usam a configuração real por padrão.
# `apply` exige o fingerprint emitido por uma execução anterior de `plan`.
case "${1:-}" in
  --plan-codex-canuto-plugin)
    [ -n "${2:-}" ] && [ -n "${3:-}" ] || { echo "uso: install.sh --plan-codex-canuto-plugin <hooks.json> <hooks-dir>" >&2; exit 64; }
    canuto_codex_plugin_hooks enabled plan --config "$2" --hooks-dir "$3"
    exit $?
    ;;
  --apply-codex-canuto-plugin)
    [ -n "${2:-}" ] && [ -n "${3:-}" ] && [ -n "${4:-}" ] && [ -n "${5:-}" ] || { echo "uso: install.sh --apply-codex-canuto-plugin <fingerprint> <hooks.json> <hooks-dir> <state-dir>" >&2; exit 64; }
    canuto_codex_plugin_hooks enabled apply --fingerprint "$2" --config "$3" --hooks-dir "$4" --state-dir "$5"
    exit $?
    ;;
  --verify-codex-canuto-plugin)
    [ -n "${2:-}" ] && [ -n "${3:-}" ] || { echo "uso: install.sh --verify-codex-canuto-plugin <hooks.json> <hooks-dir>" >&2; exit 64; }
    canuto_codex_plugin_hooks enabled verify --config "$2" --hooks-dir "$3"
    exit $?
    ;;
  --plan-disable-codex-canuto-plugin)
    [ -n "${2:-}" ] && [ -n "${3:-}" ] || { echo "uso: install.sh --plan-disable-codex-canuto-plugin <hooks.json> <hooks-dir>" >&2; exit 64; }
    canuto_codex_plugin_hooks disabled plan --config "$2" --hooks-dir "$3"
    exit $?
    ;;
  --apply-disable-codex-canuto-plugin)
    [ -n "${2:-}" ] && [ -n "${3:-}" ] && [ -n "${4:-}" ] && [ -n "${5:-}" ] || { echo "uso: install.sh --apply-disable-codex-canuto-plugin <fingerprint> <hooks.json> <hooks-dir> <state-dir>" >&2; exit 64; }
    canuto_codex_plugin_hooks disabled apply --fingerprint "$2" --config "$3" --hooks-dir "$4" --state-dir "$5"
    exit $?
    ;;
  --verify-disable-codex-canuto-plugin)
    [ -n "${2:-}" ] && [ -n "${3:-}" ] || { echo "uso: install.sh --verify-disable-codex-canuto-plugin <hooks.json> <hooks-dir>" >&2; exit 64; }
    canuto_codex_plugin_hooks disabled verify --config "$2" --hooks-dir "$3"
    exit $?
    ;;
  --rollback-codex-canuto-plugin)
    [ -n "${2:-}" ] && [ -n "${3:-}" ] || { echo "uso: install.sh --rollback-codex-canuto-plugin <batch-id> <state-dir>" >&2; exit 64; }
    node "$CANUTO_CODEX_PLUGIN_DIR/codex-plugin-reconcile.mjs" rollback --batch-id "$2" --state-dir "$3"
    exit $?
    ;;
  --plan-managed-hooks)
    [ -n "${2:-}" ] && [ -n "${3:-}" ] || { echo "uso: install.sh --plan-managed-hooks <settings.json> <hooks-dir>" >&2; exit 64; }
    canuto_managed_hooks plan --config "$2" --hooks-dir "$3"
    exit $?
    ;;
  --apply-managed-hooks)
    [ -n "${2:-}" ] && [ -n "${3:-}" ] && [ -n "${4:-}" ] && [ -n "${5:-}" ] || { echo "uso: install.sh --apply-managed-hooks <fingerprint> <settings.json> <hooks-dir> <state-dir>" >&2; exit 64; }
    canuto_managed_hooks apply --fingerprint "$2" --config "$3" --hooks-dir "$4" --state-dir "$5"
    exit $?
    ;;
  --verify-managed-hooks)
    [ -n "${2:-}" ] && [ -n "${3:-}" ] || { echo "uso: install.sh --verify-managed-hooks <settings.json> <hooks-dir>" >&2; exit 64; }
    canuto_managed_hooks verify --config "$2" --hooks-dir "$3"
    exit $?
    ;;
  --rollback-managed-hooks)
    [ -n "${2:-}" ] && [ -n "${3:-}" ] || { echo "uso: install.sh --rollback-managed-hooks <batch-id> <state-dir>" >&2; exit 64; }
    node "$SCRIPT_DIR/reconcile-hooks.mjs" rollback --batch-id "$2" --state-dir "$3"
    exit $?
    ;;
esac

echo "🔍 Verificando pré-requisitos..."

if ! command -v jq &> /dev/null; then
  echo "⚠️  jq não encontrado. Instale com: brew install jq"
  echo "Abortando — jq é necessário para hooks e MCP."
  exit 1
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

mkdir -p "$SCRIPTS_DIR/lib"
if [ -f "$TOOLS_DIR/pr-merge.sh" ] && [ -f "$TOOLS_DIR/lib/merge-clobber-check.sh" ]; then
  cp "$TOOLS_DIR/pr-merge.sh" "$SCRIPTS_DIR/pr-merge.sh"
  cp "$TOOLS_DIR/lib/merge-clobber-check.sh" "$SCRIPTS_DIR/lib/merge-clobber-check.sh"
  chmod +x "$SCRIPTS_DIR/pr-merge.sh" "$SCRIPTS_DIR/lib/merge-clobber-check.sh"
  echo "   ✅ pr-merge.sh + merge-clobber-check.sh"
else
  echo "   ❌ wrapper de merge versionado incompleto — instalação abortada."
  exit 1
fi

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

# ── Lib global de fallback (~/.canuto/lib) — contrato Tracks A/D 2026-08-01 ──
# O event log morreu em ~90% dos projetos: repos com install desatualizado não
# têm .agents/tools/event-log.sh e os hooks caíam num stub silencioso. A cópia
# global dá aos consumidores uma cascata determinística:
#   lib do repo → ~/.canuto/lib/<arquivo> → stub que LOGA a ausência em
#   ~/.canuto/vault/_health/missing-lib.jsonl (fail-loud, nunca fail-silent).
echo ""
echo "📚 Instalando libs globais de fallback em ~/.canuto/lib/..."
CANUTO_LIB_DIR="$HOME/.canuto/lib"
mkdir -p "$CANUTO_LIB_DIR"
CANUTO_LIB_OK=""
for lib in event-log.sh canuto-memory.sh brief-compose.sh memory-usage.sh delegation-ledger.sh; do
  if [ ! -f "$TOOLS_DIR/$lib" ]; then
    echo "   ⚠️  $lib ausente em $TOOLS_DIR — pulado."
    continue
  fi
  if ! bash -n "$TOOLS_DIR/$lib" 2>/dev/null; then
    echo "   ❌ $lib do repo não parseia (bash -n) — NÃO copiado para a lib global."
    continue
  fi
  # Mesmo padrão dos hooks: guarda a versão anterior e nunca deixa cópia
  # quebrada em pé (uma lib global corrompida quebraria hooks de TODOS os
  # projetos de uma vez).
  prev=""
  if [ -f "$CANUTO_LIB_DIR/$lib" ]; then
    prev="$CANUTO_LIB_DIR/$lib.prev.$$"
    cp "$CANUTO_LIB_DIR/$lib" "$prev" 2>/dev/null || prev=""
  fi
  cp "$TOOLS_DIR/$lib" "$CANUTO_LIB_DIR/$lib"
  if bash -n "$CANUTO_LIB_DIR/$lib" 2>/dev/null; then
    echo "   ✅ $lib"
    CANUTO_LIB_OK="$CANUTO_LIB_OK $lib"
    rm -f "$prev" 2>/dev/null || true
  else
    echo "   ❌ $lib: a cópia instalada não parseia"
    if [ -n "$prev" ] && bash -n "$prev" 2>/dev/null; then
      mv "$prev" "$CANUTO_LIB_DIR/$lib"
      echo "      versão anterior íntegra restaurada"
    else
      rm -f "$CANUTO_LIB_DIR/$lib"
      echo "      removida — consumidores caem no stub que loga em _health/missing-lib.jsonl"
    fi
    rm -f "$prev" 2>/dev/null || true
  fi
done
if [ -n "$CANUTO_LIB_OK" ]; then
  {
    echo "canuto-lib"
    echo "installed-at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "source: $PROJECT_ROOT ($(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown))"
    echo "files:$CANUTO_LIB_OK"
  } > "$CANUTO_LIB_DIR/VERSION" 2>/dev/null || true
  echo "   ✅ VERSION marker atualizado"
fi

echo ""
echo "🧱 Instalando runtime isolado de políticas de repositório..."
REPO_POLICY_RUNTIME="$HOOKS_DIR/canuto-runtime"
for runtime_dir in core adapters/claude adapters/codex runners policies/machine policies/repo; do
  mkdir -p "$REPO_POLICY_RUNTIME/$runtime_dir"
done
for runtime_file in \
  core/execution-identity.mjs core/invocation.mjs core/policy-result.mjs \
  adapters/claude/index.mjs adapters/codex/index.mjs \
  runners/host-pressure-evidence.mjs runners/machine-policy-runner.mjs runners/repo-policy-runner.mjs \
  policies/machine/broad-destruction.mjs policies/machine/host-pressure.mjs \
  policies/machine/index.mjs policies/machine/process-self-match.mjs \
  policies/machine/protected-read.mjs policies/machine/secret-material.mjs \
  policies/repo/build-typecheck.mjs policies/repo/deploy-target.mjs \
  policies/repo/index.mjs policies/repo/validation-receipt.mjs \
  policies/repo/validation-receipt-cli.mjs \
  repo-policy-loader.mjs; do
  [ -f "$SCRIPT_DIR/$runtime_file" ] || { echo "   ❌ runtime ausente: $runtime_file"; exit 1; }
  cp "$SCRIPT_DIR/$runtime_file" "$REPO_POLICY_RUNTIME/$runtime_file"
done
echo "   ✅ runtime de políticas instalado sem executar código do repositório consumidor"

# ── Prévia do estado desejado dos hooks ─────────────────────────────────────
# O instalador comum não aplica mudanças de wiring implicitamente. O mesmo
# fingerprint revisado precisa ser fornecido a --apply-managed-hooks.
echo ""
echo "🔌 Planejando estado desejado dos hooks em settings.json..."

MANAGED_PLAN=$(canuto_managed_hooks plan --config "$SETTINGS_FILE" --hooks-dir "$HOOKS_DIR")
MANAGED_CHANGED=$(printf '%s' "$MANAGED_PLAN" | jq -r '.changed')
MANAGED_FINGERPRINT=$(printf '%s' "$MANAGED_PLAN" | jq -r '.fingerprint')
if [ "$MANAGED_CHANGED" = "true" ]; then
  echo "   ⚠️  wiring pendente; nenhuma configuração foi escrita."
  echo "      fingerprint: $MANAGED_FINGERPRINT"
  echo "      revise com: bash .agents/hooks/install.sh --plan-managed-hooks \"$SETTINGS_FILE\" \"$HOOKS_DIR\""
else
  echo "   ✅ wiring já converge para o manifesto ($MANAGED_FINGERPRINT)"
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
  # Os wrappers executam via `uv run --script`: sem uv, o servidor morre
  # no startup com "No such file or directory" — pré-flight obrigatório.
  CLAUDE_MCP_SKIPPED=0
  if ! command -v uv &> /dev/null; then
    echo "   ⚠️  uv não encontrado — removendo/pulando claude-architect e claude-reviewer."
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
    # Smoke test ANTES de registrar — e ele vale por dois.
    #
    # (1) Aquece o cache do uv. `uv run --script` resolve o ambiente a partir do
    #     cabeçalho PEP 723 e cacheia por spec; a PRIMEIRA vez baixa, e essa
    #     primeira vez cairia no startup do Codex, com teto de 30s por servidor.
    #
    # (2) Prova que o servidor SOBE. Isto é o que faltava: até 2026-07-29 o
    #     instalador conferia que o wrapper existia e era executável, e parava
    #     aí. "Wrapper existe" não é "servidor sobe" — do mesmo jeito que
    #     "codex mcp add retornou 0" não é "registro aponta para algo real".
    #     O `mcp` 2.0.0 removeu `mcp.server.fastmcp`, o import quebrou, e o
    #     defeito só apareceu como "connection closed: initialize response" na
    #     abertura do Codex, sem nada no instalador acusando.
    #
    # `--help` exercita o import (topo do módulo roda antes do argparse) e sai
    # 0 sem subir servidor nem falar stdio. Import quebrado ⇒ rc≠0, aqui e agora.

    MCP_SCRIPT="$SCRIPTS_DIR/claude-agent-mcp.py"
    MCP_VENV="$SCRIPTS_DIR/.mcp-venv"
    MCP_VENV_PY="$MCP_VENV/bin/python"
    MCP_SPEC_MARK="$MCP_VENV/.canuto-spec"

    _mcp_limit() {
      # ADR-0008: nada no caminho de instalação espera para sempre.
      if   command -v timeout  >/dev/null 2>&1; then printf 'timeout'
      elif command -v gtimeout >/dev/null 2>&1; then printf 'gtimeout'
      fi
    }

    _mcp_run() {
      local limit; limit=$(_mcp_limit)
      if [ -n "$limit" ]; then "$limit" 180 "$@" >/dev/null 2>&1
      else "$@" >/dev/null 2>&1; fi
    }

    # As deps vêm do cabeçalho PEP 723 do próprio script — fonte única. Duplicar
    # a lista aqui é como o defeito de 2026-07-29 nasce de novo: dois lugares
    # dizendo qual `mcp` usar, e um deles envelhecendo em silêncio.
    _mcp_declared_spec() {
      command -v python3 >/dev/null 2>&1 || return 1
      python3 - "$MCP_SCRIPT" <<'PYEOF' 2>/dev/null
import re, sys
text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
m = re.search(r"^# /// script\s*$(.*?)^# ///\s*$", text, re.M | re.S)
if not m:
    raise SystemExit(1)
body = "\n".join(l.lstrip("#").strip() for l in m.group(1).splitlines())
at = re.search(r"dependencies\s*=\s*\[", body, re.S)
if not at:
    raise SystemExit(1)
i, depth, quote = at.end(), 1, None
while i < len(body) and depth:
    c = body[i]
    if quote:
        if c == quote: quote = None
    elif c in "\"'": quote = c
    elif c == "[": depth += 1
    elif c == "]": depth -= 1
    i += 1
if depth:
    raise SystemExit(1)
specs = re.findall(r"[\"']([^\"']+)[\"']", body[at.end():i - 1])
if not specs:
    raise SystemExit(1)
print("\n".join(specs))
PYEOF
    }

    # Venv fixo: tira a camada do `uv` do arranque do Codex. Medido num MacBook
    # Air: `uv run --script` gasta ~1,1s SÓ no uv, antes de o Python começar —
    # vezes dois servidores, em toda sessão. O que sobra (~2,6s do `import mcp`,
    # que arrasta o pydantic) é preço da biblioteca e não muda de caminho.
    #
    # O venv é recriado quando a spec declarada muda. Sem essa comparação, um
    # venv velho seguiria servindo a versão errada do `mcp` para sempre — que é
    # exatamente a classe de defeito que o teto de versão fechou.
    MCP_SPEC=$(_mcp_declared_spec || true)
    if [ -z "$MCP_SPEC" ]; then
      echo "   ℹ️  não consegui ler as deps do cabeçalho PEP 723 — pulando o venv (wrappers usam 'uv run --script', ~1,1s a mais por servidor)"
    else
      MCP_SPEC_NOW=$(printf '%s' "$MCP_SPEC" | tr '\n' ' ')
      MCP_SPEC_OLD=$(cat "$MCP_SPEC_MARK" 2>/dev/null || true)
      if [ ! -x "$MCP_VENV_PY" ] || [ "$MCP_SPEC_NOW" != "$MCP_SPEC_OLD" ]; then
        echo "   ⏳ montando venv do MCP (arranque do Codex ~1,1s mais rápido por servidor)..."
        rm -rf "$MCP_VENV"
        # shellcheck disable=SC2086
        if _mcp_run uv venv "$MCP_VENV" \
           && _mcp_run uv pip install --python "$MCP_VENV_PY" $MCP_SPEC_NOW; then
          printf '%s' "$MCP_SPEC_NOW" > "$MCP_SPEC_MARK"
          echo "   ✅ venv pronto ($MCP_SPEC_NOW)"
        else
          echo "   ⚠️  venv falhou — wrappers caem no 'uv run --script' (mais lento, mas funciona)"
          rm -rf "$MCP_VENV"
        fi
      else
        echo "   ✅ venv do MCP já em dia ($MCP_SPEC_NOW)"
      fi
    fi

    # Smoke test no MESMO caminho que o wrapper vai usar. Testar o `uv run` e
    # rodar pelo venv seria provar uma coisa e usar outra.
    if [ -x "$MCP_VENV_PY" ]; then
      MCP_SMOKE_CMD=("$MCP_VENV_PY" "$MCP_SCRIPT" --help)
      MCP_SMOKE_HINT="$MCP_VENV_PY $MCP_SCRIPT --help"
    else
      MCP_SMOKE_CMD=(uv run --script "$MCP_SCRIPT" --help)
      MCP_SMOKE_HINT="uv run --script $MCP_SCRIPT --help"
    fi

    echo "   ⏳ verificando se o servidor MCP sobe (testa o import no caminho real)..."
    if _mcp_run "${MCP_SMOKE_CMD[@]}"; then
      echo "   ✅ claude-agent-mcp importa e roda"
      # Estado declarado pelo usuário manda. Desligado de propósito via
      # canuto-mcp.sh, não volta sozinho aqui — instalador que desfaz escolha
      # do usuário é instalador que ninguém roda de novo.
      MCP_STATE=on
      if [ -f "$SCRIPTS_DIR/.mcp-enabled" ]; then
        case "$(tr -d '[:space:]' < "$SCRIPTS_DIR/.mcp-enabled" 2>/dev/null)" in
          off) MCP_STATE=off ;;
        esac
      fi
      if [ "$MCP_STATE" = "off" ]; then
        echo "   🔌 back-delegation desligada por você (.mcp-enabled=off) — não vou registrar."
        echo "      Religue com: bash .agents/tools/canuto-mcp.sh on"
        codex mcp remove claude-architect >/dev/null 2>&1 || true
        codex mcp remove claude-reviewer  >/dev/null 2>&1 || true
        CLAUDE_MCP_SKIPPED=1
      else
        _codex_mcp_refresh claude-architect -- "$SCRIPTS_DIR/claude-architect.sh"
        _codex_mcp_refresh claude-reviewer  -- "$SCRIPTS_DIR/claude-reviewer.sh"
      fi
    else
      # Registrar um servidor que não sobe é o pior dos mundos: o Codex tenta em
      # TODA abertura, falha, e ainda paga a espera. Melhor não registrar e
      # dizer por quê.
      echo "   ❌ claude-agent-mcp NÃO sobe — não vou registrar (registro que falha custa startup em toda sessão)."
      echo "      Diagnóstico: $MCP_SMOKE_HINT"
      echo "      Se for rede/PyPI fora, re-rode este script quando voltar."
      codex mcp remove claude-architect >/dev/null 2>&1 || true
      codex mcp remove claude-reviewer  >/dev/null 2>&1 || true
      CLAUDE_MCP_SKIPPED=1
    fi

    if [ "$CLAUDE_MCP_SKIPPED" != "1" ]; then

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
