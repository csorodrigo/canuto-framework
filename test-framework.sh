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

# Git exporta variaveis locais do repositorio para hooks. Sem limpa-las, os
# repositorios temporarios desta suite continuam apontando para o checkout que
# disparou o pre-push, mesmo quando os comandos usam `git -C <fixture>`. O
# framework continua referenciado por caminhos absolutos; fixtures devem
# descobrir o proprio repositorio.
if ! git_local_vars=$(git -C "$FRAMEWORK_DIR" rev-parse --local-env-vars 2>/dev/null); then
  echo "FATAL: nao foi possivel enumerar as variaveis locais do Git; fixtures nao executadas." >&2
  exit 2
fi
if ! grep -qx 'GIT_DIR' <<< "$git_local_vars" \
  || ! grep -qx 'GIT_WORK_TREE' <<< "$git_local_vars"; then
  echo "FATAL: lista de variaveis locais do Git incompleta; fixtures nao executadas." >&2
  exit 2
fi
while IFS= read -r git_local_var; do
  [ -n "$git_local_var" ] && unset "$git_local_var"
done <<< "$git_local_vars"
unset git_local_vars git_local_var

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

echo "── Test 3c: Federated Skill Gardener ──"

SKILL_GARDENER_DIR="$FRAMEWORK_DIR/skill-gardener"
for gardener_file in canuto-skill-gardener.js canuto-skill-gardener-lib.js canuto-skill-gardener.test.js; do
  if [ ! -f "$SKILL_GARDENER_DIR/$gardener_file" ]; then
    fail "Skill gardener file missing: $gardener_file"
  elif node --check "$SKILL_GARDENER_DIR/$gardener_file" >/dev/null 2>&1; then
    pass "skill gardener $gardener_file syntax valid"
  else
    fail "skill gardener $gardener_file has syntax errors"
  fi
done

SG_TEST_HOME="$(mktemp -d)"
SG_TEST_CRONTAB="$(mktemp)"
if HOME="$SG_TEST_HOME" CANUTO_INSTALL_TEST_ISOLATED_HOME="$SG_TEST_HOME" \
  CANUTO_SKILL_GARDENER_SOURCE_DIR="$SKILL_GARDENER_DIR" \
  CANUTO_SKILL_GARDENER_CONFIG_SOURCE="$FRAMEWORK_DIR/config/skill-gardener.json" \
  CANUTO_SKILL_GARDENER_CONFIG="$FRAMEWORK_DIR/config/skill-gardener.json" \
  CANUTO_SKILL_GARDENER_CRONTAB_FILE="$SG_TEST_CRONTAB" \
  node --test "$SKILL_GARDENER_DIR/canuto-skill-gardener.test.js" >/tmp/canuto-skill-gardener-test.$$ 2>&1; then
  pass "canuto-skill-gardener focused tests"
else
  fail "canuto-skill-gardener focused tests failed"
fi
rm -f /tmp/canuto-skill-gardener-test.$$
rm -rf "$SG_TEST_HOME"
rm -f "$SG_TEST_CRONTAB"

SG_HELP_HOME="$(mktemp -d)"
SG_HELP_CRONTAB="$(mktemp)"
if HOME="$SG_HELP_HOME" CANUTO_INSTALL_TEST_ISOLATED_HOME="$SG_HELP_HOME" \
  CANUTO_SKILL_GARDENER_SOURCE_DIR="$SKILL_GARDENER_DIR" \
  CANUTO_SKILL_GARDENER_CONFIG_SOURCE="$FRAMEWORK_DIR/config/skill-gardener.json" \
  CANUTO_SKILL_GARDENER_CONFIG="$FRAMEWORK_DIR/config/skill-gardener.json" \
  CANUTO_SKILL_GARDENER_CRONTAB_FILE="$SG_HELP_CRONTAB" \
  node "$SKILL_GARDENER_DIR/canuto-skill-gardener.js" --help >/dev/null 2>&1; then
  pass "canuto-skill-gardener CLI help"
else
  fail "canuto-skill-gardener CLI help failed"
fi
rm -rf "$SG_HELP_HOME"
rm -f "$SG_HELP_CRONTAB"

if grep -qF 'skill-gardener/canuto-skill-gardener.js' "$FRAMEWORK_DIR/install.sh" \
  && grep -qF 'setup_skill_gardener' "$FRAMEWORK_DIR/install.sh"; then
  pass "install.sh wires skill gardener CLI/library"
else
  fail "install.sh does not wire skill gardener CLI/library"
fi

SG_HOME="$(mktemp -d)"
SG_STATUS_BEFORE="$(mktemp)"
SG_STATUS_AFTER="$(mktemp)"
SG_CRONTAB="$(mktemp)"
SG_CONFIG_BEFORE="$(mktemp)"
SG_SOURCE_DIR="$FRAMEWORK_DIR/skill-gardener"
SG_CONFIG_SOURCE="$FRAMEWORK_DIR/config/skill-gardener.json"
git -C "$FRAMEWORK_DIR" status --porcelain --untracked-files=all > "$SG_STATUS_BEFORE" 2>/dev/null || true
if (
  cd "$FRAMEWORK_DIR"
  export HOME="$SG_HOME" CANUTO_INSTALL_LIBRARY_ONLY=1 \
    CANUTO_SKILL_GARDENER_SOURCE_DIR="$SG_SOURCE_DIR" \
    CANUTO_SKILL_GARDENER_CONFIG_SOURCE="$SG_CONFIG_SOURCE" \
    CANUTO_SKILL_GARDENER_CONFIG="$SG_CONFIG_SOURCE" \
    CANUTO_SKILL_GARDENER_CRONTAB_FILE="$SG_CRONTAB"
  source "$FRAMEWORK_DIR/install.sh"
  mkdir -p "$HOME/.claude/skills/skill-gardener"
  cp "$FRAMEWORK_DIR/global-skills/skill-gardener/SKILL.md" "$HOME/.claude/skills/skill-gardener/SKILL.md"
  setup_skill_gardener
) >/dev/null 2>&1 \
  && [ -L "$SG_HOME/.canuto/bin/canuto-skill-gardener" ] \
  && [ -x "$SG_HOME/.canuto/bin/canuto-skill-gardener" ] \
  && SG_TARGET="$(node -e 'process.stdout.write(require("node:fs").realpathSync(process.argv[1]))' "$SG_HOME/.canuto/bin/canuto-skill-gardener")" \
  && printf '%s\n' "$SG_TARGET" | grep -qE '/\.canuto/lib/skill-gardener/releases/[0-9a-f]{64}/canuto-skill-gardener\.js$' \
  && [ -f "$(dirname "$SG_TARGET")/canuto-skill-gardener-lib.js" ] \
  && node -e 'const fs=require("node:fs"); const crypto=require("node:crypto"); const [sourceCli,targetCli,sourceLib,targetLib]=process.argv.slice(1); const hash=(file)=>crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex"); if(hash(sourceCli)!==hash(targetCli)||hash(sourceLib)!==hash(targetLib))process.exit(1)' \
    "$SG_SOURCE_DIR/canuto-skill-gardener.js" "$SG_TARGET" "$SG_SOURCE_DIR/canuto-skill-gardener-lib.js" "$(dirname "$SG_TARGET")/canuto-skill-gardener-lib.js" \
  && [ -f "$SG_HOME/.canuto/config/skill-gardener.json" ] \
  && [ -d "$SG_HOME/.canuto/logs" ] \
  && [ -f "$SG_HOME/.claude/skills/skill-gardener/SKILL.md" ]; then
  pass "skill gardener fresh install stages runtime, config, logs and companion skill"
else
  fail "skill gardener fresh install is incomplete"
fi
mkdir -p "$SG_HOME/.canuto/config"
node - "$SG_CONFIG_SOURCE" "$SG_HOME/.canuto/config/skill-gardener.json" <<'NODE'
const fs = require('node:fs');
const [source, target] = process.argv.slice(2);
const config = JSON.parse(fs.readFileSync(source, 'utf8'));
config.policy.detailRetentionDays += 1;
fs.writeFileSync(target, `${JSON.stringify(config, null, 2)}\n`);
NODE
cp "$SG_HOME/.canuto/config/skill-gardener.json" "$SG_CONFIG_BEFORE"
if (
  cd "$FRAMEWORK_DIR"
  export HOME="$SG_HOME" CANUTO_INSTALL_LIBRARY_ONLY=1 \
    CANUTO_SKILL_GARDENER_SOURCE_DIR="$SG_SOURCE_DIR" \
    CANUTO_SKILL_GARDENER_CONFIG_SOURCE="$SG_CONFIG_SOURCE" \
    CANUTO_SKILL_GARDENER_CONFIG="$SG_CONFIG_SOURCE" \
    CANUTO_SKILL_GARDENER_CRONTAB_FILE="$SG_CRONTAB"
  source "$FRAMEWORK_DIR/install.sh"
  setup_skill_gardener
) >/dev/null 2>&1 \
  && ! cmp -s "$SG_CONFIG_SOURCE" "$SG_CONFIG_BEFORE" \
  && cmp -s "$SG_HOME/.canuto/config/skill-gardener.json" "$SG_CONFIG_BEFORE"; then
  pass "skill gardener update preserves existing config"
else
  fail "skill gardener update overwrote existing config"
fi
git -C "$FRAMEWORK_DIR" status --porcelain --untracked-files=all > "$SG_STATUS_AFTER" 2>/dev/null || true
if cmp -s "$SG_STATUS_BEFORE" "$SG_STATUS_AFTER"; then
  pass "skill gardener install does not pollute the framework checkout"
else
  fail "skill gardener install changed the framework checkout"
fi
rm -f "$SG_STATUS_BEFORE" "$SG_STATUS_AFTER"

echo "── Test 3d: Resumable Skill Refactor ──"

SKILL_REFACTOR_DIR="$FRAMEWORK_DIR/skill-refactor"
for refactor_file in canuto-skill-refactor.js canuto-skill-refactor-lib.js canuto-skill-refactor.test.js; do
  if [ ! -f "$SKILL_REFACTOR_DIR/$refactor_file" ]; then
    fail "skill refactor file missing: $refactor_file"
  elif node --check "$SKILL_REFACTOR_DIR/$refactor_file" >/dev/null 2>&1; then
    pass "skill refactor $refactor_file syntax valid"
  else
    fail "skill refactor $refactor_file has syntax errors"
  fi
done
if [ -x "$SKILL_REFACTOR_DIR/canuto-skill-refactor.js" ]; then
  pass "skill refactor CLI source is executable"
else
  fail "skill refactor CLI source is not executable"
fi

if node --test "$SKILL_REFACTOR_DIR/canuto-skill-refactor.test.js" >/tmp/canuto-skill-refactor-test.$$ 2>&1; then
  pass "canuto-skill-refactor focused tests"
else
  fail "canuto-skill-refactor focused tests failed"
fi
rm -f /tmp/canuto-skill-refactor-test.$$

SR_HOME="$(mktemp -d)"
SR_CRONTAB="$(mktemp)"
if (
  cd "$FRAMEWORK_DIR"
  export HOME="$SR_HOME" CANUTO_INSTALL_LIBRARY_ONLY=1 \
    CANUTO_SKILL_GARDENER_SOURCE_DIR="$FRAMEWORK_DIR/skill-gardener" \
    CANUTO_SKILL_GARDENER_CONFIG_SOURCE="$FRAMEWORK_DIR/config/skill-gardener.json" \
    CANUTO_SKILL_GARDENER_CONFIG="$SR_HOME/.canuto/config/skill-gardener.json" \
    CANUTO_SKILL_GARDENER_CRONTAB_FILE="$SR_CRONTAB" \
    CANUTO_SKILL_REFACTOR_SOURCE_DIR="$SKILL_REFACTOR_DIR" \
    CANUTO_SKILL_REFACTOR_GARDENER_SOURCE_DIR="$FRAMEWORK_DIR/skill-gardener"
  source "$FRAMEWORK_DIR/install.sh"
  setup_global_skills
  setup_skill_gardener
  setup_skill_refactor
) >/dev/null 2>&1 \
  && [ -L "$SR_HOME/.canuto/bin/canuto-skill-refactor" ] \
  && [ -x "$SR_HOME/.canuto/bin/canuto-skill-refactor" ] \
  && SR_TARGET="$(node -e 'process.stdout.write(require("node:fs").realpathSync(process.argv[1]))' "$SR_HOME/.canuto/bin/canuto-skill-refactor")" \
  && printf '%s\n' "$SR_TARGET" | grep -qE '/\.canuto/lib/skill-refactor/releases/[0-9a-f]{64}/skill-refactor/canuto-skill-refactor\.js$' \
  && [ -f "$(dirname "$SR_TARGET")/canuto-skill-refactor-lib.js" ] \
  && [ -f "$(dirname "$(dirname "$SR_TARGET")")/skill-gardener/canuto-skill-gardener-lib.js" ] \
  && [ -f "$SR_HOME/.claude/skills/skill-refactor/SKILL.md" ] \
  && [ -f "$SR_HOME/.claude/skills/skill-refactor/agents/openai.yaml" ] \
  && "$SR_HOME/.canuto/bin/canuto-skill-refactor" --help >/dev/null 2>&1 \
  && grep -qF '"skill-refactor"' "$FRAMEWORK_DIR/install.sh"; then
  pass "skill refactor immutable runtime and companion skill are installable"
else
  fail "skill refactor install is incomplete"
fi
rm -rf "$SR_HOME"
rm -f "$SR_CRONTAB"

SR_FAIL_HOME="$(mktemp -d)"
mkdir -p "$SR_FAIL_HOME/.claude/skills/skill-refactor"
: > "$SR_FAIL_HOME/.claude/skills/skill-refactor/agents"
if (
  cd "$FRAMEWORK_DIR"
  export HOME="$SR_FAIL_HOME" CANUTO_INSTALL_LIBRARY_ONLY=1
  source "$FRAMEWORK_DIR/install.sh"
  setup_global_skills
) >/dev/null 2>&1; then
  fail "skill refactor companion skill failure was silently accepted"
