#!/usr/bin/env bash
# =============================================================================
# Canuto Framework — Test Suite
# Validates framework structure, personas, skills, hooks, and vault setup.
#
# Usage:
#   bash test-framework.sh           — Run all tests
#   bash test-framework.sh --verbose — Show details for passing tests too
# =============================================================================

set -euo pipefail

FRAMEWORK_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENTS_DIR="$FRAMEWORK_DIR/.agents"
VERBOSE=false

[[ "${1:-}" == "--verbose" ]] && VERBOSE=true

# ── Test counters ───────────────────────────────────────────────────────────
PASS=0
FAIL=0
WARN=0
ERRORS=()
WARNINGS=()

pass() {
  PASS=$((PASS + 1))
  if [ "$VERBOSE" = true ]; then
    echo "  ✅ $1"
  fi
}

fail() {
  FAIL=$((FAIL + 1))
  ERRORS+=("$1")
  echo "  ❌ $1"
}

warn() {
  WARN=$((WARN + 1))
  WARNINGS+=("$1")
  echo "  ⚠️  $1"
}

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Canuto Framework — Test Suite"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# TEST 1: Personas
# ═══════════════════════════════════════════════════════════════════════════
echo "── Test 1: Personas ──"

REQUIRED_PERSONAS=(maestro architect coder reviewer contextualizer investigator)
for persona in "${REQUIRED_PERSONAS[@]}"; do
  PFILE="$AGENTS_DIR/personas/$persona.md"
  if [ ! -f "$PFILE" ]; then
    fail "Persona missing: $persona.md"
    continue
  fi

  # Check required sections (personas use ## Identity or ## Role)
  HAS_ROLE=$(grep -cE "^## (Role|Identity)" "$PFILE" 2>/dev/null) || HAS_ROLE=0
  if [ "$HAS_ROLE" -eq 0 ]; then
    fail "$persona.md missing '## Identity' or '## Role' section"
  else
    pass "$persona.md has Identity/Role section"
  fi

  # Check for procedure/workflow section (various names)
  HAS_PROC=$(grep -cE "^## (Procedure|Workflow|Session Start|Core Procedure)" "$PFILE" 2>/dev/null) || HAS_PROC=0
  if [ "$HAS_PROC" -eq 0 ]; then
    warn "$persona.md missing Procedure/Workflow section"
  else
    pass "$persona.md has Procedure section"
  fi
done

for archived_persona in tester debugger; do
  if [ -f "$AGENTS_DIR/personas/_archive/$archived_persona.md" ]; then
    pass "Archived persona exists: $archived_persona.md"
  else
    fail "Archived persona missing: $archived_persona.md"
  fi
done
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# TEST 2: Core Skills Exist
# ═══════════════════════════════════════════════════════════════════════════
echo "── Test 2: Core Skills ──"

CORE_SKILLS=(
  context-maintenance
  continuous-learning
  health-check
  metrics
  audit-trail
  governance
  convergence-detection
  session-goals
  runtime-flags
  mcp-obsidian
  vault-maintenance
  research
)

for skill in "${CORE_SKILLS[@]}"; do
  FLAT_FILE="$AGENTS_DIR/skills/$skill.md"
  DIRECTORY_FILE="$AGENTS_DIR/skills/$skill/SKILL.md"
  if [ -f "$FLAT_FILE" ]; then
    pass "Skill exists: $skill.md"
  elif [ -f "$DIRECTORY_FILE" ]; then
    pass "Skill exists: $skill/SKILL.md"
  else
    fail "Core skill missing: $skill (.md or /SKILL.md)"
  fi
done
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# TEST 3: Hooks Syntax
# ═══════════════════════════════════════════════════════════════════════════
echo "── Test 3: Hook Scripts ──"

HOOKS=(session-save pre-compact-save check-references check-orphans screenshot-guard codex-pretool-guard protect-files require-tests-for-pr log-commands session-start validation-mark validation-clear retry-detect fingerprint-gate posttooluse-universal pre-finalize)
for hook in "${HOOKS[@]}"; do
  HFILE="$AGENTS_DIR/hooks/$hook.sh"
  if [ ! -f "$HFILE" ]; then
    warn "Hook not found: $hook.sh"
    continue
  fi

  # Syntax check
  if bash -n "$HFILE" 2>/dev/null; then
    pass "$hook.sh syntax valid"
  else
    fail "$hook.sh has syntax errors"
  fi

  # Executable check
  if [ -x "$HFILE" ]; then
    pass "$hook.sh is executable"
  else
    warn "$hook.sh not executable (chmod +x needed)"
  fi
done
echo ""

echo "── Test 3b: Tooling ──"

CODEX_TOOLS=(canuto-memory codex-common codex-diff-context codex-context-package codex-health-check canuto-consumer-smoke codex-maestro vault-sync otel-emit)
for tool in "${CODEX_TOOLS[@]}"; do
  TFILE="$AGENTS_DIR/tools/$tool.sh"
  if [ ! -f "$TFILE" ]; then
    fail "Codex tool missing: $tool.sh"
    continue
  fi

  if bash -n "$TFILE" 2>/dev/null; then
    pass "$tool.sh syntax valid"
  else
    fail "$tool.sh has syntax errors"
  fi

  if [ -x "$TFILE" ]; then
    pass "$tool.sh is executable"
  else
    warn "$tool.sh not executable (chmod +x needed)"
  fi
done

