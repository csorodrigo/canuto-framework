#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
ROOT_DIR="$(cd "$PROJECT_DIR" && git rev-parse --show-toplevel 2>/dev/null || printf '%s\n' "$SCRIPT_ROOT")"

if [ ! -f "$ROOT_DIR/.agents/tools/codex-common.sh" ]; then
  ROOT_DIR="$SCRIPT_ROOT"
fi

# shellcheck source=/dev/null
source "$ROOT_DIR/.agents/tools/codex-common.sh"

MODE="full"
JSON_OUTPUT=false

while [ $# -gt 0 ]; do
  case "$1" in
    --smoke)
      MODE="structural"
      ;;
    --structural)
      MODE="structural"
      ;;
    --json)
      JSON_OUTPUT=true
      ;;
  esac
  shift
done

PASS=0
WARN=0
FAIL=0
ITEMS_FILE=$(mktemp)
REVIEWER_PROFILE_AVAILABLE=false

cleanup() {
  rm -f "$ITEMS_FILE"
}
trap cleanup EXIT

record() {
  local status="$1"
  local message="$2"
  printf '%s\t%s\n' "$status" "$message" >> "$ITEMS_FILE"
}

pass() {
  PASS=$((PASS + 1))
  record "PASS" "$1"
  if [ "$JSON_OUTPUT" = false ]; then
    echo "  PASS  $1"
  fi
}

warn() {
  WARN=$((WARN + 1))
  record "WARN" "$1"
  if [ "$JSON_OUTPUT" = false ]; then
    echo "  WARN  $1"
  fi
}

fail() {
  FAIL=$((FAIL + 1))
  record "FAIL" "$1"
  if [ "$JSON_OUTPUT" = false ]; then
    echo "  FAIL  $1"
  fi
}

first_version_line() {
  local command_name="$1"
  shift
  "$command_name" "$@" 2>/dev/null | head -1 | tr -d '\r'
}

check_required_command() {
  local command_name="$1"
  local label="$2"
  shift 2
  local version=""

  if command -v "$command_name" >/dev/null 2>&1; then
    version=$(first_version_line "$command_name" "$@" || true)
    if [ -n "$version" ]; then
      pass "$label available: $version"
    else
      pass "$label available: $(command -v "$command_name")"
    fi
  else
    fail "$label missing: $command_name"
  fi
}

check_optional_command() {
  # Ferramenta útil mas não essencial: ausência vira aviso, não falha. Sem isto
  # todo --doctor em Linux termina BROKEN por brew/rtk/gcloud, que não têm
  # caminho de instalação fora do Homebrew — relatório que sempre acusa defeito
  # é relatório que ninguém lê.
  local command_name="$1"
  local label="$2"
  shift 2

  if command -v "$command_name" >/dev/null 2>&1; then
    local version=""
    version=$(first_version_line "$command_name" "$@" || true)
    pass "$label available: ${version:-$(command -v "$command_name")}"
  else
    warn "$label não instalado (opcional)"
  fi
}

check_astgrep() {
  # Em Linux `sg` é o set-group do shadow (/usr/bin/sg), homônimo do alias do
  # ast-grep: `command -v sg` daria PASS apontando para a ferramenta errada.
  if command -v ast-grep >/dev/null 2>&1; then
    pass "ast-grep available: $(ast-grep --version 2>/dev/null | head -n 1)"
  elif command -v sg >/dev/null 2>&1 && sg --version 2>&1 | grep -qi ast-grep; then
    pass "ast-grep available: $(sg --version 2>/dev/null | head -n 1)"
  else
    fail "ast-grep missing: instale com npm install -g @ast-grep/cli (macOS: brew install ast-grep)"
  fi
}

check_required_file() {
  local file_path="$1"
  local label="$2"

  if [ -f "$file_path" ]; then
    pass "$label exists"
  else
    fail "$label missing: $file_path"
  fi
}

check_required_reference() {
  local file_path="$1"
  local pattern="$2"
  local label="$3"

  if [ -f "$file_path" ] && grep -q "$pattern" "$file_path" 2>/dev/null; then
    pass "$label"
  else
    fail "$label missing"
  fi
}