else
  pass "skill refactor companion skill failure propagates"
fi
rm -rf "$SR_FAIL_HOME"
if grep -qF 'setup_global_skills || global_skills_rc=50' "$FRAMEWORK_DIR/install.sh" \
  && grep -qF 'failure_mask=$((failure_mask | 8))' "$FRAMEWORK_DIR/install.sh"; then
  pass "repair_runtime propagates global skill installation failure"
else
  fail "repair_runtime ignores global skill installation failure"
fi

SG_CONSUMER="$(mktemp -d)"
git -C "$SG_CONSUMER" init -q
if (
  cd "$SG_CONSUMER"
  export HOME="$(mktemp -d)" CANUTO_INSTALL_LIBRARY_ONLY=1 \
    CANUTO_INSTALL_TEST_ISOLATED_HOME="$HOME" \
    CANUTO_SKILL_GARDENER_SOURCE_DIR="$FRAMEWORK_DIR/skill-gardener" \
    CANUTO_SKILL_GARDENER_CONFIG_SOURCE="$FRAMEWORK_DIR/config/skill-gardener.json" \
    CANUTO_SKILL_GARDENER_CONFIG="$FRAMEWORK_DIR/config/skill-gardener.json" \
    CANUTO_SKILL_GARDENER_CRONTAB_FILE="$SG_CONSUMER/crontab"
  source "$FRAMEWORK_DIR/install.sh"
  setup_skill_gardener
) >/dev/null 2>&1 \
  && [ ! -e "$SG_CONSUMER/skill-gardener" ] \
  && [ ! -e "$SG_CONSUMER/config" ] \
  && [ -z "$(git -C "$SG_CONSUMER" status --porcelain --untracked-files=all)" ]; then
  pass "consumer install uses runtime staging without checkout pollution"
else
  fail "consumer install polluted checkout or failed staging"
fi
rm -rf "$SG_HOME" "$SG_CONSUMER"
rm -f "$SG_CRONTAB" "$SG_CONFIG_BEFORE"

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
    'install|update|contract|check|skill|migrate|repair|doctor|test|deps)'
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

# 12f0. Contrato operacional único: distribuído, carregado pelos dois runtimes
# e verificado por conteúdo no --check.
if grep -qF '".agents/OPERATING-CONTRACT.md"' "$FRAMEWORK_DIR/install.sh" \
  && grep -qF '.agents/OPERATING-CONTRACT.md' "$FRAMEWORK_DIR/AGENTS.md" \
  && grep -qF '.agents/OPERATING-CONTRACT.md' "$FRAMEWORK_DIR/CLAUDE.md" \
  && grep -qF '^[[:space:]]{0,3}(```|~~~)' "$AGENTS_DIR/tools/canuto-consumer-smoke.sh" \
  && grep -qF 'content hash drift' "$FRAMEWORK_DIR/install.sh"; then
  pass "contrato operacional é distribuído, carregado por Claude/Codex e hash-checked"
else
  fail "contrato operacional sem distribuição, entrypoint ou check de conteúdo"
fi

# 12f0b. gates.env é configuração do consumidor: seed if missing, nunca
# artefato sobrescrito/hash-checked pelo framework.
framework_block=$(sed -n '/^FRAMEWORK_FILES=(/,/^)/p' "$FRAMEWORK_DIR/install.sh")
install_only_block=$(sed -n '/^INSTALL_ONLY_FILES=(/,/^)/p' "$FRAMEWORK_DIR/install.sh")
if ! printf '%s\n' "$framework_block" | grep -qF '".agents/config/gates.env"' \
  && printf '%s\n' "$install_only_block" | grep -qF '".agents/config/gates.env"'; then
  pass "gates.env pertence ao projeto: instalado se ausente e preservado em updates"
else
  fail "gates.env voltou a ser sobrescrito/hash-checked como arquivo do framework"
fi

# 12f0c. CODEX.md contem slug e regras renderizadas do consumidor. Comparar
# seu hash com o CODEX.md do framework cria drift imediatamente apos update;
# a fonte gerenciada e o template, enquanto o smoke valida o arquivo gerado.
if ! printf '%s\n' "$framework_block" | grep -qx '  "CODEX.md"' \
  && printf '%s\n' "$framework_block" | grep -qx '  ".agents/templates/CODEX.md"' \
  && grep -q '^render_codex_md() {' "$FRAMEWORK_DIR/install.sh"; then
  pass "CODEX.md renderizado nao e hash-checked contra outro projeto"
else
  fail "CODEX.md renderizado voltou ao inventario de arquivos canonicos"
fi