for js_tool in framework-session-audit framework-session-audit-lib framework-session-audit.test; do
  TFILE="$AGENTS_DIR/tools/$js_tool.js"
  if [ ! -f "$TFILE" ]; then
    fail "Codex JS tool missing: $js_tool.js"
    continue
  fi

  if node --check "$TFILE" >/dev/null 2>&1; then
    pass "$js_tool.js syntax valid"
  else
    fail "$js_tool.js has syntax errors"
  fi
done

mkdir -p "$AGENTS_DIR/tmp"
CONTEXT_SMOKE="$AGENTS_DIR/tmp/context-package-smoke.md"
if bash "$AGENTS_DIR/tools/codex-context-package.sh" --task "Smoke Test" --output "$CONTEXT_SMOKE" --file "CLAUDE.md" >/dev/null 2>&1; then
  if grep -q "Context Package" "$CONTEXT_SMOKE" 2>/dev/null; then
    pass "codex-context-package.sh happy path"
  else
    fail "codex-context-package.sh did not write expected content"
  fi
else
  fail "codex-context-package.sh happy path failed"
fi
rm -f "$CONTEXT_SMOKE"

if bash "$AGENTS_DIR/tools/codex-diff-context.sh" --staged >/dev/null 2>&1; then
  pass "codex-diff-context.sh happy path"
else
  fail "codex-diff-context.sh happy path failed"
fi

if bash "$AGENTS_DIR/tools/codex-health-check.sh" --structural --json >/tmp/codex-health-json.$$ 2>/dev/null; then
  if command -v jq >/dev/null 2>&1 && jq -e '.tool == "codex-health-check" and .verdict' /tmp/codex-health-json.$$ >/dev/null 2>&1; then
    pass "codex-health-check.sh JSON output"
  else
    fail "codex-health-check.sh JSON output invalid"
  fi
else
  fail "codex-health-check.sh --structural --json failed"
fi
rm -f /tmp/codex-health-json.$$

if bash "$AGENTS_DIR/tools/canuto-consumer-smoke.sh" --json >/tmp/canuto-consumer-smoke.$$ 2>/dev/null; then
  if command -v jq >/dev/null 2>&1 && jq -e '.tool == "canuto-consumer-smoke" and .verdict' /tmp/canuto-consumer-smoke.$$ >/dev/null 2>&1; then
    pass "canuto-consumer-smoke.sh JSON output"
  else
    fail "canuto-consumer-smoke.sh JSON output invalid"
  fi
else
  fail "canuto-consumer-smoke.sh --json failed"
fi
rm -f /tmp/canuto-consumer-smoke.$$

HOOKS_HOME="$(mktemp -d)"
mkdir -p "$HOOKS_HOME/.claude"
cat > "$HOOKS_HOME/.claude/settings.json" <<'EOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "",
        "cwd": "/tmp/preserve-me",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/codex-pretool-guard.sh",
            "timeout": 240,
            "env": {
              "KEEP_ME": "1"
            }
          }
        ]
      }
    ]
  }
}
EOF
if HOME="$HOOKS_HOME" bash "$AGENTS_DIR/hooks/install.sh" >/dev/null 2>&1; then
  PRESERVED_CWD=$(jq -r '.hooks.PreToolUse[] | select(.hooks[]?.command == "~/.claude/hooks/codex-pretool-guard.sh") | .cwd // empty' "$HOOKS_HOME/.claude/settings.json" | head -1)
  PRESERVED_ENV=$(jq -r '.hooks.PreToolUse[] | select(.hooks[]?.command == "~/.claude/hooks/codex-pretool-guard.sh") | .hooks[] | select(.command == "~/.claude/hooks/codex-pretool-guard.sh") | .env.KEEP_ME // empty' "$HOOKS_HOME/.claude/settings.json" | head -1)
  HOOK_COUNT=$(jq '[.hooks.PreToolUse[] | .hooks[] | select(.command == "~/.claude/hooks/codex-pretool-guard.sh")] | length' "$HOOKS_HOME/.claude/settings.json")
  if [ "$PRESERVED_CWD" = "/tmp/preserve-me" ] && [ "$PRESERVED_ENV" = "1" ] && [ "$HOOK_COUNT" -eq 1 ]; then
    pass "hook installer preserves existing hook metadata while deduping"
  else
    fail "hook installer lost hook metadata or duplicated entries"
  fi
else
  fail ".agents/hooks/install.sh merge regression test failed"
fi
rm -rf "$HOOKS_HOME"

if bash -c "cd '$FRAMEWORK_DIR/docs' && source '$AGENTS_DIR/tools/canuto-memory.sh' && [ \"\$(canuto_project_dir)\" = '$FRAMEWORK_DIR' ] && [ \"\$(canuto_project_slug)\" = 'canuto-framework-v1' ]" >/dev/null 2>&1; then
  pass "canuto-memory root resolution works from subdirectories"
else
  fail "canuto-memory root resolution failed from subdirectories"
fi

if bash -c "source '$AGENTS_DIR/tools/codex-common.sh' && codex_run_with_timeout 2 bash -lc 'exit 0'" >/dev/null 2>&1; then
  pass "codex-common timeout wrapper works"
else
  fail "codex-common timeout wrapper failed"
fi

if node --test "$AGENTS_DIR/tools/framework-session-audit.test.js" >/tmp/framework-session-audit-test.$$ 2>&1; then
  pass "framework-session-audit tests"
else
  fail "framework-session-audit tests failed"
fi
rm -f /tmp/framework-session-audit-test.$$

if node "$AGENTS_DIR/tools/framework-session-audit.js" --help >/dev/null 2>&1; then
  pass "framework-session-audit CLI help"
