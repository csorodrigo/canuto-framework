#!/usr/bin/env bash
# =============================================================================
# Canuto Framework — Installer / Updater
# Usage:
#   Fresh install:    curl -fsSL https://raw.githubusercontent.com/csorodrigo/canuto-framework/main/install.sh | bash
#   Local run:        bash install.sh
#   Update only:      bash install.sh --update
#   Update via curl:  curl -fsSL https://raw.githubusercontent.com/csorodrigo/canuto-framework/main/install.sh | bash -s -- --update
#   Check versions:   bash install.sh --check
#   Smoke test:       bash install.sh --test
#   Repair runtime:   bash install.sh --repair
#   Doctor mode:      bash install.sh --doctor
#   Migrate from v1:  bash install.sh --migrate
#   With API key:     bash install.sh --migrate --api-key YOUR_OBSIDIAN_API_KEY
#   Via curl + key:   curl ... | bash -s -- --migrate --api-key YOUR_KEY
#   Install a skill:  bash install.sh --skill pr-description --skill health-check
#   JSON health:      bash install.sh --test --json
# =============================================================================

set -euo pipefail

REPO_URL="https://raw.githubusercontent.com/csorodrigo/canuto-framework/main"
AGENTS_DIR=".agents"
CLAUDE_MD="CLAUDE.md"
TMP_DIR=$(mktemp -d)
MODE="auto" # auto | install | update | check | skill | migrate | repair | doctor | test
ORIGINAL_ARGS=("$@")
SCRIPT_SOURCE="${BASH_SOURCE[0]:-$0}"
SKILLS_TO_INSTALL=()
JSON_OUTPUT=false
AUTO_YES=false

# ── Colors ─────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
RESET='\033[0m'

log()    { echo -e "${CYAN}[canuto]${RESET} $1"; }
ok()     { echo -e "${GREEN}[canuto]${RESET} \u2713 $1"; }
warn()   { echo -e "${YELLOW}[canuto]${RESET} \u26a0 $1"; }
error()  { echo -e "${RED}[canuto]${RESET} \u2717 $1"; exit 1; }

# ── Parse args ──────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --update) MODE="update" ;;
    --check)   MODE="check"   ;;
    --test)    MODE="test"    ;;
    --migrate) MODE="migrate" ;;
    --repair)  MODE="repair"  ;;
    --doctor|--health) MODE="doctor" ;;
    --json) JSON_OUTPUT=true ;;
    --yes) AUTO_YES=true ;;
    --skill)
      shift
      SKILLS_TO_INSTALL+=("$1")
      ;;
    --api-key)
      shift
      OBSIDIAN_API_KEY_ARG="$1"
      ;;
  esac
  shift
done

# ── Detect mode ──────────────────────────────────────────────────────────────
if [ "$MODE" = "auto" ]; then
  if [ "${#SKILLS_TO_INSTALL[@]}" -gt 0 ]; then
    MODE="skill"
  elif [ -d "$AGENTS_DIR" ]; then
    MODE="update"
  else
    MODE="install"
  fi
fi

is_interactive() {
  [[ -t 0 ]]
}

confirm_yes() {
  local prompt="$1"
  local default_answer="${2:-Y}"
  local answer=""

  if [ "$AUTO_YES" = true ] || ! is_interactive; then
    answer="$default_answer"
  else
    read -r -p "$(echo -e "${CYAN}[canuto]${RESET} $prompt")" answer
    answer="${answer:-$default_answer}"
  fi

  [[ "$answer" =~ ^[Yy]$ ]]
}

# ── Confirm not running install/update flows in the framework repo itself ───
if git remote -v 2>/dev/null | grep -q "canuto-framework"; then
  case "$MODE" in
    install|update|migrate|skill)
      warn "This looks like the canuto-framework repo itself. Aborting."
      exit 0
      ;;
  esac
fi

# ── setup_deps ──────────────────────────────────────────────────────────────
# Ensures required CLI tools are available, installing via brew when possible.
setup_deps() {
  # brew — package manager for macOS (install all other deps via brew)
  local has_brew=false
  if command -v brew &> /dev/null; then
    has_brew=true
    ok "brew $(brew --version | head -1) already installed"
  elif [[ "$OSTYPE" == "darwin"* ]]; then
    log "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
      && has_brew=true && ok "Homebrew installed" \
      || warn "Failed to install Homebrew — install manually: https://brew.sh"
  else
    warn "brew not available (non-macOS). Install jq and ast-grep manually."
  fi

  # jq — required for hooks and MCP setup
  if ! command -v jq &> /dev/null; then
    if $has_brew; then
      log "Installing jq via Homebrew..."
      brew install jq 2>/dev/null && ok "jq installed" || warn "Failed to install jq — install manually: brew install jq"
    else
      warn "jq not found and brew unavailable. Install manually: brew install jq"
      warn "Hooks and MCP setup will be skipped."
    fi
  else
    ok "jq $(jq --version) already installed"
  fi

  # node / npx — required for ast-grep MCP server
  if ! command -v node &> /dev/null; then
    warn "node not found — ast-grep MCP server requires Node.js."
    if $has_brew; then
      warn "Install with: brew install node"
    else
      warn "Install from: https://nodejs.org"
    fi
  else
    ok "node $(node --version) already installed"
  fi

  # uv / uvx — required for codex-as-mcp
  if ! command -v uvx &> /dev/null; then
    if $has_brew; then
      log "Installing uv via Homebrew..."
      brew install uv 2>/dev/null && ok "uv/uvx installed" || warn "Failed to install uv — install manually: brew install uv"
    else
      warn "uvx not found and brew unavailable. Install manually: brew install uv"
    fi
  else
    ok "uvx available"
  fi
}

# ── Check git availability ──────────────────────────────────────────────────
if ! git rev-parse --git-dir > /dev/null 2>&1; then
  warn "Not a git repository. Files will be copied but not committed."
  GIT_AVAILABLE=false
else
  GIT_AVAILABLE=true
fi

# ── Download helper ─────────────────────────────────────────────────────────
download() {
  local remote_path="$1"
  local local_path="$2"
  local dir
  dir=$(dirname "$local_path")
  mkdir -p "$dir"
  if command -v curl > /dev/null 2>&1; then
    curl -fsSL "$REPO_URL/$remote_path" -o "$local_path"
  elif command -v wget > /dev/null 2>&1; then
    wget -q "$REPO_URL/$remote_path" -O "$local_path"
  else
    error "Neither curl nor wget found. Install one and retry."
  fi
}

# Fetch helper (returns content, no write)
fetch_content() {
  local remote_path="$1"
  if command -v curl > /dev/null 2>&1; then
    curl -fsSL "$REPO_URL/$remote_path" 2>/dev/null
  elif command -v wget > /dev/null 2>&1; then
    wget -q "$REPO_URL/$remote_path" -O - 2>/dev/null
  fi
}