# 12f0d. Rollout mínimo: repos com `.agents/*` ignorado precisam versionar o
# contrato, sem que o instalador toque hooks, modelos, personas ou install.sh.
contract_only_tmp=$(mktemp -d)
mkdir -p "$contract_only_tmp/.agents/hooks"
cat > "$contract_only_tmp/.gitignore" <<'EOF'
.agents/*
/AGENTS.md
/CLAUDE.md
EOF
cat > "$contract_only_tmp/AGENTS.md" <<'EOF'
# Consumer Codex

Regra exclusiva do produto.
EOF
cat > "$contract_only_tmp/CLAUDE.md" <<'EOF'
# Consumer Claude

Regra exclusiva do produto.
EOF
cat > "$contract_only_tmp/.agents/hooks/product-gate.sh" <<'EOF'
#!/usr/bin/env bash
echo product-only
EOF
git -C "$contract_only_tmp" init -q
git -C "$contract_only_tmp" config user.name Canuto
git -C "$contract_only_tmp" config user.email canuto@example.invalid
git -C "$contract_only_tmp" add .gitignore
git -C "$contract_only_tmp" add -f .agents/hooks/product-gate.sh
git -C "$contract_only_tmp" commit -qm fixture
contract_hook_before=$(cksum < "$contract_only_tmp/.agents/hooks/product-gate.sh")

contract_only_ok=true
( cd "$contract_only_tmp" \
  && CANUTO_SOURCE_DIR="$FRAMEWORK_DIR" bash "$FRAMEWORK_DIR/install.sh" --contract-only --yes >/dev/null 2>&1 ) \
  || contract_only_ok=false
contract_first_head=$(git -C "$contract_only_tmp" rev-parse HEAD 2>/dev/null || true)
( cd "$contract_only_tmp" \
  && CANUTO_SOURCE_DIR="$FRAMEWORK_DIR" bash "$FRAMEWORK_DIR/install.sh" --contract-only --yes >/dev/null 2>&1 ) \
  || contract_only_ok=false
contract_second_head=$(git -C "$contract_only_tmp" rev-parse HEAD 2>/dev/null || true)
contract_names=$(git -C "$contract_only_tmp" diff-tree --no-commit-id --name-only -r "$contract_first_head" | sort)
contract_expected=$(printf '%s\n' .agents/OPERATING-CONTRACT.md AGENTS.md CLAUDE.md | sort)

if [ "$contract_only_ok" = true ] \
  && [ "$contract_first_head" = "$contract_second_head" ] \
  && [ "$contract_names" = "$contract_expected" ] \
  && git -C "$contract_only_tmp" ls-files --error-unmatch .agents/OPERATING-CONTRACT.md >/dev/null 2>&1 \
  && [ "$contract_hook_before" = "$(cksum < "$contract_only_tmp/.agents/hooks/product-gate.sh")" ] \
  && [ "$(grep -c 'Read `.agents/OPERATING-CONTRACT.md` before non-trivial work; it is the shared' "$contract_only_tmp/AGENTS.md")" = "1" ] \
  && [ "$(grep -c 'Read `.agents/OPERATING-CONTRACT.md` before non-trivial work; it is the shared' "$contract_only_tmp/CLAUDE.md")" = "1" ] \
  && [ -z "$(git -C "$contract_only_tmp" status --porcelain)" ]; then
  pass "--contract-only versiona contrato ignorado e preserva runtime do produto"
else
  fail "--contract-only alterou escopo, nao versionou contrato ou nao foi idempotente"
fi
rm -rf "$contract_only_tmp"

# Falha real de commit nao pode ser rotulada como idempotencia nem sair verde.
contract_fail_tmp=$(mktemp -d)
mkdir -p "$contract_fail_tmp/.hooks"
printf '# Consumer\n' > "$contract_fail_tmp/AGENTS.md"
printf '# Consumer\n' > "$contract_fail_tmp/CLAUDE.md"
cat > "$contract_fail_tmp/.hooks/pre-commit" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$contract_fail_tmp/.hooks/pre-commit"
git -C "$contract_fail_tmp" init -q
git -C "$contract_fail_tmp" config user.name Canuto
git -C "$contract_fail_tmp" config user.email canuto@example.invalid
git -C "$contract_fail_tmp" config core.hooksPath .hooks
git -C "$contract_fail_tmp" add .hooks/pre-commit AGENTS.md CLAUDE.md
git -C "$contract_fail_tmp" commit --no-verify -qm fixture
contract_fail_head=$(git -C "$contract_fail_tmp" rev-parse HEAD)
contract_fail_out=$(mktemp)
if ( cd "$contract_fail_tmp" \
  && CANUTO_SOURCE_DIR="$FRAMEWORK_DIR" bash "$FRAMEWORK_DIR/install.sh" --contract-only --yes ) >"$contract_fail_out" 2>&1; then
  fail "--contract-only saiu verde quando o pre-commit rejeitou o commit"
elif [ "$contract_fail_head" = "$(git -C "$contract_fail_tmp" rev-parse HEAD)" ] \
  && grep -q 'Git commit failed' "$contract_fail_out" \
  && ! grep -q 'already synchronized' "$contract_fail_out"; then
  pass "--contract-only distingue falha real de commit de idempotencia"
else
  fail "--contract-only mascarou ou descreveu incorretamente a falha de commit"
fi
rm -rf "$contract_fail_tmp"
rm -f "$contract_fail_out"

codex_render_tmp=$(mktemp -d)
mkdir -p "$codex_render_tmp/.agents/templates"
cp "$FRAMEWORK_DIR/.agents/templates/CODEX.md" "$codex_render_tmp/.agents/templates/CODEX.md"
cat > "$codex_render_tmp/CLAUDE.md" <<'EOF'
# Consumer

## Project Rules

- Regra exclusiva do consumidor.
EOF
if ( cd "$codex_render_tmp" \
  && export CANUTO_INSTALL_LIBRARY_ONLY=1 \
  && . "$FRAMEWORK_DIR/install.sh" \
  && trap 'rm -rf "$TMP_DIR"' EXIT \
  && render_codex_md >/dev/null \
  && ! grep -q '{{' CODEX.md \
  && grep -qF -- '- Regra exclusiva do consumidor.' CODEX.md ); then
  pass "render_codex_md resolve placeholders e preserva regras do consumidor"
else
  fail "render_codex_md nao produziu um CODEX.md valido para o consumidor"
fi
rm -rf "$codex_render_tmp"

# 12f1. merge_claude_md executada: headings exatos, referências fora de cerca,
# autoridade comum e idempotência. Grep estático não prova nenhum desses casos.
mcm_tmp=$(mktemp -d)
{
  echo 'set -euo pipefail'
  echo 'ok(){ :; }'
  echo 'warn(){ :; }'
  sed -n '/^merge_claude_md() {/,/^}/p' "$FRAMEWORK_DIR/install.sh"
} > "$mcm_tmp/fn.sh"
mcm_run(){ ( cd "$1" && CLAUDE_MD=CLAUDE.md && . "$mcm_tmp/fn.sh" && merge_claude_md ) >/dev/null 2>&1 || true; }
mcm_fail=""

mkdir -p "$mcm_tmp/a"
cat > "$mcm_tmp/a/CLAUDE.md" <<'EOF'
# X

## Framework Notes
- `.agents/OPERATING-CONTRACT.md` aparece só numa nota.

```markdown
## Framework
- Read `.agents/OPERATING-CONTRACT.md` before non-trivial work; it is fake.
```

## Framework
- Location: .agents/
- Contract path documented as `.agents/OPERATING-CONTRACT.md`, without loading it.

## Framework
- seção duplicada legada

## Project Rules
- Never run Git or shell commands without explicit confirmation.
EOF
mcm_run "$mcm_tmp/a" && mcm_run "$mcm_tmp/a"
[ "$(grep -c 'Read `.agents/OPERATING-CONTRACT.md` before non-trivial work; it is the shared' "$mcm_tmp/a/CLAUDE.md")" = "1" ] \
  || mcm_fail="referência ativa ausente ou duplicada"
[ "$(grep -c 'Read-only Git and shell inspection within the active task' "$mcm_tmp/a/CLAUDE.md")" = "1" ] \
  || mcm_fail="${mcm_fail:+$mcm_fail; }autoridade read-only ausente ou duplicada"
[ "$(grep -c '^- Before finalizing any plan, always interview the user' "$mcm_tmp/a/CLAUDE.md")" = "1" ] \
  || mcm_fail="${mcm_fail:+$mcm_fail; }regra de planejamento inserida em cerca ou duplicada"
[ "$(grep -c '^- Before planning, implementing, or reviewing ANY user-facing UI' "$mcm_tmp/a/CLAUDE.md")" = "1" ] \
  || mcm_fail="${mcm_fail:+$mcm_fail; }regra de design inserida em cerca ou duplicada"
[ "$(grep -c '^- Never run Git or shell commands without explicit confirmation.$' "$mcm_tmp/a/CLAUDE.md")" = "0" ] \
  || mcm_fail="${mcm_fail:+$mcm_fail; }proibição legada não removida da seção real"
[ "$(find "$mcm_tmp" -name '*.tmp' | wc -l)" -eq 0 ] \
  || mcm_fail="${mcm_fail:+$mcm_fail; }temp órfão"

mkdir -p "$mcm_tmp/b"
cat > "$mcm_tmp/b/CLAUDE.md" <<'EOF'
# X

```markdown
## Framework
- Read `.agents/OPERATING-CONTRACT.md` before non-trivial work; it is fake.
## Project Rules
- Never run Git or shell commands without explicit confirmation.
```
EOF
mcm_run "$mcm_tmp/b" && mcm_run "$mcm_tmp/b"
[ "$(grep -c '^## Framework$' "$mcm_tmp/b/CLAUDE.md")" = "2" ] \
  || mcm_fail="${mcm_fail:+$mcm_fail; }heading cercado suprimiu seção real ou duplicou em re-run"
[ "$(grep -c 'Read `.agents/OPERATING-CONTRACT.md` before non-trivial work; it is the shared' "$mcm_tmp/b/CLAUDE.md")" = "1" ] \
  || mcm_fail="${mcm_fail:+$mcm_fail; }referência cercada suprimiu diretiva real"

mkdir -p "$mcm_tmp/c"
printf '# X\n\n```markdown\ncerca nunca fechada\n' > "$mcm_tmp/c/CLAUDE.md"
mcm_run "$mcm_tmp/c" && mcm_run "$mcm_tmp/c"
mcm_active=$(awk '
  /^[[:space:]]{0,3}(```|~~~)/ { fenced=!fenced; next }
  !fenced && /Read `\.agents\/OPERATING-CONTRACT\.md` before non-trivial work;/ { count++ }
  END { print count+0 }
' "$mcm_tmp/c/CLAUDE.md")
[ "$mcm_active" = "1" ] && [ "$(grep -c '^## Framework$' "$mcm_tmp/c/CLAUDE.md")" = "1" ] \
  || mcm_fail="${mcm_fail:+$mcm_fail; }cerca não fechada deixou contrato inativo ou duplicou recovery"

if [ -z "$mcm_fail" ]; then
  pass "merge_claude_md executada: heading exato, cerca ignorada, autoridade alinhada e idempotência"
else
  fail "merge_claude_md: $mcm_fail"
fi
rm -rf "$mcm_tmp"

# 12f1b. Gates mecânicos: update recusa WIP e --check nunca fica verde com
# drift, missing ou UNKNOWN.
gate_tmp=$(mktemp -d)
{
  sed -n '/^update_tree_is_clean() {/,/^}/p' "$FRAMEWORK_DIR/install.sh"
  sed -n '/^check_result_code() {/,/^}/p' "$FRAMEWORK_DIR/install.sh"
} > "$gate_tmp/fn.sh"
git -C "$gate_tmp" init -q
git -C "$gate_tmp" add fn.sh
git -C "$gate_tmp" -c user.name=Canuto -c user.email=canuto@example.invalid commit -qm fixture
( cd "$gate_tmp" && . "$gate_tmp/fn.sh" && GIT_AVAILABLE=true && update_tree_is_clean ) \
  || fail "update_tree_is_clean rejeitou worktree limpa"
printf 'wip\n' > "$gate_tmp/user-wip.txt"
if ( cd "$gate_tmp" && . "$gate_tmp/fn.sh" && GIT_AVAILABLE=true && update_tree_is_clean ); then
  fail "update_tree_is_clean aceitou WIP untracked"
elif ( . "$gate_tmp/fn.sh"; check_result_code 0 0 0 ) \
  && ! ( . "$gate_tmp/fn.sh"; check_result_code 1 0 0 ) \
  && [ "$( ( . "$gate_tmp/fn.sh"; check_result_code 0 0 1 ); printf '%s' "$?" )" = "2" ]; then
  pass "gates de update/check: WIP recusado e estados não verdes retornam não-zero"
else
  fail "check_result_code não distingue verde, drift e UNKNOWN"
fi
mkdir -p "$gate_tmp/not-a-repo"
if ( cd "$gate_tmp/not-a-repo" && . "$gate_tmp/fn.sh" && GIT_AVAILABLE=true && update_tree_is_clean ); then
  fail "update_tree_is_clean ficou verde quando git status falhou"
else
  pass "update_tree_is_clean falha fechado quando o estado Git não pode ser lido"
fi
rm -rf "$gate_tmp"

check_out=$(mktemp)
if ( cd "$FRAMEWORK_DIR" && CANUTO_SOURCE_DIR="$FRAMEWORK_DIR" bash install.sh --check ) > "$check_out" 2>&1 \
  && grep -q '0 unknown' "$check_out" \
  && grep -q 'All framework files are up to date' "$check_out"; then
  pass "--check contra fonte idêntica: hashes cobrem arquivos sem version e resultado é verde"
else
  fail "--check não reconheceu fonte idêntica como integralmente atualizada"
fi
rm -f "$check_out"

# 12f2. Coding Rules: os dois caminhos de merge_agents_md têm de emitir a MESMA
# seção. Comparação textual do bloco inteiro — checar só as 3 regras novas
# deixaria passar edição em qualquer um dos outros 6 bullets, e deixaria passar
# uma 4a regra adicionada só no heredoc de geração.
gen_block=$(awk '/^## Coding Rules$/{f++} f==1 && /^- /{print} f==1 && /^$/ && seen{exit} f==1 && /^- /{seen=1}' "$FRAMEWORK_DIR/install.sh" || true)
patch_block=$(awk '/^## Coding Rules$/{f++} f==2 && /^RULESPATCH$/{exit} f==2 && /^- /{print}' "$FRAMEWORK_DIR/install.sh" || true)
gen_n=$(printf '%s\n' "$gen_block" | grep -c '^- ' || true)
# RULESLIST é a fonte EXECUTÁVEL: alimenta o sentinela de presença e o conteúdo
# inserido. Se divergir das outras duas, o instalador procura e injeta o texto
# velho em todo projeto existente — e comparar só gen vs patch não veria nada.
list_block=$(awk '/<< .RULESLIST.$/{f=1; next} f && /^RULESLIST$/{exit} f && /^- /{print}' "$FRAMEWORK_DIR/install.sh" || true)
gen_first3=$(printf '%s\n' "$gen_block" | head -3)
if [ -z "$gen_block" ] || [ "$gen_n" -lt 9 ]; then
  fail "12f2: não consegui extrair a seção Coding Rules do heredoc de geração (achei $gen_n bullets)"
elif [ "$gen_block" != "$patch_block" ]; then
  fail "12f2: heredoc de geração e RULESPATCH divergiram — projeto novo e projeto patchado receberiam regras diferentes"
elif [ -z "$list_block" ] || [ "$list_block" != "$gen_first3" ]; then
  fail "12f2: RULESLIST divergiu do texto emitido — o instalador procuraria/injetaria texto que não é o publicado"
else
  # e o AGENTS.md deste repo tem de conter cada bullet emitido
  missing_in_repo=""
  while IFS= read -r r; do
    [ -n "$r" ] || continue
    grep -qF -- "$r" "$FRAMEWORK_DIR/AGENTS.md" || missing_in_repo="${r:0:44}"
  done <<< "$gen_block"
  if [ -n "$missing_in_repo" ]; then
    fail "12f2: AGENTS.md do repo não tem a regra emitida pelo instalador: $missing_in_repo..."
  else
    pass "AGENTS.md Coding Rules: geração e patch idênticos ($gen_n bullets), AGENTS.md em dia"
  fi
fi

# 12f3. merge_agents_md EXECUTADA — 12f2 é estático e não prova comportamento.
# Cobre: geração, idempotência em 2 runs, inserção escopada à seção real
# (regra citada em bloco de código não conta como aplicada), preservação de
# conteúdo custom, e ausência de temp órfão.
mam_tmp=$(mktemp -d)
{ echo 'set -euo pipefail'; echo 'ok(){ :; }'; echo 'warn(){ :; }'
  sed -n '/^merge_agents_md() {/,/^}/p' "$FRAMEWORK_DIR/install.sh"; } > "$mam_tmp/fn.sh"
R_GROW="- Grow in layers:"
mam_run(){ ( cd "$1" && . "$mam_tmp/fn.sh" && merge_agents_md ) >/dev/null 2>&1 || true; }
mam_count(){ grep -cF -- "$2" "$1/AGENTS.md" 2>/dev/null || echo 0; }
mam_fail=""

# a) geração do zero + idempotência
mkdir -p "$mam_tmp/a" && mam_run "$mam_tmp/a" && mam_run "$mam_tmp/a"
[ "$(mam_count "$mam_tmp/a" "$R_GROW")" = "1" ] || mam_fail="geração/idempotência"
[ "$(mam_count "$mam_tmp/a" '.agents/OPERATING-CONTRACT.md')" = "1" ] || mam_fail="${mam_fail:+$mam_fail; }contrato ausente/duplicado na geração"

# b) seção existente sem uma regra, 2 runs → exatamente 1 de cada
mkdir -p "$mam_tmp/b"
printf '# X\n\n## Coding Rules\n- Follow existing patterns\n\n## Custom\n- preservar isto\n' > "$mam_tmp/b/AGENTS.md"
mam_run "$mam_tmp/b" && mam_run "$mam_tmp/b"
[ "$(mam_count "$mam_tmp/b" "$R_GROW")" = "1" ] || mam_fail="${mam_fail:+$mam_fail; }duplicou em 2 runs"
[ "$(mam_count "$mam_tmp/b" '.agents/OPERATING-CONTRACT.md')" = "1" ] || mam_fail="${mam_fail:+$mam_fail; }contrato ausente/duplicado no patch"
grep -q "preservar isto" "$mam_tmp/b/AGENTS.md" || mam_fail="${mam_fail:+$mam_fail; }perdeu seção custom"

# b2) menção em prosa ou cerca não satisfaz a diretiva ativa exigida pelo smoke.
mkdir -p "$mam_tmp/b2"
cat > "$mam_tmp/b2/AGENTS.md" <<'EOF'
# X

O arquivo `.agents/OPERATING-CONTRACT.md` existe.

   ```markdown
- Read `.agents/OPERATING-CONTRACT.md` before non-trivial work; it is fake.
   ```
EOF
mam_run "$mam_tmp/b2" && mam_run "$mam_tmp/b2"
active_contract_refs=$(awk '
  /^[[:space:]]{0,3}(```|~~~)/ { fenced=!fenced; next }
  !fenced && /^[[:space:]]*-[[:space:]]+Read `\.agents\/OPERATING-CONTRACT\.md` before non-trivial work;/ { count++ }
  END { print count+0 }
' "$mam_tmp/b2/AGENTS.md")
[ "$active_contract_refs" = "1" ] || mam_fail="${mam_fail:+$mam_fail; }menção/cerca suprimiu ou duplicou contrato ativo"

# c) regra citada dentro de bloco de código não conta como aplicada.
# O fixture usa o texto INTEGRAL da regra: com o prefixo só, uma regressão para
# escopo-de-arquivo passaria verde, porque o grep não acharia o texto de todo
# jeito. Com o texto integral, escopo-de-arquivo acha → não insere → falha.
R_FULL=$(awk '/<< .RULESLIST.$/{f=1; next} f && /^- Grow in layers:/{print; exit}' "$FRAMEWORK_DIR/install.sh")
mkdir -p "$mam_tmp/c"
{ printf '# X\n\n## Exemplo\n\n```markdown\n## Coding Rules\n%s\n```\n\n## Coding Rules\n- Follow existing patterns\n' "$R_FULL"; } > "$mam_tmp/c/AGENTS.md"
mam_run "$mam_tmp/c"
if [ "$(awk '/^## Coding Rules[[:space:]]*$/{f++} f==2 && /^- Grow in layers:/{c++} END{print c+0}' "$mam_tmp/c/AGENTS.md")" != "1" ]; then
  mam_fail="${mam_fail:+$mam_fail; }não inseriu na seção real (bloco de código contou como aplicada)"
fi

# c2) subtítulo ### dentro da seção não pode truncar a extração e duplicar
mkdir -p "$mam_tmp/c2"
{ printf '# X\n\n## Coding Rules\n\n### Gerais\n'; printf '%s\n' "$gen_first3"; } > "$mam_tmp/c2/AGENTS.md"
mam_run "$mam_tmp/c2"
[ "$(mam_count "$mam_tmp/c2" "$R_GROW")" = "1" ] || mam_fail="${mam_fail:+$mam_fail; }duplicou por causa de subtítulo ###"

# c3) cerca não fechada não pode fazer a seção sumir e anexar outra a cada run
mkdir -p "$mam_tmp/c3"
printf '# X\n\n```\ncerca aberta e nunca fechada\n\n## Coding Rules\n- Follow existing patterns\n' > "$mam_tmp/c3/AGENTS.md"
mam_run "$mam_tmp/c3"; mam_run "$mam_tmp/c3"; mam_run "$mam_tmp/c3"
[ "$(grep -cE '^##+ Coding Rules[[:space:]]*$' "$mam_tmp/c3/AGENTS.md")" = "1" ] || mam_fail="${mam_fail:+$mam_fail; }anexou seção duplicada (cerca não fechada, 3 runs)"
mam_c3_active=$(awk '
  /^[[:space:]]{0,3}(```|~~~)/ { fenced=!fenced; next }
  !fenced && /Read `\.agents\/OPERATING-CONTRACT\.md` before non-trivial work;/ { count++ }
  END { print count+0 }
' "$mam_tmp/c3/AGENTS.md")
[ "$mam_c3_active" = "1" ] && [ "$(grep -c '^## Shared Operating Contract$' "$mam_tmp/c3/AGENTS.md")" = "1" ] \
  || mam_fail="${mam_fail:+$mam_fail; }cerca não fechada deixou contrato inativo ou duplicou recovery"

# d) falha na publicação não pode danificar o arquivo do usuário
mkdir -p "$mam_tmp/d"
printf '# X\n\n## Coding Rules\n- Follow existing patterns\n\n## Custom\n- insubstituivel\n' > "$mam_tmp/d/AGENTS.md"
mam_run "$mam_tmp/d"   # assenta as seções irmãs
grep -v "Grow in layers" "$mam_tmp/d/AGENTS.md" > "$mam_tmp/d/x" && mv "$mam_tmp/d/x" "$mam_tmp/d/AGENTS.md"
d_before=$(cksum < "$mam_tmp/d/AGENTS.md")
( cd "$mam_tmp/d" && . "$mam_tmp/fn.sh" && mv(){ return 1; } && merge_agents_md ) >/dev/null 2>&1 || true
[ "$d_before" = "$(cksum < "$mam_tmp/d/AGENTS.md")" ] || mam_fail="${mam_fail:+$mam_fail; }falha de mv danificou o arquivo"
grep -q insubstituivel "$mam_tmp/d/AGENTS.md" || mam_fail="${mam_fail:+$mam_fail; }falha de mv perdeu conteúdo custom"

# e) nenhum temp órfão em nenhum dos casos, inclusive no de falha
[ "$(find "$mam_tmp" -name '*.tmp' -o -name '*.canuto.*' | wc -l)" -eq 0 ] || mam_fail="${mam_fail:+$mam_fail; }deixou temp órfão"

if [ -z "$mam_fail" ]; then
  pass "merge_agents_md executada: gera, é idempotente em 2 runs, escopa à seção real, preserva custom"
else
  fail "merge_agents_md: $mam_fail"
fi
rm -rf "$mam_tmp"

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
# TEST 15: Identidade em duas posturas (Fase 2 — A3)
# ═══════════════════════════════════════════════════════════════════════════
# canuto_project_slug DEGRADA (leitura sempre devolve algo) e
# canuto_require_project_slug FALHA ALTO (escrita recusa slug que não
# sobrevive a `git worktree add`). Sem estes testes o basename volta a ser
# identidade de escrita — foi assim que o vault virou 184 ilhas.
# Tudo em sandbox: HOME, CANUTO_VAULT_DIR e TMPDIR falsos; o vault real
# (~/.canuto) nunca é lido nem escrito.
echo "── Test 15: Identidade em duas posturas (A3) ──"

f2_eq()    { if [ "$2" = "$3" ]; then pass "$1"; else fail "$1 — esperado [$2], obtido [$3]"; fi; }
f2_has()   { case "$2" in *"$3"*) pass "$1" ;; *) fail "$1 — saída não contém [$3]" ;; esac; }
f2_hasnt() { case "$2" in *"$3"*) fail "$1 — saída contém [$3] e não deveria" ;; *) pass "$1" ;; esac; }

MEM_LIB="$AGENTS_DIR/tools/canuto-memory.sh"
A3_SB="$(mktemp -d "${TMPDIR:-/tmp}/canuto-a3.XXXXXX")"
A3_VAULT="$A3_SB/vault"
A3_HOME="$A3_SB/home"
A3_ERRF="$A3_SB/.stderr"
# NB: nenhum diretório do sandbox pode se chamar workspaces/repos/projects/
# worktrees fora dos casos que TESTAM colapso de container — o colapso é por
# nome de segmento e contaminaria os demais casos.
mkdir -p "$A3_VAULT/projects" "$A3_HOME" "$A3_SB/cases" "$A3_SB/tmp"

A3_OUT=""; A3_ERR=""; A3_RC=0
a3_call() {
  # $1 = snippet bash · $2 = CLAUDE_PROJECT_DIR · $3 = CANUTO_SLUG_NO_CACHE (default 1)
  # CLAUDE_PROJECT_DIR SEMPRE apontando para o sandbox: canuto_event_append o usa
  # para resolver o destino do log; deixá-lo vazio escreveria no vault real.
  local snippet="$1" projdir="${2:-$A3_SB/cases}" nocache="${3:-1}"
  A3_RC=0
  A3_OUT=$(
    HOME="$A3_HOME" CANUTO_VAULT_DIR="$A3_VAULT" CANUTO_SLUG_NO_CACHE="$nocache" \
    CLAUDE_PROJECT_DIR="$projdir" TMPDIR="$A3_SB/tmp" \
    bash -c "cd '$A3_SB' || exit 9; . '$MEM_LIB'; set +e +u +o pipefail; $snippet" 2>"$A3_ERRF"
  ) || A3_RC=$?
  A3_ERR="$(cat "$A3_ERRF" 2>/dev/null || true)"
}

# ── A3-1: dir pelado (sem CLAUDE.md, sem git, fora de container) ────────────
mkdir -p "$A3_SB/cases/pelado"
a3_call "canuto_require_project_slug '$A3_SB/cases/pelado'" "$A3_SB/cases/pelado"
if [ "$A3_RC" -eq 1 ] && [ -z "$A3_OUT" ]; then
  pass "A3-1 require recusa dir sem identidade (exit 1, stdout vazio)"
else
  fail "A3-1 require deveria sair 1 com stdout vazio (rc=$A3_RC, out=[$A3_OUT])"
fi
f2_has "A3-1b require nomeia a ação no stderr" "$A3_ERR" "canuto-init"

# ── A3-2: override project-slug no CLAUDE.md ────────────────────────────────
mkdir -p "$A3_SB/cases/com-override"
printf 'project-slug: meu-produto\n' > "$A3_SB/cases/com-override/CLAUDE.md"
a3_call "canuto_require_project_slug '$A3_SB/cases/com-override'" "$A3_SB/cases/com-override"
f2_eq "A3-2 require aceita override do CLAUDE.md" "meu-produto" "$A3_OUT"

# ── A3-3: colapso de container (.../workspaces/<proj>/<wt>) ─────────────────
mkdir -p "$A3_SB/cases/root/workspaces/produto-x/wt-feature"
a3_call "canuto_require_project_slug '$A3_SB/cases/root/workspaces/produto-x/wt-feature'" \
  "$A3_SB/cases/root/workspaces/produto-x/wt-feature"
f2_eq "A3-3 require aceita colapso de container" "produto-x" "$A3_OUT"

# ── A3-4: basename do remote origin ─────────────────────────────────────────
mkdir -p "$A3_SB/cases/com-remote"
( cd "$A3_SB/cases/com-remote" && git init -q . && \
  git remote add origin 'git@github.com:acme/Produto_Y.git' ) >/dev/null 2>&1 || true
a3_call "canuto_require_project_slug '$A3_SB/cases/com-remote'" "$A3_SB/cases/com-remote"
f2_eq "A3-4 require aceita basename do remote origin" "produto-y" "$A3_OUT"

# ── A3-5: as DUAS posturas no MESMO dir (git sem remote, fora de container) ──
mkdir -p "$A3_SB/cases/repo-sem-remote"
( cd "$A3_SB/cases/repo-sem-remote" && git init -q . ) >/dev/null 2>&1 || true
a3_call "canuto_require_project_slug '$A3_SB/cases/repo-sem-remote'" "$A3_SB/cases/repo-sem-remote"
A3_STRICT_RC="$A3_RC"
a3_call "canuto_project_slug '$A3_SB/cases/repo-sem-remote'" "$A3_SB/cases/repo-sem-remote"
if [ "$A3_STRICT_RC" -eq 1 ] && [ "$A3_OUT" = "repo-sem-remote" ]; then
  pass "A3-5 escrita recusa o basename enquanto leitura o devolve (duas posturas)"
else
  fail "A3-5 duas posturas quebradas (require rc=$A3_STRICT_RC, slug=[$A3_OUT])"
fi

# ── A3-6: slug do template num repo que não é o framework ───────────────────
mkdir -p "$A3_SB/cases/repo-alheio"
printf 'project-slug: canuto-framework-v1\n' > "$A3_SB/cases/repo-alheio/CLAUDE.md"
a3_call "canuto_require_project_slug '$A3_SB/cases/repo-alheio'" "$A3_SB/cases/repo-alheio"
if [ "$A3_RC" -eq 1 ]; then
  f2_has "A3-6 require recusa slug de template citando a guarda" "$A3_ERR" "anti-template"
else
  fail "A3-6 require aceitou slug de template em repo alheio (rc=$A3_RC, out=[$A3_OUT])"
fi

# ── Fixtures de vault para o classificador ──────────────────────────────────
printf '{"velho": "canon", "velho2": "canon2", "velho3": "canon3"}\n' \
  > "$A3_VAULT/.project-aliases.json"
mkdir -p "$A3_VAULT/projects/populado/sessions"
printf '# nota\n' > "$A3_VAULT/projects/populado/sessions/s1.md"
mkdir -p "$A3_VAULT/projects/so-audit/audit" "$A3_VAULT/projects/so-audit/metrics"
printf '# a\n' > "$A3_VAULT/projects/so-audit/audit/a.md"
printf '# m\n' > "$A3_VAULT/projects/so-audit/metrics/m.md"
mkdir -p "$A3_VAULT/projects/sozinho"
mkdir -p "$A3_VAULT/projects/velho/sessions" "$A3_VAULT/projects/canon"
printf '# nota antiga\n' > "$A3_VAULT/projects/velho/sessions/s1.md"
mkdir -p "$A3_VAULT/projects/velho2/sessions" "$A3_VAULT/projects/canon2/sessions"
printf '# a\n' > "$A3_VAULT/projects/velho2/sessions/s1.md"
printf '# b\n' > "$A3_VAULT/projects/canon2/sessions/s1.md"
mkdir -p "$A3_VAULT/projects/velho3" "$A3_VAULT/projects/canon3"
mkdir -p "$A3_VAULT/projects/produto-x/sessions"
printf '# nota do produto\n' > "$A3_VAULT/projects/produto-x/sessions/s1.md"

# ── A3-7: POPULATED ─────────────────────────────────────────────────────────
a3_call "canuto_classify_vault populado '$A3_SB/cases/pelado'" "$A3_SB/cases/pelado"
if [ "$A3_OUT" = "POPULATED" ] && [ "$A3_RC" -eq 0 ]; then
  pass "A3-7 classify POPULATED (exit 0)"
else
  fail "A3-7 classify deveria ser POPULATED/0 (out=[$A3_OUT] rc=$A3_RC)"
fi

# ── A3-8: audit/metrics são projeção mecânica, não conteúdo ─────────────────
a3_call "canuto_classify_vault so-audit '$A3_SB/cases/pelado'" "$A3_SB/cases/pelado"
f2_eq "A3-8 classify não conta audit/metrics como conteúdo" "FRESH" "$A3_OUT"

# ── A3-9: FRESH honesto ─────────────────────────────────────────────────────
a3_call "canuto_classify_vault sozinho '$A3_SB/cases/pelado'" "$A3_SB/cases/pelado"
if [ "$A3_OUT" = "FRESH" ] && [ "$A3_RC" -eq 0 ]; then
  pass "A3-9 classify FRESH sem irmão (exit 0)"
else
  fail "A3-9 classify deveria ser FRESH/0 (out=[$A3_OUT] rc=$A3_RC)"
fi

# ── A3-10: ORPHAN por alias REVERSO + evento VAULT_ORPHAN ───────────────────
mkdir -p "$A3_SB/cases/orfao-repo"
printf 'project-slug: canon\n' > "$A3_SB/cases/orfao-repo/CLAUDE.md"
a3_call "canuto_classify_vault canon '$A3_SB/cases/orfao-repo'" "$A3_SB/cases/orfao-repo"
if [ "$A3_OUT" = "ORPHAN" ] && [ "$A3_RC" -eq 1 ]; then
  pass "A3-10 classify ORPHAN por alias reverso (exit 1)"
else
  fail "A3-10 classify deveria ser ORPHAN/1 (out=[$A3_OUT] rc=$A3_RC)"
fi
f2_has "A3-10b stderr nomeia o irmão" "$A3_ERR" "velho"
A3_EVLOG="$A3_VAULT/projects/canon/events/log.jsonl"
if [ -f "$A3_EVLOG" ]; then
  A3_EVTXT="$(cat "$A3_EVLOG")"
  f2_has "A3-10c evento VAULT_ORPHAN gravado" "$A3_EVTXT" '"event":"VAULT_ORPHAN"'
  f2_has "A3-10d evento carrega o irmão" "$A3_EVTXT" 'velho'
else
  fail "A3-10c evento VAULT_ORPHAN não foi gravado em $A3_EVLOG"
fi

# ── A3-11: ORPHAN por colapso de container ──────────────────────────────────
a3_call "canuto_classify_vault wt-feature '$A3_SB/cases/root/workspaces/produto-x/wt-feature'" \
  "$A3_SB/cases/root/workspaces/produto-x/wt-feature"
f2_eq "A3-11 classify ORPHAN por colapso de container" "ORPHAN" "$A3_OUT"

# ── A3-12: irmão existe mas está vazio -> não inventar órfão ────────────────
a3_call "canuto_classify_vault canon3 '$A3_SB/cases/pelado'" "$A3_SB/cases/pelado"
f2_eq "A3-12 irmão vazio não vira ORPHAN" "FRESH" "$A3_OUT"

# ── A3-13: POPULATED com irmão populado -> aviso, sem mudar o contrato ──────
a3_call "canuto_classify_vault canon2 '$A3_SB/cases/pelado'" "$A3_SB/cases/pelado"
if [ "$A3_OUT" = "POPULATED" ] && [ "$A3_RC" -eq 0 ]; then
  f2_has "A3-13 fragmentação vira aviso em stderr (stdout/exit intactos)" "$A3_ERR" "fragmenta"
else
  fail "A3-13 contrato quebrado com irmão populado (out=[$A3_OUT] rc=$A3_RC)"
fi

# ── A3-14: fresh_clone_check nos 4 estados, sempre rc=0 ─────────────────────
mkdir -p "$A3_SB/cases/clone-template"
printf 'project-slug: canuto-framework-v1\n' > "$A3_SB/cases/clone-template/CLAUDE.md"
a3_call "canuto_fresh_clone_check '$A3_SB/cases/clone-template' | head -1" "$A3_SB/cases/clone-template"
if [ "$A3_RC" -eq 0 ]; then
  f2_has "A3-14a fresh_clone_check TEMPLATE-CLONE (rc=0)" "$A3_OUT" "TEMPLATE-CLONE"
else
  fail "A3-14a fresh_clone_check deveria ser informativo (rc=$A3_RC)"
fi

mkdir -p "$A3_SB/cases/clone-novo/.agents"
a3_call "canuto_fresh_clone_check '$A3_SB/cases/clone-novo' | head -1" "$A3_SB/cases/clone-novo"
if [ "$A3_RC" -eq 0 ]; then
  f2_has "A3-14b fresh_clone_check UNINITIALIZED (rc=0)" "$A3_OUT" "UNINITIALIZED"
else
  fail "A3-14b fresh_clone_check deveria ser informativo (rc=$A3_RC)"
fi

mkdir -p "$A3_SB/cases/nao-canuto"
a3_call "canuto_fresh_clone_check '$A3_SB/cases/nao-canuto' | head -1" "$A3_SB/cases/nao-canuto"
if [ "$A3_RC" -eq 0 ]; then
  f2_has "A3-14c fresh_clone_check NOT-CANUTO (rc=0)" "$A3_OUT" "NOT-CANUTO"
else
  fail "A3-14c fresh_clone_check deveria ser informativo (rc=$A3_RC)"
fi

mkdir -p "$A3_SB/cases/install-vivo/.agents"
printf 'project-slug: populado\n' > "$A3_SB/cases/install-vivo/CLAUDE.md"
a3_call "canuto_fresh_clone_check '$A3_SB/cases/install-vivo' | head -1" "$A3_SB/cases/install-vivo"
if [ "$A3_RC" -eq 0 ]; then
  f2_has "A3-14d fresh_clone_check OK (rc=0)" "$A3_OUT" "OK:"
else
  fail "A3-14d fresh_clone_check deveria ser informativo (rc=$A3_RC)"
fi

# ── A3-15: CANUTO_SLUG_NO_CACHE=1 ignora cache E memo ───────────────────────
mkdir -p "$A3_SB/cases/cache-test"
printf 'project-slug: slug-a\n' > "$A3_SB/cases/cache-test/CLAUDE.md"
a3_call "canuto_project_slug '$A3_SB/cases/cache-test'" "$A3_SB/cases/cache-test" 0
printf 'project-slug: slug-b\n' > "$A3_SB/cases/cache-test/CLAUDE.md"
a3_call "canuto_project_slug '$A3_SB/cases/cache-test'" "$A3_SB/cases/cache-test" 1
f2_eq "A3-15 NO_CACHE=1 devolve o valor novo" "slug-b" "$A3_OUT"

# ── A3-16: nenhuma função de identidade consome o stdin do hook ─────────────
# Hooks recebem JSON por stdin: uma função que come stdin cega o hook inteiro.
A3_STDIN_OUT=$(printf '{"hook_event_name":"SessionStart"}' | \
  HOME="$A3_HOME" CANUTO_VAULT_DIR="$A3_VAULT" CANUTO_SLUG_NO_CACHE=1 \
  CLAUDE_PROJECT_DIR="$A3_SB/cases/orfao-repo" TMPDIR="$A3_SB/tmp" \
  bash -c ". '$MEM_LIB'; set +e +u +o pipefail
    canuto_classify_vault canon '$A3_SB/cases/orfao-repo' >/dev/null 2>&1
    canuto_require_project_slug '$A3_SB/cases/orfao-repo' >/dev/null 2>&1
    canuto_fresh_clone_check '$A3_SB/cases/orfao-repo' >/dev/null 2>&1
    cat" 2>/dev/null || true)
f2_eq "A3-16 identidade não consome o stdin do caller" \
  '{"hook_event_name":"SessionStart"}' "$A3_STDIN_OUT"

# ── A3-17: sem event-log.sh, a degradação deixa rastro (nunca silenciosa) ───
A3_ISO="$A3_SB/isolado"
mkdir -p "$A3_ISO/lib" "$A3_ISO/home" "$A3_ISO/proj" "$A3_ISO/tmp" \
         "$A3_ISO/vault/projects/velho/sessions" "$A3_ISO/vault/projects/canon"
cp "$MEM_LIB" "$A3_ISO/lib/canuto-memory.sh"
printf '# nota\n' > "$A3_ISO/vault/projects/velho/sessions/s1.md"
printf '{"velho": "canon"}\n' > "$A3_ISO/vault/.project-aliases.json"
A3_ISO_OUT=$(
  HOME="$A3_ISO/home" CANUTO_VAULT_DIR="$A3_ISO/vault" CANUTO_SLUG_NO_CACHE=1 \
  CLAUDE_PROJECT_DIR="$A3_ISO/proj" TMPDIR="$A3_ISO/tmp" \
  bash -c "cd '$A3_ISO' || exit 9; . '$A3_ISO/lib/canuto-memory.sh'; set +e +u +o pipefail
    canuto_classify_vault canon '$A3_ISO/proj'" 2>/dev/null || true)
f2_eq "A3-17 classify segue funcionando sem event-log.sh" "ORPHAN" "$A3_ISO_OUT"
if [ -f "$A3_ISO/vault/_health/missing-lib.jsonl" ] && \
   grep -q 'event-log-lib-missing' "$A3_ISO/vault/_health/missing-lib.jsonl" 2>/dev/null; then
  pass "A3-17b perda de telemetria vira nota em _health (degradação não-silenciosa)"
else
  fail "A3-17b lib de evento ausente não deixou nota em _health/missing-lib.jsonl"
fi

# ── A3-18: sintaxe nos dois shells ──────────────────────────────────────────
if bash -n "$MEM_LIB" 2>/dev/null; then
  pass "A3-18a canuto-memory.sh: bash -n"
else
  fail "A3-18a canuto-memory.sh: erro de sintaxe (bash -n)"
fi
if command -v zsh >/dev/null 2>&1; then
  if zsh -n "$MEM_LIB" 2>/dev/null; then
    pass "A3-18b canuto-memory.sh: zsh -n"
  else
    fail "A3-18b canuto-memory.sh: erro de sintaxe (zsh -n)"
  fi
else
  warn "zsh ausente — checagem zsh -n pulada"
fi

rm -rf "$A3_SB"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# TEST 16: Briefing garantido + medição de uso (Fase 2 — A4)
# ═══════════════════════════════════════════════════════════════════════════
# O brief NUNCA pode sair vazio por quebra sem dizer que quebrou: vazio-honesto
# e lobotomia silenciosa têm de ser distinguíveis (eoc briefing-lifecycle-audit).
# O gate `check-identity` é o que prova isso — então ele próprio é testado
# contra sabotagem, senão vira decoração.
echo "── Test 16: Briefing garantido + uso (A4) ──"

BRIEF_LIB="$AGENTS_DIR/tools/brief-compose.sh"
USAGE_LIB="$AGENTS_DIR/tools/memory-usage.sh"
A4_SB="$(mktemp -d "${TMPDIR:-/tmp}/canuto-a4.XXXXXX")"
mkdir -p "$A4_SB/home" "$A4_SB/tmp"

a4_brief() {
  # $1 = root · $2 = vault · $3 = lib alternativa (sabotagem)
  HOME="$A4_SB/home" CANUTO_VAULT_DIR="$2" CANUTO_SLUG_NO_CACHE=1 \
  CLAUDE_PROJECT_DIR="$1" TMPDIR="$A4_SB/tmp" \
    bash "${3:-$BRIEF_LIB}" brief "$1" 2>/dev/null || true
}
A4_CHECK_OUT=""; A4_CHECK_RC=0
a4_check() {
  A4_CHECK_RC=0
  A4_CHECK_OUT=$(
    HOME="$A4_SB/home" CANUTO_VAULT_DIR="$2" CANUTO_SLUG_NO_CACHE=1 \
    CLAUDE_PROJECT_DIR="$1" TMPDIR="$A4_SB/tmp" \
      bash "${3:-$BRIEF_LIB}" check-identity "$1" 2>&1
  ) || A4_CHECK_RC=$?
}

# ── A4-1: sintaxe das duas libs novas nos dois shells ───────────────────────
for A4_LIB in "$BRIEF_LIB" "$USAGE_LIB"; do
  A4_LIB_NAME="$(basename "$A4_LIB")"
  if [ ! -f "$A4_LIB" ]; then
    fail "A4-1 lib ausente: $A4_LIB_NAME"
    continue
  fi
  if bash -n "$A4_LIB" 2>/dev/null; then
    pass "A4-1 $A4_LIB_NAME: bash -n"
  else
    fail "A4-1 $A4_LIB_NAME: erro de sintaxe (bash -n)"
  fi
  if command -v zsh >/dev/null 2>&1; then
    if zsh -n "$A4_LIB" 2>/dev/null; then
      pass "A4-1 $A4_LIB_NAME: zsh -n"
    else
      fail "A4-1 $A4_LIB_NAME: erro de sintaxe (zsh -n)"
    fi
  fi
done

# ── A4-2: o compositor não pode VOLTAR a morar dentro do hook ──────────────
if grep -qE '^[[:space:]]*build_vault_brief[[:space:]]*\(\)' "$AGENTS_DIR/hooks/session-start.sh" 2>/dev/null; then
  fail "A4-2 build_vault_brief() voltou a ser definido dentro de session-start.sh (não é provável fora do hook)"
else
  pass "A4-2 compositor segue extraído (nenhuma definição de build_vault_brief() no hook)"
fi
if grep -q 'brief-compose.sh' "$AGENTS_DIR/hooks/session-start.sh" 2>/dev/null; then
  pass "A4-2b session-start.sh consome brief-compose.sh"
else
  fail "A4-2b session-start.sh não referencia brief-compose.sh"
fi

# ── Fixtures dos 4 estados de vault ─────────────────────────────────────────
# (1) populado
mkdir -p "$A4_SB/pop" "$A4_SB/vault-pop/projects/a4-brief-pop/sessions" \
         "$A4_SB/vault-pop/projects/a4-brief-pop/pending" \
         "$A4_SB/vault-pop/projects/a4-brief-pop/instincts"
printf 'project-slug: a4-brief-pop\n' > "$A4_SB/pop/CLAUDE.md"
printf '# Sessao A4 populada\n\nnext-entrypoint: retomar o gate de identidade\n' \
  > "$A4_SB/vault-pop/projects/a4-brief-pop/sessions/2026-08-01-x.md"
printf '# Pendencia numero um\n' > "$A4_SB/vault-pop/projects/a4-brief-pop/pending/p1.md"
printf '# Instinto numero um\n' > "$A4_SB/vault-pop/projects/a4-brief-pop/instincts/i1.md"
# (2) vault existe e está vazio
mkdir -p "$A4_SB/vazio" "$A4_SB/vault-vazio/projects/a4-brief-vazio/sessions" \
         "$A4_SB/vault-vazio/projects/a4-brief-vazio/pending" \
         "$A4_SB/vault-vazio/projects/a4-brief-vazio/instincts"
printf 'project-slug: a4-brief-vazio\n' > "$A4_SB/vazio/CLAUDE.md"
# (3) declarado no CLAUDE.md e AUSENTE no disco
mkdir -p "$A4_SB/decl"
printf 'project-slug: a4-brief-decl\n' > "$A4_SB/decl/CLAUDE.md"
# (4) nada declarado e sem vault -> fresco
mkdir -p "$A4_SB/fresco"

A4_OUT="$(a4_brief "$A4_SB/pop" "$A4_SB/vault-pop")"
f2_has "A4-3 vault populado: título da última sessão no brief" "$A4_OUT" "Sessao A4 populada"
f2_has "A4-3b vault populado: next-entrypoint destilado" "$A4_OUT" "retomar o gate de identidade"
f2_has "A4-3c vault populado: seção Pending com contagem" "$A4_OUT" "Pending (1)"
f2_has "A4-3d vault populado: seção Instincts com contagem" "$A4_OUT" "Instincts (1)"

A4_OUT="$(a4_brief "$A4_SB/vazio" "$A4_SB/vault-vazio")"
f2_has "A4-4a vault vazio: marcador de sessão" "$A4_OUT" "(nenhuma sessão registrada)"
f2_has "A4-4b vault vazio: marcador de next-entrypoint" "$A4_OUT" "(nenhum next-entrypoint declarado)"
f2_has "A4-4c vault vazio: marcador de pending" "$A4_OUT" "(nenhum pending registrado)"
f2_has "A4-4d vault vazio: marcador de instinct" "$A4_OUT" "(nenhum instinct registrado)"

A4_OUT="$(a4_brief "$A4_SB/decl" "$A4_SB/vault-decl-inexistente")"
f2_has "A4-5 vault declarado-e-ausente: marcador QUEBRADO (memória desligada, não vazia)" \
  "$A4_OUT" "vault declarado"
f2_has "A4-5b declarado-e-ausente aponta a ação" "$A4_OUT" "canuto-project-doctor"

A4_OUT="$(a4_brief "$A4_SB/fresco" "$A4_SB/vault-fresco-inexistente")"
f2_has "A4-6 projeto fresco: marcador de 1ª sessão" "$A4_OUT" "1ª sessão"
f2_hasnt "A4-6b projeto fresco não mente dizendo 'declarado'" "$A4_OUT" "vault declarado"

# ── A4-7: o gate no repo real e num sandbox populado ────────────────────────
# Este é o único caso que lê o vault REAL (só leitura — a perna 2 monta o
# próprio mktemp). Num clone recém-baixado (CI) o vault sequer existe: aí o
# gate reporta declarado-e-ausente, que é o veredito CERTO e não uma regressão.
# Por isso a ausência de vault instalado vira WARN; a asserção dura é a
# hermética logo abaixo (A4-7b), que não depende da máquina.
A4_REAL_RC=0
A4_REAL_OUT=$(bash "$BRIEF_LIB" check-identity "$FRAMEWORK_DIR" 2>&1) || A4_REAL_RC=$?
if [ "$A4_REAL_RC" -eq 0 ]; then
  pass "A4-7 check-identity OK no repo real"
elif [ ! -d "${CANUTO_VAULT_DIR:-$HOME/.canuto/vault}/projects" ]; then
  warn "A4-7 nenhum vault instalado nesta máquina — gate não exercitado no repo real"
else
  fail "A4-7 check-identity FALHOU no repo real: $A4_REAL_OUT"
fi

a4_check "$A4_SB/pop" "$A4_SB/vault-pop"
if [ "$A4_CHECK_RC" -eq 0 ]; then
  pass "A4-7b check-identity OK em sandbox populado (hermético)"
else
  fail "A4-7b check-identity falhou em sandbox populado: $A4_CHECK_OUT"
fi

# ── A4-8: o gate FALHA no feeder declarado-e-ausente ────────────────────────
a4_check "$A4_SB/decl" "$A4_SB/vault-decl-inexistente"
if [ "$A4_CHECK_RC" -ne 0 ]; then
  f2_has "A4-8 gate falha no feeder declarado-e-ausente" "$A4_CHECK_OUT" "declarado-e-ausente"
else
  fail "A4-8 gate passou com vault declarado e ausente (memória desligada passaria por saudável)"
fi

# ── A4-9: SABOTAGEM — seção vazia renderizada SEM marcador (perna 2) ────────
# É o teste que dá valor ao gate: sem ele, um compositor que devolvesse "" para
# toda seção vazia passaria na perna 1 de qualquer projeto populado.
mkdir -p "$A4_SB/sab2"
cp "$AGENTS_DIR/tools/canuto-memory.sh" "$AGENTS_DIR/tools/memory-usage.sh" "$A4_SB/sab2/" 2>/dev/null || true
sed 's/^Pending: \$CANUTO_BRIEF_MARK_NO_PENDING"$/Pending:"/' "$BRIEF_LIB" > "$A4_SB/sab2/brief-compose.sh"
if cmp -s "$BRIEF_LIB" "$A4_SB/sab2/brief-compose.sh"; then
  fail "A4-9 sabotagem da perna 2 não aplicou (o sed não casou — teste inválido, não código são)"
else
  a4_check "$A4_SB/pop" "$A4_SB/vault-pop" "$A4_SB/sab2/brief-compose.sh"
  if [ "$A4_CHECK_RC" -ne 0 ]; then
    f2_has "A4-9 perna 2 pega seção vazia sem marcador honesto" \
      "$A4_CHECK_OUT" "marcador honesto de vazio"
  else
    fail "A4-9 gate passou com compositor sabotado (perna 2 é decorativa)"
  fi
fi

# ── A4-10: SABOTAGEM — marcador VAZIO (perna 0) ────────────────────────────
# Marcador vazio faz `case "$x" in *""*` casar com tudo: o gate passaria por
# vacuidade justamente quando o compositor está mudo.
mkdir -p "$A4_SB/sab0"
cp "$AGENTS_DIR/tools/canuto-memory.sh" "$AGENTS_DIR/tools/memory-usage.sh" "$A4_SB/sab0/" 2>/dev/null || true
sed 's/^CANUTO_BRIEF_MARK_NO_PENDING=.*/CANUTO_BRIEF_MARK_NO_PENDING=""/' "$BRIEF_LIB" \
  > "$A4_SB/sab0/brief-compose.sh"