else
  fail "framework-session-audit CLI help failed"
fi

PORTABILITY_HOME="$(mktemp -d)"
mkdir -p "$PORTABILITY_HOME/.canuto/vault"
cat > "$PORTABILITY_HOME/.canuto/vault/A.md" <<'EOF'
[[B]]
[Local](B.md)
EOF
cat > "$PORTABILITY_HOME/.canuto/vault/B.md" <<'EOF'
[[A]]
EOF

if HOME="$PORTABILITY_HOME" CLAUDE_PROJECT_DIR="$FRAMEWORK_DIR" bash "$AGENTS_DIR/hooks/check-references.sh" >/dev/null 2>&1; then
  pass "check-references.sh portable runtime"
else
  fail "check-references.sh portable runtime failed"
fi

if HOME="$PORTABILITY_HOME" CLAUDE_PROJECT_DIR="$FRAMEWORK_DIR" bash "$AGENTS_DIR/hooks/check-orphans.sh" >/dev/null 2>&1; then
  pass "check-orphans.sh portable runtime"
else
  fail "check-orphans.sh portable runtime failed"
fi

rm -rf "$PORTABILITY_HOME"

if CLAUDE_PROJECT_DIR="$FRAMEWORK_DIR" bash "$AGENTS_DIR/tools/vault-sync.sh" >/dev/null 2>&1; then
  pass "vault-sync.sh no-op path"
else
  fail "vault-sync.sh no-op path failed"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# TEST 4: Vault Bases
# ═══════════════════════════════════════════════════════════════════════════
echo "── Test 4: Vault Bases ──"

REQUIRED_BASES=(
  instincts-by-confidence
  metrics-dashboard
  decisions-timeline
  pending-tasks
  audit-by-type
  components-registry
  global-instincts
  all-instincts
  all-metrics
  cross-project-patterns
)

for base in "${REQUIRED_BASES[@]}"; do
  BFILE="$AGENTS_DIR/vault/bases/$base.base"
  if [ ! -f "$BFILE" ]; then
    fail "Base missing: $base.base"
    continue
  fi

  # Check that base has filters: section
  if grep -q "^filters:" "$BFILE" 2>/dev/null; then
    pass "$base.base has filters"
  else
    fail "$base.base missing 'filters:' section"
  fi

  # Check that base has views: section
  if grep -q "^views:" "$BFILE" 2>/dev/null; then
    pass "$base.base has views"
  else
    warn "$base.base missing 'views:' section"
  fi
done
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# TEST 5: Install Script
# ═══════════════════════════════════════════════════════════════════════════
echo "── Test 5: Install Script ──"

if [ -f "$FRAMEWORK_DIR/install.sh" ]; then
  if bash -n "$FRAMEWORK_DIR/install.sh" 2>/dev/null; then
    pass "install.sh syntax valid"
  else
    fail "install.sh has syntax errors"
  fi

  INSTALL_STATIC_PATTERNS=(
    'install|update|check|skill|migrate|repair|doctor|test|deps)'
    '"install.sh"'
    '--test)    MODE="test"'
    '--repair)  MODE="repair"'
    '--doctor|--health) MODE="doctor"'
    'rtk init -g --auto-patch'
    'rtk init -g --codex'
    '--deps-only|--deps'
  )

  for pattern in "${INSTALL_STATIC_PATTERNS[@]}"; do
    if grep -qF -- "$pattern" "$FRAMEWORK_DIR/install.sh" 2>/dev/null; then
      pass "install.sh covers: $pattern"
    else
      fail "install.sh missing expected dependency coverage: $pattern"
    fi
  done

  # Cobertura de dependências por FERRAMENTA, não pela string da chamada.
  # Antes esta lista continha as linhas literais `ensure_brew_formula ...`, o
  # que amarrava o teste ao gerenciador de pacotes: ao ensinar o instalador a
  # usar apt/dnf na VPS, 13 testes quebraram sem nenhuma dependência ter
  # deixado de ser coberta. O que importa é a ferramenta aparecer no bloco.
  INSTALL_REQUIRED_TOOLS=(git curl wget jq node python3 rg codex)
  INSTALL_OPTIONAL_TOOLS=(gh bun rtk)

  for tool in "${INSTALL_REQUIRED_TOOLS[@]}"; do
    if grep -qE "^\s*ensure_dep\s+$tool\s" "$FRAMEWORK_DIR/install.sh" 2>/dev/null; then
      pass "install.sh cobre dependência obrigatória: $tool"
    else
      fail "install.sh missing expected dependency coverage: $tool"
    fi
  done

  for tool in "${INSTALL_OPTIONAL_TOOLS[@]}"; do
    if grep -qE "^\s*ensure_dep\s+$tool\s.*\sopt\s*$" "$FRAMEWORK_DIR/install.sh" 2>/dev/null; then
      pass "install.sh cobre dependência opcional: $tool"
    else
      fail "install.sh should cover $tool as optional (sem caminho de instalação fora do brew)"
    fi
  done

  # uv e ast-grep têm helper próprio (instalador oficial da Astral / colisão do
  # `sg` com o shadow em Linux), então não aparecem como ensure_dep no bloco.
  for helper in ensure_uv ensure_astgrep; do
    if grep -qE "^\s*$helper\s*$" "$FRAMEWORK_DIR/install.sh" 2>/dev/null; then
      pass "install.sh chama $helper"
    else
      fail "install.sh missing expected dependency coverage: $helper"
    fi
  done

  # Multi-gerenciador: o instalador não pode voltar a exigir Homebrew.
  for marker in 'PKG_MGR="apt"' 'PKG_MGR="dnf"' 'dep_present'; do
    if grep -qF -- "$marker" "$FRAMEWORK_DIR/install.sh" 2>/dev/null; then
      pass "install.sh mantém suporte multi-gerenciador: $marker"
    else
      fail "install.sh perdeu suporte multi-gerenciador: $marker"
    fi
  done

  canonical_line=$(grep -n 'local CANONICAL_MODEL=' "$FRAMEWORK_DIR/install.sh" | head -1 | cut -d: -f1)
  config_branch_line=$(grep -n 'if \[ ! -f "$config_toml" \]' "$FRAMEWORK_DIR/install.sh" | head -1 | cut -d: -f1)
  if [ -n "$canonical_line" ] && [ -n "$config_branch_line" ] && [ "$canonical_line" -lt "$config_branch_line" ]; then
    pass "install.sh defines canonical model before fresh-config branch"
  else
    fail "install.sh may use an unbound canonical model on fresh install"
  fi

  if grep -qF 'Merged per-role profiles v2' "$FRAMEWORK_DIR/install.sh" \
    && ! grep -qF '> "$HOME/.codex/${role}.config.toml"' "$FRAMEWORK_DIR/install.sh"; then
    pass "install.sh preserves existing per-role profile settings"
  else
    fail "install.sh still truncates existing per-role profile settings"
  fi

  for role in architect maestro; do
    if grep -Eq "^[[:space:]]{2}${role}:.*effort:[[:space:]]*xhigh" "$AGENTS_DIR/config/models.yaml"; then
      pass "$role uses wrapper-compatible xhigh effort"
    else
      fail "$role uses an effort unsupported by released wrappers"
    fi
  done