should_refresh_installer() {
  case "$MODE" in
    install|update|check|skill|migrate|repair|doctor)
      ;;
    *)
      return 1
      ;;
  esac

  [ "${CANUTO_BOOTSTRAPPED:-0}" = "1" ] && return 1

  if git remote -v 2>/dev/null | grep -q "canuto-framework"; then
    return 1
  fi

  case "$SCRIPT_SOURCE" in
    /dev/fd/*|/proc/*|stdin|-)
      return 1
      ;;
  esac

  [ -f "$SCRIPT_SOURCE" ]
}

refresh_from_remote_installer_if_needed() {
  if ! should_refresh_installer; then
    return
  fi

  if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
    warn "Could not refresh installer from main (curl/wget missing). Continuing with local copy."
    return
  fi

  log "Refreshing installer from main before proceeding..."
  local remote_installer="$TMP_DIR/install.remote.sh"
  if download "install.sh" "$remote_installer"; then
    chmod +x "$remote_installer"
    CANUTO_BOOTSTRAPPED=1 bash "$remote_installer" "${ORIGINAL_ARGS[@]}"
    exit $?
  fi

  warn "Failed to refresh installer from main. Continuing with local copy."
}

refresh_from_remote_installer_if_needed

skill_remote_files() {
  local skill_name="$1"
  case "$skill_name" in
    context-maintenance)
      printf '%s\n' \
        ".agents/skills/context-maintenance/SKILL.md" \
        ".agents/skills/context-maintenance/references/evaluate-repo-pipeline.md" \
        ".agents/skills/context-maintenance/references/examples.md"
      ;;
    continuous-learning)
      printf '%s\n' \
        ".agents/skills/continuous-learning/SKILL.md" \
        ".agents/skills/continuous-learning/references/instinct-promotion.md" \
        ".agents/skills/continuous-learning/references/examples.md"
      ;;
    frontend-design)
      printf '%s\n' \
        ".agents/skills/frontend-design/SKILL.md" \
        ".agents/skills/frontend-design/references/design-patterns.md" \
        ".agents/skills/frontend-design/references/aesthetic-patterns.md"
      ;;
    *)
      printf '%s\n' ".agents/skills/${skill_name}.md"
      ;;
  esac
}

# ── File lists ──────────────────────────────────────────────────────────────

FRAMEWORK_FILES=(
  ".agents/personas/maestro.md"
  ".agents/personas/architect.md"
  ".agents/personas/coder.md"
  ".agents/personas/tester.md"
  ".agents/personas/debugger.md"
  ".agents/personas/reviewer.md"
  ".agents/personas/contextualizer.md"
  ".agents/skills/context-maintenance/SKILL.md"
  ".agents/skills/context-maintenance/references/evaluate-repo-pipeline.md"
  ".agents/skills/context-maintenance/references/examples.md"
  ".agents/skills/api-design.md"
  ".agents/skills/frontend-implementation.md"
  ".agents/skills/cli-usage.md"
  ".agents/skills/security-practices.md"
  ".agents/skills/git-workflow.md"
  ".agents/skills/plugin-system.md"
  ".agents/skills/multi-provider.md"
  ".agents/skills/metrics.md"
  ".agents/skills/squads.md"
  ".agents/skills/pr-description.md"
  ".agents/skills/health-check.md"
  ".agents/skills/stack-lock.md"
  ".agents/skills/plan-second-opinion.md"
  ".agents/hooks/plan-review.sh"
  ".agents/hooks/codex-pretool-guard.sh"
  ".agents/hooks/session-save.sh"
  ".agents/hooks/session-load.sh"
  ".agents/hooks/pre-compact-save.sh"
  ".agents/skills/continuous-learning/SKILL.md"
  ".agents/skills/continuous-learning/references/instinct-promotion.md"
  ".agents/skills/continuous-learning/references/examples.md"
  ".agents/skills/absence-reporting.md"
  ".agents/skills/cross-persona-flags.md"
  ".agents/skills/coverage-tracking.md"
  ".agents/skills/budget-controls.md"
  ".agents/skills/governance.md"
  ".agents/skills/audit-trail.md"
  ".agents/skills/runtime-flags.md"
  ".agents/skills/convergence-detection.md"
  ".agents/skills/heartbeat.md"
  ".agents/skills/product-review.md"
  ".agents/skills/browser-qa.md"
  ".agents/skills/session-goals.md"
  ".agents/skills/adr.md"
  ".agents/skills/brand-bootstrap.md"
  ".agents/skills/frontend-design/SKILL.md"
  ".agents/skills/frontend-design/references/design-patterns.md"
  ".agents/skills/frontend-design/references/aesthetic-patterns.md"
  ".agents/skills/api-docs-fetch.md"
  ".agents/skills/defuddle.md"
  ".agents/skills/obsidian-markdown.md"
  ".agents/skills/obsidian-bases.md"
  ".agents/skills/json-canvas.md"
  ".agents/skills/mcp-obsidian.md"
  ".agents/skills/obsidian-cli.md"
  ".agents/skills/obsidian-markdown/references/CALLOUTS.md"
  ".agents/skills/obsidian-markdown/references/EMBEDS.md"
  ".agents/skills/obsidian-markdown/references/PROPERTIES.md"
  ".agents/skills/obsidian-bases/references/FUNCTIONS_REFERENCE.md"
  ".agents/skills/json-canvas/references/EXAMPLES.md"
  ".agents/SPEC.md"
  # Codex integration skills (Fase 2+3)
  ".agents/skills/co-review/SKILL.md"
  ".agents/skills/parallel-impl.md"
  ".agents/skills/codex-test-fix.md"
  ".agents/skills/competition.md"
  ".agents/skills/codex-security-gate.md"
  ".agents/skills/cost-routing.md"
  ".agents/skills/context-digest.md"
  ".agents/skills/context-preload.md"
  ".agents/skills/codex-browser-qa.md"
  ".agents/mcp/codex-collab.md"
  ".agents/tools/vault-bridge.sh"
  ".agents/tools/codex-common.sh"
  ".agents/tools/codex-diff-context.sh"
  ".agents/tools/codex-context-package.sh"
  ".agents/tools/codex-health-check.sh"
  ".agents/tools/canuto-consumer-smoke.sh"
  # Codex economy + integration skills (Fase 3)
  ".agents/skills/codex-context-loader.md"
  ".agents/skills/codex-session-writer.md"
  ".agents/skills/codex-pr-writer.md"
  ".agents/skills/smart-token-metering.md"
  ".agents/skills/codex-github-ops.md"
  ".agents/skills/codex-refactor-prep.md"
  ".agents/skills/lazy-opus-review.md"
  ".agents/skills/codex-onboarding.md"
  ".agents/skills/codex-multi-vault.md"
  ".agents/skills/codex-smoke-test.md"
)

INSTALL_ONLY_FILES=(
  ".agents/vault/_index.md"
  ".agents/vault/.obsidian/app.json"
  ".agents/vault/.obsidian/community-plugins.json"
  ".agents/vault/.obsidian/core-plugins.json"
  ".agents/vault/.obsidian/.gitignore"
  ".agents/vault/repo-index.json"
  ".agents/mcp/server.json"
  ".agents/mcp/setup.md"
  ".agents/stack.md"
  "docs/CLAUDE-EXAMPLES.md"
)

# Vault directories to create (no files to download, just mkdir)
VAULT_DIRS=(
  ".agents/vault/sessions"
  ".agents/vault/decisions"
  ".agents/vault/instincts"
  ".agents/vault/pending"
  ".agents/vault/audit"
  ".agents/vault/metrics"
  ".agents/vault/design"
  ".agents/vault/design/components"
  ".agents/vault/bases"
  ".agents/vault/canvas"
  ".agents/vault/digests"
)

# ── merge_claude_md ─────────────────────────────────────────────────────────
# Creates CLAUDE.md if missing.
# If it exists: adds missing top-level sections AND patches missing rules
# inside existing sections. Safe to run multiple times (idempotent).
merge_claude_md() {
  if [ ! -f "$CLAUDE_MD" ]; then
    download "CLAUDE.md" "$CLAUDE_MD"
    ok "$CLAUDE_MD created"
    return
  fi

  log "$CLAUDE_MD already exists — checking for missing sections and rules..."
  local appended=0

  # ── Section: ## Framework ──────────────────────────────────────────────
  if ! grep -q "^## Framework" "$CLAUDE_MD" 2>/dev/null; then
    cat >> "$CLAUDE_MD" << 'SECTION'

## Framework
- Location: .agents/
- Always act as the **Maestro** persona defined in the framework.
- Delegate to other personas as defined in their playbooks.
SECTION
    ok "  added: ## Framework"
    appended=1
  fi

  # ── Section: ## Preferences ────────────────────────────────────────────
  if ! grep -q "^## Preferences" "$CLAUDE_MD" 2>/dev/null; then
    cat >> "$CLAUDE_MD" << 'SECTION'

## Preferences
- tests: required
- handoff-verbosity: explicit
- session-briefing: true
SECTION
    ok "  added: ## Preferences"
    appended=1
  fi

  # ── Section: ## Project Rules ──────────────────────────────────────────
  if ! grep -q "^## Project Rules" "$CLAUDE_MD" 2>/dev/null; then
    # Section missing entirely — add the full block
    cat >> "$CLAUDE_MD" << 'SECTION'

## Project Rules
- Before finalizing any plan, always interview the user in detail using AskUserQuestion about implementation choices, UI/UX decisions, trade-offs, and concerns. Never assume — always ask first.
- Read any .context.md and docs/FEATURE-MAP.md files if they exist.
- If they do not exist, have the Contextualizer create them (with approval).
- Never run Git or shell commands without explicit confirmation.
- When in doubt, ask questions instead of guessing.
SECTION
    ok "  added: ## Project Rules (full block)"
    appended=1
  else
    # Section exists — patch individual missing rules
    if ! grep -q "AskUserQuestion" "$CLAUDE_MD" 2>/dev/null; then
      # Insert planning-interview rule as first item under ## Project Rules
      awk '/^## Project Rules/{
        print
        print "- Before finalizing any plan, always interview the user in detail using AskUserQuestion about implementation choices, UI/UX decisions, trade-offs, and concerns. Never assume \342\200\224 always ask first."
        next
      }1' "$CLAUDE_MD" > "${CLAUDE_MD}.tmp" && mv "${CLAUDE_MD}.tmp" "$CLAUDE_MD"
      ok "  patched: planning-interview rule added to ## Project Rules"
      appended=1
    fi
  fi

  # ── Section: ## On Session Start ───────────────────────────────────────
  if ! grep -q "^## On Session Start" "$CLAUDE_MD" 2>/dev/null; then
    cat >> "$CLAUDE_MD" << 'SECTION'

## On Session Start
1. Query vault via MCP: latest session note, pending tasks, high-confidence instincts
2. Check for stale contexts (git diff)
3. Present the session briefing
4. Ask what to work on
SECTION
    ok "  added: ## On Session Start"
    appended=1
  fi

  if [ "$appended" -eq 1 ]; then
    ok "$CLAUDE_MD — updated (missing sections/rules added)"
  else
    ok "$CLAUDE_MD — already up to date, nothing to do"
  fi
}

# ── setup_hooks ─────────────────────────────────────────────────────────────
# Installs all hooks to ~/.claude/hooks/ and registers them in settings.json
setup_hooks() {
  local settings="$HOME/.claude/settings.json"

  # Require jq
  if ! command -v jq &> /dev/null; then
    warn "jq not found — skipping hook setup. Install with: brew install jq"
    return
  fi

  if [ -x ".agents/hooks/install.sh" ]; then
    bash ".agents/hooks/install.sh"
    return
  fi

  log "Setting up hooks..."
  mkdir -p "$HOME/.claude/hooks"

  # Initialize settings.json if missing
  if [ ! -f "$settings" ]; then
    echo '{"hooks":{}}' > "$settings"
  fi

  # ── Helper: install a single hook ──────────────────────────────────────
  install_hook() {
    local src="$1"       # e.g. ".agents/hooks/plan-review.sh"
    local event="$2"     # e.g. "PostToolUse"
    local timeout="$3"   # e.g. 120
    local matcher="${4:-}"
    local filename
    filename=$(basename "$src")
    local dst="$HOME/.claude/hooks/$filename"

    if [ ! -f "$src" ]; then
      warn "$filename not found — skipping."
      return
    fi

    cp "$src" "$dst"
    chmod +x "$dst"
    ok "Installed: $dst"

    if grep -q "$filename" "$settings" 2>/dev/null; then
      ok "Hook $event ($filename) already in settings.json — skipping."
    else
      local new_hook
      new_hook=$(jq -n \
        --arg matcher "${matcher:-}" \
        --arg cmd "~/.claude/hooks/$filename" \
        --argjson timeout "$timeout" \
        '{matcher: $matcher, hooks: [{type: "command", command: $cmd, timeout: $timeout}]}')
      local updated
      updated=$(jq --argjson hook "$new_hook" --arg event "$event" '
        if .hooks[$event] then
          .hooks[$event] += [$hook]
        else
          .hooks[$event] = [$hook]
        end
      ' "$settings")
      if [[ -n "$updated" ]]; then
        echo "$updated" > "$settings"
        ok "Hook $event ($filename) registered in $settings"
      else
        warn "jq failed for $filename — settings.json not modified."
      fi
    fi
  }

  # ── Install all hooks ──────────────────────────────────────────────────
  install_hook ".agents/hooks/plan-review.sh"       "PostToolUse"   180 "ExitPlanMode"
  install_hook ".agents/hooks/codex-pretool-guard.sh" "PreToolUse"  240
  install_hook ".agents/hooks/session-save.sh"      "Stop"          30
  install_hook ".agents/hooks/pre-compact-save.sh"  "Notification"  15
  # session-load.sh is a utility script, not a hook — it's called manually or via CLAUDE.md
  if [ -f ".agents/hooks/session-load.sh" ]; then
    cp ".agents/hooks/session-load.sh" "$HOME/.claude/hooks/session-load.sh"
    chmod +x "$HOME/.claude/hooks/session-load.sh"
    ok "Installed: $HOME/.claude/hooks/session-load.sh (utility — run manually with: bash ~/.claude/hooks/session-load.sh)"
  fi
}

setup_local_script_permissions() {
  find ".agents/hooks" -maxdepth 1 -type f -name "*.sh" -exec chmod +x {} + 2>/dev/null || true
  find ".agents/tools" -maxdepth 1 -type f -name "*.sh" -exec chmod +x {} + 2>/dev/null || true
}

# ── setup_search_tools ───────────────────────────────────────────────────────
# Installs ast-grep and registers its MCP server in ~/.claude/settings.json
setup_search_tools() {
  local settings="$HOME/.claude/settings.json"

  if ! command -v jq &> /dev/null; then
    warn "jq not found — skipping search tools setup."
    return
  fi

  log "Setting up search tools (ast-grep)..."

  # Install ast-grep if missing
  if command -v sg &> /dev/null; then
    ok "ast-grep already installed ($(sg --version))"
  elif command -v brew &> /dev/null; then
    log "Installing ast-grep via Homebrew..."
    brew install ast-grep 2>/dev/null && ok "ast-grep installed" || warn "Failed to install ast-grep — install manually: brew install ast-grep"
  else
    warn "ast-grep not found and brew unavailable. Install manually: brew install ast-grep"
  fi

  # Add ast-grep MCP server to settings.json
  if [ ! -f "$settings" ]; then
    echo '{}' > "$settings"
  fi

  if jq -e '.mcpServers["ast-grep"]' "$settings" &>/dev/null; then
    ok "ast-grep MCP server already in settings.json"
  else
    local updated
    updated=$(jq '.mcpServers["ast-grep"] = {"command":"npx","args":["-y","@ast-grep/mcp"],"type":"stdio"}' "$settings")
    if [[ -n "$updated" ]]; then
      echo "$updated" > "$settings"
      ok "ast-grep MCP server added to $settings"
    else
      warn "jq failed — MCP server not added to settings.json."
    fi
  fi
}

# ── resolve_project_dir / detect_project_slug ────────────────────────────────
# Resolve the canonical project directory before deriving the slug.
# This handles:
# - normal repos executed from subdirectories
# - git worktrees where .git is a file
# - Conductor layouts that may include a branch-named child directory
resolve_project_dir() {
  local dir="${1:-$(pwd)}"
  local root=""

  if command -v git &> /dev/null; then
    root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null || true)
  fi

  if [[ -n "$root" ]]; then
    echo "$root"
  else
    echo "$dir"
  fi
}

detect_project_slug() {
  local dir
  dir=$(resolve_project_dir "${1:-$(pwd)}")
  local slug
  slug=$(basename "$dir")
  local parent
  parent=$(basename "$(dirname "$dir")")
  local grandparent
  grandparent=$(basename "$(dirname "$(dirname "$dir")")")

  # Conductor pattern: workspaces/{project-name}/{branch-name}/
  # Only match if grandparent is "workspaces" AND current dir has .git
  # Note: use -e (exists) not -d (is directory) because git worktrees use a .git file, not a directory
  if [[ "$grandparent" == "workspaces" && -e "$dir/.git" ]]; then
    slug="$parent"
  fi

  echo "$slug"
}

# ── slug_from_conductor_path ──────────────────────────────────────────────────
# Derives the project slug from a stored path string without requiring the
# directory to exist on disk. Used for vault cleanup of stale entries.
# Handles both:
#   /conductor/workspaces/{project}/{branch}/  → returns {project}
#   /any/other/path/                           → returns basename of path
slug_from_conductor_path() {
  local path="$1"
  # Strip trailing slash
  path="${path%/}"
  local grandparent
  grandparent=$(basename "$(dirname "$(dirname "$path")")")
  if [[ "$grandparent" == "workspaces" ]]; then
    basename "$(dirname "$path")"
  else
    basename "$path"
  fi
}

# ── cleanup_stale_vault_slugs ─────────────────────────────────────────────────
# Scans vault/projects/ for entries whose folder name differs from the correct
# project slug (i.e., they were created with a branch/city name instead of
# the project name). Uses project-index.json.path to derive the correct slug.
# Renames or merges stale entries automatically.
cleanup_stale_vault_slugs() {
  local vault="$1"
  local projects_dir="$vault/projects"

  [ -d "$projects_dir" ] || return 0

  for project_dir in "$projects_dir"/*/; do
    [ -d "$project_dir" ] || continue
    local dir_name
    dir_name=$(basename "$project_dir")
    local index="$project_dir/project-index.json"

    [ -f "$index" ] || continue

    # Extract 'path' field from project-index.json
    local stored_path
    stored_path=$(python3 - "$index" << 'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    print(d.get('path', '').strip())
except Exception:
    print('')
PYEOF
)
    [ -z "$stored_path" ] && continue

    # Derive correct slug from stored path (no filesystem access needed)
    local correct_slug
    correct_slug=$(slug_from_conductor_path "$stored_path")

    [ "$correct_slug" = "$dir_name" ] && continue  # already correct, skip

    local target="$projects_dir/$correct_slug"
    log "Renaming stale vault entry: $dir_name → $correct_slug"

    if [ -d "$target" ]; then
      # Target already exists — recursively merge all files without overwriting
      while IFS= read -r -d '' src; do
        local rel="${src#${project_dir}/}"
        local dest="$target/$rel"
        if [ -d "$src" ]; then
          mkdir -p "$dest"
        elif [ ! -e "$dest" ]; then
          mkdir -p "$(dirname "$dest")"
          mv "$src" "$dest"
        fi
      done < <(find "$project_dir" -mindepth 1 -print0)
      rm -rf "$project_dir"
    else
      mv "$project_dir" "$target"
    fi

    # Update slug field inside project-index.json to match the new name
    if [ -f "$target/project-index.json" ]; then
      python3 - "$target/project-index.json" "$correct_slug" << 'PYEOF'
import json, os, sys
path, slug = sys.argv[1], sys.argv[2]
try:
    with open(path) as f:
        d = json.load(f)
    d['slug'] = slug
    tmp = path + '.tmp'
    with open(tmp, 'w') as f:
        json.dump(d, f, indent=2)
    os.replace(tmp, path)