if cmp -s "$BRIEF_LIB" "$A4_SB/sab0/brief-compose.sh"; then
  fail "A4-10 sabotagem da perna 0 não aplicou (o sed não casou — teste inválido)"
else
  a4_check "$A4_SB/pop" "$A4_SB/vault-pop" "$A4_SB/sab0/brief-compose.sh"
  if [ "$A4_CHECK_RC" -ne 0 ]; then
    f2_has "A4-10 perna 0 pega marcador vazio antes das demais pernas" \
      "$A4_CHECK_OUT" "marcador honesto vazio"
  else
    fail "A4-10 gate passou por vacuidade com marcador vazio"
  fi
fi

# ── A4-11..16: memory-usage (record + rerank) ──────────────────────────────
A4_USLUG="a4-usage-test"
A4_UVAULT="$A4_SB/vault-usage"
A4_USTORE="$A4_UVAULT/projects/$A4_USLUG/_usage/usage.jsonl"
mkdir -p "$A4_UVAULT/projects/$A4_USLUG"

a4_rerank() {
  printf '%s\n' "$@" | HOME="$A4_SB/home" CANUTO_VAULT_DIR="$A4_UVAULT" TMPDIR="$A4_SB/tmp" \
    bash "$USAGE_LIB" rerank "$A4_USLUG" 2>/dev/null || true
}