else
  fail "install.sh not found"
fi

if [ -f "$FRAMEWORK_DIR/analyze.sh" ]; then
  if bash -n "$FRAMEWORK_DIR/analyze.sh" 2>/dev/null; then
    pass "analyze.sh syntax valid"
  else
    fail "analyze.sh has syntax errors"
  fi
else
  warn "analyze.sh not found"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# TEST 6: SPEC and CLAUDE.md
# ═══════════════════════════════════════════════════════════════════════════
echo "── Test 6: Framework Config ──"

if [ -f "$AGENTS_DIR/SPEC.md" ]; then
  pass "SPEC.md exists"
else
  fail "SPEC.md missing"
fi

if [ -f "$FRAMEWORK_DIR/CLAUDE.md" ]; then
  pass "CLAUDE.md exists"

  # Check required sections
  for section in "## Framework" "## Preferences" "## On Session Start"; do
    if grep -q "$section" "$FRAMEWORK_DIR/CLAUDE.md" 2>/dev/null; then
      pass "CLAUDE.md has '$section'"
    else
      fail "CLAUDE.md missing '$section'"
    fi
  done
else
  fail "CLAUDE.md missing"
fi

if [ -f "$FRAMEWORK_DIR/.context.md" ]; then
  pass ".context.md exists"
else
  fail ".context.md missing"
fi

if [ -f "$FRAMEWORK_DIR/docs/FEATURE-MAP.md" ]; then
  pass "docs/FEATURE-MAP.md exists"
else
  fail "docs/FEATURE-MAP.md missing"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# TEST 7: MCP Config
# ═══════════════════════════════════════════════════════════════════════════
echo "── Test 7: MCP Config ──"

if [ -f "$AGENTS_DIR/mcp/server.json" ]; then
  pass "MCP server.json exists"

  # Validate JSON syntax
  if command -v jq &> /dev/null; then
    if jq empty "$AGENTS_DIR/mcp/server.json" 2>/dev/null; then
      pass "server.json is valid JSON"
    else
      fail "server.json has invalid JSON syntax"
    fi
  else
    warn "jq not available — skipping JSON validation"
  fi
else
  warn "MCP server.json not found"
fi

if [ -f "$AGENTS_DIR/mcp/setup.md" ]; then
  pass "MCP setup.md exists"
else
  warn "MCP setup.md not found"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# TEST 8: Canvas Templates
# ═══════════════════════════════════════════════════════════════════════════
echo "── Test 8: Canvas Templates ──"

for canvas in persona-flow memory-map; do
  CFILE="$AGENTS_DIR/vault/canvas/$canvas.canvas"
  if [ -f "$CFILE" ]; then
    # Validate JSON
    if command -v jq &> /dev/null; then
      if jq empty "$CFILE" 2>/dev/null; then
        pass "$canvas.canvas valid JSON"
      else
        fail "$canvas.canvas invalid JSON"
      fi
    else
      pass "$canvas.canvas exists"
    fi
  else
    warn "Canvas template missing: $canvas.canvas"
  fi
done
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# TEST 8.5: CI Workflow
# ═══════════════════════════════════════════════════════════════════════════
echo "── Test 8.5: CI Workflow ──"

CI_FILE="$FRAMEWORK_DIR/.github/workflows/validate-framework.yml"
if [ -f "$CI_FILE" ]; then
  pass "CI workflow exists"
  # Check for required steps
  if grep -q "test-framework.sh" "$CI_FILE" 2>/dev/null; then
    pass "CI workflow runs test-framework.sh"
  else
    warn "CI workflow missing test-framework.sh step"
  fi
  if grep -q "install.sh" "$CI_FILE" 2>/dev/null; then
    pass "CI workflow runs install check"
  else
    warn "CI workflow missing install check step"
  fi
