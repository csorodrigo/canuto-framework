#!/usr/bin/env bash
# =============================================================================
# Canuto Framework — Installer / Updater
# Usage:
#   Fresh install:    curl -fsSL https://raw.githubusercontent.com/csorodrigo/canuto-framework/main/install.sh | bash
#   Local run:        bash install.sh
#   Update only:      bash install.sh --update
#   Check versions:   bash install.sh --check
#   Install a skill:  bash install.sh --skill adr --skill pr-description
# =============================================================================

set -euo pipefail

REPO_URL="https://raw.githubusercontent.com/csorodrigo/canuto-framework/main"
AGENTS_DIR=".agents"
CLAUDE_MD="CLAUDE.md"
TMP_DIR=$(mktemp -d)
MODE="auto" # auto | install | update | check | skill
SKILLS_TO_INSTALL=()

# ── Colors ─────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
RESET='\033[0m'

log()    { echo -e "${CYAN}[canuto]${RESET} $1"; }
ok()     { echo -e "${GREEN}[canuto]${RESET} \u2713 $1"; }
warn()   { echo -e "${YELLOW}[canuto]${RESET} \u26a0 $1"; }
error()  { echo -e "${RED}[canuto]${RESET} \u2717 $1"; exit 1; }

# ── Parse args ─────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --update) MODE="update" ;;
    --check)  MODE="check"  ;;
    --skill)
      shift
      SKILLS_TO_INSTALL+=("$1")
      ;;
  esac
  shift
done

# ── Detect mode ─────────────────────────────────────────────────────────
if [ "$MODE" = "auto" ]; then
  if [ "${#SKILLS_TO_INSTALL[@]}" -gt 0 ]; then
    MODE="skill"
  elif [ -d "$AGENTS_DIR" ]; then
    MODE="update"
  else
    MODE="install"
  fi
fi

# ── Confirm not running in the framework repo itself ───────────────────────
if [ -f ".agents/SPEC.md" ] && grep -q "Canuto Framework" ".agents/SPEC.md" 2>/dev/null; then
  if [ ! -f "src/index.js" ] && [ ! -f "src/main.py" ] && [ ! -f "package.json" ]; then
    warn "This looks like the canuto-framework repo itself. Aborting."
    exit 0
  fi
fi

# ── Check git availability ──────────────────────────────────────────────────────
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

# ── File lists ─────────────────────────────────────────────────────────

# Files to always copy on install/update (personas + skills)
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
  ".agents/skills/session-goals.md"
  ".agents/skills/pr-description.md"
  ".agents/skills/adr.md"
  ".agents/skills/health-check.md"
  ".agents/SPEC.md"
)

# Files only copied on fresh install (never overwrite user data)
INSTALL_ONLY_FILES=(
  ".agents/memory/last-session.md"
  ".agents/memory/decisions.md"
  ".agents/memory/pending.md"
  ".agents/memory/metrics.md"
)

# ── merge_claude_md ─────────────────────────────────────────────────────────
# Creates CLAUDE.md if missing; merges only missing sections if it exists.
merge_claude_md() {
  if [ ! -f "$CLAUDE_MD" ]; then
    download "CLAUDE.md" "$CLAUDE_MD"
    ok "$CLAUDE_MD created"
    return
  fi

  log "$CLAUDE_MD already exists — checking for missing framework sections..."
  local appended=0

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

  if ! grep -q "^## Project Rules" "$CLAUDE_MD" 2>/dev/null; then
    cat >> "$CLAUDE_MD" << 'SECTION'

## Project Rules
- Read any .context.md and docs/FEATURE-MAP.md files if they exist.
- If they do not exist, have the Contextualizer create them (with approval).
- Never run Git or shell commands without explicit confirmation.
- When in doubt, ask questions instead of guessing.
SECTION
    ok "  added: ## Project Rules"
    appended=1
  fi

  if ! grep -q "^## On Session Start" "$CLAUDE_MD" 2>/dev/null; then
    cat >> "$CLAUDE_MD" << 'SECTION'

## On Session Start
1. Read .agents/memory/last-session.md
2. Check for stale contexts (git diff)
3. Present the session briefing
4. Ask what to work on
SECTION
    ok "  added: ## On Session Start"
    appended=1
  fi

  if [ "$appended" -eq 1 ]; then
    ok "$CLAUDE_MD — missing sections added automatically"
  else
    ok "$CLAUDE_MD — all framework sections already present, nothing to do"
  fi
}

# ── CHECK ──────────────────────────────────────────────────────────────
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

# ── SKILL INSTALL ─────────────────────────────────────────────────────────
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
      warn "Skill '$skill_name' not found in registry. Check registry.md for available skills."
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

# ── INSTALL ──────────────────────────────────────────────────────────────
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

  # decisions/ directory for ADRs
  mkdir -p ".agents/decisions"
  touch ".agents/decisions/.gitkeep"
  ok ".agents/decisions/ (ready for ADRs)"

  # plugins/ directory
  mkdir -p ".agents/plugins"
  touch ".agents/plugins/.gitkeep"
  ok ".agents/plugins/ (empty, ready for plugins)"

  # CLAUDE.md: create or merge missing sections
  merge_claude_md

  # Git commit
  if [ "$GIT_AVAILABLE" = true ]; then
    echo ""
    log "Staging files for git..."
    git add "$AGENTS_DIR/" "$CLAUDE_MD" 2>/dev/null || true
    echo ""
    read -r -p "$(echo -e "${CYAN}[canuto]${RESET} Commit now? [Y/n] ")" COMMIT_ANSWER
    COMMIT_ANSWER="${COMMIT_ANSWER:-Y}"
    if [[ "$COMMIT_ANSWER" =~ ^[Yy]$ ]]; then
      git commit -m "chore: add Canuto Framework v1.1"
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

# ── UPDATE ──────────────────────────────────────────────────────────────
if [ "$MODE" = "update" ]; then
  echo ""
  echo -e "${CYAN}\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501${RESET}"
  echo -e "${CYAN}  Canuto Framework \u2014 Update${RESET}"
  echo -e "${CYAN}\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501${RESET}"
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

  # Ensure decisions/ directory exists (new in v1.1)
  mkdir -p ".agents/decisions"
  [ ! -f ".agents/decisions/.gitkeep" ] && touch ".agents/decisions/.gitkeep" && ok ".agents/decisions/ created"

  # CLAUDE.md: merge any missing sections (never overwrite)
  merge_claude_md

  # Git commit
  if [ "$GIT_AVAILABLE" = true ]; then
    echo ""
    log "Staging updated files..."
    git add "$AGENTS_DIR/personas/" "$AGENTS_DIR/skills/" "$AGENTS_DIR/SPEC.md" "$AGENTS_DIR/decisions/" "$CLAUDE_MD" 2>/dev/null || true
    echo ""
    read -r -p "$(echo -e "${CYAN}[canuto]${RESET} Commit now? [Y/n] ")" COMMIT_ANSWER
    COMMIT_ANSWER="${COMMIT_ANSWER:-Y}"
    if [[ "$COMMIT_ANSWER" =~ ^[Yy]$ ]]; then
      git commit -m "chore: update Canuto Framework to v1.1"
      ok "Committed!"
    else
      warn "Files staged but not committed. Run 'git commit' when ready."
    fi
  fi

  echo ""
  echo -e "${GREEN}\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501${RESET}"
  echo -e "${GREEN}  Framework updated to v1.1 successfully.${RESET}"
  echo -e "${GREEN}\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501${RESET}"
  echo ""
fi

# ── Cleanup ──────────────────────────────────────────────────────────────
rm -rf "$TMP_DIR"