except Exception as e:
    print(f'[canuto] warn: could not update slug in {path}: {e}', file=sys.stderr)
PYEOF
    fi

    ok "Vault: renamed $dir_name → $correct_slug"
  done
}

# ── promote_global_instincts ──────────────────────────────────────────────────
# Copies high-confidence instinct notes into vault/global-instincts/ so the
# global-instincts.base shows cross-project data.
# Scans two sources:
#   1. Global vault: ~/.canuto/vault/projects/*/instincts/ (migrated projects)
#   2. Local project vault: .agents/vault/instincts/ (current project, atomized notes)
# Uses {project}-{filename} naming to avoid collisions.
# Safe to re-run (skips already-promoted files).
promote_global_instincts() {
  local vault="$1"
  local current_project_slug="$2"        # optional: slug for the local vault
  local local_instincts_dir="${3:-.agents/vault/instincts}"  # local vault path
  local global_dir="$vault/global-instincts"
  mkdir -p "$global_dir"

  local promoted=0

  # Source 1: global vault project directories (migrated projects)
  for project_dir in "$vault/projects"/*/; do
    [ -d "$project_dir" ] || continue
    local slug
    slug=$(basename "$project_dir")
    local instincts_dir="$project_dir/instincts"
    [ -d "$instincts_dir" ] || continue

    for f in "$instincts_dir"/*.md; do
      [ -f "$f" ] || continue
      if grep -q 'confidence: high' "$f" 2>/dev/null; then
        local fname
        fname=$(basename "$f")
        local dest="$global_dir/${slug}-${fname}"
        if [ ! -f "$dest" ]; then
          cp "$f" "$dest"
          promoted=$((promoted + 1))
        fi
      fi
    done
  done

  # Source 2: current project's local vault (atomized instinct notes)
  if [[ -n "$current_project_slug" && -d "$local_instincts_dir" ]]; then
    for f in "$local_instincts_dir"/*.md; do
      [ -f "$f" ] || continue
      if grep -q 'confidence: high' "$f" 2>/dev/null; then
        local fname
        fname=$(basename "$f")
        local dest="$global_dir/${current_project_slug}-${fname}"
        if [ ! -f "$dest" ]; then
          cp "$f" "$dest"
          promoted=$((promoted + 1))
        fi
      fi
    done
  fi

  [ "$promoted" -gt 0 ] && ok "Promoted $promoted high-confidence instincts to global-instincts/"
  return 0
}

# ── setup_global_vault ────────────────────────────────────────────────────────
# Creates a global Obsidian vault at ~/.canuto/vault/ (one vault for all projects).
# Each project gets its own subdirectory under projects/{project-slug}/.
# Safe to run multiple times.
setup_global_vault() {
  local vault="$HOME/.canuto/vault"
  local project_slug
  project_slug=$(detect_project_slug)

  log "Setting up global vault at $vault..."

  # Create vault root with Obsidian config
  mkdir -p "$vault/.obsidian"
  mkdir -p "$vault/projects"

  # Rename any stale project entries that were created with a branch name
  cleanup_stale_vault_slugs "$vault"

  # Copy Obsidian config if not already present
  if [ ! -f "$vault/.obsidian/app.json" ]; then
    for cfg in app.json community-plugins.json core-plugins.json .gitignore; do
      if [ -f ".agents/vault/.obsidian/$cfg" ]; then
        cp ".agents/vault/.obsidian/$cfg" "$vault/.obsidian/$cfg"
      fi
    done
    ok "Obsidian config installed"
  else
    ok "Obsidian config already exists"
  fi

  # Create vault index
  if [ ! -f "$vault/_index.md" ]; then
    cat > "$vault/_index.md" << 'EOF'
---
title: Canuto Vault
tags:
  - vault
  - index
---

# Canuto Vault

Global memory vault for all projects. Each project's memory lives under `projects/{project-name}/`.

Use the graph view and bases to explore cross-project patterns.
EOF
    ok "Created vault _index.md"
  fi

  # Create global dirs (bases, canvas, global-instincts, reports)
  mkdir -p "$vault/bases" "$vault/canvas" "$vault/global-instincts" "$vault/reports"

  # Create project-specific directories
  local project_dir="$vault/projects/$project_slug"
  for dir in sessions decisions instincts pending audit metrics design design/components; do
    mkdir -p "$project_dir/$dir"
  done
  ok "Project directory ready: projects/$project_slug/"

  # Create project index if not present
  if [ ! -f "$project_dir/_index.md" ]; then
    cat > "$project_dir/_index.md" << PEOF
---
title: $project_slug
tags:
  - project
created: $(date +%Y-%m-%d)
---

# $project_slug

Project memory for \`$project_slug\`.
PEOF
    ok "Created project index: projects/$project_slug/_index.md"
  fi

  # Copy global canvas templates if not present
  for canvas_file in persona-flow.canvas memory-map.canvas; do
    if [ ! -f "$vault/canvas/$canvas_file" ] && [ -f ".agents/vault/canvas/$canvas_file" ]; then
      cp ".agents/vault/canvas/$canvas_file" "$vault/canvas/$canvas_file"
      ok "Canvas: $canvas_file"
    fi
  done

  # Deploy global bases (always overwrite to propagate filter fixes)
  for base_file in .agents/vault/bases/*.base; do
    [ -f "$base_file" ] || continue
    local base_name
    base_name=$(basename "$base_file")
    cp "$base_file" "$vault/bases/$base_name"
    ok "Base: $base_name"
  done

  # Generate project-specific canvas (requires python3)
  if command -v python3 &> /dev/null; then
    generate_project_canvas "$project_slug" "$project_dir"
  else
    warn "python3 not found — skipping canvas generation"
  fi

  # Promote high-confidence instincts from all projects to global-instincts/
  # Also includes the current project's local vault (atomized instinct notes)
  promote_global_instincts "$vault" "$project_slug" ".agents/vault/instincts"
}

# ── generate_project_canvas ───────────────────────────────────────────────────
# Creates visual canvas files for a project: overview map and session timeline.
# Requires python3 for reliable JSON generation.
generate_project_canvas() {
  local slug="$1"
  local project_dir="$2"
  local vault="$HOME/.canuto/vault"

  python3 - "$slug" "$project_dir" "$vault" << 'PYEOF'
import json, os, sys, glob
from datetime import date

slug = sys.argv[1]
project_dir = sys.argv[2]
vault = sys.argv[3]

def count_md(subdir):
    return len([f for f in glob.glob(f"{project_dir}/{subdir}/*.md") if '.gitkeep' not in f])

# ── Project Overview Canvas ─────────────────────────────────────────────
overview_path = f"{vault}/canvas/{slug}-overview.canvas"
if not os.path.exists(overview_path):
    n = {d: count_md(d) for d in ['sessions','decisions','instincts','pending','metrics','audit']}
    canvas = {
        "nodes": [
            {"id":"po_grp","type":"group","x":-50,"y":-100,"width":1300,"height":600,"label":slug,"color":"6"},
            {"id":"po_title","type":"text","x":0,"y":-40,"width":300,"height":80,"text":f"# {slug}\n\nProject Overview","color":"6"},
            {"id":"po_sessions","type":"text","x":400,"y":-40,"width":180,"height":100,"text":f"# Sessions\n\n{n['sessions']} notes\n`sessions/`","color":"5"},
            {"id":"po_decisions","type":"text","x":640,"y":-40,"width":180,"height":100,"text":f"# Decisions\n\n{n['decisions']} notes\n`decisions/`","color":"4"},
            {"id":"po_instincts","type":"text","x":880,"y":-40,"width":180,"height":100,"text":f"# Instincts\n\n{n['instincts']} notes\n`instincts/`","color":"3"},
            {"id":"po_pending","type":"text","x":400,"y":140,"width":180,"height":100,"text":f"# Pending\n\n{n['pending']} tasks\n`pending/`","color":"2"},
            {"id":"po_metrics","type":"text","x":640,"y":140,"width":180,"height":100,"text":f"# Metrics\n\n{n['metrics']} notes\n`metrics/`","color":"2"},
            {"id":"po_audit","type":"text","x":880,"y":140,"width":180,"height":100,"text":f"# Audit\n\n{n['audit']} events\n`audit/`","color":"1"},
            {"id":"po_design","type":"text","x":0,"y":140,"width":300,"height":100,"text":"# Design\n\nProfile + Components\n`design/`","color":"3"},
            {"id":"po_date","type":"text","x":0,"y":340,"width":300,"height":60,"text":f"Created: {date.today()}\nVault: ~/.canuto/vault/"},
        ],
        "edges": [
            {"id":"po_e1","fromNode":"po_title","fromSide":"right","toNode":"po_sessions","toSide":"left","toEnd":"arrow"},
            {"id":"po_e2","fromNode":"po_sessions","fromSide":"right","toNode":"po_decisions","toSide":"left","toEnd":"arrow","label":"records"},
            {"id":"po_e3","fromNode":"po_sessions","fromSide":"right","toNode":"po_instincts","toSide":"left","toEnd":"arrow","label":"extracts"},
            {"id":"po_e4","fromNode":"po_sessions","fromSide":"bottom","toNode":"po_pending","toSide":"top","toEnd":"arrow","label":"defers"},
            {"id":"po_e5","fromNode":"po_sessions","fromSide":"bottom","toNode":"po_metrics","toSide":"top","toEnd":"arrow","label":"tracks"},
            {"id":"po_e6","fromNode":"po_sessions","fromSide":"bottom","toNode":"po_audit","toSide":"top","toEnd":"arrow","label":"logs"},
        ]
    }
    with open(overview_path, 'w') as f:
        json.dump(canvas, f, indent=2)
    print(f"\033[0;32m[canuto]\033[0m \u2713 Canvas: {slug}-overview.canvas")

# ── Session Timeline Canvas ─────────────────────────────────────────────
timeline_path = f"{vault}/canvas/{slug}-timeline.canvas"
if not os.path.exists(timeline_path):
    session_files = sorted(glob.glob(f"{project_dir}/sessions/*.md"))
    session_files = [f for f in session_files if '.gitkeep' not in f]
    nodes = []
    edges = []

    if not session_files:
        nodes.append({"id":"tl_empty","type":"text","x":0,"y":0,"width":300,"height":100,
            "text":"# Timeline\n\nNo sessions yet.\nThe Maestro will populate this.","color":"5"})
    else:
        for i, sf in enumerate(session_files):
            name = os.path.basename(sf).replace('.md','')
            # Try to extract first goal
            summary = ""
            try:
                with open(sf) as fh:
                    for line in fh:
                        if line.startswith('- ['):
                            summary = line.strip()[:45]
                            break
            except (IOError, OSError):
                pass
            if not summary:
                summary = f"Session {name}"

            y = 0 if i % 2 == 0 else 160
            color = str((i % 6) + 1)
            node_id = f"tl_{i:04d}"
            nodes.append({"id":node_id,"type":"text","x":i*300,"y":y,"width":220,"height":80,
                "text":f"## {name}\n{summary}","color":color})
            if i > 0:
                edges.append({"id":f"tl_e_{i:04d}","fromNode":f"tl_{i-1:04d}","fromSide":"right",
                    "toNode":node_id,"toSide":"left","toEnd":"arrow"})

        # Add group around all nodes
        nodes.insert(0, {"id":"tl_grp","type":"group","x":-50,"y":-80,
            "width":len(session_files)*300+50,"height":400,
            "label":f"{slug} — Session Timeline","color":"5"})

    canvas = {"nodes": nodes, "edges": edges}
    with open(timeline_path, 'w') as f:
        json.dump(canvas, f, indent=2)
    print(f"\033[0;32m[canuto]\033[0m \u2713 Canvas: {slug}-timeline.canvas")
PYEOF
}

# ── setup_obsidian_mcp ────────────────────────────────────────────────────────
# Registers the obsidian-mcp-server in ~/.claude/settings.json.
# Prompts for API key if not already configured.
setup_obsidian_mcp() {
  local settings="$HOME/.claude/settings.json"

  if ! command -v jq &> /dev/null; then
    warn "jq not found — skipping Obsidian MCP setup."
    return
  fi

  log "Setting up Obsidian MCP server..."

  if [ ! -f "$settings" ]; then
    echo '{}' > "$settings"
  fi

  # Check if already configured
  if jq -e '.mcpServers["obsidian-mcp-server"]' "$settings" &>/dev/null; then
    ok "obsidian-mcp-server already in settings.json"
    return
  fi

  # Use --api-key arg if provided
  local API_KEY="${OBSIDIAN_API_KEY_ARG:-${OBSIDIAN_API_KEY:-}}"

  if [ -z "$API_KEY" ]; then
    # Try interactive prompt (won't work when piped via curl)
    if [[ -t 0 ]]; then
      echo ""
      echo -e "${CYAN}  Obsidian MCP requires the Local REST API plugin.${RESET}"
      echo -e "${CYAN}  In Obsidian: Settings → Community Plugins → Browse → \"Local REST API\" → Install → Enable${RESET}"
      echo -e "${CYAN}  Then copy the API Key from the plugin settings.${RESET}"
      echo ""
      read -r -p "$(echo -e "${CYAN}[canuto]${RESET} Paste your Obsidian Local REST API key (or press Enter to skip): ")" API_KEY
    fi
  fi

  if [ -z "$API_KEY" ]; then
    warn "Obsidian MCP not configured. Run again with: bash install.sh --api-key YOUR_KEY"
    warn "Or pass it via curl: curl ... | bash -s -- --migrate --api-key YOUR_KEY"
    return
  fi

  local updated
  updated=$(jq --arg key "$API_KEY" '
    .mcpServers["obsidian-mcp-server"] = {
      "command": "npx",
      "args": ["obsidian-mcp-server"],
      "env": {
        "OBSIDIAN_API_KEY": $key,
        "OBSIDIAN_BASE_URL": "https://127.0.0.1:27124",
        "MCP_TRANSPORT_TYPE": "stdio",
        "OBSIDIAN_VERIFY_SSL": "false"
      }
    }
  ' "$settings")

  if [[ -n "$updated" ]]; then
    echo "$updated" > "$settings"
    ok "obsidian-mcp-server added to $settings"
  else
    warn "jq failed — Obsidian MCP server not added."
  fi
}

# ── setup_codex ──────────────────────────────────────────────────────────────
# Detects/installs Codex CLI, configures profiles in config.toml, registers
# project trust (Conductor-aware), and adds codex-coder + codex-reviewer MCPs
# to ~/.claude/settings.json. Idempotent — safe to run on every update.
setup_codex() {
  local settings="$HOME/.claude/settings.json"
  local config_toml="$HOME/.codex/config.toml"

  log "Setting up Codex CLI integration..."

  # ── Check/install Codex CLI ──────────────────────────────────────────────
  if ! command -v codex &> /dev/null; then
    if command -v npm &> /dev/null; then
      if [[ -t 0 ]]; then
        read -r -p "$(echo -e "${CYAN}[canuto]${RESET} Codex CLI not found. Install via npm? [Y/n] ")" INSTALL_CODEX
        INSTALL_CODEX="${INSTALL_CODEX:-Y}"
      else
        INSTALL_CODEX="Y"
      fi
      if [[ "$INSTALL_CODEX" =~ ^[Yy]$ ]]; then
        log "Installing Codex CLI..."
        npm i -g @openai/codex 2>/dev/null \
          && ok "Codex CLI installed" \
          || { warn "Failed to install Codex CLI. Install manually: npm i -g @openai/codex"; return; }
      else
        warn "Codex CLI not installed — Codex integration will be skipped."
        return
      fi
    else
      warn "Codex CLI not found and npm unavailable. Install manually: npm i -g @openai/codex"
      return
    fi
  else
    ok "Codex CLI $(codex --version 2>/dev/null || echo 'installed')"
  fi

  # ── Configure config.toml with profiles ──────────────────────────────────
  mkdir -p "$HOME/.codex"
  if [ ! -f "$config_toml" ]; then
    cat > "$config_toml" << 'TOMLEOF'
personality = "pragmatic"
model = "gpt-5-codex"
model_reasoning_effort = "high"

[profiles.coder]
model = "gpt-5-codex"
model_reasoning_effort = "medium"

[profiles.reviewer]
model = "o1-pro"
model_reasoning_effort = "high"

[profiles.architect]
model = "o3"
model_reasoning_effort = "high"

[profiles.fast]
model = "gpt-5-codex"
model_reasoning_effort = "low"
TOMLEOF
    ok "Created $config_toml with profiles (coder, reviewer, architect, fast)"
  else
    # Patch-merge: add missing profiles without overwriting
    local patched=false
    for profile in coder reviewer architect fast; do
      if ! grep -q "\[profiles\.$profile\]" "$config_toml" 2>/dev/null; then
        case $profile in
          coder)     echo -e "\n[profiles.coder]\nmodel = \"gpt-5-codex\"\nmodel_reasoning_effort = \"medium\"" >> "$config_toml" ;;
          reviewer)  echo -e "\n[profiles.reviewer]\nmodel = \"o1-pro\"\nmodel_reasoning_effort = \"high\"" >> "$config_toml" ;;
          architect) echo -e "\n[profiles.architect]\nmodel = \"o3\"\nmodel_reasoning_effort = \"high\"" >> "$config_toml" ;;
          fast)      echo -e "\n[profiles.fast]\nmodel = \"gpt-5-codex\"\nmodel_reasoning_effort = \"low\"" >> "$config_toml" ;;
        esac
        patched=true
      fi
    done
    if $patched; then
      ok "Patched $config_toml with missing profiles"
    else
      ok "config.toml profiles already configured"
    fi
  fi

  # ── Add project trust (Conductor-aware) ──────────────────────────────────
  local project_dir
  project_dir=$(resolve_project_dir "$(pwd)")
  local escaped_dir
  escaped_dir=$(printf '%s' "$project_dir" | sed 's/[\/&]/\\&/g')

  if ! grep -q "projects.\"$project_dir\"" "$config_toml" 2>/dev/null; then
    cat >> "$config_toml" << TRUSTEOF

[projects."$project_dir"]
trust_level = "trusted"
approval_policy = "never"
sandbox_mode = "danger-full-access"
TRUSTEOF
    ok "Project trusted in config.toml: $project_dir"
  else
    ok "Project already trusted in config.toml"
  fi

  # For Conductor: also trust the workspace parent so new worktrees auto-trust
  local grandparent
  grandparent=$(basename "$(dirname "$(dirname "$project_dir")")")
  if [[ "$grandparent" == "workspaces" ]]; then
    local workspace_parent
    workspace_parent=$(dirname "$project_dir")
    if ! grep -q "projects.\"$workspace_parent\"" "$config_toml" 2>/dev/null; then
      cat >> "$config_toml" << TRUSTEOF2

[projects."$workspace_parent"]
trust_level = "trusted"
approval_policy = "never"
sandbox_mode = "danger-full-access"
TRUSTEOF2
      ok "Conductor workspace parent trusted: $workspace_parent"
    fi
  fi

  # ── Register codex-coder MCP in settings.json ───────────────────────────
  if ! command -v jq &> /dev/null; then
    warn "jq not found — skipping Codex MCP registration."
    return
  fi

  if [ ! -f "$settings" ]; then
    echo '{}' > "$settings"
  fi

  if ! jq -e '.mcpServers["codex-coder"]' "$settings" &>/dev/null; then
    local updated
    updated=$(jq '.mcpServers["codex-coder"] = {"command":"uvx","args":["codex-as-mcp@latest"],"type":"stdio"}' "$settings")
    if [[ -n "$updated" ]]; then
      echo "$updated" > "$settings"
      ok "codex-coder MCP added to settings.json (gpt-5-codex)"
    fi
  else
    ok "codex-coder MCP already in settings.json"
  fi

  # ── Register codex-reviewer MCP in settings.json ────────────────────────
  if ! jq -e '.mcpServers["codex-reviewer"]' "$settings" &>/dev/null; then
    local updated
    updated=$(jq '.mcpServers["codex-reviewer"] = {"command":"codex","args":["mcp","serve","-c","model=o1-pro"],"type":"stdio"}' "$settings")
    if [[ -n "$updated" ]]; then
      echo "$updated" > "$settings"
      ok "codex-reviewer MCP added to settings.json (o1-pro)"
    fi
  else
    ok "codex-reviewer MCP already in settings.json"
  fi
}

# ── setup_codex_mcps ─────────────────────────────────────────────────────────
# Registers MCP servers natively in Codex CLI so that agents spawned via
# codex exec have access to Obsidian vault, ast-grep, and Playwright.
# Experimental (codex mcp is v0.40+). Degrades gracefully if unavailable.
setup_codex_mcps() {
  if ! command -v codex &> /dev/null; then
    return
  fi

  # Check if codex mcp subcommand exists
  if ! codex mcp list &>/dev/null; then
    warn "codex mcp not available (requires v0.40+). Codex agents will use vault-bridge.sh fallback."
    return
  fi

  log "Registering MCP servers in Codex CLI..."
  local existing
  existing=$(codex mcp list 2>/dev/null || echo "")

  ensure_codex_mcp_stdio() {
    local name="$1"
    shift
    if echo "$existing" | grep -q "^$name" 2>/dev/null || echo "$existing" | grep -q "$name" 2>/dev/null; then
      codex mcp remove "$name" >/dev/null 2>&1 || true
    fi
    codex mcp add "$name" "$@"
  }

  # Obsidian vault
  local settings="$HOME/.claude/settings.json"
  local api_key=""
  if [ -f "$settings" ] && command -v jq &>/dev/null; then
    api_key=$(jq -r '.mcpServers["obsidian-mcp-server"].env.OBSIDIAN_API_KEY // empty' "$settings" 2>/dev/null)
  fi
  api_key="${api_key:-${OBSIDIAN_API_KEY_ARG:-${OBSIDIAN_API_KEY:-}}}"
  if [ -n "$api_key" ]; then
    ensure_codex_mcp_stdio obsidian-vault \
      --env "OBSIDIAN_API_KEY=$api_key" \
      --env "OBSIDIAN_BASE_URL=https://127.0.0.1:27124" \
      --env "MCP_TRANSPORT_TYPE=stdio" \
      --env "OBSIDIAN_VERIFY_SSL=false" \
      -- npx obsidian-mcp-server >/dev/null 2>&1 \
      && ok "Codex MCP: obsidian-vault" \
      || warn "Failed to add obsidian-vault to Codex"
  else
    warn "Obsidian API key not found — skipping obsidian-vault MCP for Codex"
  fi

  # ast-grep
  ensure_codex_mcp_stdio ast-grep -- npx -y @ast-grep/mcp >/dev/null 2>&1 \
    && ok "Codex MCP: ast-grep" \
    || warn "Failed to add ast-grep to Codex"

  # Playwright
  ensure_codex_mcp_stdio playwright -- npx -y @anthropic-ai/mcp-server-playwright >/dev/null 2>&1 \
    && ok "Codex MCP: playwright" \
    || warn "Failed to add playwright to Codex"

  # GitHub (requires GITHUB_PERSONAL_ACCESS_TOKEN)
  if [ -n "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]; then
    ensure_codex_mcp_stdio github -- npx -y @anthropic-ai/mcp-server-github >/dev/null 2>&1 \
      && ok "Codex MCP: github" \
      || warn "Failed to add github to Codex"
  fi
}

# ── merge_agents_md ──────────────────────────────────────────────────────────
# Creates AGENTS.md (Codex's equivalent of CLAUDE.md) in project root.
# Gives Codex agents project-specific context, rules, and MCP tools list.
# Idempotent — section-level merge, never overwrites custom sections.
merge_agents_md() {
  local agents_md="AGENTS.md"

  if [ ! -f "$agents_md" ]; then
    cat > "$agents_md" << 'AGENTSEOF'
# Project Rules (Codex)

## Context
- Framework: Canuto v1.x at .agents/
- Read .context.md files in each directory for local context
- Read docs/FEATURE-MAP.md for feature status and flows
- Read .agents/tmp/context-package.md if it exists (pre-loaded context from Architect)

## Coding Rules
- Follow existing patterns in nearby files — match style, naming, structure
- Do NOT add new dependencies without explicit instruction in the prompt
- Include basic happy-path tests for new functions
- Use TypeScript strict mode if tsconfig.json has strict: true
- Prefer editing existing files over creating new ones
- Do NOT add comments, docstrings, or type annotations to code you didn't change

## MCP Tools Available
- **obsidian-vault**: Read/write vault notes at ~/.canuto/vault/ for project memory
- **ast-grep**: Structural code search — use for finding patterns, symbols, callers
- **playwright**: Browser automation — navigate, click, fill, screenshot, assert

## Vault Access (Fallback)
If MCP tools are not available, use the vault-bridge shell script:
```bash
bash .agents/tools/vault-bridge.sh read <note-path>
bash .agents/tools/vault-bridge.sh search <query>
```

## File Conventions
- New files follow the naming pattern of existing files in the same directory
- Imports use the project's alias paths (check tsconfig.json or package.json)
- Test files go next to source files or in the nearest tests/ directory

## Codex Profiles

Available profiles in \`~/.codex/config.toml\` — use when spawned with \`--profile\`:

| Profile | Model | Reasoning | Use For |
|---------|-------|-----------|---------|
| \`coder\` | gpt-5-codex | medium | Standard code generation |
| \`reviewer\` | o1-pro | high | Deep code review, security audit |
| \`architect\` | o3 | high | Architecture, complex reasoning |
| \`fast\` | gpt-5-codex | low | Quick edits, formatting, docs |

## Anti-Patterns
- Do NOT create README.md, documentation files, or CHANGELOG entries
- Do NOT refactor unrelated code
- Do NOT install packages or modify lock files
- Do NOT modify .env files or configuration
AGENTSEOF
    ok "AGENTS.md created (Codex project instructions)"
  else
    # Patch missing sections
    local patched=false
    if ! grep -q "## MCP Tools Available" "$agents_md" 2>/dev/null; then
      cat >> "$agents_md" << 'MCPPATCH'

## MCP Tools Available
- **obsidian-vault**: Read/write vault notes at ~/.canuto/vault/ for project memory
- **ast-grep**: Structural code search — use for finding patterns, symbols, callers
- **playwright**: Browser automation — navigate, click, fill, screenshot, assert
MCPPATCH
      patched=true
    fi
    if ! grep -q "## Codex Profiles" "$agents_md" 2>/dev/null; then
      cat >> "$agents_md" << 'PROFILEPATCH'

## Codex Profiles

Available profiles in `~/.codex/config.toml` — use when spawned with `--profile`:

| Profile | Model | Reasoning | Use For |
|---------|-------|-----------|---------|
| `coder` | gpt-5-codex | medium | Standard code generation |
| `reviewer` | o1-pro | high | Deep code review, security audit |
| `architect` | o3 | high | Architecture, complex reasoning |
| `fast` | gpt-5-codex | low | Quick edits, formatting, docs |
PROFILEPATCH
      patched=true
    fi
    if ! grep -q "## Vault Access" "$agents_md" 2>/dev/null; then
      cat >> "$agents_md" << 'VAULTPATCH'

## Vault Access (Fallback)
If MCP tools are not available, use the vault-bridge shell script:
```bash
bash .agents/tools/vault-bridge.sh read <note-path>
bash .agents/tools/vault-bridge.sh search <query>
```
VAULTPATCH
      patched=true
    fi
    if $patched; then
      ok "AGENTS.md patched with missing sections"
    else
      ok "AGENTS.md already up to date"
    fi
  fi
}

ensure_project_bootstrap_files() {
  local project_dir
  project_dir=$(resolve_project_dir "$(pwd)")
  local project_slug
  project_slug=$(detect_project_slug "$project_dir")

  mkdir -p "$project_dir/docs" "$project_dir/.agents/vault/digests"

  if [ ! -f "$project_dir/.context.md" ]; then
    cat > "$project_dir/.context.md" <<EOF
# Project Context

## Snapshot
- project: $project_slug
- repo_root: $(basename "$project_dir")
- framework: Canuto v1.x

## Working Agreements
- Read this file and \`docs/FEATURE-MAP.md\` before structural changes.
- Update both files when architecture, entry points, or key workflows change.

## Architecture
- Fill in primary stack, key directories, and critical entry points.

## Runtime
- dev:
- test:
- build:

## Notes
- This file was created by Canuto during bootstrap. Replace placeholders with repo-specific facts.
EOF
    ok "Created .context.md"
  else
    ok ".context.md already exists"
  fi

  if [ ! -f "$project_dir/docs/FEATURE-MAP.md" ]; then
    cat > "$project_dir/docs/FEATURE-MAP.md" <<'EOF'
# Feature Map

## Status Legend
- `implemented`
- `partial`
- `planned`
- `unknown`

| Area | Status | Entry Points | Notes |
|------|--------|--------------|-------|
| Bootstrap | implemented | `.agents/`, `install.sh`, `CLAUDE.md` | Created by Canuto |
| Core product areas | unknown | TBD | Replace with repo-specific feature inventory |
EOF
    ok "Created docs/FEATURE-MAP.md"
  else
    ok "docs/FEATURE-MAP.md already exists"
  fi

  if [ ! -f "$project_dir/.agents/vault/digests/00-bootstrap-digest.md" ]; then
    cat > "$project_dir/.agents/vault/digests/00-bootstrap-digest.md" <<EOF
---
title: Bootstrap Digest
type: digest
generated_by: canuto-install
project: $project_slug
---

# Bootstrap Digest

- Starter context files were created or verified.
- Starter feature map was created or verified.
- Validate this project with \`bash install.sh --test\`.
- Repair runtime state with \`bash install.sh --doctor\`.
EOF
    ok "Created bootstrap digest"
  else
    ok "Bootstrap digest already exists"
  fi
}

run_consumer_smoke() {
  local project_dir
  project_dir=$(resolve_project_dir "$(pwd)")
  local script="$project_dir/.agents/tools/canuto-consumer-smoke.sh"
  if [ "$JSON_OUTPUT" = true ]; then
    bash "$script" --json
  else
    bash "$script"
  fi
}

run_codex_health() {
  local project_dir
  project_dir=$(resolve_project_dir "$(pwd)")
  local script="$project_dir/.agents/tools/codex-health-check.sh"
  if [ "$JSON_OUTPUT" = true ]; then
    bash "$script" --json
  else
    bash "$script"
  fi
}

run_install_validation() {
  local consumer_json=""
  local codex_json=""
  local consumer_rc=0
  local codex_rc=0

  if [ "$JSON_OUTPUT" = true ]; then
    consumer_json=$(run_consumer_smoke) || consumer_rc=$?
    codex_json=$(run_codex_health) || codex_rc=$?
    python3 - "$consumer_json" "$codex_json" "$consumer_rc" "$codex_rc" <<'PYEOF'
import json
import sys

consumer_json, codex_json, consumer_rc, codex_rc = sys.argv[1:]
consumer = json.loads(consumer_json)
codex = json.loads(codex_json)

verdict_order = {"HEALTHY": 0, "DEGRADED": 1, "BROKEN": 2}
overall = max(consumer["verdict"], codex["verdict"], key=lambda v: verdict_order[v])

print(json.dumps({
    "tool": "canuto-install-validation",
    "verdict": overall,
    "counts": {
        "consumer": consumer["counts"],
        "codex": codex["counts"],
    },
    "consumer_smoke": consumer,
    "codex_health": codex,
}, ensure_ascii=True))
PYEOF
    if [ "$consumer_rc" -ne 0 ] || [ "$codex_rc" -ne 0 ]; then
      return 1
    fi
    return 0
  fi

  run_consumer_smoke || consumer_rc=$?
  run_codex_health || codex_rc=$?

  if [ "$consumer_rc" -ne 0 ] || [ "$codex_rc" -ne 0 ]; then
    return 1
  fi
  return 0
}

repair_runtime() {
  setup_deps
  setup_local_script_permissions
  merge_claude_md
  merge_agents_md
  ensure_project_bootstrap_files
  setup_hooks
  setup_search_tools
  setup_global_vault
  setup_obsidian_mcp
  setup_codex
  setup_codex_mcps
  setup_gstack
  setup_global_skills

  mkdir -p ".agents/tmp"
  if [ ! -f ".agents/tmp/.gitkeep" ]; then
    echo "# Temporary files — gitignored" > ".agents/tmp/.gitkeep"
  fi
  if [ -x ".agents/tools/codex-context-package.sh" ]; then
    bash ".agents/tools/codex-context-package.sh" \
      --task "Bootstrap Context" \
      --output ".agents/tmp/context-package.md" \
      --file "CLAUDE.md" \
      --file ".context.md" \
      --file "docs/FEATURE-MAP.md" >/dev/null 2>&1 || true
  fi
  if [ -f ".gitignore" ] && ! grep -q ".agents/tmp/" ".gitignore" 2>/dev/null; then
    echo ".agents/tmp/" >> ".gitignore"
  fi
}

# ── setup_gstack ─────────────────────────────────────────────────────────────
# Installs/updates gstack (Garry Tan's 21 engineering skills) globally.
# Requires: git. Optional: bun (for /browse binary compilation).
setup_gstack() {
  local gstack_dir="$HOME/.claude/skills/gstack"

  log "Setting up gstack..."

  if ! command -v bun &> /dev/null; then
    warn "Bun not found — /browse binary will not be compiled."
    command -v brew &> /dev/null && warn "Install: brew install bun"
  else
    ok "bun $(bun --version)"
  fi

  if [ -d "$gstack_dir" ]; then
    git -C "$gstack_dir" pull --ff-only --quiet 2>/dev/null \
      && ok "gstack updated" \
      || warn "Could not update gstack — check manually: cd ~/.claude/skills/gstack && git pull"
  else
    git clone --quiet https://github.com/garrytan/gstack.git "$gstack_dir" 2>/dev/null \
      && ok "gstack cloned" \
      || { warn "Could not clone gstack. Manual: git clone https://github.com/garrytan/gstack.git ~/.claude/skills/gstack"; return; }
  fi

  [ -f "$gstack_dir/setup" ] && chmod +x "$gstack_dir/setup" \
    && (cd "$gstack_dir" && ./setup 2>/dev/null || ./setup) \
    && ok "gstack setup complete" \
    || warn "gstack/setup failed — verify manually."
}

# ── setup_global_skills ───────────────────────────────────────────────────────
# Downloads Canuto-adapted global skills (slash commands) to ~/.claude/skills/.
# Uses the existing download() helper — no duplicate curl/wget logic.
setup_global_skills() {
  local -a global_skills=(
    # Canuto originals
    "office-hours"
    "investigate"
    "document-release"
    "retro"
    "auto-analysis"
    "vault-maintenance"
    # Impeccable design skills
    "audit"
    "animate"
    "bolder"
    "polish"
    "critique"
    "typeset"
    "harden"
    "colorize"
    "overdrive"
    "clarify"
  )

  log "Installing Canuto global skills to ~/.claude/skills/..."

  for skill in "${global_skills[@]}"; do
    local remote="global-skills/${skill}/SKILL.md"
    local dst="$HOME/.claude/skills/${skill}/SKILL.md"
    download "$remote" "$dst" \
      && ok "/$skill" \
      || warn "Could not download $remote"
  done
}

# ── post_install_analysis ─────────────────────────────────────────────────────
# Generates project-index.json (deep scan) and onboarding-report.md
# by cross-referencing with other indexed projects in the vault.
post_install_analysis() {
  local project_dir="${1:-.}"
  project_dir=$(resolve_project_dir "$project_dir")
  local project_slug
  project_slug=$(detect_project_slug "$project_dir")
  local vault="$HOME/.canuto/vault"
  local project_vault="$vault/projects/$project_slug"

  if ! command -v python3 &> /dev/null; then
    warn "python3 required for auto-analysis. Skipping."
    return
  fi

  log "Running deep project analysis..."

  PROJECT_DIR="$project_dir" PROJECT_SLUG="$project_slug" CANUTO_VAULT="$vault" \
  python3 << 'PYEOF'
import os, sys, json, glob, re
from pathlib import Path
from datetime import datetime
from collections import defaultdict, Counter

import sys as _sys

project_dir = os.environ["PROJECT_DIR"]
project_slug = os.environ["PROJECT_SLUG"]
vault = os.environ["CANUTO_VAULT"]
project_vault = f"{vault}/projects/{project_slug}"
today = datetime.now().isoformat()[:19]

# Max file size for reading content (1MB)
MAX_FILE_SIZE = 1_000_000
# Max source files to scan for API surface / env vars
MAX_SCAN_FILES = 500

def _warn(msg):
    print(f"\033[1;33m[canuto]\033[0m {msg}", file=_sys.stderr)

def _safe_read(filepath, max_size=MAX_FILE_SIZE):
    """Read file content with size guard. Returns None if too large or unreadable."""
    try:
        if os.path.getsize(filepath) > max_size:
            return None
        with open(filepath, errors='ignore') as f:
            return f.read()
    except (IOError, OSError):
        return None

def _safe_int(val, default=0):
    """Convert to int safely."""
    try:
        return int(val or default)
    except (ValueError, TypeError):
        return default

def _stack_info(idx):
    stack = idx.get("stack", {})
    return stack if isinstance(stack, dict) else {}

def _dependency_map(idx, kind):
    deps = idx.get("dependencies", {})
    if not isinstance(deps, dict):
        return {}
    dep_map = deps.get(kind, {})
    return dep_map if isinstance(dep_map, dict) else {}

def _dependency_keys(idx):
    return set(_dependency_map(idx, "production").keys()) | set(_dependency_map(idx, "development").keys())

def _domain_names(idx):
    names = []
    for domain in idx.get("domains", []):
        if isinstance(domain, dict):
            name = domain.get("name")
        elif isinstance(domain, str):
            name = domain
        else:
            name = None
        if isinstance(name, str) and name:
            names.append(name)
    return names

def _pattern_names(idx):
    patterns = idx.get("patterns_detected", idx.get("patterns", []))
    if not isinstance(patterns, list):
        return []
    return [pattern for pattern in patterns if isinstance(pattern, str) and pattern]

def _looks_like_nested_project(dirpath):
    if not os.path.isdir(dirpath):
        return False
    markers = [
        os.path.join(dirpath, ".agents"),
        os.path.join(dirpath, "CLAUDE.md"),
        os.path.join(dirpath, "install.sh"),
        os.path.join(dirpath, "registry.md"),
    ]
    return os.path.isdir(markers[0]) and any(os.path.exists(marker) for marker in markers[1:])

# ═══════════════════════════════════════════════════════════════════════
# PHASE 1: Generate project-index.json (deep scan)
# ═══════════════════════════════════════════════════════════════════════

index = {
    "slug": project_slug,
    "path": project_dir,
    "last_scanned": today,
    "stack": {},
    "dependencies": {"production": {}, "development": {}},
    "structure": {},
    "domains": [],
    "patterns_detected": [],
    "ci": {"has_ci": False},
    "scripts": {},
    "env_vars": [],
    "api_surface": {}
}

# ── Detect stack ─────────────────────────────────────────────────────
pkg_json = f"{project_dir}/package.json"
pyproject = f"{project_dir}/pyproject.toml"
requirements = f"{project_dir}/requirements.txt"
go_mod = f"{project_dir}/go.mod"
cargo_toml = f"{project_dir}/Cargo.toml"
pubspec_files = [
    path for path in glob.glob(f"{project_dir}/**/pubspec.yaml", recursive=True)
    if "/Pods/" not in path and "/.dart_tool/" not in path
]