else
  warn "CI workflow not found (.github/workflows/validate-framework.yml)"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# TEST 9: Documentation
# ═══════════════════════════════════════════════════════════════════════════
echo "── Test 9: Documentation ──"

DOCS=(TUTORIAL.md TROUBLESHOOTING.md PLUGIN-REGISTRY.md CLAUDE-EXAMPLES.md FEATURE-MAP.md)
for doc in "${DOCS[@]}"; do
  if [ -f "$FRAMEWORK_DIR/docs/$doc" ]; then
    pass "docs/$doc exists"
  else
    warn "docs/$doc not found"
  fi
done
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# TEST 10: Tools Available
# ═══════════════════════════════════════════════════════════════════════════
echo "── Test 10: External Tools ──"

for tool in python3 jq git; do
  if command -v "$tool" &> /dev/null; then
    pass "$tool available"
  else
    warn "$tool not found (some features may not work)"
  fi
done
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# TEST 11: Identity Blinding (grep-gate — padrão edge-of-chaos
# test_identity_blinding: o genótipo não carrega literais de um install)
# ═══════════════════════════════════════════════════════════════════════════
echo "── Test 11: Identity Blinding ──"

# 11a. Literais banidos em superfícies distribuíveis (hooks, tools, templates,
# install.sh). O CLAUDE.md do próprio repo é fenótipo — fica de fora.
BANNED_LITERALS=("rodrigooliveira" "/Users/rodrigo")
BLINDING_SURFACES=("$FRAMEWORK_DIR/install.sh")
while IFS= read -r f; do BLINDING_SURFACES+=("$f"); done < <(
  find "$AGENTS_DIR/hooks" "$AGENTS_DIR/tools" "$AGENTS_DIR/templates" \
    -type f \( -name '*.sh' -o -name '*.js' -o -name '*.py' -o -name '*.md' -o -name '*.json' \) 2>/dev/null
)
for literal in "${BANNED_LITERALS[@]}"; do
  HITS=$(grep -l "$literal" "${BLINDING_SURFACES[@]}" 2>/dev/null || true)
  if [ -z "$HITS" ]; then
    pass "banned literal ausente das superfícies distribuíveis: $literal"
  else
    fail "literal de identidade '$literal' em: $(echo "$HITS" | tr '\n' ' ')"
  fi
done

# 11b. install.sh não pode semear project-slug do próprio canuto em templates
# (poluição de slug — follow-up #1 da auditoria 2026-04-17)
if grep -q "project-slug: canuto-framework-v1" "$FRAMEWORK_DIR/install.sh" 2>/dev/null; then
  fail "install.sh contém 'project-slug: canuto-framework-v1' (poluição de template)"
else
  pass "install.sh não semeia o slug do canuto em templates"
fi
if grep -A3 'if \[ ! -f "\$CLAUDE_MD" \]' "$FRAMEWORK_DIR/install.sh" | grep -q 'download "CLAUDE.md"'; then
  fail "merge_claude_md volta a baixar o CLAUDE.md do repo canuto (regressão de poluição)"
else
  pass "merge_claude_md gera template limpo (não baixa CLAUDE.md do canuto)"
fi

# 11c. Sync de distribuição: todo skill ativo no repo precisa estar em
# FRAMEWORK_FILES/INSTALL_ONLY_FILES (o drift de 30 arquivos de 2026-07 não volta)
SHIPPED_LIST=$(awk '/^FRAMEWORK_FILES=\(/,/^\)/' "$FRAMEWORK_DIR/install.sh"; \
               awk '/^INSTALL_ONLY_FILES=\(/,/^\)/' "$FRAMEWORK_DIR/install.sh")
UNSHIPPED=()
while IFS= read -r skill_file; do
  rel="${skill_file#"$FRAMEWORK_DIR"/}"
  base=$(basename "$rel")
  # CLAUDE.md dentro de skills são cache do claude-mem, não distribuíveis
  [ "$base" = "CLAUDE.md" ] && continue
  if ! printf '%s' "$SHIPPED_LIST" | grep -qF "\"$rel\""; then
    UNSHIPPED+=("$rel")
  fi