# A4-11: store frio == ordem de entrada (rerank é um `cat`)
A4_OUT="$(a4_rerank ref-a ref-b ref-c)"
f2_eq "A4-11 rerank com store frio devolve a ordem de entrada" \
  "$(printf 'ref-a\nref-b\nref-c')" "$A4_OUT"

# A4-12: sinal de uso levanta a ref usada, e a estabilidade preserva o resto
HOME="$A4_SB/home" CANUTO_VAULT_DIR="$A4_UVAULT" bash "$USAGE_LIB" record "$A4_USLUG" ref-c >/dev/null 2>&1 || true
HOME="$A4_SB/home" CANUTO_VAULT_DIR="$A4_UVAULT" bash "$USAGE_LIB" record "$A4_USLUG" ref-c >/dev/null 2>&1 || true
A4_OUT="$(a4_rerank ref-a ref-b ref-c)"
f2_eq "A4-12 ref usada sobe ao topo e as demais mantêm a ordem (sort estável)" \
  "$(printf 'ref-c\nref-a\nref-b')" "$A4_OUT"

# A4-13: ts no FUTURO é relógio torto, não sinal fresco
A4_UVAULT2="$A4_SB/vault-usage2"
A4_USTORE2="$A4_UVAULT2/projects/$A4_USLUG/_usage/usage.jsonl"
mkdir -p "$(dirname "$A4_USTORE2")"
printf '{"ts":%s,"refs":["ref-z"]}\n' "$(( $(date +%s) + 9999 ))" > "$A4_USTORE2"
A4_OUT="$(printf 'ref-a\nref-z\n' | HOME="$A4_SB/home" CANUTO_VAULT_DIR="$A4_UVAULT2" \
  TMPDIR="$A4_SB/tmp" bash "$USAGE_LIB" rerank "$A4_USLUG" 2>/dev/null || true)"