if os.path.exists(pkg_json):
    try:
        with open(pkg_json) as f:
            pkg = json.load(f)

        prod_deps = pkg.get("dependencies", {})
        dev_deps = pkg.get("devDependencies", {})
        all_deps = {**prod_deps, **dev_deps}
        index["dependencies"]["production"] = prod_deps
        index["dependencies"]["development"] = dev_deps

        # Detect language
        has_ts = "typescript" in dev_deps or os.path.exists(f"{project_dir}/tsconfig.json")
        index["stack"]["primary_language"] = "typescript" if has_ts else "javascript"
        langs = ["javascript"]
        if has_ts: langs.insert(0, "typescript")
        if glob.glob(f"{project_dir}/**/*.css", recursive=True): langs.append("css")
        if glob.glob(f"{project_dir}/**/*.scss", recursive=True): langs.append("scss")
        index["stack"]["languages"] = langs
        index["stack"]["runtime"] = "node"

        # Detect framework
        frameworks = {
            "next": "next", "nuxt": "nuxt", "express": "express",
            "fastify": "fastify", "koa": "koa", "hapi": "@hapi/hapi",
            "nest": "@nestjs/core", "remix": "@remix-run/react",
            "astro": "astro", "gatsby": "gatsby", "svelte": "svelte",
            "angular": "@angular/core"
        }
        for name, dep in frameworks.items():
            if dep in all_deps:
                index["stack"]["framework"] = name
                break

        # Detect UI framework
        ui_fws = {"react": "react", "vue": "vue", "svelte": "svelte", "angular": "@angular/core", "solid": "solid-js"}
        for name, dep in ui_fws.items():
            if dep in all_deps:
                index["stack"]["ui_framework"] = name
                break

        # Detect ORM
        orms = {"prisma": "prisma", "typeorm": "typeorm", "sequelize": "sequelize",
                "drizzle": "drizzle-orm", "mongoose": "mongoose", "knex": "knex"}
        for name, dep in orms.items():
            if dep in all_deps:
                index["stack"]["orm"] = name
                break

        # Detect test framework
        test_fws = {"vitest": "vitest", "jest": "jest", "mocha": "mocha",
                    "ava": "ava", "tap": "tap", "playwright": "@playwright/test",
                    "cypress": "cypress"}
        for name, dep in test_fws.items():
            if dep in all_deps:
                index["stack"]["test_framework"] = name
                break

        # Detect bundler
        bundlers = {"vite": "vite", "webpack": "webpack", "esbuild": "esbuild",
                    "rollup": "rollup", "parcel": "parcel", "turbopack": "turbopack", "tsup": "tsup"}
        for name, dep in bundlers.items():
            if dep in all_deps:
                index["stack"]["bundler"] = name
                break

        # Detect package manager
        if os.path.exists(f"{project_dir}/pnpm-lock.yaml"):
            index["stack"]["package_manager"] = "pnpm"
        elif os.path.exists(f"{project_dir}/yarn.lock"):
            index["stack"]["package_manager"] = "yarn"
        elif os.path.exists(f"{project_dir}/bun.lockb"):
            index["stack"]["package_manager"] = "bun"
        else:
            index["stack"]["package_manager"] = "npm"

        # Scripts
        index["scripts"] = pkg.get("scripts", {})

    except (json.JSONDecodeError, IOError, OSError, KeyError, TypeError) as e:
        _warn(f"Could not parse package.json: {e}")