done < <(find "$AGENTS_DIR/skills" -name '*.md' -not -path '*/_archive/*' 2>/dev/null)
if [ ${#UNSHIPPED[@]} -eq 0 ]; then
  pass "todos os skills ativos estão na lista de distribuição do install.sh"
else
  fail "skills no repo mas fora de FRAMEWORK_FILES: ${UNSHIPPED[*]:0:5} (${#UNSHIPPED[@]} total)"
fi

# 11d. Toda entrada de FRAMEWORK_FILES existe no repo (lista não aponta pro vazio)
MISSING_ENTRIES=()
while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  [ -e "$FRAMEWORK_DIR/$entry" ] || MISSING_ENTRIES+=("$entry")
done < <(printf '%s\n' "$SHIPPED_LIST" | grep -o '"[^"]*"' | tr -d '"')
if [ ${#MISSING_ENTRIES[@]} -eq 0 ]; then
  pass "todas as entradas de FRAMEWORK_FILES/INSTALL_ONLY_FILES existem no repo"
else
  fail "entradas de distribuição sem arquivo: ${MISSING_ENTRIES[*]:0:5}"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
echo "── Test 12: Contrato Codex-side (runtime-agnóstico) ──"
# Paridade dos gates fora do Claude Code: git pre-push + wrapper com eventos.
# Validação funcional completa: scratchpad/validate-codex-side.sh (15 checks,
# 2026-07-27). Aqui, o wiring que não pode regredir.

# 12a. git-pre-push-gate existe, é executável e lê o protocolo do pre-push
GATE_HOOK="$AGENTS_DIR/hooks/git-pre-push-gate.sh"
if [ -x "$GATE_HOOK" ] && grep -q "remote_ref remote_sha" "$GATE_HOOK"; then
  pass "git-pre-push-gate.sh presente, executável, lê protocolo do git"
else
  fail "git-pre-push-gate.sh ausente/não-executável/sem protocolo stdin"
fi

# 12b. Os dois instaladores geram o shim (marker canuto:git-pre-push-gate)
if grep -q "canuto:git-pre-push-gate" "$FRAMEWORK_DIR/install.sh" \
  && grep -q "canuto:git-pre-push-gate" "$AGENTS_DIR/hooks/install.sh"; then
  pass "shim pre-push gerado por install.sh E hooks/install.sh"
else
  fail "instalação do shim pre-push ausente em um dos instaladores"
fi

# 12c. Escapes registrados e independentes (allow-main não pula gate de testes)
if grep -q "CANUTO_ALLOW_MAIN_PUSH" "$GATE_HOOK" && grep -q "CANUTO_SKIP_PR_GATE" "$GATE_HOOK" \
  && grep -q 'verdict=skipped' "$GATE_HOOK"; then
  pass "escapes do pre-push existem e registram GATE skipped no event log"
else
  fail "escapes do pre-push sem registro no event log"
fi

# 12d. codex-maestro.sh: eventos mecânicos + gate de CLOSEOUT + sem exec
CM="$AGENTS_DIR/tools/codex-maestro.sh"
if grep -q "SESSION_START" "$CM" && grep -q "trap _canuto_codex_session_end EXIT" "$CM" \
  && grep -q "CLOSEOUT" "$CM" && ! grep -q "^exec codex" "$CM"; then
  pass "codex-maestro.sh registra SESSION_START/END e cobra CLOSEOUT via trap"
else
  fail "codex-maestro.sh sem eventos mecânicos/trap de CLOSEOUT"
fi

# 12e. require-tests-for-pr parametriza a costura (via=mcp|gh-cli|pre-push)
if grep -q "CANUTO_GATE_VIA" "$AGENTS_DIR/hooks/require-tests-for-pr.sh"; then
  pass "require-tests-for-pr.sh declara a costura via CANUTO_GATE_VIA"
else
  fail "require-tests-for-pr.sh sem CANUTO_GATE_VIA"
fi

# 12f. AGENTS.md carrega o contrato para sessões Codex
if grep -q "Contrato de Eventos e Gates" "$FRAMEWORK_DIR/AGENTS.md"; then
  pass "AGENTS.md tem a seção 'Contrato de Eventos e Gates'"
else
  fail "AGENTS.md sem a seção do contrato Codex-side"
fi

# 12g. install.sh não cria blocos [profiles.*] mortos em máquina limpa
if grep -q "Bloco ausente: NÃO criar" "$FRAMEWORK_DIR/install.sh"; then
  pass "install.sh não semeia [profiles.*] morto em config.toml limpo"
else
  fail "install.sh voltou a criar blocos [profiles.*] mortos"
fi

# 12h. Wrapper canônico de delegação: template versionado + install-if-missing
DELEGATE="$AGENTS_DIR/tools/codex-delegate.sh"
if [ -x "$DELEGATE" ] && grep -q "template versionado" "$DELEGATE" \
  && grep -q 'codex-delegate.sh.*bin/codex-delegate.sh' "$FRAMEWORK_DIR/install.sh"; then
  pass "codex-delegate.sh: template versionado + instalado quando ausente"
else
  fail "codex-delegate.sh sem template versionado ou sem wiring no install.sh"
fi

# 12i. O parser do wrapper casa TODOS os roles do models.yaml (regressão do
# formato flow-style — a mesma que deixou 211 delegações no default errado)
BROKEN_ROLES=()
for r in coder reviewer architect maestro fast; do
  grep -Eq "^[[:space:]]{2}${r}:[[:space:]]*\{" "$AGENTS_DIR/config/models.yaml" || BROKEN_ROLES+=("$r")
done
if [ ${#BROKEN_ROLES[@]} -eq 0 ]; then
  pass "models.yaml flow-style parseável para os 5 roles"
else
  fail "models.yaml não parseável para: ${BROKEN_ROLES[*]} (block-style volta a ser decorativo)"
fi

# 12j. postdelegate-verify não dispara em bash -n/cp/chmod do arquivo do wrapper
if grep -q '""|-\*)' "$AGENTS_DIR/hooks/postdelegate-verify.sh" 2>/dev/null \
  || grep -q '"")\|-\*)' "$AGENTS_DIR/hooks/postdelegate-verify.sh" 2>/dev/null; then
  pass "postdelegate-verify ignora toques no arquivo do wrapper (out-file vazio ou -*)"
else
  fail "postdelegate-verify sem guarda de falso positivo (bash -n vira 'delegação')"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
echo "── Test 13: Hooks não bloqueiam em stdin de TTY ──"
# CLAUDE.md manda testar todo script com TTY e com stdin piped, mas nada
# verificava isso mecanicamente. O custo do esquecimento é caro e mudo: um hook
# que lê stdin sem guarda fica preso PARA SEMPRE quando stdin é um terminal, e o
# runtime que espera o hook trava junto — sem log, sem erro, com cara de
# deadlock. Foi o que segurava a abertura do Codex CLI.
#
# A checagem é ESTÁTICA de propósito. A versão que executava cada hook num pty
# real achou o bug, mas se auto-envenena: require-tests-for-pr.sh roda
# test-framework.sh, que rodaria o probe, que rodaria o gate de novo — recursão
# infinita. O probe dinâmico vive separado em .agents/tests/tty-block-probe.sh.
if command -v python3 >/dev/null 2>&1; then
  TTY_UNGUARDED=$(python3 - "$AGENTS_DIR/hooks" <<'PYEOF'
import os, re, sys, glob

# Construções que consomem stdin quando nenhuma origem é dada:
#   $(cat) / $(cat 2>/dev/null)  — sem nome de arquivo
#   =$(jq ...)                   — jq sem operando de arquivo também lê stdin
#   while [IFS=] read ... done   — SÓ quando o `done` não traz redirecionamento
CAT_RX = re.compile(r'\$\(\s*cat\s*(?:2>[^\s)]+\s*)*(?:\|\|[^)]*)?\)')
JQ_RX  = re.compile(r'=\$\(\s*jq\b(?![^)]*\$[A-Za-z_])[^)]*\)')
WHILE_RX = re.compile(r'^\s*while\b.*\bread\b')
OPEN_RX  = re.compile(r'(^|\s|;)do\s*$')
DONE_RX  = re.compile(r'^\s*done\b')

def unredirected_while(lines):
    """Laço while-read cujo `done` não é alimentado por `< arquivo` ou `< <(...)`."""
    for i, line in enumerate(lines):
        if not WHILE_RX.search(line):
            continue
        depth = 0
        for j in range(i, len(lines)):
            if OPEN_RX.search(lines[j]):
                depth += 1
            if DONE_RX.search(lines[j]):
                depth -= 1
                if depth <= 0:
                    if "<" not in lines[j]:
                        return True
                    break
    return False

bad = []
for hook in sorted(glob.glob(os.path.join(sys.argv[1], "*.sh"))):
    name = os.path.basename(hook)
    if name == "install.sh":
        continue  # instalador, não hook de runtime
    text = open(hook, encoding="utf-8", errors="replace").read()
    if "-t 0" in text:
        continue
    if CAT_RX.search(text) or JQ_RX.search(text) or unredirected_while(text.splitlines()):
        bad.append(name)
print(" ".join(bad))
PYEOF
  )
  if [ -z "$TTY_UNGUARDED" ]; then
    pass "todo hook que lê stdin tem guarda de TTY"
  else
    fail "hooks leem stdin sem guarda '-t 0' (travam em TTY): $TTY_UNGUARDED"
  fi
else
  warn "python3 ausente — checagem de guarda de TTY pulada"
fi

# 13b. Timeout precisa existir de fato onde um filho pode travar.
# macOS não traz GNU `timeout`; sem o ramo gtimeout o limite vira decorativo.
for TIMEOUT_USER in "$AGENTS_DIR/tools/codex-common.sh" "$AGENTS_DIR/tools/heartbeat-run.sh"; do
  if [ -f "$TIMEOUT_USER" ]; then
    if grep -q "gtimeout" "$TIMEOUT_USER"; then
      pass "$(basename "$TIMEOUT_USER"): tem fallback gtimeout (macOS)"
    else
      fail "$(basename "$TIMEOUT_USER"): usa timeout sem fallback gtimeout — vira no-op no macOS"
    fi
  fi
done

# 13c. O health check do session-start precisa MATAR o filho no estouro.
# A versão antiga usava `alarm` do perl e só saía do pai: o filho seguia vivo e
# o close do pipe esperava por ele — 4s prometidos, 30s medidos.
SS_HOOK="$AGENTS_DIR/hooks/session-start.sh"
if [ -f "$SS_HOOK" ]; then
  if grep -q 'kill("KILL", -\$pid)' "$SS_HOOK" || ! grep -q 'alarm' "$SS_HOOK"; then
    pass "session-start.sh: timeout do health check mata o filho"
  else
    fail "session-start.sh: alarm sem kill — timeout decorativo, não limita nada"
  fi
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
echo "── Test 14: Servidor MCP declara a própria dependência, com teto ──"
# Em 2026-07-29 os dois MCPs de back-delegation pararam de subir. Ninguém tinha
# tocado neles. O launcher era `uvx --from codex-as-mcp python claude-agent-mcp.py`
# — usávamos o virtualenv de um pacote de terceiro só para ter o `mcp` no path,
# sem consumir uma linha do código dele. O pedido do codex-as-mcp é
# `mcp[cli]>=1.12.4`, SEM TETO. O `mcp` 2.0.0 saiu, o resolvedor pegou, e o
# 2.0.0 removeu `mcp.server.fastmcp`. Import morria, processo saía com rc=1
# antes do `initialize`, e o Codex dizia "connection closed: initialize
# response" — mensagem que não aponta para lugar nenhum.
#
# Duas regras, verificadas estaticamente (sem rede):
MCP_PY="$AGENTS_DIR/tools/claude-agent-mcp.py"
if [ ! -f "$MCP_PY" ]; then
  warn "claude-agent-mcp.py ausente — checagem de dependência pulada"
elif ! command -v python3 >/dev/null 2>&1; then
  warn "python3 ausente — checagem de dependência do MCP pulada"
else
  # 14a. A dependência é declarada no próprio script e tem limite superior.
  DEP_VERDICT=$(python3 - "$MCP_PY" <<'PYEOF'
import re, sys

text = open(sys.argv[1], encoding="utf-8", errors="replace").read()
m = re.search(r"^# /// script\s*$(.*?)^# ///\s*$", text, re.M | re.S)
if not m:
    print("SEM_HEADER")
    raise SystemExit

body = "\n".join(l.lstrip("#").strip() for l in m.group(1).splitlines())
open_at = re.search(r"dependencies\s*=\s*\[", body, re.S)
if not open_at:
    print("SEM_DEPS")
    raise SystemExit

# Varredura ciente de aspas para achar o `]` que fecha. Regex não-guloso não
# serve: `"mcp[cli]>=1.12.4,<2"` tem um `]` DENTRO da string e o match parava
# ali, devolvendo `"mcp[cli` — sem aspa de fechamento, zero specs, e o teste
# acusava "dependência ausente" num arquivo que a declara certinho.
i, depth, quote = open_at.end(), 1, None
while i < len(body) and depth:
    c = body[i]
    if quote:
        if c == quote:
            quote = None
    elif c in "\"'":
        quote = c
    elif c == "[":
        depth += 1
    elif c == "]":
        depth -= 1
    i += 1
if depth:
    print("DEPS_ABERTO")
    raise SystemExit

specs = re.findall(r"[\"']([^\"']+)[\"']", body[open_at.end():i - 1])
mcp_spec = next((s for s in specs if re.match(r"^mcp\b", s)), None)
if not mcp_spec:
    print("SEM_MCP")
elif not re.search(r"[<!]|==", mcp_spec):
    # >= sozinho é o defeito: deixa o próximo major entrar sozinho.
    print("SEM_TETO:" + mcp_spec)
else:
    print("OK:" + mcp_spec)
PYEOF
  )
  case "$DEP_VERDICT" in
    OK:*)        pass "claude-agent-mcp.py declara mcp com teto (${DEP_VERDICT#OK:})" ;;
    SEM_TETO:*)  fail "claude-agent-mcp.py pede '${DEP_VERDICT#SEM_TETO:}' sem teto — o próximo major entra sozinho e quebra o import" ;;
    SEM_HEADER)  fail "claude-agent-mcp.py sem cabeçalho PEP 723 — a dependência não está declarada em lugar nenhum" ;;
    *)           fail "claude-agent-mcp.py: não achei a dependência 'mcp' declarada ($DEP_VERDICT)" ;;
  esac

  # 14b. Nenhum wrapper pode emprestar o virtualenv de um pacote de terceiro.
  BORROWED=""
  for W in "$AGENTS_DIR/tools/claude-architect.sh" "$AGENTS_DIR/tools/claude-reviewer.sh"; do
    [ -f "$W" ] || continue
    if grep -qE 'uvx[[:space:]].*--from[[:space:]]+[^[:space:]]+[[:space:]]+python' "$W"; then
      BORROWED="$BORROWED $(basename "$W")"
    fi
  done
  if [ -z "$BORROWED" ]; then
    pass "wrappers MCP não dependem do virtualenv de terceiros"
  else
    fail "wrapper roda 'uvx --from <pacote> python' — herda o calendário de releases de terceiro:$BORROWED"
  fi

  # 14c. O venv é otimização; não pode ser ponto único de falha.
  # Os wrappers preferem o python do venv fixo porque ele tira ~1,1s de `uv` do
  # arranque de cada servidor (medido num MacBook Air). Mas venv some: disco
  # cheio, `rm -rf` distraído, upgrade de Python que invalida o venv. Sem a
  # linha de reserva, qualquer um desses derruba a back-delegation inteira em
  # vez de só deixá-la lenta — trocar disponibilidade por 1,1s é péssimo negócio.
  # Comentário não é reserva. Estes wrappers EXPLICAM a reserva em prosa, então
  # grep no arquivo inteiro passa mesmo com a linha executável removida — foi o
  # que aconteceu na primeira versão desta checagem. Só linha de código conta.
  NO_FALLBACK=""
  for W in "$AGENTS_DIR/tools/claude-architect.sh" "$AGENTS_DIR/tools/claude-reviewer.sh"; do
    [ -f "$W" ] || continue
    W_CODE=$(grep -vE '^[[:space:]]*#' "$W" || true)
    if printf '%s' "$W_CODE" | grep -q "mcp-venv" \
       && ! printf '%s' "$W_CODE" | grep -qE 'uv[[:space:]]+run[[:space:]]+--script'; then
      NO_FALLBACK="$NO_FALLBACK $(basename "$W")"
    fi
  done
  if [ -z "$NO_FALLBACK" ]; then
    pass "wrappers MCP degradam para 'uv run --script' se o venv sumir"
  else
    fail "wrapper depende só do venv, sem reserva — venv quebrado mata a back-delegation:$NO_FALLBACK"
  fi
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# SUMMARY
# ═══════════════════════════════════════════════════════════════════════════
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Results: ✅ $PASS passed, ❌ $FAIL failed, ⚠️  $WARN warnings"
echo ""

if [ $FAIL -eq 0 ]; then
  if [ $WARN -eq 0 ]; then
    echo "  Verdict: HEALTHY"
  else
    echo "  Verdict: DEGRADED ($WARN warnings)"
  fi
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 0
else
  echo "  Verdict: BROKEN ($FAIL failures)"
  echo ""
  echo "  Failures:"
  for err in "${ERRORS[@]}"; do
    echo "    - $err"
  done
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit 1
fi