f2_eq "A4-13 ts no futuro é ignorado (não sobe a ref)" "$(printf 'ref-a\nref-z')" "$A4_OUT"

# A4-14: linha malformada não pode SUMIR com item do briefing
A4_UVAULT3="$A4_SB/vault-usage3"
A4_USTORE3="$A4_UVAULT3/projects/$A4_USLUG/_usage/usage.jsonl"
mkdir -p "$(dirname "$A4_USTORE3")"
{ printf 'lixo nao json\n'; printf '{"ts":%s,"refs":["ref-b"]}\n' "$(date +%s)"; } > "$A4_USTORE3"
A4_OUT="$(printf 'ref-a\nref-b\nref-c\n' | HOME="$A4_SB/home" CANUTO_VAULT_DIR="$A4_UVAULT3" \
  TMPDIR="$A4_SB/tmp" bash "$USAGE_LIB" rerank "$A4_USLUG" 2>/dev/null || true)"
A4_NLINES="$(printf '%s\n' "$A4_OUT" | grep -c . || true)"
f2_eq "A4-14 linha malformada no store não reduz o número de refs" "3" "$A4_NLINES"

# A4-15/16: DECAY por recência — 30d decai abaixo do fresco, mas segue acima
# de quem nunca foi usado (é o ponto do half-life: esquecer sem apagar).
A4_UVAULT4="$A4_SB/vault-usage4"
A4_USTORE4="$A4_UVAULT4/projects/$A4_USLUG/_usage/usage.jsonl"
mkdir -p "$(dirname "$A4_USTORE4")"
{
  printf '{"ts":%s,"refs":["ref-velha"]}\n' "$(( $(date +%s) - 2592000 ))"
  printf '{"ts":%s,"refs":["ref-nova"]}\n' "$(date +%s)"
} > "$A4_USTORE4"
A4_OUT="$(printf 'ref-nunca\nref-velha\nref-nova\n' | HOME="$A4_SB/home" \
  CANUTO_VAULT_DIR="$A4_UVAULT4" TMPDIR="$A4_SB/tmp" \
  bash "$USAGE_LIB" rerank "$A4_USLUG" 2>/dev/null || true)"
f2_eq "A4-15 decay: fresca > velha(30d) > nunca-usada" \
  "$(printf 'ref-nova\nref-velha\nref-nunca')" "$A4_OUT"

# A4-16: o store de uso NUNCA mora no event log (invariante de governança N4)
A4_OUT="$(HOME="$A4_SB/home" CANUTO_VAULT_DIR="$A4_UVAULT" bash "$USAGE_LIB" path "$A4_USLUG" 2>/dev/null || true)"
f2_has "A4-16 store de uso vive em _usage/ (separado do event log)" "$A4_OUT" "/_usage/usage.jsonl"
f2_hasnt "A4-16b store de uso não pode cair em events/" "$A4_OUT" "/events/"

rm -rf "$A4_SB"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# TEST 17: Closeout atômico + pendings endereçáveis (Fase 2 — A5)
# ═══════════════════════════════════════════════════════════════════════════
# Nota sem intent kernel é memória write-only (eoc ADR-0009): prosa sem índice
# de retrieval. E o Next-Entrypoint que não vira pending EVAPORA POR OMISSÃO
# (ADR-0007). Ambos são gates mecânicos aqui — nenhum depende do agente lembrar.
echo "── Test 17: Closeout atômico (A5) ──"

A5_HOOK="$AGENTS_DIR/hooks/session-save.sh"
A5_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/canuto-a5.XXXXXX")"
A5_SLUG="a5-closeout-test"
A5_CASE=""; A5_VAULT=""

a5_setup() {
  # Sandbox NOVO por caso: pending/rework acumulam, e cruzar casos esconderia
  # exatamente o bug de idempotência que o caso 6 procura.
  A5_CASE="$A5_ROOT/$1"
  A5_VAULT="$A5_CASE/vault/projects/$A5_SLUG"
  mkdir -p "$A5_CASE/proj/.agents/tools" "$A5_VAULT/sessions" \
           "$A5_CASE/home" "$A5_CASE/tmp"
  printf 'project-slug: %s\n' "$A5_SLUG" > "$A5_CASE/proj/CLAUDE.md"
  cp "$AGENTS_DIR/tools/canuto-memory.sh" "$AGENTS_DIR/tools/event-log.sh" \
     "$A5_CASE/proj/.agents/tools/" 2>/dev/null || true
}
a5_run() {
  HOME="$A5_CASE/home" CANUTO_VAULT_DIR="$A5_CASE/vault" CANUTO_SLUG_NO_CACHE=1 \
  CLAUDE_PROJECT_DIR="$A5_CASE/proj" TMPDIR="$A5_CASE/tmp" \
    bash "$A5_HOOK" 2>&1 || true
}
a5_events() { cat "$A5_VAULT/events/log.jsonl" 2>/dev/null || true; }
a5_count()  { ls "$A5_VAULT/$1" 2>/dev/null | grep -c '\.md$' || true; }

# ── A5-1: sem nota canônica -> nada a publicar, nenhum evento ──────────────
a5_setup sem-nota
A5_OUT="$(a5_run)"
f2_has "A5-1 sem nota canônica o hook diz o que falta" "$A5_OUT" "nenhuma nota canônica"
f2_hasnt "A5-1b sem nota não emite CLOSEOUT_PUBLISHED" "$(a5_events)" "CLOSEOUT_PUBLISHED"

# ── A5-2: kernel de 3 linhas -> CLOSEOUT_PUBLISHED ─────────────────────────
a5_setup kernel-3-linhas
cat > "$A5_VAULT/sessions/2026-08-01-sessao.md" <<'A5EOF'
# Sessao com kernel

intent: fechar a fase 2 do canuto
porque: a memoria estava write-only
proximo: rodar o gate de identidade no repo consumidor
A5EOF
A5_OUT="$(a5_run)"
A5_EV="$(a5_events)"
f2_has "A5-2 kernel presente -> CLOSEOUT PUBLICADO no output" "$A5_OUT" "CLOSEOUT PUBLICADO"
f2_has "A5-2b evento CLOSEOUT_PUBLISHED emitido" "$A5_EV" '"event":"CLOSEOUT_PUBLISHED"'
f2_has "A5-2c evento carrega status=published" "$A5_EV" '"status":"published"'
f2_has "A5-2d evento carrega o kernel (intent)" "$A5_EV" 'fechar a fase 2 do canuto'

# ── A5-5: Next Entrypoint acionável vira pending endereçável ───────────────
if [ "$(a5_count pending)" = "1" ]; then
  pass "A5-5 next-entrypoint virou pending auto-criado"
  A5_PEND="$(cat "$A5_VAULT"/pending/*.md 2>/dev/null || true)"
  f2_has "A5-5b pending nasce com status: proposed (ADR-0007)" "$A5_PEND" "status: proposed"
  f2_has "A5-5c pending é endereçável (id: no frontmatter)" "$A5_PEND" "id: "
else
  fail "A5-5 next-entrypoint não virou pending (contagem=$(a5_count pending)) — evaporação por omissão"
fi

# ── A5-6: idempotência — rodar 2× não duplica ──────────────────────────────
A5_OUT="$(a5_run)"
if [ "$(a5_count pending)" = "1" ]; then
  pass "A5-6 hook idempotente: 2 execuções -> 1 pending"