elif os.path.exists(pyproject):
    index["stack"]["primary_language"] = "python"
    index["stack"]["languages"] = ["python"]
    index["stack"]["runtime"] = "python"
    try:
        with open(pyproject) as f:
            content = f.read()
        # Simple TOML parsing for deps
        deps = re.findall(r'"([a-zA-Z0-9_-]+)[><=!~]*', content)
        index["dependencies"]["production"] = {d: "*" for d in deps[:30]}

        py_fws = {"fastapi": "fastapi", "django": "django", "flask": "flask",
                  "starlette": "starlette", "sanic": "sanic"}
        for name, dep in py_fws.items():
            if dep in content.lower():
                index["stack"]["framework"] = name
                break

        py_orms = {"sqlalchemy": "sqlalchemy", "tortoise": "tortoise", "peewee": "peewee",
                   "django": "django"}
        for name, dep in py_orms.items():
            if dep in content.lower():
                index["stack"]["orm"] = name
                break

        if "pytest" in content: index["stack"]["test_framework"] = "pytest"
        elif "unittest" in content: index["stack"]["test_framework"] = "unittest"
    except (IOError, OSError) as e:
        _warn(f"Could not parse pyproject.toml: {e}")

elif os.path.exists(requirements):
    index["stack"]["primary_language"] = "python"
    index["stack"]["languages"] = ["python"]
    index["stack"]["runtime"] = "python"
    try:
        with open(requirements) as f:
            deps = [l.split("==")[0].split(">=")[0].split("<=")[0].strip()
                    for l in f if l.strip() and not l.startswith("#")]
        index["dependencies"]["production"] = {d: "*" for d in deps}
    except (IOError, OSError) as e:
        _warn(f"Could not parse requirements.txt: {e}")

