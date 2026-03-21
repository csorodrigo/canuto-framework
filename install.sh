#!/usr/bin/env bash
# =============================================================================
# Canuto Framework — Installer / Updater
# Usage:
#   Fresh install:    curl -fsSL https://raw.githubusercontent.com/csorodrigo/canuto-framework/main/install.sh | bash
#   Local run:        bash install.sh
#   Update only:      bash install.sh --update
#   Update via curl:  curl -fsSL https://raw.githubusercontent.com/csorodrigo/canuto-framework/main/install.sh | bash -s -- --update
#   Check versions:   bash install.sh --check
#   Migrate from v1:  bash install.sh --migrate
#   Install a skill:  bash install.sh --skill pr-description --skill health-check
# =============================================================================

set -euo pipefail

REPO_URL="https://raw.githubusercontent.com/csorodrigo/canuto-framework/main"
AGENTS_DIR=".agents"
CLAUDE_MD="CLAUDE.md"
TMP_DIR=$(mktemp -d)
MODE="auto" # auto | install | update | check | skill | migrate
SKILLS_TO_INSTALL=()

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
    --migrate) MODE="migrate" ;;
    --skill)
      shift
      SKILLS_TO_INSTALL+=("$1")
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

# ── Confirm not running in the framework repo itself ────────────────────────
if git remote -v 2>/dev/null | grep -q "canuto-framework"; then
  warn "This looks like the canuto-framework repo itself. Aborting."
  exit 0
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

# ── File lists ──────────────────────────────────────────────────────────────

