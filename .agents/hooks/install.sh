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

# ── Merge idempotente + self-heal do settings.json (auditoria 2026-08-01) ────
# CAUSA-RAIZ da duplicação de hooks corrigida aqui: o merge jq antigo
# identificava grupos por (matcher + conjunto ordenado dos comandos do grupo).
# Bastava o grupo local ter UM hook a mais (git-truth, ccgram,
# session-budget-warn...) para a chave nunca bater — e o grupo do snippet era
# appendado INTEIRO de novo a cada install. A dedup por hook só rodava DENTRO
# de um grupo casado, nunca entre grupos do mesmo evento: 12 hooks chegaram a
# rodar 2x por evento na máquina de referência.
#
# Regras novas:
#   1. Presença por (evento + command): se o comando já está registrado no
#      evento — em QUALQUER grupo/matcher — skip. Cobre (evento+matcher+
#      command) e também respeita consolidação manual do usuário (ex.:
#      codex-pretool-guard movido do matcher "" para "Bash").
#   2. Self-heal: duplicatas exatas (evento+matcher+command) PRÉ-EXISTENTES de
#      hooks canuto são removidas (1ª ocorrência preservada), incluindo o caso
#      nominal cross-matcher do codex-pretool-guard ("" duplica "Bash" porque
#      matcher vazio casa todo tool). Hooks não-canuto nunca são tocados.
#   3. Só reescreve o arquivo quando houve mudança real (escrita atômica).
canuto_settings_merge() {
  local settings="$1" snippet="$2"
  if [ ! -f "$snippet" ]; then
    echo "   ⚠️  snippet não encontrado: $snippet — merge de hooks pulado."
    return 0
  fi
  if [ ! -f "$settings" ]; then
    mkdir -p "$(dirname "$settings")"
    cp "$snippet" "$settings"
    echo "   ✅ settings.json criado com hooks e MCP servers"
    return 0
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    echo "   ⚠️  python3 indisponível — merge de hooks pulado (settings.json intacto; instale python3 e re-rode)."
    return 0
  fi

  # Hooks canuto = exatamente os .sh que este diretório distribui.
  local canuto_list="" f
  for f in "$SCRIPT_DIR"/*.sh; do
    [ -f "$f" ] || continue
    canuto_list="$canuto_list$(basename "$f"),"
  done

  if python3 - "$settings" "$snippet" "$canuto_list" <<'PYMERGE'
import json, os, sys

settings_path, snippet_path = sys.argv[1], sys.argv[2]
canuto_names = set(n for n in sys.argv[3].split(",") if n)
HOME = os.path.expanduser("~")

def norm(cmd):
    # "~/.claude/hooks/x.sh" e "/Users/me/.claude/hooks/x.sh" são o mesmo hook.
    if isinstance(cmd, str) and cmd.startswith("~"):
        return HOME + cmd[1:]
    return cmd

def script_name(cmd):
    # basename do executável, ignorando argumentos ("api-reference-guard.sh stop")
    # e pulando interpretador ("bash ~/.claude/hooks/x.sh" -> "x.sh" — sem isso,
    # toda regra por nome falhava em silêncio na forma bash-prefixada).
    if not isinstance(cmd, str) or not cmd.strip():
        return ""
    toks = cmd.split()
    tok = toks[0]
    if tok.rsplit("/", 1)[-1] in ("bash", "sh", "zsh") and len(toks) > 1:
        tok = toks[1]
    return tok.rsplit("/", 1)[-1]

with open(settings_path) as fh:
    data = json.load(fh)
with open(snippet_path) as fh:
    snip = json.load(fh)

changes = []
hooks = data.setdefault("hooks", {})

# ── Migração matcher ""->"Bash" do codex-pretool-guard ──────────────────────
# Ressalva do review cego 2026-08-01: "preservar a 1ª ocorrência" deixava o
# guard sob matcher "" vencer quando esse grupo vinha primeiro — e matcher
# vazio dispara o guard para TODO tool. Migra PRESERVANDO metadata do usuário
# (cwd/timeout/env — garantia testada no test-framework): grupo "" só com o
# guard tem o matcher convertido em-lugar; grupo misto tem só o hook-objeto do
# guard movido para o grupo "Bash". Roda ANTES do self-heal: duplicatas que a
# migração criar (guard já existente sob "Bash") caem na dedup logo abaixo.
for event, groups in list(hooks.items()):
    if not isinstance(groups, list):
        continue
    for group in groups:
        if not isinstance(group, dict) or group.get("matcher", "") != "":
            continue
        ghooks = group.get("hooks", [])
        guard_hooks = [h for h in ghooks if isinstance(h, dict)
                       and script_name(h.get("command", "")) == "codex-pretool-guard.sh"]
        if not guard_hooks:
            continue
        others = [h for h in ghooks if h not in guard_hooks]
        if not others:
            group["matcher"] = "Bash"
            changes.append('migração: grupo do codex-pretool-guard convertido de '
                           'matcher "" para "Bash" (metadata preservada) [%s]' % event)
        else:
            target = None
            for g in groups:
                if isinstance(g, dict) and g.get("matcher", "") == "Bash":
                    target = g
                    break
            if target is None:
                target = {"matcher": "Bash", "hooks": []}
                groups.append(target)
            target.setdefault("hooks", []).extend(guard_hooks)
            group["hooks"] = others
            changes.append('migração: codex-pretool-guard movido do matcher "" '
                           'para "Bash" (hook-metadata preservada) [%s]' % event)

# ── Self-heal: remove duplicatas pré-existentes de hooks canuto ─────────────
for event, groups in list(hooks.items()):
    if not isinstance(groups, list):
        continue
    seen_exact = set()   # (matcher, command normalizado)
    seen_cmd = {}        # command normalizado -> primeiro matcher
    new_groups = []
    for group in groups:
        if not isinstance(group, dict):
            new_groups.append(group)
            continue
        matcher = group.get("matcher", "")
        kept = []
        for h in group.get("hooks", []):
            if not isinstance(h, dict):
                kept.append(h)
                continue
            cmd = norm(h.get("command", ""))
            name = script_name(cmd)
            key = (matcher, cmd)
            if key in seen_exact and name in canuto_names:
                changes.append("self-heal: duplicata exata removida [%s] matcher=%r %s"
                               % (event, matcher, h.get("command", "")))
                continue
            if (name == "codex-pretool-guard.sh" and cmd in seen_cmd
                    and seen_cmd[cmd] != matcher):
                changes.append("self-heal: duplicata cross-matcher removida [%s] matcher=%r %s"
                               % (event, matcher, h.get("command", "")))
                continue
            seen_exact.add(key)
            seen_cmd.setdefault(cmd, matcher)
            kept.append(h)
        if kept:
            g2 = dict(group)
            g2["hooks"] = kept
            new_groups.append(g2)
        else:
            changes.append("self-heal: grupo vazio removido [%s] matcher=%r"
                           % (event, group.get("matcher", "")))
    hooks[event] = new_groups

# ── Merge: registra hooks do snippet ausentes (presença por evento+command) ─
for event, sgroups in (snip.get("hooks") or {}).items():
    if not isinstance(sgroups, list):
        continue
    groups = hooks.setdefault(event, [])
    present = set()
    for g in groups:
        if isinstance(g, dict):
            for h in g.get("hooks", []):
                if isinstance(h, dict):
                    present.add(norm(h.get("command", "")))
    for sgroup in sgroups:
        if not isinstance(sgroup, dict):
            continue
        matcher = sgroup.get("matcher", "")
        for h in sgroup.get("hooks", []):
            if not isinstance(h, dict):
                continue
            cmd = norm(h.get("command", ""))
            if not cmd or cmd in present:
                continue
            target = None
            for g in groups:
                if isinstance(g, dict) and g.get("matcher", "") == matcher:
                    target = g
                    break
            if target is None:
                target = {"matcher": matcher, "hooks": []}
                groups.append(target)
            target.setdefault("hooks", []).append(h)
            present.add(cmd)
            changes.append("registrado [%s] matcher=%r %s"
                           % (event, matcher, h.get("command", "")))

# ── mcpServers: deep-merge (preserva chaves extras locais, ex. env custom) ──
def deep_merge(base, over):
    out = dict(base)
    for k, v in over.items():
        if isinstance(v, dict) and isinstance(out.get(k), dict):
            out[k] = deep_merge(out[k], v)
        else:
            out[k] = v
    return out

snip_mcp = snip.get("mcpServers") or {}
if snip_mcp:
    current = data.get("mcpServers") or {}
    merged = deep_merge(current, snip_mcp)
    if merged != current:
        changes.append("mcpServers atualizados a partir do snippet")
        data["mcpServers"] = merged

if changes:
    tmp = settings_path + ".canuto-merge.tmp"
    with open(tmp, "w") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    os.replace(tmp, settings_path)
    for c in changes:
        print("   • " + c)
    print("   ✅ settings.json: %d mudança(s) aplicada(s)" % len(changes))
else:
    print("   ✅ settings.json já em dia (0 mudanças)")
PYMERGE
  then
    :
  else
    echo "   ⚠️  merge de settings falhou — settings.json NÃO foi modificado."
  fi
}

# Modo restrito (usado pelos testes e pelo track de validação): roda SÓ o
# merge/self-heal do settings, sem copiar hooks nem tocar em mais nada.
#   bash .agents/hooks/install.sh --merge-settings-only <settings.json> [snippet.json]
if [ "${1:-}" = "--merge-settings-only" ]; then
  [ -n "${2:-}" ] || { echo "uso: install.sh --merge-settings-only <settings.json> [snippet.json]" >&2; exit 64; }
  canuto_settings_merge "$2" "${3:-$SCRIPT_DIR/settings-snippet.json}"
  exit $?
fi

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

# ── MCP Servers + registro de hooks no settings.json ────────────────────────
# O merge/self-heal mora em canuto_settings_merge() (topo deste arquivo) — o
# merge jq antigo, que causava a duplicação de hooks, foi removido em
# 2026-08-01 (ver comentário da função para a causa-raiz).
echo ""
echo "🔌 Configurando hooks e MCP servers em settings.json..."

SNIPPET="$SCRIPT_DIR/settings-snippet.json"
canuto_settings_merge "$SETTINGS_FILE" "$SNIPPET"

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