elif os.path.exists(go_mod):
    index["stack"]["primary_language"] = "go"
    index["stack"]["languages"] = ["go"]
    index["stack"]["runtime"] = "go"
    try:
        with open(go_mod) as f:
            content = f.read()
        deps = re.findall(r'^\s+(\S+)\s+v', content, re.MULTILINE)
        index["dependencies"]["production"] = {d: "*" for d in deps}
        if "gin-gonic" in content: index["stack"]["framework"] = "gin"
        elif "gofiber" in content: index["stack"]["framework"] = "fiber"
        elif "echo" in content: index["stack"]["framework"] = "echo"
    except (IOError, OSError) as e:
        _warn(f"Could not parse go.mod: {e}")

elif os.path.exists(cargo_toml):
    index["stack"]["primary_language"] = "rust"
    index["stack"]["languages"] = ["rust"]
    index["stack"]["runtime"] = "rust"
    try:
        with open(cargo_toml) as f:
            content = f.read()
        deps = re.findall(r'^(\w[\w-]*)\s*=', content, re.MULTILINE)
        index["dependencies"]["production"] = {d: "*" for d in deps if d not in ("name", "version", "edition", "authors")}
        if "actix" in content: index["stack"]["framework"] = "actix"
        elif "axum" in content: index["stack"]["framework"] = "axum"
        elif "rocket" in content: index["stack"]["framework"] = "rocket"
    except (IOError, OSError) as e:
        _warn(f"Could not parse Cargo.toml: {e}")

elif pubspec_files:
    index["stack"]["primary_language"] = "dart"
    index["stack"]["languages"] = ["dart"]
    index["stack"]["runtime"] = "flutter"
    index["stack"]["framework"] = "flutter"

# ── Analyze structure ────────────────────────────────────────────────
IGNORE = {'.git', 'node_modules', '.next', 'dist', 'build', '__pycache__',
          '.venv', 'venv', 'target', '.agents', '.obsidian', 'vendor', 'coverage',
          'Pods', '.dart_tool'}
SOURCE_EXTS = {'.ts', '.tsx', '.js', '.jsx', '.py', '.go', '.rs', '.java', '.kt', '.rb', '.php', '.swift', '.dart'}
TEST_PATTERNS = {'test', 'spec', '__tests__', 'tests', '_test'}
CONFIG_EXTS = {'.json', '.yaml', '.yml', '.toml', '.ini', '.env', '.config.js', '.config.ts'}

source_files = []
test_files = []
config_files = []
source_dirs = set()
test_dirs = set()
total_loc = 0
source_loc = 0
test_loc = 0

for root, dirs, files in os.walk(project_dir):
    dirs[:] = [
        d for d in dirs
        if d not in IGNORE and not _looks_like_nested_project(os.path.join(root, d))
    ]
    rel_root = os.path.relpath(root, project_dir)

    for fname in files:
        fpath = os.path.join(root, fname)
        rel_path = os.path.relpath(fpath, project_dir)
        ext = Path(fname).suffix

        if ext in SOURCE_EXTS:
            try:
                fsize = os.path.getsize(fpath)
                if fsize > MAX_FILE_SIZE:
                    lc = 0  # Skip large files
                else:
                    lc = sum(1 for _ in open(fpath, errors='ignore'))
            except (IOError, OSError):
                lc = 0

            is_test = any(p in rel_path.lower() for p in TEST_PATTERNS)
            if is_test:
                test_files.append(rel_path)
                test_dirs.add(os.path.dirname(rel_path) + "/")
                test_loc += lc
            else:
                source_files.append(rel_path)
                source_dirs.add(os.path.dirname(rel_path) + "/")
                source_loc += lc
            total_loc += lc

        elif ext in CONFIG_EXTS or fname.startswith('.env'):
            config_files.append(rel_path)

# Entry points
entry_candidates = ['src/index.ts', 'src/index.js', 'src/main.ts', 'src/main.py',
                    'src/app.ts', 'src/app.py', 'main.go', 'src/main.rs',
                    'src/server.ts', 'src/server.js', 'app.py', 'manage.py',
                    'apps/resumeai/lib/main.dart', 'lib/main.dart',
                    'index.ts', 'index.js']
entry_points = [e for e in entry_candidates if os.path.exists(f"{project_dir}/{e}")]

index["structure"] = {
    "entry_points": entry_points,
    "source_dirs": sorted(list(source_dirs))[:20],
    "test_dirs": sorted(list(test_dirs))[:10],
    "config_files": sorted(config_files)[:15],
    "loc": {"total": total_loc, "source": source_loc, "test": test_loc},
    "file_count": {"total": len(source_files) + len(test_files) + len(config_files),
                   "source": len(source_files), "test": len(test_files), "config": len(config_files)}
}

# ── Detect domains ───────────────────────────────────────────────────
domain_keywords = {
    "auth": ["auth", "login", "signup", "jwt", "token", "session", "oauth", "password", "bcrypt"],
    "api": ["route", "controller", "endpoint", "handler", "middleware", "api"],
    "data": ["model", "schema", "migration", "repository", "database", "db", "prisma", "orm"],
    "payments": ["payment", "billing", "stripe", "invoice", "subscription", "checkout"],
    "notifications": ["notification", "email", "sms", "push", "mailer", "sendgrid"],
    "storage": ["upload", "storage", "s3", "bucket", "file", "media", "image"],
    "admin": ["admin", "dashboard", "backoffice", "panel"],
    "testing": ["test", "spec", "mock", "fixture", "factory", "seed"],
    "config": ["config", "env", "settings", "constants"],
    "ui": ["component", "page", "layout", "view", "template", "widget"],
}

domain_files = defaultdict(list)
domain_deps = defaultdict(set)
all_deps_flat = set(index["dependencies"]["production"].keys()) | set(index["dependencies"]["development"].keys())

for sf in source_files:
    sf_lower = sf.lower()
    for domain, keywords in domain_keywords.items():
        if any(kw in sf_lower for kw in keywords):
            domain_files[domain].append(sf)
            break

# Map deps to domains
dep_domain_map = {
    "auth": ["jsonwebtoken", "bcrypt", "passport", "next-auth", "clerk", "auth0", "jose"],
    "data": ["prisma", "@prisma/client", "typeorm", "sequelize", "mongoose", "knex", "drizzle-orm", "sqlalchemy"],
    "payments": ["stripe", "@stripe/stripe-js", "paypal"],
    "notifications": ["nodemailer", "sendgrid", "@sendgrid/mail", "twilio"],
    "storage": ["@aws-sdk/client-s3", "multer", "sharp", "cloudinary"],
}
for domain, deps in dep_domain_map.items():
    for dep in deps:
        if dep in all_deps_flat:
            domain_deps[domain].add(dep)

domains = []
for domain, files in domain_files.items():
    confidence = min(0.5 + len(files) * 0.1 + len(domain_deps.get(domain, [])) * 0.15, 1.0)
    domains.append({
        "name": domain,
        "files": files[:10],
        "deps": list(domain_deps.get(domain, [])),
        "confidence": round(confidence, 2)
    })
index["domains"] = sorted(domains, key=lambda d: d["confidence"], reverse=True)

# ── Detect patterns ──────────────────────────────────────────────────
patterns = []
all_source_lower = " ".join(source_files).lower()
all_config_lower = " ".join(config_files).lower()

if "middleware" in all_source_lower: patterns.append("middleware-chain")
if "repository" in all_source_lower or "repo" in all_source_lower: patterns.append("repository-pattern")
if "factory" in all_source_lower: patterns.append("factory-pattern")
if "service" in all_source_lower: patterns.append("service-layer")
if "controller" in all_source_lower: patterns.append("controller-pattern")
if "hook" in all_source_lower or "use" in " ".join(f for f in source_files if f.endswith(('.ts', '.tsx', '.js', '.jsx'))): patterns.append("custom-hooks")
if ".env" in all_config_lower: patterns.append("env-validation")
if "singleton" in all_source_lower: patterns.append("singleton")
if "observer" in all_source_lower or "event" in all_source_lower: patterns.append("event-driven")
if "queue" in all_source_lower or "worker" in all_source_lower: patterns.append("queue-worker")
if "cache" in all_source_lower or "redis" in all_source_lower: patterns.append("caching")
if "graphql" in all_source_lower or "gql" in all_source_lower: patterns.append("graphql")
if "websocket" in all_source_lower or "socket" in all_source_lower: patterns.append("websockets")
index["patterns_detected"] = patterns

# ── Detect CI ────────────────────────────────────────────────────────
ci = {"has_ci": False}
gh_workflows = glob.glob(f"{project_dir}/.github/workflows/*.yml") + glob.glob(f"{project_dir}/.github/workflows/*.yaml")
if gh_workflows:
    ci["has_ci"] = True
    ci["provider"] = "github-actions"
    ci["workflows"] = [os.path.basename(w) for w in gh_workflows]
    # Detect steps
    all_wf_content = ""
    for wf in gh_workflows:
        wf_content = _safe_read(wf)
        if wf_content:
            all_wf_content += wf_content.lower()
    ci["has_lint"] = "lint" in all_wf_content or "eslint" in all_wf_content
    ci["has_tests"] = "test" in all_wf_content
    ci["has_deploy"] = "deploy" in all_wf_content or "release" in all_wf_content