else
  fail "A5-6 hook duplicou pending na 2ª execução (contagem=$(a5_count pending))"
fi

# ── A5-3: contrato legado Summary/Proof/Next Entrypoint também publica ─────
a5_setup kernel-legado
cat > "$A5_VAULT/sessions/2026-08-01-legado.md" <<'A5EOF'
---
next-entrypoint: "consolidar os ADRs da fase 2"
---

# Sessao no formato canuto-brain

## Summary
Consolidei o ledger de delegacao.

## Proof
bash test-framework.sh

## Next Entrypoint
consolidar os ADRs da fase 2
A5EOF
A5_OUT="$(a5_run)"
f2_has "A5-3 contrato legado (Summary/Proof/Next) não é penalizado" "$A5_OUT" "CLOSEOUT PUBLICADO"
f2_has "A5-3b evento legado sai como published" "$(a5_events)" '"status":"published"'

# ── A5-4: nota sem nenhum dos dois contratos -> write-only ─────────────────
a5_setup sem-kernel
printf '# Nota qualquer\n\nTrabalhei em varias coisas hoje.\n' \
  > "$A5_VAULT/sessions/2026-08-01-solta.md"
A5_OUT="$(a5_run)"
f2_has "A5-4 nota sem kernel é nomeada como write-only" "$A5_OUT" "closeout sem intent kernel"
A5_EV="$(a5_events)"
f2_has "A5-4b evento sai como incomplete" "$A5_EV" '"status":"incomplete"'
f2_has "A5-4c evento nomeia a razão" "$A5_EV" '"reason":"no_kernel"'

# ── A5-7: admissão de retrabalho vira nota em rework/ ──────────────────────
a5_setup rework
cat > "$A5_VAULT/sessions/2026-08-01-rework.md" <<'A5EOF'
# Sessao com retrabalho

intent: corrigir o gate de identidade
porque: o brief saia vazio sem dizer que quebrou
proximo: portar os testes para test-framework.sh

Hoje redescobri o mesmo bug de resolucao de slug do mes passado.
A5EOF
A5_OUT="$(a5_run)"
if [ "$(a5_count rework)" = "1" ]; then
  pass "A5-7 admissão de retrabalho virou nota em rework/"
  A5_RW="$(cat "$A5_VAULT"/rework/*.md 2>/dev/null || true)"
  f2_has "A5-7b rework nasce com status: proposed" "$A5_RW" "status: proposed"
else
  fail "A5-7 'redescobri' não gerou nota de rework (contagem=$(a5_count rework))"
fi
A5_OUT="$(a5_run)"
if [ "$(a5_count rework)" = "1" ]; then
  pass "A5-7c rework também é idempotente (2 execuções -> 1 nota)"
else
  fail "A5-7c rework duplicou na 2ª execução (contagem=$(a5_count rework))"
fi

# ── A5-8: menção a segredo alerta por CONTAGEM + LINHA, nunca por conteúdo ──
# Reconciliado com a mitigação S4 (review cego 2026-08-02): a versão anterior
# deste teste exigia o NOME da variável no alerta, mas o extrator de "nomes"
# ([A-Z][A-Z0-9_]{2,}) capturava a própria CHAVE (ex.: AKIA…) e a colava no
# transcript — o oposto do que o alerta promete. O contrato atual é mais
# ESTRITO: o alerta existe, diz QUANTAS referências e EM QUE LINHAS da nota,
# e não copia nada do conteúdo (nem nome, nem valor). Quem precisa do nome
# abre a nota; o log fica limpo.
a5_setup segredo
cat > "$A5_VAULT/sessions/2026-08-01-segredo.md" <<'A5EOF'
# Sessao com segredo

intent: rotacionar credencial exposta
porque: o valor vazou no transcript
proximo: confirmar a rotacao no provedor

Preciso rotacionar TOKEN=abc123 antes do proximo deploy.
A5EOF
A5_OUT="$(a5_run)"
f2_has "A5-8 alerta de segredo aparece no output" "$A5_OUT" "ALERTA"
f2_has "A5-8b alerta cita a CONTAGEM de referências (não o conteúdo)" \
  "$A5_OUT" "referência(s) a segredo"
f2_has "A5-8b2 alerta endereça a nota por linha (auditável sem copiar nada)" \
  "$A5_OUT" "linha(s):"
f2_hasnt "A5-8c alerta NUNCA imprime o valor do segredo" "$A5_OUT" "abc123"
f2_hasnt "A5-8d alerta também não ecoa o NOME da variável (S4)" "$A5_OUT" "TOKEN"

# ── A5-8e: segredo NO KERNEL não vaza para id/arquivo/evento/stdout ─────────
# Gap do review cego 2026-08-02: `_a5_create_pending` embutia o texto CRU (e
# derivava o id/nome de arquivo do slug dele), e os 3 campos do kernel iam
# verbatim para o evento CLOSEOUT_PUBLISHED e para o stdout. Uma nota com
# "proximo: rotacionar TOKEN=abc123" publicava o VALOR em três lugares.
a5_setup segredo-no-kernel
cat > "$A5_VAULT/sessions/2026-08-01-kernel-segredo.md" <<'A5EOF'
# Sessao com segredo no kernel

intent: fechar o gap de redacao do kernel
porque: o valor ia verbatim para o evento e para o stdout
proximo: rotacionar TOKEN=abc123 no provedor
A5EOF
A5_OUT="$(a5_run)"
f2_hasnt "A5-8e valor do kernel não vaza no stdout do hook" "$A5_OUT" "abc123"
f2_has "A5-8e2 kernel redigido preserva o NOME e mata o VALOR" "$A5_OUT" "TOKEN=<redigido>"
A5_LEAK=""
for A5_D in pending events; do
  [ -d "$A5_VAULT/$A5_D" ] || continue
  if grep -rq 'abc123' "$A5_VAULT/$A5_D" 2>/dev/null; then
    A5_LEAK="$A5_LEAK $A5_D/"
  fi
done
if [ -z "$A5_LEAK" ]; then
  pass "A5-8f valor do kernel não vazou para pending/ nem events/"
else
  fail "A5-8f VALOR DE SEGREDO do kernel vazou para:$A5_LEAK"
fi
A5_PENDNAMES="$(ls "$A5_VAULT/pending" 2>/dev/null || true)"
f2_hasnt "A5-8g nome do arquivo do pending não carrega o valor do segredo" \
  "$A5_PENDNAMES" "abc123"
f2_has "A5-8h pending foi criado mesmo assim (redação não engole a thread)" \
  "$A5_PENDNAMES" "redigido"

# ── A5-9: EXTRA — retrabalho e segredo na MESMA linha ──────────────────────
# Gap declarado no recibo A5 (§2.5) e mitigado depois com redação `=<redigido>`
# em _a5_create_rework. Sem este teste a mitigação some no próximo refactor:
# a evidência de rework é copiada VERBATIM para a nota nova, então uma linha
# "redescobri ... TOKEN=<valor>" levaria o segredo para um arquivo novo.
a5_setup segredo-na-linha-do-rework
cat > "$A5_VAULT/sessions/2026-08-01-misto.md" <<'A5EOF'
# Sessao com segredo na linha do retrabalho

intent: fechar o gap de redacao
porque: evidencia de rework era copiada verbatim
proximo: rodar o test-framework

Hoje redescobri que precisava rotacionar TOKEN=abc123 de novo.
A5EOF
A5_OUT="$(a5_run)"
if [ "$(a5_count rework)" = "1" ]; then
  pass "A5-9 nota de rework criada mesmo com segredo na mesma linha"
else
  fail "A5-9 rework não foi criado (contagem=$(a5_count rework))"
fi
A5_LEAK=""
for A5_D in rework pending events; do
  [ -d "$A5_VAULT/$A5_D" ] || continue
  if grep -rq 'abc123' "$A5_VAULT/$A5_D" 2>/dev/null; then
    A5_LEAK="$A5_LEAK $A5_D/"
  fi
done
if [ -z "$A5_LEAK" ]; then
  pass "A5-9b valor do segredo não vazou para rework/, pending/ nem events/"
else
  fail "A5-9b VALOR DE SEGREDO vazou para:$A5_LEAK (redação de _a5_create_rework quebrou)"
fi
f2_hasnt "A5-9c valor do segredo não vaza no stdout do hook" "$A5_OUT" "abc123"
A5_RW="$(cat "$A5_VAULT"/rework/*.md 2>/dev/null || true)"
f2_has "A5-9d a evidência foi redigida (prova de que é mitigação, não acaso)" \
  "$A5_RW" "=<redigido>"
# Nota conhecida e aceita: <vault>/.snapshots/ guarda cópia byte-a-byte da nota
# ORIGINAL (backup pré-existente ao A5), então o valor continua lá — por isso a
# asserção acima é sobre os arquivos que ESTE mecanismo cria.

# ── A5-10: regressão dos backends que não têm vault ────────────────────────
# Backend offline não pode alcançar nenhum código novo (set -u veria $VAULT_DIR
# não-vinculado se alcançasse).
A5_OFF="$A5_ROOT/offline"
mkdir -p "$A5_OFF/proj/.agents/tools" "$A5_OFF/home" "$A5_OFF/tmp"
cp "$AGENTS_DIR/tools/canuto-memory.sh" "$AGENTS_DIR/tools/event-log.sh" \
   "$A5_OFF/proj/.agents/tools/" 2>/dev/null || true
A5_OFF_RC=0
A5_OUT=$(HOME="$A5_OFF/home" CANUTO_VAULT_DIR="$A5_OFF/vault-inexistente" \
  CANUTO_SLUG_NO_CACHE=1 CLAUDE_PROJECT_DIR="$A5_OFF/proj" TMPDIR="$A5_OFF/tmp" \
  bash "$A5_HOOK" 2>&1) || A5_OFF_RC=$?
if [ "$A5_OFF_RC" -eq 0 ]; then
  f2_has "A5-10 backend offline segue no caminho antigo (OFFLINE Save)" "$A5_OUT" "OFFLINE Save"
  f2_hasnt "A5-10b backend offline não menciona kernel" "$A5_OUT" "intent kernel"
else
  fail "A5-10 hook quebrou no backend offline (rc=$A5_OFF_RC)"
fi

# ── A5-11: sintaxe nos dois shells ─────────────────────────────────────────
if bash -n "$A5_HOOK" 2>/dev/null; then
  pass "A5-11a session-save.sh: bash -n"
else
  fail "A5-11a session-save.sh: erro de sintaxe (bash -n)"
fi
if command -v zsh >/dev/null 2>&1; then
  if zsh -n "$A5_HOOK" 2>/dev/null; then
    pass "A5-11b session-save.sh: zsh -n"
  else
    fail "A5-11b session-save.sh: erro de sintaxe (zsh -n)"
  fi
fi

rm -rf "$A5_ROOT"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# TEST 18: Ledger de pendências de delegação (Fase 2 — A2b)
# ═══════════════════════════════════════════════════════════════════════════
# "Fallback nunca é silencioso" não se sustentava como prompt (42 falhas de
# delegação -> 3 declarações). O ledger torna a pendência um FOLD mecânico:
# só dead-letter COM RAZÃO ou fallback declarado fecham (eoc ADR-0017:
# "an autonomous grill may only park, never fabricate acknowledged").
echo "── Test 18: Ledger de delegação (A2b) ──"

LEDGER="$AGENTS_DIR/tools/delegation-ledger.sh"
A2_SB="$(mktemp -d "${TMPDIR:-/tmp}/canuto-a2b.XXXXXX")"
A2_METRICS="$A2_SB/metrics.jsonl"
A2_ID_ERR="2026-08-01T10:05:00Z"
A2_ID_TMO="2026-08-01T10:10:00Z"
A2_ID_OUTRO="2026-08-01T10:20:00Z"
A2_ID_SEMCWD="2026-08-01T10:30:00Z"
mkdir -p "$A2_SB/proj" "$A2_SB/home" "$A2_SB/tmp"
# CANUTO_VAULT_DIR aponta para um vault inexistente de propósito: o backend cai
# em `none` e o event log fica DENTRO do sandbox, nunca no vault real. E
# CANUTO_METRICS_FILE substitui ~/.codex/delegate-metrics.jsonl.
#
# Heredoc NÃO-quotado (review cego 2026-08-02): as métricas são globais e os
# fechamentos por projeto, então o fold passou a recortar por `cwd`. As
# fixtures precisam de cwd REAL do sandbox para exercitar o recorte — e
# incluem de propósito uma linha de OUTRO projeto e uma linha ANTIGA sem cwd.
cat > "$A2_METRICS" <<A2EOF
{"ts":"2026-08-01T10:00:00Z","role":"coder","result":"OK","reason":"","out":"/tmp/ok.md","cwd":"$A2_SB/proj"}
{"ts":"2026-08-01T10:05:00Z","role":"coder","result":"ERROR","reason":"exit 4","out":"/tmp/a.md","cwd":"$A2_SB/proj"}
{"ts":"2026-08-01T10:10:00Z","role":"reviewer","result":"TIMEOUT","reason":"600s","out":"/tmp/b.md","cwd":"$A2_SB/proj/pacote/x"}
{"ts":"2026-08-01T10:20:00Z","role":"coder","result":"ERROR","reason":"falha do projeto B","out":"/tmp/z.md","cwd":"$A2_SB/outro-projeto"}
{"ts":"2026-08-01T10:30:00Z","role":"coder","result":"ERROR","reason":"linha antiga sem cwd","out":"/tmp/y.md"}
A2EOF