check_rtk_activation() {
  local rtk_show=""

  if command -v rtk >/dev/null 2>&1; then
    rtk_show=$(mktemp)
    if rtk init --show >"$rtk_show" 2>&1; then
      pass "rtk init --show executes"
      if grep -q "settings.json: exists but RTK hook not configured" "$rtk_show" 2>/dev/null; then
        fail "Claude RTK hook configured"
      elif grep -q "Hook: not found" "$rtk_show" 2>/dev/null; then
        fail "Claude RTK hook configured"
      else
        pass "Claude RTK hook configured"
      fi
    else
      fail "rtk init --show failed: $(head -n 1 "$rtk_show" 2>/dev/null || echo unknown error)"
    fi
    rm -f "$rtk_show"
  else
    fail "rtk init --show unavailable: rtk missing"
  fi

  check_required_file "$HOME/.claude/RTK.md" "Claude RTK.md"
  check_required_reference "$HOME/.claude/CLAUDE.md" "RTK.md" "Claude CLAUDE.md references RTK.md"
  check_required_file "$HOME/.codex/RTK.md" "Codex RTK.md"
  check_required_reference "$HOME/.codex/AGENTS.md" "RTK.md" "Codex AGENTS.md references RTK.md"
}

run_codex_reviewer_helper_smoke() {
  local tmp_dir
  tmp_dir=$(mktemp -d)
  local schema_file="$tmp_dir/schema.json"
  local prompt_file="$tmp_dir/prompt.txt"
  local output_file="$tmp_dir/output.json"
  local used_file="$tmp_dir/used.txt"
  local error_file="$tmp_dir/error.txt"

  cat > "$schema_file" <<'EOF'
{"type":"object","additionalProperties":false,"required":["verdict","summary","score","issues"],"properties":{"verdict":{"type":"string","enum":["LGTM","CONCERNS"]},"summary":{"type":"string"},"score":{"type":"number"},"issues":{"type":"array","items":{"type":"object","additionalProperties":false,"required":["severity","issue","fix"],"properties":{"severity":{"type":"string","enum":["high","medium","low"]},"issue":{"type":"string"},"fix":{"type":"string"}}}}}}
EOF

  cat > "$prompt_file" <<'EOF'
You are reviewing an implementation plan before coding starts.
Return JSON only, matching the provided schema.
Use verdict LGTM.
Plan:
- Step 1: Confirm the helper works.
EOF

  CODEX_REVIEWER_TIMEOUT="${CODEX_REVIEWER_TIMEOUT:-30}"
  if codex_run_reviewer "$tmp_dir" "$schema_file" "$output_file" "$prompt_file" "$used_file" "$error_file"; then
    local used_candidate
    used_candidate=$(cat "$used_file" 2>/dev/null || echo "unknown")
    REVIEWER_PROFILE_AVAILABLE=true
    pass "reviewer helper smoke test: $used_candidate"
  else
    warn "reviewer helper smoke test failed: $(head -n 1 "$error_file")"
  fi

  rm -rf "$tmp_dir"
}

if [ "$JSON_OUTPUT" = false ]; then
  echo ""
  echo "Codex Integration Health Check"
  echo ""
fi

PROJECT_ROOT=$(codex_project_dir)
CONFIG_TOML="$HOME/.codex/config.toml"
CLAUDE_SCRIPTS_DIR="$HOME/.claude/scripts"
# Codex MCP wrappers were retired on 2026-04-29. Maestro now invokes Codex via
# ~/.codex/bin/codex-delegate.sh, which wraps current Codex CLI semantics and
# avoids stdin/profile footguns. The shared lib codex-common.sh is still used by
# reviewer helpers and by this script.