elif os.path.exists(f"{project_dir}/.gitlab-ci.yml"):
    ci = {"has_ci": True, "provider": "gitlab-ci", "workflows": [".gitlab-ci.yml"]}
elif os.path.exists(f"{project_dir}/.circleci"):
    ci = {"has_ci": True, "provider": "circleci", "workflows": ["config.yml"]}
index["ci"] = ci

# ── Detect env vars ──────────────────────────────────────────────────
env_vars = set()
for env_file in ['.env.example', '.env.sample', '.env.template', '.env.local.example']:
    env_path = f"{project_dir}/{env_file}"
    if os.path.exists(env_path):
        try:
            with open(env_path) as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith('#') and '=' in line:
                        env_vars.add(line.split('=')[0].strip())
        except (IOError, OSError) as e:
            _warn(f"Could not read {env_file}: {e}")

# Also scan source for process.env / os.environ (with size guard)
for sf in source_files[:MAX_SCAN_FILES]:
    content = _safe_read(f"{project_dir}/{sf}")
    if content is None:
        continue
    env_vars.update(re.findall(r'process\.env\.([A-Z_][A-Z0-9_]*)', content))
    env_vars.update(re.findall(r'os\.environ\.get\(["\']([A-Z_][A-Z0-9_]*)', content))
    env_vars.update(re.findall(r'os\.getenv\(["\']([A-Z_][A-Z0-9_]*)', content))
index["env_vars"] = sorted(list(env_vars))

# ── API surface ──────────────────────────────────────────────────────
routes_count = 0
middleware_count = 0
models_count = 0
for sf in source_files[:MAX_SCAN_FILES]:
    content = _safe_read(f"{project_dir}/{sf}")
    if content is None:
        continue
    routes_count += len(re.findall(r'\.(get|post|put|patch|delete|all)\s*\(', content, re.I))
    routes_count += len(re.findall(r'@(Get|Post|Put|Patch|Delete|Route)\s*\(', content))
    middleware_count += len(re.findall(r'\.use\s*\(', content))
    models_count += len(re.findall(r'model\s+\w+\s*\{', content))
index["api_surface"] = {
    "routes_count": routes_count,
    "middleware_count": middleware_count,
    "models_count": models_count
}

# ── Save project-index.json ──────────────────────────────────────────
os.makedirs(project_vault, exist_ok=True)
index_path = f"{project_vault}/project-index.json"
with open(index_path, 'w') as f:
    json.dump(index, f, indent=2)
print(f"\033[0;32m[canuto]\033[0m \u2713 project-index.json ({index['structure'].get('file_count', {}).get('total', 0)} files, {total_loc} LOC, {len(domains)} domains)")

# ═══════════════════════════════════════════════════════════════════════
# PHASE 2: Cross-reference with other projects → onboarding-report.md
# ═══════════════════════════════════════════════════════════════════════

projects_dir = f"{vault}/projects"
other_projects = []

if os.path.exists(projects_dir):
    for p in os.listdir(projects_dir):
        if p == project_slug or p == '.obsidian':
            continue
        p_index = f"{projects_dir}/{p}/project-index.json"
        if os.path.exists(p_index):
            try:
                with open(p_index) as f:
                    other_projects.append(json.load(f))
            except (json.JSONDecodeError, IOError, OSError) as e:
                _warn(f"Could not read project-index.json for {p}: {e}")

if not other_projects:
    print(f"\033[1;33m[canuto]\033[0m No other indexed projects in vault. Onboarding report skipped.")
    print(f"\033[1;33m[canuto]\033[0m Run install.sh in other projects first, then re-run /auto-analysis.")
    sys.exit(0)

# ── Calculate stack match ────────────────────────────────────────────
my_deps = _dependency_keys(index)
my_domains = set(_domain_names(index))
my_patterns = set(_pattern_names(index))

matches = []
for other in other_projects:
    other_deps = _dependency_keys(other)
    other_domains = set(_domain_names(other))
    other_patterns = set(_pattern_names(other))

    shared_deps = my_deps & other_deps
    dep_match = len(shared_deps) / max(len(my_deps | other_deps), 1)
    domain_match = len(my_domains & other_domains) / max(len(my_domains | other_domains), 1)
    pattern_match = len(my_patterns & other_patterns) / max(len(my_patterns | other_patterns), 1)

    overall = dep_match * 0.5 + domain_match * 0.3 + pattern_match * 0.2
    matches.append({
        "slug": other["slug"],
        "dep_match": round(dep_match * 100),
        "domain_match": round(domain_match * 100),
        "overall": round(overall * 100),
        "shared_deps": sorted(list(shared_deps))[:15],
        "shared_domains": sorted(list(my_domains & other_domains)),
        "stack": _stack_info(other),
    })

matches.sort(key=lambda m: m["overall"], reverse=True)

# ── Collect instincts from similar projects ──────────────────────────
def read_frontmatter(filepath):
    """Extract YAML frontmatter and first heading from a markdown note."""
    fm = {}
    try:
        with open(filepath, errors='ignore') as f:
            lines = f.readlines()
        if not lines or lines[0].strip() != '---':
            return fm
        # Parse frontmatter (handle values with colons like URLs)
        for line in lines[1:]:
            if line.strip() == '---':
                break
            if ':' in line:
                key, _, val = line.partition(':')
                key = key.strip()
                val = val.strip().strip('"')
                # Skip YAML arrays/objects and comments
                if key and not key.startswith('#') and not key.startswith('-'):
                    fm[key] = val
        # Grab first heading after frontmatter as title
        found_end = 0
        for line in lines[1:]:
            if line.strip() == '---':
                found_end += 1
                if found_end >= 1:
                    continue
            if found_end >= 1 and line.startswith('# '):
                fm['_title'] = line.lstrip('# ').strip()
                break
    except (IOError, OSError) as e:
        _warn(f"Could not read {filepath}: {e}")
    return fm

recommended_instincts = []
relevant_decisions = []
common_issues = Counter()

for match in matches[:5]:  # Top 5 similar projects
    if match["overall"] < 40:
        continue
    slug = match["slug"]
    p_dir = f"{projects_dir}/{slug}"

    # Instincts
    for ifile in glob.glob(f"{p_dir}/instincts/*.md"):
        if '.gitkeep' in ifile:
            continue
        fm = read_frontmatter(ifile)
        conf = fm.get("confidence", "low")
        if conf in ("high", "medium"):
            recommended_instincts.append({
                "project": slug,
                "name": os.path.basename(ifile).replace('.md', ''),
                "title": fm.get('_title', fm.get('id', 'unknown')),
                "category": fm.get('category', 'unknown'),
                "confidence": conf,
                "applied": _safe_int(fm.get('applied', '0')),
                "match": match["overall"],
            })

    # Decisions
    for dfile in glob.glob(f"{p_dir}/decisions/*.md"):
        if '.gitkeep' in dfile or 'migrated' in dfile:
            continue
        fm = read_frontmatter(dfile)
        relevant_decisions.append({
            "project": slug,
            "name": os.path.basename(dfile).replace('.md', ''),
            "title": fm.get('_title', fm.get('id', 'unknown')),
            "domain": fm.get('domain', 'unknown'),
            "status": fm.get('status', 'unknown'),
            "match": match["overall"],
        })

    # Session rework patterns
    for sfile in glob.glob(f"{p_dir}/sessions/*.md"):
        if '.gitkeep' in sfile:
            continue
        content = _safe_read(sfile)
        if content is None:
            continue
        content = content.lower()
        if 'rework' in content:
            common_issues['rework detected'] += 1
        if 'error' in content and 'swallow' in content:
            common_issues['silent error swallowing'] += 1
        if 'flak' in content or 'intermittent' in content:
            common_issues['test flakiness'] += 1
        if 'timeout' in content:
            common_issues['timeout issues'] += 1
        if 'memory' in content and ('leak' in content or 'oom' in content):
            common_issues['memory issues'] += 1

# Also check global instincts
for ifile in glob.glob(f"{vault}/global-instincts/*.md"):
    if '.gitkeep' in ifile:
        continue
    fm = read_frontmatter(ifile)
    recommended_instincts.append({
        "project": "GLOBAL",
        "name": os.path.basename(ifile).replace('.md', ''),
        "title": fm.get('_title', fm.get('id', 'unknown')),
        "category": fm.get('category', 'unknown'),
        "confidence": fm.get('confidence', 'high'),
        "applied": _safe_int(fm.get('applied', '0')),
        "match": 100,
    })

# Sort by relevance
recommended_instincts.sort(key=lambda i: (i["match"], i["applied"]), reverse=True)
relevant_decisions.sort(key=lambda d: d["match"], reverse=True)

# ── Generate onboarding-report.md ────────────────────────────────────
report = []
report.append("---")
report.append(f"title: Auto-Analysis — {project_slug}")
report.append(f"date: {today[:10]}")
report.append("type: onboarding-report")
report.append("tags:")
report.append("  - auto-analysis")
report.append("  - cross-project")
report.append("---")
report.append("")
report.append(f"# Auto-Analysis: {project_slug}")
report.append("")
report.append(f"Generated: {today}")
report.append("")

# Stack summary
st = index.get("stack", {})
report.append("## Project Stack")
report.append("")
report.append(f"- **Language**: {st.get('primary_language', 'unknown')}")
if st.get("framework"): report.append(f"- **Framework**: {st['framework']}")
if st.get("orm"): report.append(f"- **ORM**: {st['orm']}")
if st.get("test_framework"): report.append(f"- **Tests**: {st['test_framework']}")
if st.get("ui_framework"): report.append(f"- **UI**: {st['ui_framework']}")
report.append(f"- **LOC**: {total_loc:,}")
report.append(f"- **Domains**: {', '.join(_domain_names(index)) or 'none detected'}")
report.append(f"- **Patterns**: {', '.join(_pattern_names(index)) or 'none detected'}")
report.append("")

# Similar projects
report.append("## Similar Projects in Vault")
report.append("")
if matches and matches[0]["overall"] >= 20:
    report.append("| Project | Overall Match | Deps Match | Domains Match | Shared Deps |")
    report.append("|---------|--------------|------------|---------------|-------------|")
    for m in matches[:5]:
        if m["overall"] < 20:
            break
        deps_preview = ", ".join(m["shared_deps"][:5])
        if len(m["shared_deps"]) > 5:
            deps_preview += f" +{len(m['shared_deps'])-5} more"
        safe_slug = m['slug'].replace('|', '-')
        report.append(f"| [[projects/{safe_slug}\\|{safe_slug}]] | {m['overall']}% | {m['dep_match']}% | {m['domain_match']}% | {deps_preview} |")
    report.append("")
else:
    report.append("No similar projects found (all matches < 20%).")
    report.append("")

# Recommended instincts
report.append("## Recommended Instincts")
report.append("")
if recommended_instincts:
    for inst in recommended_instincts[:10]:
        icon = {'high': '🟢', 'medium': '🟡'}.get(inst["confidence"], '⚪')
        src = f"[{inst['project']}]" if inst["project"] != "GLOBAL" else "[GLOBAL]"
        report.append(f"- {icon} {src} **{inst['title']}** ({inst['category']}) — confidence: {inst['confidence']}, applied: {inst['applied']}x")
    report.append("")
else:
    report.append("No instincts found in similar projects yet.")
    report.append("")

# Relevant decisions
report.append("## Relevant Decisions")
report.append("")
if relevant_decisions:
    for dec in relevant_decisions[:8]:
        report.append(f"- [{dec['project']}] **{dec['title']}** (domain: {dec['domain']}, status: {dec['status']})")
    report.append("")
else:
    report.append("No decisions found in similar projects yet.")
    report.append("")

# Common issues
report.append("## Common Issues in Similar Projects")
report.append("")
if common_issues:
    for issue, count in common_issues.most_common(5):
        report.append(f"- **{issue}** — seen in {count} session(s)")
    report.append("")
else:
    report.append("No common issues detected.")
    report.append("")

# Save
report_path = f"{project_vault}/onboarding-report.md"
with open(report_path, 'w') as f:
    f.write('\n'.join(report))

print(f"\033[0;32m[canuto]\033[0m \u2713 onboarding-report.md ({len(matches)} projects compared, {len(recommended_instincts)} instincts, {len(relevant_decisions)} decisions)")

PYEOF
}

# ── CHECK ───────────────────────────────────────────────────────────────────
if [ "$MODE" = "check" ]; then
  echo ""
  echo -e "${CYAN}\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501${RESET}"
  echo -e "${CYAN}  Canuto Framework \u2014 Version Check${RESET}"
  echo -e "${CYAN}\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501${RESET}"
  echo ""

  UP_TO_DATE=0
  OUTDATED=0
  MISSING=0

  for file in "${FRAMEWORK_FILES[@]}"; do
    if [ ! -f "$file" ]; then
      echo -e "  ${RED}\u2717 MISSING${RESET}    $file"
      MISSING=$((MISSING + 1))
    else
      LOCAL_VER=$(grep "^version:" "$file" 2>/dev/null | head -1 | awk '{print $2}')
      REMOTE_VER=$(fetch_content "$file" | grep "^version:" | head -1 | awk '{print $2}')

      if [ -z "$LOCAL_VER" ] || [ -z "$REMOTE_VER" ]; then
        echo -e "  ${YELLOW}? UNKNOWN${RESET}    $file (no version field)"
      elif [ "$LOCAL_VER" = "$REMOTE_VER" ]; then
        echo -e "  ${GREEN}\u2713 OK${RESET}        $file (v$LOCAL_VER)"
        UP_TO_DATE=$((UP_TO_DATE + 1))
      else
        echo -e "  ${YELLOW}\u26a0 OUTDATED${RESET}   $file (local: v$LOCAL_VER \u2192 remote: v$REMOTE_VER)"
        OUTDATED=$((OUTDATED + 1))
      fi
    fi
  done

  echo ""
  echo -e "  Summary: ${GREEN}${UP_TO_DATE} up-to-date${RESET}  ${YELLOW}${OUTDATED} outdated${RESET}  ${RED}${MISSING} missing${RESET}"
  echo ""

  if [ "$OUTDATED" -gt 0 ] || [ "$MISSING" -gt 0 ]; then
    log "Run 'bash install.sh --update' to update outdated/missing files."
  else
    ok "All framework files are up to date."
  fi
  echo ""
  rm -rf "$TMP_DIR"
  exit 0