FRAMEWORK_FILES=(
  ".agents/personas/maestro.md"
  ".agents/personas/architect.md"
  ".agents/personas/coder.md"
  ".agents/personas/tester.md"
  ".agents/personas/debugger.md"
  ".agents/personas/reviewer.md"
  ".agents/personas/contextualizer.md"
  ".agents/skills/context-maintenance.md"
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
  ".agents/hooks/session-save.sh"
  ".agents/hooks/session-load.sh"
  ".agents/hooks/pre-compact-save.sh"
  ".agents/skills/continuous-learning.md"
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
  ".agents/skills/frontend-design.md"
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

  log "Setting up hooks..."
  mkdir -p "$HOME/.claude/hooks"

  # Initialize settings.json if missing
  if [ ! -f "$settings" ]; then
    echo '{"hooks":{}}' > "$settings"
  fi

  # ── Helper: install a single hook ──────────────────────────────────────
  install_hook() {
    local src="$1"       # e.g. ".agents/hooks/plan-review.sh"
    local event="$2"     # e.g. "ExitPlanMode"
    local timeout="$3"   # e.g. 120
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
      local new_hook="{\"hooks\":[{\"type\":\"command\",\"command\":\"~/.claude/hooks/$filename\",\"timeout\":$timeout}]}"
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
  # Note: ExitPlanMode is not a valid Claude Code hook event.
  # plan-review.sh is installed to ~/.claude/hooks/ for manual use only.
  if [ -f ".agents/hooks/plan-review.sh" ]; then
    cp ".agents/hooks/plan-review.sh" "$HOME/.claude/hooks/plan-review.sh"
    chmod +x "$HOME/.claude/hooks/plan-review.sh"
    ok "Installed: $HOME/.claude/hooks/plan-review.sh (run manually: bash ~/.claude/hooks/plan-review.sh)"
  fi
  install_hook ".agents/hooks/session-save.sh"      "Stop"          30
  install_hook ".agents/hooks/pre-compact-save.sh"  "Notification"  15
  # session-load.sh is a utility script, not a hook — it's called manually or via CLAUDE.md
  if [ -f ".agents/hooks/session-load.sh" ]; then
    cp ".agents/hooks/session-load.sh" "$HOME/.claude/hooks/session-load.sh"
    chmod +x "$HOME/.claude/hooks/session-load.sh"
    ok "Installed: $HOME/.claude/hooks/session-load.sh (utility — run manually with: bash ~/.claude/hooks/session-load.sh)"
  fi
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

# ── setup_global_vault ────────────────────────────────────────────────────────
# Creates a global Obsidian vault at ~/.canuto/vault/ (one vault for all projects).
# Each project gets its own subdirectory under projects/{project-slug}/.
# Safe to run multiple times.
setup_global_vault() {
  local vault="$HOME/.canuto/vault"
  local project_slug
  project_slug=$(basename "$(pwd)")

  log "Setting up global vault at $vault..."

  # Create vault root with Obsidian config
  mkdir -p "$vault/.obsidian"
  mkdir -p "$vault/projects"

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

  # Create global dirs (bases, canvas)
  mkdir -p "$vault/bases" "$vault/canvas"

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

  echo ""
  echo -e "${CYAN}  Obsidian MCP requires the Local REST API plugin.${RESET}"
  echo -e "${CYAN}  In Obsidian: Settings → Community Plugins → Browse → \"Local REST API\" → Install → Enable${RESET}"
  echo -e "${CYAN}  Then copy the API Key from the plugin settings.${RESET}"
  echo ""
  read -r -p "$(echo -e "${CYAN}[canuto]${RESET} Paste your Obsidian Local REST API key (or press Enter to skip): ")" API_KEY

  if [ -z "$API_KEY" ]; then
    warn "Skipped Obsidian MCP setup. Configure manually later (see .agents/mcp/setup.md)."
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
    skill_file=".agents/skills/${skill_name}.md"
    remote_path=".agents/skills/${skill_name}.md"
    log "Installing skill: $skill_name..."
    if download "$remote_path" "$skill_file"; then
      ok "Installed: $skill_file"
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

  PROJECT_SLUG=$(basename "$(pwd)")
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
  setup_deps
  merge_claude_md
  setup_hooks
  setup_search_tools
  setup_global_vault
  setup_obsidian_mcp

  # ── Step 6: Clean up old memory dir ──────────────────────────────────────
  if [ -d ".agents/memory" ] && [ "$MIGRATED" -gt 0 ]; then
    echo ""
    warn "Old .agents/memory/ still exists (backup at $BACKUP_DIR)."
    read -r -p "$(echo -e "${CYAN}[canuto]${RESET} Delete old .agents/memory/? [y/N] ")" DELETE_OLD
    if [[ "$DELETE_OLD" =~ ^[Yy]$ ]]; then
      rm -rf ".agents/memory"
      ok "Deleted .agents/memory/"
    else
      log "Kept .agents/memory/ — delete manually when ready."
    fi
  fi

  # ── Step 7: Commit ──────────────────────────────────────────────────────
  if [ "$GIT_AVAILABLE" = true ]; then
    echo ""
    git add "$AGENTS_DIR/" "$CLAUDE_MD" 2>/dev/null || true
    read -r -p "$(echo -e "${CYAN}[canuto]${RESET} Commit migration? [Y/n] ")" COMMIT_ANSWER
    COMMIT_ANSWER="${COMMIT_ANSWER:-Y}"
    if [[ "$COMMIT_ANSWER" =~ ^[Yy]$ ]]; then
      git commit -m "chore: migrate Canuto Framework to v1.5 (Obsidian vault)"
      ok "Committed!"
    fi
  fi

  echo ""
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
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

  setup_deps
  merge_claude_md
  setup_hooks
  setup_search_tools
  setup_global_vault
  setup_obsidian_mcp
  setup_gstack
  setup_global_skills

  if [ "$GIT_AVAILABLE" = true ]; then
    echo ""
    log "Staging files for git..."
    git add "$AGENTS_DIR/" "$CLAUDE_MD" 2>/dev/null || true
    echo ""
    read -r -p "$(echo -e "${CYAN}[canuto]${RESET} Commit now? [Y/n] ")" COMMIT_ANSWER
    COMMIT_ANSWER="${COMMIT_ANSWER:-Y}"
    if [[ "$COMMIT_ANSWER" =~ ^[Yy]$ ]]; then
      git commit -m "chore: add Canuto Framework v1.5"
      ok "Committed!"
    else
      warn "Files staged but not committed. Run 'git commit' when ready."
    fi
  fi

  echo ""
  echo -e "${GREEN}\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501${RESET}"
  echo -e "${GREEN}  Done! v1.5 installed. Open the project in Claude and${RESET}"
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
  read -r -p "$(echo -e "${CYAN}[canuto]${RESET} Proceed? [Y/n] ")" PROCEED
  PROCEED="${PROCEED:-Y}"
  if [[ ! "$PROCEED" =~ ^[Yy]$ ]]; then
    log "Aborted."
    exit 0
  fi

  log "Downloading updated framework files..."
  for file in "${FRAMEWORK_FILES[@]}"; do
    download "$file" "$file"
    ok "updated: $file"
  done

  setup_deps
  merge_claude_md
  setup_hooks
  setup_search_tools
  setup_global_vault
  setup_obsidian_mcp
  setup_gstack
  setup_global_skills

  if [ "$GIT_AVAILABLE" = true ]; then
    echo ""
    log "Staging updated files..."
    git add "$AGENTS_DIR/personas/" "$AGENTS_DIR/skills/" "$AGENTS_DIR/hooks/" "$AGENTS_DIR/SPEC.md" "$CLAUDE_MD" 2>/dev/null || true
    echo ""
    read -r -p "$(echo -e "${CYAN}[canuto]${RESET} Commit now? [Y/n] ")" COMMIT_ANSWER
    COMMIT_ANSWER="${COMMIT_ANSWER:-Y}"
    if [[ "$COMMIT_ANSWER" =~ ^[Yy]$ ]]; then
      git commit -m "chore: update Canuto Framework to v1.5"
      ok "Committed!"
    else
      warn "Files staged but not committed. Run 'git commit' when ready."
    fi
  fi

  echo ""
  echo -e "${GREEN}\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501${RESET}"
  echo -e "${GREEN}  Framework updated to v1.5 successfully.${RESET}"
  echo -e "${GREEN}\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501${RESET}"
  echo ""
fi

# ── Cleanup ──────────────────────────────────────────────────────────────────
rm -rf "$TMP_DIR"
