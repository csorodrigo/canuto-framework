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

REQUIRED_PERSONAS=(maestro architect coder tester debugger reviewer contextualizer)
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
  plugin-system
  vault-maintenance
  research
  headless-validation
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

HOOKS=(session-load session-save pre-compact-save check-references check-orphans plan-review codex-pretool-guard)
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

CODEX_TOOLS=(codex-common codex-diff-context codex-context-package codex-health-check canuto-consumer-smoke)
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

if bash "$AGENTS_DIR/tools/codex-health-check.sh" --json >/tmp/codex-health-json.$$ 2>/dev/null; then
  if command -v jq >/dev/null 2>&1 && jq -e '.tool == "codex-health-check" and .verdict' /tmp/codex-health-json.$$ >/dev/null 2>&1; then
    pass "codex-health-check.sh JSON output"
  else
    fail "codex-health-check.sh JSON output invalid"
  fi
else
  fail "codex-health-check.sh --json failed"
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
