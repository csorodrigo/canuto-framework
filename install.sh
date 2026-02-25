#!/usr/bin/env bash
# =============================================================================
# Canuto Framework — Installer / Updater
# Usage:
#   Fresh install:  curl -fsSL https://raw.githubusercontent.com/csorodrigo/canuto-framework/main/install.sh | bash
#   Local run:      bash install.sh
#   Update only:    bash install.sh --update
# =============================================================================

set -euo pipefail

REPO_URL="https://raw.githubusercontent.com/csorodrigo/canuto-framework/main"
AGENTS_DIR=".agents"
CLAUDE_MD="CLAUDE.md"
TMP_DIR=$(mktemp -d)
MODE="auto" # auto | update

# ── Colors ────────────────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
RESET='\033[0m'

log()    { echo -e "${CYAN}[canuto]${RESET} $1"; }
ok()     { echo -e "${GREEN}[canuto]${RESET} \u2713 $1"; }
warn()   { echo -e "${YELLOW}[canuto]${RESET} \u26a0 $1"; }
error()  { echo -e "${RED}[canuto]${RESET} \u2717 $1"; exit 1; }

# ── Parse args ────────────────────────────────────────────────────────────────────────────
for arg in "$@"; do
  case $arg in
    --update) MODE="update" ;;
  esac
done

# ── Detect mode ────────────────────────────────────────────────────────────────────────────
if [ "$MODE" = "auto" ]; then
  if [ -d "$AGENTS_DIR" ]; then
    MODE="update"
  else
    MODE="install"
  fi
fi

# ── Confirm not running in the framework repo itself ───────────────────────────────
if [ -f ".agents/SPEC.md" ] && grep -q "Canuto Framework" ".agents/SPEC.md" 2>/dev/null; then
  if [ ! -f "src/index.js" ] && [ ! -f "src/main.py" ] && [ ! -f "package.json" ]; then
    warn "This looks like the canuto-framework repo itself. Aborting."
    exit 0
  fi
fi

# ── Check if we're inside a git repo ───────────────────────────────────────────────────
if ! git rev-parse --git-dir > /dev/null 2>&1; then
  warn "Not a git repository. Files will be copied but not committed."
  GIT_AVAILABLE=false
else
  GIT_AVAILABLE=true
fi

# ── Download files from GitHub ─────────────────────────────────────────────────────────────────────
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

# Files to always copy (personas + skills)
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
  ".agents/SPEC.md"
)

# Files only copied on fresh install (never overwrite user data)
INSTALL_ONLY_FILES=(
  ".agents/memory/last-session.md"
  ".agents/memory/decisions.md"
  ".agents/memory/pending.md"
  ".agents/memory/metrics.md"
)

# ── INSTALL ───────────────────────────────────────────────────────────────────────────────────
if [ "$MODE" = "install" ]; then
  echo ""
  echo -e "${CYAN}\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501${RESET}"
  echo -e "${CYAN}  Canuto Framework \u2014 Fresh Install${RESET}"
  echo -e "${CYAN}\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501${RESET}"
  echo ""

  log "Downloading framework files..."

  # Download all framework files
  for file in "${FRAMEWORK_FILES[@]}"; do
    download "$file" "$file"
    ok "$file"
  done

  # Download memory templates
  for file in "${INSTALL_ONLY_FILES[@]}"; do
    download "$file" "$file"
    ok "$file"
  done

  # Create plugins directory placeholder
  mkdir -p ".agents/plugins"
  touch ".agents/plugins/.gitkeep"
  ok ".agents/plugins/ (empty, ready for plugins)"

  # CLAUDE.md: create only if it doesn't exist
  if [ -f "$CLAUDE_MD" ]; then
    warn "$CLAUDE_MD already exists \u2014 skipping. Add the Framework section manually (see .agents/SPEC.md \u00a78)."
  else
    download "CLAUDE.md" "$CLAUDE_MD"
    ok "$CLAUDE_MD created"
  fi

  # Git commit
  if [ "$GIT_AVAILABLE" = true ]; then
    echo ""
    log "Staging files for git..."
    git add "$AGENTS_DIR/" "$CLAUDE_MD" 2>/dev/null || true
    echo ""
    read -r -p "$(echo -e "${CYAN}[canuto]${RESET} Commit now? [Y/n] ")" COMMIT_ANSWER
    COMMIT_ANSWER="${COMMIT_ANSWER:-Y}"
    if [[ "$COMMIT_ANSWER" =~ ^[Yy]$ ]]; then
      git commit -m "chore: add Canuto Framework v1.0"
      ok "Committed!"
    else
      warn "Files staged but not committed. Run 'git commit' when ready."
    fi
  fi

  echo ""
  echo -e "${GREEN}\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501${RESET}"
  echo -e "${GREEN}  Done! Open the project in Claude and${RESET}"
  echo -e "${GREEN}  the Maestro will take it from here.${RESET}"
  echo -e "${GREEN}\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501${RESET}"
  echo ""
fi

# ── UPDATE ────────────────────────────────────────────────────────────────────────────────────
if [ "$MODE" = "update" ]; then
  echo ""
  echo -e "${CYAN}\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501${RESET}"
  echo -e "${CYAN}  Canuto Framework \u2014 Update${RESET}"
  echo -e "${CYAN}\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2500\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501${RESET}"
  echo ""
  warn "This will update personas and skills only."
  warn "memory/ and plugins/ will NOT be touched."
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

  # CLAUDE.md: never overwrite on update
  warn "$CLAUDE_MD was NOT updated \u2014 your project-specific config is preserved."

  # Git commit
  if [ "$GIT_AVAILABLE" = true ]; then
    echo ""
    log "Staging updated files..."
    git add "$AGENTS_DIR/personas/" "$AGENTS_DIR/skills/" "$AGENTS_DIR/SPEC.md" 2>/dev/null || true
    echo ""
    read -r -p "$(echo -e "${CYAN}[canuto]${RESET} Commit now? [Y/n] ")" COMMIT_ANSWER
    COMMIT_ANSWER="${COMMIT_ANSWER:-Y}"
    if [[ "$COMMIT_ANSWER" =~ ^[Yy]$ ]]; then
      git commit -m "chore: update Canuto Framework"
      ok "Committed!"
    else
      warn "Files staged but not committed. Run 'git commit' when ready."
    fi
  fi

  echo ""
  echo -e "${GREEN}\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501${RESET}"
  echo -e "${GREEN}  Framework updated successfully.${RESET}"
  echo -e "${GREEN}\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2500\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501${RESET}"
  echo ""
fi

# ── Cleanup ────────────────────────────────────────────────────────────────────────────────────
rm -rf "$TMP_DIR"