fi

# ── SKILL INSTALL ───────────────────────────────────────────────────────────
if [ "$MODE" = "skill" ]; then
  echo ""
  echo -e "${CYAN}\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501${RESET}"
  echo -e "${CYAN}  Canuto Framework \u2014 Skill Install${RESET}"
  echo -e "${CYAN}\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501${RESET}"
  echo ""

  INSTALLED=()
  for skill_name in "${SKILLS_TO_INSTALL[@]}"; do
    log "Installing skill: $skill_name..."
    mapfile -t skill_files < <(skill_remote_files "$skill_name")
    installed_skill=true
    for skill_file in "${skill_files[@]}"; do
      if ! download "$skill_file" "$skill_file"; then
        installed_skill=false
        break
      fi
    done

    if [ "$installed_skill" = true ]; then
      ok "Installed: $skill_name"
      INSTALLED+=("$skill_name")
    else
      warn "Skill '$skill_name' not found. Check registry.md for available skills."
    fi
  done

  if [ "${#INSTALLED[@]}" -gt 0 ] && [ "$GIT_AVAILABLE" = true ]; then
    git add ".agents/skills/" 2>/dev/null || true
    echo ""
    read -r -p "$(echo -e "${CYAN}[canuto]${RESET} Commit installed skills? [Y/n] ")" COMMIT_ANSWER
    COMMIT_ANSWER="${COMMIT_ANSWER:-Y}"
    if [[ "$COMMIT_ANSWER" =~ ^[Yy]$ ]]; then
      SKILL_LIST=$(IFS=', '; echo "${INSTALLED[*]}")
      git commit -m "chore: install Canuto skills ($SKILL_LIST)"
      ok "Committed!"
    fi
  fi

  echo ""
  ok "Done. Maestro will pick up new skills in the next session."
  echo ""
  rm -rf "$TMP_DIR"
  exit 0
fi

# ── REPAIR ──────────────────────────────────────────────────────────────────
if [ "$MODE" = "repair" ]; then
  echo ""
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${CYAN}  Canuto Framework — Repair${RESET}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo ""

  repair_runtime

  if [ "$JSON_OUTPUT" = false ]; then
    echo ""
    ok "Runtime repaired. Validate with: bash install.sh --test"
    echo ""
  fi

  rm -rf "$TMP_DIR"
  exit 0
fi

# ── DOCTOR ──────────────────────────────────────────────────────────────────
if [ "$MODE" = "doctor" ]; then
  repair_runtime
  if run_install_validation; then
    rm -rf "$TMP_DIR"
    exit 0
  fi
  rm -rf "$TMP_DIR"
  exit 1
fi

# ── MIGRATE ─────────────────────────────────────────────────────────────────
# Upgrades from old flat-file memory (.agents/memory/) to Obsidian vault.
# Safe to run multiple times. Backs up old memory/ before touching anything.
if [ "$MODE" = "migrate" ]; then
  echo ""
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${CYAN}  Canuto Framework — Migrate to v1.5${RESET}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo ""

  # ── Step 1: Backup ────────────────────────────────────────────────────────
  BACKUP_DIR=".agents/memory-backup-$(date +%Y%m%d-%H%M%S)"
  if [ -d ".agents/memory" ]; then
    cp -r ".agents/memory" "$BACKUP_DIR"
    ok "Backup created: $BACKUP_DIR"
  else
    log "No .agents/memory/ found — skipping backup."
  fi

  # ── Step 2: Update framework files (personas, skills, hooks, SPEC) ───────
  log "Downloading updated framework files..."
  for file in "${FRAMEWORK_FILES[@]}"; do
    download "$file" "$file"
  done
  ok "Framework files updated"

  # ── Step 3: Create vault structure ───────────────────────────────────────
  log "Creating vault structure..."
  for file in "${INSTALL_ONLY_FILES[@]}"; do
    if [ ! -f "$file" ]; then
      download "$file" "$file"
      ok "Created: $file"
    else
      ok "Already exists: $file (skipped)"
    fi
  done

  for dir in "${VAULT_DIRS[@]}"; do
    mkdir -p "$dir"
    touch "$dir/.gitkeep"
  done
  ok "Vault directories ready"

  # ── Step 4: Migrate data from flat files to vault notes ──────────────────
  MIGRATED=0

  migrate_flat_file() {
    local src="$1"    # e.g. ".agents/memory/decisions.md"
    local dst_dir="$2" # e.g. ".agents/vault/decisions"
    local dst_file="$3" # e.g. "migrated-from-flat.md"

    if [ -f "$src" ]; then
      local content
      content=$(cat "$src")
      # Skip if file is just a template (< 200 bytes or only has headers)
      local size
      size=$(wc -c < "$src" | tr -d ' ')
      if [ "$size" -gt 200 ]; then
        mkdir -p "$dst_dir"
        cp "$src" "$dst_dir/$dst_file"
        ok "Migrated: $src → $dst_dir/$dst_file"
        MIGRATED=$((MIGRATED + 1))
      else
        log "Skipped: $src (template only, ${size} bytes)"
      fi
    fi
  }

  PROJECT_DIR=$(resolve_project_dir)
  PROJECT_SLUG=$(detect_project_slug "$PROJECT_DIR")
  PROJECT_VAULT="$HOME/.canuto/vault/projects/$PROJECT_SLUG"

  migrate_flat_file ".agents/memory/decisions.md"           "$PROJECT_VAULT/decisions"  "migrated-decisions.md"
  migrate_flat_file ".agents/memory/instincts.md"           "$PROJECT_VAULT/instincts"  "migrated-instincts.md"
  migrate_flat_file ".agents/memory/last-session.md"        "$PROJECT_VAULT/sessions"   "migrated-last-session.md"
  migrate_flat_file ".agents/memory/pending.md"             "$PROJECT_VAULT/pending"    "migrated-pending.md"
  migrate_flat_file ".agents/memory/metrics.md"             "$PROJECT_VAULT/metrics"    "migrated-metrics.md"
  migrate_flat_file ".agents/memory/audit-log.md"           "$PROJECT_VAULT/audit"      "migrated-audit-log.md"
  migrate_flat_file ".agents/memory/design-profile.md"      "$PROJECT_VAULT/design"     "profile.md"
  migrate_flat_file ".agents/memory/component-inventory.md" "$PROJECT_VAULT/design/components" "migrated-inventory.md"

  # ── Step 5: Setup deps, hooks, tools ─────────────────────────────────────
  repair_runtime

  # ── Step 6: Clean up old memory dir ──────────────────────────────────────
  if [ -d ".agents/memory" ] && [ "$MIGRATED" -gt 0 ]; then
    echo ""
    warn "Old .agents/memory/ still exists (backup at $BACKUP_DIR)."
    if confirm_yes "Delete old .agents/memory/? [y/N] " "N"; then
      rm -rf ".agents/memory"
      ok "Deleted .agents/memory/"
    else
      log "Kept .agents/memory/ — delete manually when ready."
    fi
  fi

  # ── Step 7: Commit ──────────────────────────────────────────────────────
  if [ "$GIT_AVAILABLE" = true ]; then
    echo ""
    git add "$AGENTS_DIR/" "$CLAUDE_MD" "AGENTS.md" ".context.md" "docs/" 2>/dev/null || true
    if confirm_yes "Commit migration? [Y/n] " "Y"; then
      if git diff --cached --quiet; then
        log "Nothing to commit — framework already up to date."
      else
        git commit -m "chore: migrate Canuto Framework to v1.5 (Obsidian vault)"
        ok "Committed!"
      fi
    fi
  fi

  echo ""
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  # ── Post-migrate analysis ────────────────────────────────────────────────
  echo ""
  if confirm_yes "Run cross-project auto-analysis? [Y/n] " "Y"; then
    PROJECT_DIR="$(resolve_project_dir "$(pwd)")" post_install_analysis "$(pwd)"
  fi

  echo -e "${GREEN}  Migration complete! $MIGRATED files migrated.${RESET}"
  echo -e "${GREEN}  Next: open ~/.canuto/vault/ in Obsidian${RESET}"
  echo -e "${GREEN}  (if not already open) and you're done.${RESET}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo ""
  rm -rf "$TMP_DIR"
  exit 0
fi

# ── INSTALL ─────────────────────────────────────────────────────────────────
if [ "$MODE" = "install" ]; then
  echo ""
  echo -e "${CYAN}\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501${RESET}"
  echo -e "${CYAN}  Canuto Framework \u2014 Fresh Install${RESET}"
  echo -e "${CYAN}\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501${RESET}"
  echo ""

  log "Downloading framework files..."

  for file in "${FRAMEWORK_FILES[@]}"; do
    download "$file" "$file"
    ok "$file"
  done

  for file in "${INSTALL_ONLY_FILES[@]}"; do
    download "$file" "$file"
    ok "$file"
  done

  mkdir -p ".agents/plugins"
  touch ".agents/plugins/.gitkeep"
  ok ".agents/plugins/ (empty, ready for plugins)"

  for dir in "${VAULT_DIRS[@]}"; do
    mkdir -p "$dir"
    touch "$dir/.gitkeep"
  done
  ok "Vault directories created"

  repair_runtime

  if [ "$GIT_AVAILABLE" = true ]; then
    echo ""
    log "Staging files for git..."
    git add "$AGENTS_DIR/" "$CLAUDE_MD" "AGENTS.md" ".context.md" "docs/" 2>/dev/null || true
    echo ""
    if confirm_yes "Commit now? [Y/n] " "Y"; then
      git commit -m "chore: add Canuto Framework v1.6"
      ok "Committed!"
    else
      warn "Files staged but not committed. Run 'git commit' when ready."
    fi
  fi

  echo ""
  echo -e "${GREEN}\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501${RESET}"
  # ── Post-install analysis ─────────────────────────────────────────────────
  echo ""
  if confirm_yes "Run cross-project auto-analysis? [Y/n] " "Y"; then
    PROJECT_DIR="$(resolve_project_dir "$(pwd)")" post_install_analysis "$(pwd)"
  fi

  if ! run_install_validation; then
    warn "Post-install validation reported issues. Re-run: bash install.sh --doctor"
  fi

  echo -e "${GREEN}  Done! v1.6 installed. Open the project in Claude and${RESET}"
  echo -e "${GREEN}  the Maestro will take it from here.${RESET}"
  echo -e "${GREEN}\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501${RESET}"
  echo ""
fi

# ── UPDATE ───────────────────────────────────────────────────────────────────
if [ "$MODE" = "update" ]; then
  echo ""
  echo -e "${CYAN}\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501${RESET}"
  echo -e "${CYAN}  Canuto Framework \u2014 Update${RESET}"
  echo -e "${CYAN}\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501${RESET}"
  echo ""
  warn "This will update personas, skills, hooks, and SPEC.md."
  warn "vault/ and plugins/ will NOT be touched."
  echo ""
  if ! confirm_yes "Proceed? [Y/n] " "Y"; then
    log "Aborted."
    exit 0
  fi

  log "Downloading updated framework files..."
  for file in "${FRAMEWORK_FILES[@]}"; do
    download "$file" "$file"
    ok "updated: $file"
  done
  for file in "${INSTALL_ONLY_FILES[@]}"; do
    if [ ! -f "$file" ]; then
      download "$file" "$file"
      ok "created missing support file: $file"
    fi
  done

  repair_runtime

  if [ "$GIT_AVAILABLE" = true ]; then
    echo ""
    log "Staging updated files..."
    git add "$AGENTS_DIR/" "$CLAUDE_MD" "AGENTS.md" ".context.md" "docs/" 2>/dev/null || true
    echo ""
    if confirm_yes "Commit now? [Y/n] " "Y"; then
      git commit -m "chore: update Canuto Framework to v1.6"
      ok "Committed!"
    else
      warn "Files staged but not committed. Run 'git commit' when ready."
    fi
  fi

  if ! run_install_validation; then
    warn "Post-update validation reported issues. Re-run: bash install.sh --doctor"
  fi

  echo ""
  echo -e "${GREEN}\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501${RESET}"
  echo -e "${GREEN}  Framework updated to v1.6 successfully.${RESET}"
  echo -e "${GREEN}\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501${RESET}"
  echo ""
fi

# ── TEST ────────────────────────────────────────────────────────────────────
if [ "$MODE" = "test" ]; then
  if run_install_validation; then
    rm -rf "$TMP_DIR"
    exit 0
  fi
  rm -rf "$TMP_DIR"
  exit 1
fi

# ── Cleanup ──────────────────────────────────────────────────────────────────
rm -rf "$TMP_DIR"