if [ "$MODE" = "full" ]; then
  if [ "$JSON_OUTPUT" = false ]; then
    echo "Dependency checks"
  fi

  check_required_command git "git" --version
  check_required_command curl "curl" --version
  check_required_command wget "wget" --version
  check_required_command jq "jq" --version
  check_required_command node "node" --version
  check_required_command npm "npm" --version
  check_required_command npx "npx" --version
  check_required_command python3 "python3" --version
  check_required_command uv "uv" --version
  check_required_command uvx "uvx" --version
  check_required_command codex "codex" --version
  check_astgrep
  check_required_command rg "ripgrep" --version

  # Opcionais: sem caminho de instalação fora do Homebrew (brew/rtk/gcloud) ou
  # dispensáveis para o framework rodar (bun/gh). Ver ADR-0007.
  check_optional_command brew "brew" --version
  check_optional_command bun "bun" --version
  check_optional_command rtk "rtk" --version
  check_optional_command gcloud "Google Cloud CLI" --version
  check_optional_command gh "GitHub CLI" --version

  if command -v rtk >/dev/null 2>&1; then
    check_rtk_activation
  else
    warn "rtk ausente — checagens de ativação do RTK puladas"
  fi

  if [ "$JSON_OUTPUT" = false ]; then
    echo ""
    echo "Codex runtime checks"
  fi

  if command -v codex >/dev/null 2>&1; then
    pass "codex CLI available: $(codex --version 2>/dev/null || echo unknown)"
  else
    fail "codex CLI not found"
  fi

  if [ -f "$CONFIG_TOML" ]; then
    # O modelo esperado vem de models.yaml, não de um literal aqui. Esta linha
    # dizia `gpt-5.5` enquanto o real já era gpt-5.6 — exatamente a defasagem
    # silenciosa que models.yaml existe para evitar (ver o cabeçalho dele).
    expected_model=$(grep -E "^[[:space:]]{2}maestro:[[:space:]]*\{" \
      "$PROJECT_DIR/.agents/config/models.yaml" 2>/dev/null \
      | sed -nE "s/.*[{,][[:space:]]*model:[[:space:]]*([^,}[:space:]]+).*/\1/p" | head -1)
    configured_model=$(grep -E '^model = ' "$CONFIG_TOML" 2>/dev/null | head -1 | sed -E 's/^model = "?([^"]*)"?.*/\1/')

    if [ -z "$expected_model" ]; then
      warn "não consegui ler o modelo esperado de .agents/config/models.yaml"
    elif [ "$configured_model" = "$expected_model" ]; then
      pass "codex default model configured: $configured_model"
    else
      warn "codex default model é '${configured_model:-<ausente>}', models.yaml diz '$expected_model'"
    fi
    if [ -x "$HOME/.codex/bin/codex-delegate.sh" ]; then
      pass "codex delegate wrapper executable"
    else
      fail "missing executable: ~/.codex/bin/codex-delegate.sh"
    fi
  else
    fail "missing $CONFIG_TOML"
  fi

  SETTINGS_FILE="$HOME/.claude/settings.json"
  if [ -f "$SETTINGS_FILE" ] && command -v jq >/dev/null 2>&1; then
    # Codex is now invoked via CLI (`codex exec --profile <name>`), not MCP.
    # If legacy codex-* MCP entries are still in settings.json, warn — they were
    # retired on 2026-04-29 and should be removed by `bash install.sh --doctor`.
    for server in codex-coder codex-reviewer codex-maestro; do
      if jq -e --arg server "$server" '.mcpServers[$server]' "$SETTINGS_FILE" >/dev/null 2>&1; then
        warn "legacy MCP entry still present: $server (retired — re-run install.sh --doctor to clean)"
      fi
    done

    for hook_name in codex-pretool-guard.sh screenshot-guard.sh; do
      if grep -q "$hook_name" "$SETTINGS_FILE" 2>/dev/null; then
        pass "settings.json hook registered: $hook_name"
      else
        fail "settings.json hook missing: $hook_name"
      fi
    done
  else
    fail "cannot inspect ~/.claude/settings.json"
  fi

  for hook_file in codex-pretool-guard.sh screenshot-guard.sh session-save.sh pre-compact-save.sh; do
    if [ -x "$HOME/.claude/hooks/$hook_file" ]; then
      pass "installed hook executable: $hook_file"
    else
      fail "hook not installed/executable: ~/.claude/hooks/$hook_file"
    fi
  done

  if [ -f "$CONFIG_TOML" ] && {
    grep -q "projects.\"$PROJECT_ROOT\"" "$CONFIG_TOML" 2>/dev/null ||
    grep -q "projects.\"$(dirname "$PROJECT_ROOT")\"" "$CONFIG_TOML" 2>/dev/null
  }; then
    pass "project trust configured for $PROJECT_ROOT"
  else
    warn "project trust missing for $PROJECT_ROOT"
  fi

  if command -v codex >/dev/null 2>&1 && codex mcp list >/dev/null 2>&1; then
    pass "codex mcp list is available"
    _MCP_TMP=$(mktemp)
    trap 'rm -f "$ITEMS_FILE" "$_MCP_TMP"' EXIT
    # obsidian-vault é opcional por decisão documentada (auditoria 2026-06-10:
    # 0 chamadas em 200 sessões — o caminho real é filesystem direto). Exigi-lo
    # aqui contradizia o CLAUDE.md e fazia toda máquina sem Obsidian dar BROKEN.
    for server in ast-grep playwright; do
      if codex mcp get "$server" --json >"$_MCP_TMP" 2>/dev/null; then
        pass "codex native MCP present: $server"
      else
        fail "codex native MCP missing: $server"
      fi
    done

    if codex mcp get obsidian-vault --json >"$_MCP_TMP" 2>/dev/null; then
      if jq -e '(.transport.env.OBSIDIAN_API_KEY // .env.OBSIDIAN_API_KEY) and (.transport.env.OBSIDIAN_BASE_URL // .env.OBSIDIAN_BASE_URL)' "$_MCP_TMP" >/dev/null 2>&1; then
        pass "obsidian-vault has required env configuration"
      else
        warn "obsidian-vault registrado sem env completo (OBSIDIAN_API_KEY/BASE_URL)"
      fi
    else
      warn "obsidian-vault não registrado (opcional — filesystem é o caminho padrão)"
    fi
  else
    fail "codex mcp list unavailable"
  fi

  run_codex_reviewer_helper_smoke