A2_OUT=""; A2_ERR=""; A2_RC=0
a2_run() {
  A2_RC=0
  A2_OUT=$(
    HOME="$A2_SB/home" CANUTO_METRICS_FILE="$A2_METRICS" \
    CANUTO_VAULT_DIR="$A2_SB/vault-inexistente" CANUTO_SLUG_NO_CACHE=1 \
    CLAUDE_PROJECT_DIR="$A2_SB/proj" TMPDIR="$A2_SB/tmp" \
    CANUTO_LEDGER_ALL="${A2_ALL:-0}" \
      bash "$LEDGER" "$@" 2>"$A2_SB/.err"
  ) || A2_RC=$?
  A2_ERR="$(cat "$A2_SB/.err" 2>/dev/null || true)"
}
a2_pending_count() { printf '%s' "$A2_OUT" | grep -c . || true; }

# ── A2b-1: fold — só as não-OK DESTE projeto (2 de 5 linhas) ───────────────
a2_run pending
f2_eq "A2b-1 fold lista só as não-OK deste projeto (5 linhas -> 2)" "2" "$(a2_pending_count)"
f2_has "A2b-1b pendência nomeia o id do ERROR" "$A2_OUT" "$A2_ID_ERR"
f2_has "A2b-1c pendência de SUBDIRETÓRIO do projeto conta como do projeto" "$A2_OUT" "$A2_ID_TMO"
f2_hasnt "A2b-1d delegação OK não entra no fold" "$A2_OUT" "2026-08-01T10:00:00Z"

# ── A2b-1e/f/g: escopo de projeto (métricas globais, fechamentos por projeto)
# Sem o recorte, todo projeto listava o backlog global inteiro no primeiro Stop
# e um dead-letter feito no projeto B nunca fechava a linha no projeto A.
f2_hasnt "A2b-1e falha de OUTRO projeto não polui o Stop deste" "$A2_OUT" "$A2_ID_OUTRO"
f2_hasnt "A2b-1f linha antiga sem cwd fica fora por default (limitação documentada)" \
  "$A2_OUT" "$A2_ID_SEMCWD"
f2_has "A2b-1g recorte não é silencioso: stderr conta as omitidas" "$A2_ERR" "CANUTO_LEDGER_ALL=1"
A2_ALL=1
a2_run pending
f2_eq "A2b-1h CANUTO_LEDGER_ALL=1 desliga o filtro (backlog global = 4)" "4" "$(a2_pending_count)"
f2_has "A2b-1i com ALL=1 a falha do outro projeto reaparece" "$A2_OUT" "$A2_ID_OUTRO"
f2_has "A2b-1j com ALL=1 a linha sem cwd reaparece" "$A2_OUT" "$A2_ID_SEMCWD"
A2_ALL=0
a2_run pending

# ── A2b-2/3: dead-letter SEM razão é recusado (não se fabrica fechamento) ──
a2_run dead-letter "$A2_ID_ERR" ""
if [ "$A2_RC" -eq 1 ]; then
  f2_has "A2b-2 dead-letter sem razão sai 1 nomeando o id" "$A2_ERR" "$A2_ID_ERR"
else
  fail "A2b-2 dead-letter aceitou razão vazia (rc=$A2_RC) — park fabricado"
fi
a2_run dead-letter "$A2_ID_ERR" "   "
if [ "$A2_RC" -eq 1 ]; then
  pass "A2b-3 dead-letter com razão só-espaço também é recusado"
else
  fail "A2b-3 dead-letter aceitou razão em branco (rc=$A2_RC)"
fi
a2_run pending
f2_eq "A2b-3b recusa não fecha nada: as 2 pendências continuam" "2" "$(a2_pending_count)"

# ── A2b-4: dead-letter COM razão fecha o id ────────────────────────────────
a2_run dead-letter "$A2_ID_ERR" "sandbox: resgatado manualmente"
if [ "$A2_RC" -eq 0 ]; then
  pass "A2b-4 dead-letter com razão é aceito"
else
  fail "A2b-4 dead-letter com razão falhou (rc=$A2_RC): $A2_ERR"
fi
a2_run pending
f2_eq "A2b-4b id com dead-letter sai do fold (2 -> 1)" "1" "$(a2_pending_count)"
f2_hasnt "A2b-4c o id fechado não reaparece" "$A2_OUT" "$A2_ID_ERR"

# ── A2b-5: fallback declarado também fecha ─────────────────────────────────
a2_run declare-fallback "$A2_ID_TMO" claude-direct
if [ "$A2_RC" -eq 0 ]; then
  pass "A2b-5 declare-fallback é aceito"
else
  fail "A2b-5 declare-fallback falhou (rc=$A2_RC): $A2_ERR"
fi
a2_run pending
f2_eq "A2b-5b fallback declarado esvazia o fold (1 -> 0)" "0" "$(a2_pending_count)"

# ── A2b-6: linha malformada no metrics não derruba o fold ──────────────────
{
  printf 'not-json-garbage\n'
  printf '{"ts":truncated-broken-line\n'
  printf '{"ts":"2026-08-01T11:00:00Z","role":"coder","result":"ERROR","reason":"x","out":"/tmp/c.md","cwd":"%s"}\n' "$A2_SB/proj"
} >> "$A2_METRICS"
a2_run pending
f2_eq "A2b-6 linhas malformadas são puladas e a válida seguinte aparece" "1" "$(a2_pending_count)"
f2_has "A2b-6b a pendência válida após o lixo é listada" "$A2_OUT" "2026-08-01T11:00:00Z"

# ── A2b-7: uso incorreto é erro de uso, não fechamento silencioso ──────────
a2_run dead-letter
f2_eq "A2b-7 dead-letter sem argumentos sai 64 (erro de uso)" "64" "$A2_RC"
a2_run declare-fallback "$A2_ID_TMO"
f2_eq "A2b-7b declare-fallback sem executor sai 64" "64" "$A2_RC"

# ── A2b-8: sintaxe nos dois shells ─────────────────────────────────────────
if bash -n "$LEDGER" 2>/dev/null; then
  pass "A2b-8a delegation-ledger.sh: bash -n"
else
  fail "A2b-8a delegation-ledger.sh: erro de sintaxe (bash -n)"
fi
if command -v zsh >/dev/null 2>&1; then
  if zsh -n "$LEDGER" 2>/dev/null; then
    pass "A2b-8b delegation-ledger.sh: zsh -n"
  else
    fail "A2b-8b delegation-ledger.sh: erro de sintaxe (zsh -n)"
  fi
fi

rm -rf "$A2_SB"
echo ""

# ═══════════════════════════════════════════════════════════════════════════
# TEST 19: Cobertura dos ADR-0005 (aging) e ADR-0006 (revisor cego)
# ═══════════════════════════════════════════════════════════════════════════
# Gap conhecido: os dois ADRs tinham decisão escrita e ZERO teste. Um muro que
# ninguém verifica é um muro que já caiu e ninguém viu.
echo "── Test 19: ADR-0005 (aging) / ADR-0006 (revisor cego) ──"

# ── 19a. instinct-aging: decay é por ESCASSEZ, não por tempo ───────────────
# O tier curado (medium/high) é EXENTO por mais velho que esteja: idade sozinha
# nunca arquiva. O gatilho é a escassez de confirmação (confidence: low).
AGING="$AGENTS_DIR/tools/instinct-aging.sh"
if [ ! -f "$AGING" ]; then
  fail "19a instinct-aging.sh ausente (ADR-0005 sem implementação)"
else
  IA_SB="$(mktemp -d "${TMPDIR:-/tmp}/canuto-aging.XXXXXX")"
  IA_SLUG="instinct-aging-test"
  IA_INST="$IA_SB/vault/projects/$IA_SLUG/instincts"
  mkdir -p "$IA_SB/proj" "$IA_INST" "$IA_SB/home" "$IA_SB/tmp"
  printf 'project-slug: %s\n' "$IA_SLUG" > "$IA_SB/proj/CLAUDE.md"
  cat > "$IA_INST/velho-low.md" <<'IAEOF'
---
id: velho-low
confidence: low
last-seen: 2020-01-01
---
# hipotese velha e nunca reconfirmada
IAEOF
  cat > "$IA_INST/velho-high.md" <<'IAEOF'
---
id: velho-high
confidence: high
last-seen: 2020-01-01
---
# curado, igualmente velho
IAEOF
  cat > "$IA_INST/novo-low.md" <<IAEOF
---
id: novo-low
confidence: low
last-seen: $(date +%Y-%m-%d)
---
# hipotese recente
IAEOF
  ia_run() {
    HOME="$IA_SB/home" CANUTO_VAULT_DIR="$IA_SB/vault" CANUTO_SLUG_NO_CACHE=1 \
    CLAUDE_PROJECT_DIR="$IA_SB/proj" TMPDIR="$IA_SB/tmp" \
      bash "$AGING" "$1" 2>&1 || true
  }
  IA_OUT="$(ia_run --dry-run)"
  f2_has "19a hipótese escassa e velha é candidata a arquivamento" "$IA_OUT" "velho-low"
  f2_hasnt "19a2 DECAY É POR ESCASSEZ: instinct curado (high) igualmente velho é EXENTO" \
    "$IA_OUT" "velho-high"
  f2_hasnt "19a3 hipótese recente não é candidata" "$IA_OUT" "novo-low"

  IA_OUT="$(ia_run --apply)"
  if [ -f "$IA_INST/velho-low.md" ]; then
    pass "19a4 aging NUNCA deleta: o arquivo continua no vault"
  else
    fail "19a4 aging DELETOU o instinct (ADR-0005 manda arquivar, nunca apagar)"
  fi
  if grep -q '^status: archived' "$IA_INST/velho-low.md" 2>/dev/null; then
    pass "19a5 arquivamento é uma transição de status no frontmatter"
  else
    fail "19a5 --apply não marcou 'status: archived' em velho-low.md"
  fi
  if grep -q '^status: archived' "$IA_INST/velho-high.md" 2>/dev/null; then
    fail "19a6 --apply arquivou um instinct CURADO (tier medium/high deve ser intocado)"
  else
    pass "19a6 --apply não tocou o tier curado"
  fi
  rm -rf "$IA_SB"
fi

# ── 19b. blind-reviewer: o muro é MECÂNICO, não uma promessa em prosa ──────
# ADR-0006: a cegueira do revisor vale pelo que ele estruturalmente NÃO TEM.
# Se `tools:` ganhar Bash/Edit/Write, o revisor passa a executar e consertar —
# e o co-review vira o mesmo agente se auto-aprovando. O frontmatter É o muro.
BR_FILE="$FRAMEWORK_DIR/.claude/agents/blind-reviewer.md"
if [ ! -f "$BR_FILE" ]; then
  fail "19b .claude/agents/blind-reviewer.md ausente (ADR-0006 sem agente)"
else
  BR_TOOLS=$(awk 'NR==1&&$0=="---"{i=1;next} i&&$0=="---"{exit} i&&/^tools:/{sub(/^tools:[[:space:]]*/,"");print;exit}' "$BR_FILE" 2>/dev/null || true)
  if [ -z "$BR_TOOLS" ]; then
    fail "19b blind-reviewer.md sem 'tools:' no frontmatter — sem allowlist, o agente herda TUDO"
  else
    pass "19b blind-reviewer.md declara allowlist de tools"
    if printf '%s' "$BR_TOOLS" | grep -qE '(^|[,[:space:]])(Bash|Edit|Write|NotebookEdit|MultiEdit)([,[:space:]([]|$)'; then
      fail "19b2 blind-reviewer ganhou ferramenta de execução/escrita ('$BR_TOOLS') — o muro do ADR-0006 caiu"
    else
      pass "19b2 blind-reviewer sem Bash/Edit/Write (muro do ADR-0006 de pé)"
    fi
    if printf '%s' "$BR_TOOLS" | grep -q 'Read'; then
      pass "19b3 blind-reviewer mantém Read (consegue ler o artefato que julga)"
    else
      fail "19b3 blind-reviewer sem Read — não consegue nem ler o que revisa"
    fi
  fi
  if grep -q 'blind-reviewer.md' "$FRAMEWORK_DIR/install.sh" 2>/dev/null; then
    pass "19b4 blind-reviewer.md está na lista de distribuição do install.sh"
  else
    fail "19b4 blind-reviewer.md fora do install.sh — o muro não chega a repo consumidor"
  fi
fi

# ── 19c. As libs da Fase 2 precisam CHEGAR ao repo consumidor ──────────────
# Test 11c já cobre skills; ferramenta nova não era coberta por nada. Uma lib
# que existe no repo mas não é distribuída é o buraco exato que deixou o event
# log morto em ~90% dos projetos consumidores (auditoria 2026-08-01): a cascata
# `~/.canuto/lib/<lib>.sh` dos hooks nunca resolve e a degradação é silenciosa.
# Dois wirings, independentes: a lista de arquivos E o loop de libs globais.
for F2_LIB in brief-compose.sh memory-usage.sh delegation-ledger.sh; do
  if [ ! -f "$AGENTS_DIR/tools/$F2_LIB" ]; then
    fail "19c lib da Fase 2 ausente do repo: .agents/tools/$F2_LIB"
    continue
  fi
  if grep -qF "\".agents/tools/$F2_LIB\"" "$FRAMEWORK_DIR/install.sh" 2>/dev/null; then
    pass "19c $F2_LIB está na lista de distribuição do install.sh"
  else
    fail "19c $F2_LIB fora de FRAMEWORK_FILES — não é copiada para o repo consumidor"
  fi
  if grep -qE "^[[:space:]]*for lib in .*\b${F2_LIB}( |;)" "$FRAMEWORK_DIR/install.sh" 2>/dev/null \
     || grep -qE "^[[:space:]]*for lib in .*${F2_LIB}\b" "$FRAMEWORK_DIR/install.sh" 2>/dev/null; then
    pass "19c2 $F2_LIB entra em ~/.canuto/lib (cascata de fallback dos hooks)"
  else
    fail "19c2 $F2_LIB fora de install_global_fallback_libs — hook em install antigo degrada calado"
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