else
  pass "structural mode: skipped user-environment Codex checks"
fi

for script_file in \
  "$ROOT_DIR/.agents/tools/canuto-memory.sh" \
  "$ROOT_DIR/.agents/tools/codex-common.sh" \
  "$ROOT_DIR/.agents/tools/codex-diff-context.sh" \
  "$ROOT_DIR/.agents/tools/codex-context-package.sh" \
  "$ROOT_DIR/.agents/tools/codex-health-check.sh" \
  "$ROOT_DIR/.agents/tools/codex-maestro.sh" \
  "$ROOT_DIR/.agents/tools/vault-sync.sh"; do
  if [ -x "$script_file" ]; then
    pass "tool executable: $(basename "$script_file")"
  else
    fail "tool missing or not executable: $script_file"
  fi
done

if find "$PROJECT_ROOT" -name '.context.md' -print -quit 2>/dev/null | grep -q .; then
  pass "at least one .context.md found"
else
  warn "no .context.md files found"
fi

if [ -f "$PROJECT_ROOT/docs/FEATURE-MAP.md" ]; then
  pass "docs/FEATURE-MAP.md present"
else
  warn "docs/FEATURE-MAP.md missing"
fi

if [ -f "$PROJECT_ROOT/CODEX.md" ] && grep -q "codex-maestro.sh" "$PROJECT_ROOT/CODEX.md" 2>/dev/null; then
  pass "CODEX.md rendered for direct Codex runtime"
else
  warn "CODEX.md missing direct Codex runtime marker"
fi

if find "$PROJECT_ROOT/.agents/vault/digests" -maxdepth 1 -type f ! -name '.gitkeep' -print -quit 2>/dev/null | grep -q .; then
  pass "context digests available"
else
  warn "no generated context digests found"
fi

if [ "$MODE" = "full" ]; then
  if [ -f "$PROJECT_ROOT/.agents/tmp/context-package.md" ] || find "$PROJECT_ROOT/.agents/tmp" -maxdepth 1 -type f -name 'context-package*.md' -print -quit 2>/dev/null | grep -q .; then
    pass "context package available in .agents/tmp/"
  else
    warn "no context package found in .agents/tmp/"
  fi

  if command -v codex >/dev/null 2>&1; then
    if [ "$REVIEWER_PROFILE_AVAILABLE" = true ]; then
      pass "reviewer helper available (gpt-5.5, high)"
    else
      warn "reviewer helper unavailable — reviewer/maestro calls will fall back"
    fi
  fi
fi

# ── Contrato Codex-side (runtime-agnóstico) ─────────────────────────────────
# Paridade dos gates fora do Claude Code: pre-push do git + wrapper com eventos.
_prepush_path="$(git -C "$PROJECT_ROOT" rev-parse --git-path hooks 2>/dev/null || true)"
if [ -n "$_prepush_path" ]; then
  case "$_prepush_path" in /*) : ;; *) _prepush_path="$PROJECT_ROOT/$_prepush_path" ;; esac
  if [ -f "$_prepush_path/pre-push" ] && grep -q "canuto:git-pre-push-gate" "$_prepush_path/pre-push" 2>/dev/null; then
    pass "git pre-push gate instalado (gate de PR vale para Codex e push manual)"
  else
    warn "git pre-push gate ausente — rode: bash .agents/hooks/install.sh"
  fi
fi
if grep -q "SESSION_START" "$ROOT_DIR/.agents/tools/codex-maestro.sh" 2>/dev/null \
  && grep -q "trap _canuto_codex_session_end EXIT" "$ROOT_DIR/.agents/tools/codex-maestro.sh" 2>/dev/null; then
  pass "codex-maestro.sh registra eventos de sessão + gate de CLOSEOUT"
else
  warn "codex-maestro.sh sem eventos/CLOSEOUT — atualize o framework (install.sh --update)"
fi
if grep -q "Contrato de Eventos e Gates" "$PROJECT_ROOT/AGENTS.md" 2>/dev/null; then
  pass "AGENTS.md carrega o contrato de eventos/gates para sessões Codex"
else
  warn "AGENTS.md sem a seção 'Contrato de Eventos e Gates' — rode install.sh --update"
fi
if [ -f "$ROOT_DIR/.agents/tools/event-log.sh" ] \
  && bash "$ROOT_DIR/.agents/tools/event-log.sh" path >/dev/null 2>&1; then
  pass "event-log.sh resolve caminho do log (fonte de verdade compartilhada)"
else
  warn "event-log.sh ausente ou sem caminho resolvível"
fi
if [ -x "$HOME/.codex/bin/codex-delegate.sh" ]; then
  pass "wrapper de delegação presente: ~/.codex/bin/codex-delegate.sh"
else
  warn "wrapper de delegação ausente — rode install.sh --update (instala o template quando ausente)"
fi

VERDICT="HEALTHY"
EXIT_CODE=0
if [ "$FAIL" -gt 0 ]; then
  VERDICT="BROKEN"
  EXIT_CODE=1
elif [ "$WARN" -gt 0 ]; then
  VERDICT="DEGRADED"
fi

if [ "$JSON_OUTPUT" = true ]; then
  python3 - "$ITEMS_FILE" "$PROJECT_ROOT" "$MODE" "$VERDICT" "$PASS" "$WARN" "$FAIL" <<'PYEOF'
import json
import sys

items_file, project_root, mode, verdict, pass_count, warn_count, fail_count = sys.argv[1:]
results = []
with open(items_file, encoding="utf-8") as fh:
    for line in fh:
        status, message = line.rstrip("\n").split("\t", 1)
        results.append({"status": status, "message": message})

print(json.dumps({
    "tool": "codex-health-check",
    "project_root": project_root,
    "mode": mode,
    "verdict": verdict,
    "counts": {
        "pass": int(pass_count),
        "warn": int(warn_count),
        "fail": int(fail_count),
    },
    "results": results,
}, ensure_ascii=True))
PYEOF
else
  echo ""
  if [ "$VERDICT" = "BROKEN" ]; then
    echo "Verdict: BROKEN ($FAIL failures, $WARN warnings, $PASS passing)"
  elif [ "$VERDICT" = "DEGRADED" ]; then
    echo "Verdict: DEGRADED ($WARN warnings, $PASS passing)"
  else
    echo "Verdict: HEALTHY ($PASS passing)"
  fi
fi

exit "$EXIT_CODE"
