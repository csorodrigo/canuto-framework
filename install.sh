#!/usr/bin/env bash
# =============================================================================
# Canuto Framework — Installer / Updater
# Usage:
#   Fresh install:    curl -fsSL https://raw.githubusercontent.com/csorodrigo/canuto-framework/main/install.sh | bash
#   Local run:        bash install.sh
#   Update only:      bash install.sh --update
#   Update via curl:  curl -fsSL https://raw.githubusercontent.com/csorodrigo/canuto-framework/main/install.sh | bash -s -- --update
#   Contract only:    bash install.sh --contract-only
#   Check versions:   bash install.sh --check
#   Smoke test:       bash install.sh --test
#   Repair runtime:   bash install.sh --repair
#   Doctor mode:      bash install.sh --doctor
#   Dependency setup: bash install.sh --deps-only
#   Migrate from v1:  bash install.sh --migrate
#   With API key:     bash install.sh --migrate --api-key YOUR_OBSIDIAN_API_KEY
#   Via curl + key:   curl ... | bash -s -- --migrate --api-key YOUR_KEY
#   Install a skill:  bash install.sh --skill pr-description --skill health-check
#   JSON health:      bash install.sh --test --json
# =============================================================================

set -euo pipefail

REPO_URL="${CANUTO_REPO_URL:-https://raw.githubusercontent.com/csorodrigo/canuto-framework/main}"
SOURCE_DIR="${CANUTO_SOURCE_DIR:-}"
AGENTS_DIR=".agents"
CLAUDE_MD="CLAUDE.md"
TMP_DIR=$(mktemp -d)
MODE="auto" # auto | install | update | contract | check | skill | migrate | repair | doctor | test | deps
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
    --contract-only) MODE="contract" ;;
    --check)   MODE="check"   ;;
    --test)    MODE="test"    ;;
    --migrate) MODE="migrate" ;;
    --repair)  MODE="repair"  ;;
    --deps-only|--deps) MODE="deps" ;;
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

emit_repair_warnings() {
  local repair_rc="$1"
  case "$repair_rc" in
    10) warn "Runtime dependency repair failed; local repairs were continued." ;;
    20) warn "Skill gardener repair failed; the remaining local repairs were continued." ;;
    30)
      warn "Runtime dependency repair failed; local repairs were continued."
      warn "Skill gardener repair failed; the remaining local repairs were continued."
      ;;
  esac
}

handle_repair_outcome() {
  local mode="$1"
  local repair_rc="$2"
  local validation_rc="${3:-0}"
  case "$repair_rc" in
    0|10|20|30) ;;
    *) warn "Invalid repair outcome: $repair_rc"; return 30 ;;
  esac
  case "$mode" in
    repair)
      if [ "$repair_rc" -eq 0 ]; then
        ok "Runtime repaired. Validate with: bash install.sh --test"
      else
        emit_repair_warnings "$repair_rc"
      fi
      return "$repair_rc"
      ;;
    doctor)
      [ "$repair_rc" -eq 0 ] || emit_repair_warnings "$repair_rc"
      if [ "$validation_rc" -eq 0 ]; then
        [ "$repair_rc" -eq 0 ] && ok "Runtime repair and validation passed."
      else
        warn "Runtime validation reported issues."
      fi
      if [ "$repair_rc" -ne 0 ]; then return "$repair_rc"; fi
      return "$validation_rc"
      ;;
    install)
      if [ "$repair_rc" -eq 0 ]; then return 0; fi
      emit_repair_warnings "$repair_rc"
      rm -rf "$TMP_DIR"
      return "$repair_rc"
      ;;
    update)
      if [ "$repair_rc" -eq 0 ]; then return 0; fi
      emit_repair_warnings "$repair_rc"
      if [ "$repair_rc" -eq 10 ]; then
        warn "Continuing update; dependency repair is incomplete."
        return 0
      fi
      warn "Framework files may already be updated; stopping before further update actions."
      rm -rf "$TMP_DIR"
      return "$repair_rc"
      ;;
    migrate)
      if [ "$repair_rc" -eq 0 ]; then return 0; fi
      emit_repair_warnings "$repair_rc"
      warn "Stopping migration before destructive cleanup and success reporting."
      rm -rf "$TMP_DIR"
      return "$repair_rc"
      ;;
    *)
      warn "Unsupported repair outcome mode: $mode"
      return 30
      ;;
  esac
}

if [ -n "${CANUTO_INSTALL_TEST_DISPATCH_REPAIR_RC:-}" ] && [ "${CANUTO_INSTALL_LIBRARY_ONLY:-0}" != "1" ]; then
  TEST_REPAIR_RC="$CANUTO_INSTALL_TEST_DISPATCH_REPAIR_RC"
  case "$TEST_REPAIR_RC" in
    0|10|20|30) ;;
    *) echo "Invalid CANUTO_INSTALL_TEST_DISPATCH_REPAIR_RC: $TEST_REPAIR_RC" >&2; rm -rf "$TMP_DIR"; exit 1 ;;
  esac
  TEST_ISOLATED_HOME="${CANUTO_INSTALL_TEST_ISOLATED_HOME:-}"
  case "$TEST_ISOLATED_HOME" in
    /*) ;;
    *) echo "CANUTO_INSTALL_TEST_ISOLATED_HOME must be an absolute path" >&2; rm -rf "$TMP_DIR"; exit 1 ;;
  esac
  if [ "$TEST_ISOLATED_HOME" = "/" ] || [ "${HOME:-}" != "$TEST_ISOLATED_HOME" ] || [ ! -d "$TEST_ISOLATED_HOME" ]; then
    echo "CANUTO_INSTALL_TEST_ISOLATED_HOME must equal a dedicated HOME directory" >&2
    rm -rf "$TMP_DIR"
    exit 1
  fi
  TEST_OUTCOME_RC=0
  handle_repair_outcome "$MODE" "$TEST_REPAIR_RC" 0 || TEST_OUTCOME_RC=$?
  rm -rf "$TMP_DIR"
  exit "$TEST_OUTCOME_RC"
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
if [ "${CANUTO_INSTALL_LIBRARY_ONLY:-0}" != "1" ] && git remote -v 2>/dev/null | grep -q "canuto-framework"; then
  case "$MODE" in
    install|update|contract|migrate|skill)
      warn "This looks like the canuto-framework repo itself. Aborting."
      exit 0
      ;;
  esac
fi

# ── setup_deps ──────────────────────────────────────────────────────────────
# Ensures required global runtime tools are available and RTK is initialized.
setup_deps() {
  local failures=0
  local has_brew=false

  fail_dep() {
    local message="$1"
    failures=$((failures + 1))
    warn "$message"
  }

  add_brew_formula_path() {
    local formula="$1"
    local prefix=""

    if ! command -v brew >/dev/null 2>&1; then
      return 0
    fi

    prefix=$(brew --prefix "$formula" 2>/dev/null || true)
    if [ -n "$prefix" ] && [ -d "$prefix/bin" ]; then
      case ":$PATH:" in
        *":$prefix/bin:"*) ;;
        *) export PATH="$prefix/bin:$PATH" ;;
      esac
    fi
  }

  ensure_homebrew() {
    if command -v brew >/dev/null 2>&1; then
      has_brew=true
      ok "brew $(brew --version | head -1) already installed"
      return 0
    fi

    if [[ "$OSTYPE" != "darwin"* ]]; then
      fail_dep "Homebrew is required for automatic dependency setup. Install the missing tools manually; apt/yum are not used by this installer."
      return 0
    fi

    if ! command -v curl >/dev/null 2>&1; then
      fail_dep "Homebrew is missing and curl is unavailable. Install Homebrew manually from https://brew.sh and retry."
      return 0
    fi

    log "Installing Homebrew..."
    if /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
      export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
      if command -v brew >/dev/null 2>&1; then
        has_brew=true
        ok "Homebrew installed"
      else
        fail_dep "Homebrew installer completed, but brew is still not on PATH. Add Homebrew to PATH and retry."
      fi
    else
      fail_dep "Failed to install Homebrew. Install manually from https://brew.sh and retry."
    fi
  }

  # ── Gerenciador de pacotes: brew (macOS) ou apt/dnf (Linux/VPS) ────────────
  # O framework roda onde a sessão roda. Com desenvolvimento migrando para VPS
  # Linux, exigir Homebrew tornaria o instalador inutilizável lá. Mesma lista
  # de dependências, gerenciador detectado em runtime.
  PKG_MGR="none"
  SUDO=""
  APT_UPDATED=false

  detect_sudo() {
    if [ "$(id -u)" -eq 0 ]; then
      SUDO=""
    elif command -v sudo >/dev/null 2>&1; then
      SUDO="sudo"
    else
      SUDO="__none__"
    fi
  }

  detect_pkg_mgr() {
    if command -v brew >/dev/null 2>&1; then
      PKG_MGR="brew"; has_brew=true
      ok "brew $(brew --version 2>/dev/null | head -1) already installed"
      return 0
    fi

    if [[ "$OSTYPE" == "darwin"* ]]; then
      ensure_homebrew
      [ "$has_brew" = true ] && PKG_MGR="brew"
      return 0
    fi

    detect_sudo
    if command -v apt-get >/dev/null 2>&1; then
      PKG_MGR="apt"
    elif command -v dnf >/dev/null 2>&1; then
      PKG_MGR="dnf"
    else
      PKG_MGR="none"
      fail_dep "No supported package manager found (brew/apt/dnf). Install the tools below manually."
      return 0
    fi

    if [ "$SUDO" = "__none__" ]; then
      warn "$PKG_MGR detected but this user is not root and sudo is unavailable — packages must be installed manually."
    else
      ok "Package manager: $PKG_MGR${SUDO:+ (via sudo)}"
    fi
  }

  pkg_install() {
    # pkg_install <brew_formula|-> <linux_pkg|->  (dnf reusa o nome do apt)
    local brew_formula="$1" linux_pkg="$2"

    case "$PKG_MGR" in
      brew)
        [ "$brew_formula" = "-" ] && return 1
        brew install "$brew_formula" || return 1
        add_brew_formula_path "$brew_formula"
        ;;
      apt)
        [ "$linux_pkg" = "-" ] && return 1
        [ "$SUDO" = "__none__" ] && return 1
        if [ "$APT_UPDATED" != true ]; then
          ${SUDO:+$SUDO} apt-get update -qq >/dev/null 2>&1 || true
          APT_UPDATED=true
        fi
        DEBIAN_FRONTEND=noninteractive ${SUDO:+$SUDO} apt-get install -y -qq "$linux_pkg" >/dev/null 2>&1 || return 1
        ;;
      dnf)
        [ "$linux_pkg" = "-" ] && return 1
        [ "$SUDO" = "__none__" ] && return 1
        ${SUDO:+$SUDO} dnf install -y "$linux_pkg" >/dev/null 2>&1 || return 1
        ;;
      *) return 1 ;;
    esac
  }

  dep_present() {
    # dep_present <cmd> — existe no PATH E é realmente a ferramenta esperada.
    local cmd="$1"
    command -v "$cmd" >/dev/null 2>&1 || return 1

    # `sg` em Linux é o set-group do shadow (/usr/bin/sg), homônimo do alias
    # do ast-grep. Sem esta checagem o instalador reporta ast-grep OK e o MCP
    # quebra silenciosamente na VPS.
    if [ "$cmd" = "sg" ]; then
      "$cmd" --version 2>&1 | grep -qi "ast-grep" || return 1
    fi
    return 0
  }

  ensure_dep() {
    # ensure_dep <cmd> <label> <brew|-> <linux_pkg|-> <npm_pkg|-> <req|opt>
    local cmd="$1" label="$2" brew_formula="$3" linux_pkg="$4" npm_pkg="$5" need="${6:-req}"

    if dep_present "$cmd"; then
      ok "$label available: $(command -v "$cmd")"
      return 0
    fi

    # Só anuncia o gerenciador que de fato será tentado — "Installing rtk via
    # apt" seguido de um skip silencioso é ruído que parece erro.
    local mgr_pkg="-"
    case "$PKG_MGR" in
      brew) mgr_pkg="$brew_formula" ;;
      apt|dnf) mgr_pkg="$linux_pkg" ;;
    esac
    if [ "$mgr_pkg" != "-" ]; then
      log "Installing $label via $PKG_MGR: $mgr_pkg"
      pkg_install "$brew_formula" "$linux_pkg" || true
    fi

    if ! dep_present "$cmd" && [ "$npm_pkg" != "-" ] && command -v npm >/dev/null 2>&1; then
      log "Installing $label via npm: npm install -g $npm_pkg"
      npm install -g "$npm_pkg" >/dev/null 2>&1 || true
    fi

    if dep_present "$cmd"; then
      ok "$label installed: $(command -v "$cmd")"
      return 0
    fi

    local hint="Install manually"
    [ "$brew_formula" != "-" ] && hint="brew install $brew_formula"
    [ "$PKG_MGR" = "apt" ] && [ "$linux_pkg" != "-" ] && hint="apt-get install $linux_pkg"
    [ "$PKG_MGR" = "dnf" ] && [ "$linux_pkg" != "-" ] && hint="dnf install $linux_pkg"
    [ "$npm_pkg" != "-" ] && hint="$hint  (ou: npm install -g $npm_pkg)"

    if [ "$need" = "opt" ]; then
      warn "$label not installed (optional). To enable it: $hint"
      return 0
    fi
    fail_dep "$label missing. $hint"
  }

  ensure_astgrep() {
    # ast-grep expõe `ast-grep` e o alias `sg`. Em Linux o alias colide com o
    # shadow, então o binário canônico é o que vale.
    if dep_present ast-grep || dep_present sg; then
      ok "ast-grep available: $(command -v ast-grep 2>/dev/null || command -v sg)"
      return 0
    fi
    ensure_dep ast-grep "ast-grep" ast-grep - @ast-grep/cli req
  }

  ensure_uv() {
    if dep_present uv && dep_present uvx; then
      ok "uv/uvx available: $(command -v uv)"
      return 0
    fi

    if [ "$PKG_MGR" = "brew" ]; then
      pkg_install uv - || true
    fi

    # Fora do brew, o caminho oficial do uv é o instalador da Astral: uv não
    # está nos repositórios do Ubuntu 24.04 e pip é bloqueado por PEP 668.
    if ! dep_present uv && command -v curl >/dev/null 2>&1; then
      log "Installing uv via installer oficial (astral.sh)..."
      curl -LsSf https://astral.sh/uv/install.sh 2>/dev/null | sh >/dev/null 2>&1 || true
      for candidate in "$HOME/.local/bin" "$HOME/.cargo/bin"; do
        if [ -x "$candidate/uv" ]; then
          case ":$PATH:" in *":$candidate:"*) ;; *) export PATH="$candidate:$PATH" ;; esac
        fi
      done
    fi

    if dep_present uv && dep_present uvx; then
      ok "uv/uvx installed: $(command -v uv)"
    else
      fail_dep "uv/uvx missing. Install with: curl -LsSf https://astral.sh/uv/install.sh | sh   (macOS: brew install uv)"
    fi
  }

  ensure_command() {
    local command_name="$1"
    local install_hint="$2"
    local label="$3"

    if command -v "$command_name" >/dev/null 2>&1; then
      ok "$label available: $(command -v "$command_name")"
    else
      fail_dep "$label missing. $install_hint"
    fi
  }

  ensure_brew_cask() {
    local command_name="$1"
    local cask="$2"
    local label="$3"

    if command -v "$command_name" >/dev/null 2>&1; then
      ok "$label already installed: $(command -v "$command_name")"
      return 0
    fi

    if [ "$has_brew" != true ]; then
      fail_dep "$label missing. Install manually or install Homebrew, then run: brew install --cask $cask"
      return 0
    fi

    log "Installing $label via Homebrew cask: brew install --cask $cask"
    if brew install --cask "$cask"; then
      if command -v "$command_name" >/dev/null 2>&1; then
        ok "$label installed: $(command -v "$command_name")"
      else
        fail_dep "$label installed via Homebrew cask, but '$command_name' is still not on PATH."
      fi
    else
      if command -v "$command_name" >/dev/null 2>&1; then
        ok "$label available after Homebrew cask check: $(command -v "$command_name")"
      else
        fail_dep "Failed to install $label. Retry manually with: brew install --cask $cask"
      fi
    fi
  }

  setup_rtk() {
    local rtk_show=""

    if ! command -v rtk >/dev/null 2>&1; then
      fail_dep "rtk missing. Install with: brew install rtk"
      return 0
    fi

    if rtk --version >/dev/null 2>&1; then
      ok "rtk available: $(rtk --version 2>/dev/null | head -1)"
    else
      fail_dep "rtk is installed but 'rtk --version' failed."
    fi

    log "Initializing RTK for Claude..."
    if rtk init -g --auto-patch >/dev/null 2>&1; then
      ok "rtk init -g --auto-patch configured"
    else
      fail_dep "rtk init -g --auto-patch failed."
    fi

    log "Initializing RTK for Codex..."
    if rtk init -g --codex >/dev/null 2>&1; then
      ok "rtk init -g --codex configured"
    else
      fail_dep "rtk init -g --codex failed."
    fi

    rtk_show=$(mktemp)
    if rtk init --show >"$rtk_show" 2>&1; then
      ok "rtk init --show succeeded"
      if grep -q "settings.json: exists but RTK hook not configured" "$rtk_show" 2>/dev/null; then
        fail_dep "Claude settings.json exists but RTK hook is not configured."
      fi
      if grep -q "Hook: not found" "$rtk_show" 2>/dev/null; then
        fail_dep "Claude RTK hook is not configured."
      fi
    else
      fail_dep "rtk init --show failed: $(head -1 "$rtk_show" 2>/dev/null || echo unknown error)"
    fi
    rm -f "$rtk_show"

    if [ -f "$HOME/.claude/RTK.md" ]; then
      ok "~/.claude/RTK.md exists"
    else
      fail_dep "~/.claude/RTK.md missing after RTK init."
    fi

    if [ -f "$HOME/.claude/CLAUDE.md" ] && grep -q "RTK.md" "$HOME/.claude/CLAUDE.md" 2>/dev/null; then
      ok "~/.claude/CLAUDE.md references RTK.md"
    else
      fail_dep "~/.claude/CLAUDE.md does not reference RTK.md."
    fi

    if [ -f "$HOME/.codex/RTK.md" ]; then
      ok "~/.codex/RTK.md exists"
    else
      fail_dep "~/.codex/RTK.md missing after RTK init."
    fi

    if [ -f "$HOME/.codex/AGENTS.md" ] && grep -q "RTK.md" "$HOME/.codex/AGENTS.md" 2>/dev/null; then
      ok "~/.codex/AGENTS.md references RTK.md"
    else
      fail_dep "~/.codex/AGENTS.md does not reference RTK.md."
    fi
  }

  detect_pkg_mgr

  #          cmd      label            brew            linux_pkg  npm            req/opt
  ensure_dep git      "git"            git             git        -              req
  ensure_dep curl     "curl"           curl            curl       -              req
  ensure_dep wget     "wget"           wget            wget       -              req
  ensure_dep jq       "jq"             jq              jq         -              req
  ensure_dep node     "node/npm/npx"   node            nodejs     -              req
  ensure_command npm "Install Node.js (brew install node | apt-get install npm)" "npm"
  ensure_command npx "Install Node.js (brew install node | apt-get install npm)" "npx"
  ensure_dep python3  "python3"        python          python3    -              req
  ensure_uv
  ensure_astgrep
  ensure_dep rg       "ripgrep"        ripgrep         ripgrep    -              req
  ensure_dep codex    "Codex CLI"      -               -          @openai/codex@latest req

  # Opcionais: úteis, mas o framework roda sem eles. Marcá-los como obrigatórios
  # fazia toda instalação Linux terminar em "N dependency check(s) failed" —
  # rtk e gcloud-cli não têm caminho de instalação fora do Homebrew.
  ensure_dep gh       "GitHub CLI"     gh              gh         -              opt
  ensure_dep bun      "bun"            oven-sh/bun/bun -          bun            opt
  ensure_dep rtk      "rtk"            rtk             -          -              opt
  if [ "$PKG_MGR" = "brew" ]; then
    ensure_brew_cask gcloud gcloud-cli "Google Cloud CLI"
  else
    warn "Google Cloud CLI not installed (optional). See https://cloud.google.com/sdk/docs/install"
  fi

  if dep_present rtk; then
    setup_rtk
  else
    warn "rtk unavailable — skipping RTK hook setup (Claude/Codex work without it)."
  fi

  if [ "$failures" -gt 0 ]; then
    warn "$failures dependency check(s) failed."
    return 1
  fi

  ok "All Canuto runtime dependencies are installed and configured."
  return 0
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
  local dir tmp rc
  dir=$(dirname "$local_path")
  mkdir -p "$dir"

  # Temp + mv (rename), nunca escrita direta: cp/curl -o truncam o MESMO
  # inode, e quando o alvo é o próprio install.sh em execução o bash continua
  # lendo o inode truncado e morre com "unexpected EOF" ao fim do update —
  # exit != 0 num update que na verdade deu certo (sandbox 2026-08-21).
  # rename troca o inode: o processo em execução segue no antigo até o fim.
  tmp="$local_path.canuto-dl.$$"
  rc=0
  if [ -n "$SOURCE_DIR" ] && [ -f "$SOURCE_DIR/$remote_path" ]; then
    cp "$SOURCE_DIR/$remote_path" "$tmp" || rc=$?
  elif command -v curl > /dev/null 2>&1; then
    curl -fsSL "$REPO_URL/$remote_path" -o "$tmp" || rc=$?
  elif command -v wget > /dev/null 2>&1; then
    wget -q "$REPO_URL/$remote_path" -O "$tmp" || rc=$?
  else
    error "Neither curl nor wget found. Install one and retry."
  fi
  if [ "$rc" -ne 0 ]; then
    rm -f "$tmp" 2>/dev/null || true
    return "$rc"
  fi
  mv "$tmp" "$local_path" || { rm -f "$tmp" 2>/dev/null || true; return 1; }

  # Exec bit é parte da distribuição: curl/wget sempre gravam 644, e o chmod
  # do repair_runtime não roda quando setup_deps falha (fail-open silencioso
  # que deixava gates e heartbeats não-executáveis no consumidor).
  case "$local_path" in
    *.sh) chmod +x "$local_path" 2>/dev/null || true ;;
  esac
}

# Fetch helper (returns content, no write)
fetch_content() {
  local remote_path="$1"
  if [ -n "$SOURCE_DIR" ] && [ -f "$SOURCE_DIR/$remote_path" ]; then
    cat "$SOURCE_DIR/$remote_path"
    return 0
  fi

  if command -v curl > /dev/null 2>&1; then
    curl -fsSL "$REPO_URL/$remote_path" 2>/dev/null
  elif command -v wget > /dev/null 2>&1; then
    wget -q "$REPO_URL/$remote_path" -O - 2>/dev/null
  fi
}

should_refresh_installer() {
  case "$MODE" in
    install|update|contract|check|skill|migrate|repair|doctor|test|deps)
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

if [ "${CANUTO_INSTALL_LIBRARY_ONLY:-0}" != "1" ]; then
  refresh_from_remote_installer_if_needed
fi

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
    skill-creator)
      printf '%s\n' \
        ".agents/skills/skill-creator/SKILL.md" \
        ".agents/skills/skill-creator/GLOSSARY.md"
      ;;
    domain-modeling)
      printf '%s\n' \
        ".agents/skills/domain-modeling/SKILL.md" \
        ".agents/skills/domain-modeling/CONTEXT-FORMAT.md"
      ;;
    tdd)
      printf '%s\n' \
        ".agents/skills/tdd/SKILL.md" \
        ".agents/skills/tdd/tests.md"
      ;;
    codebase-design)
      printf '%s\n' \
        ".agents/skills/codebase-design/SKILL.md" \
        ".agents/skills/codebase-design/TESTABILIDADE.md"
      ;;
    *)
      printf '%s\n' ".agents/skills/${skill_name}.md"
      ;;
  esac
}

# ── File lists ──────────────────────────────────────────────────────────────

FRAMEWORK_FILES=(
  "install.sh"
  # Carimbo de versão do framework: fonte do `--check` agregado, do aviso de
  # desatualização no SessionStart e do canuto-update-all.sh. Distribuído como
  # arquivo normal para o caminho ser idêntico no repo e no consumidor.
  ".agents/VERSION"
  # Design system normativo (denso/compacto/sem overflow) — NÃO é skill:
  # contrato neutro consultado por Claude E Codex antes de qualquer front.
  ".agents/design/DESIGN-RULES.md"
  # Contrato operacional comum a Claude/Codex e Mac/SSH. O projeto mantém
  # SPEC/DESIGN próprios; este arquivo distribui apenas disciplina operacional.
  ".agents/OPERATING-CONTRACT.md"
  ".agents/tools/canuto-update-all.sh"
  ".agents/personas/maestro.md"
  ".agents/personas/architect.md"
  ".agents/personas/coder.md"
  ".agents/personas/reviewer.md"
  ".agents/personas/contextualizer.md"
  ".agents/personas/investigator.md"
  ".agents/skills/context-maintenance/SKILL.md"
  ".agents/skills/context-maintenance/references/evaluate-repo-pipeline.md"
  ".agents/skills/context-maintenance/references/examples.md"
  ".agents/skills/api-design.md"
  ".agents/skills/frontend-implementation.md"
  ".agents/skills/security-practices.md"
  ".agents/skills/multi-provider.md"
  ".agents/skills/vault-sync.md"
  ".agents/skills/metrics.md"
  ".agents/skills/pr-description.md"
  ".agents/skills/health-check.md"
  ".agents/skills/canuto-project-doctor.md"
  ".agents/skills/canuto-session-end-learning.md"
  ".agents/skills/canuto-rework-detector.md"
  ".agents/skills/canuto-pending-triage.md"
  ".agents/skills/obsidian-writeback-queue.md"
  ".agents/hooks/codex-pretool-guard.sh"
  ".agents/hooks/install.sh"
  ".agents/hooks/settings-snippet.json"
  ".agents/hooks/log-commands.sh"
  ".agents/hooks/protect-files.sh"
  ".agents/hooks/require-tests-for-pr.sh"
  ".agents/hooks/screenshot-guard.sh"
  ".agents/hooks/session-save.sh"
    ".agents/hooks/pre-compact-save.sh"
  ".agents/hooks/session-start.sh"
  ".agents/hooks/validation-mark.sh"
  ".agents/hooks/validation-clear.sh"
  ".agents/hooks/retry-detect.sh"
  ".agents/hooks/fingerprint-gate.sh"
  ".agents/hooks/posttooluse-universal.sh"
  ".agents/hooks/pre-finalize.sh"
  ".agents/hooks/pre-commit-branch-check.sh"
  ".agents/hooks/worktree-collision-check.sh"
  ".agents/hooks/pre-claim-grep.sh"
  ".agents/config/models.yaml"
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
  ".agents/skills/browser-qa.md"
  ".agents/skills/session-goals.md"
  ".agents/skills/frontend-design/SKILL.md"
  ".agents/skills/frontend-design/references/design-patterns.md"
  ".agents/skills/frontend-design/references/aesthetic-patterns.md"
  ".agents/skills/defuddle.md"
  ".agents/skills/obsidian-markdown.md"
  ".agents/skills/mcp-obsidian.md"
  ".agents/skills/obsidian-markdown/references/CALLOUTS.md"
  ".agents/skills/obsidian-markdown/references/EMBEDS.md"
  ".agents/skills/obsidian-markdown/references/PROPERTIES.md"
  ".agents/SPEC.md"
  # Codex integration skills (Fase 2+3)
  ".agents/skills/co-review/SKILL.md"
  ".agents/skills/cost-routing.md"
  ".agents/mcp/codex-collab.md"
  ".agents/tools/vault-bridge.sh"
  ".agents/tools/canuto-memory.sh"
  ".agents/tools/canuto-mcp.sh"
  ".agents/tools/codex-common.sh"
  ".agents/tools/codex-diff-context.sh"
  ".agents/tools/codex-context-package.sh"
  ".agents/tools/codex-health-check.sh"
  ".agents/tools/canuto-consumer-smoke.sh"
  ".agents/tools/codex-maestro.sh"
  ".agents/tools/otel-emit.sh"
  ".agents/tools/vault-sync.sh"
  # Codex economy + integration skills (Fase 3)
  # CODEX.md e gerado por render_codex_md com slug e regras do consumidor;
  # somente o template pode ser distribuido/hash-checked como arquivo canonico.
  ".agents/templates/CODEX.md"
  # Learning-loop, QA and design skills (sync 2026-07-26 — previously in the
  # repo but never distributed; test-framework.sh now enforces this list stays
  # in sync with .agents/skills/)
  ".agents/skills/adaptive-routing/SKILL.md"
  ".agents/skills/audit.md"
  ".agents/skills/auto-analysis.md"
  ".agents/skills/co-review/references/modes.md"
  ".agents/skills/colorize.md"
  ".agents/skills/design-consultation.md"
  ".agents/skills/experiment-loop/SKILL.md"
  ".agents/skills/experiment-loop/references/auto-triggers.md"
  ".agents/skills/experiment-loop/references/use-cases-and-examples.md"
  ".agents/skills/experiment-loop/references/vault-schema.md"
  ".agents/skills/knowledge-ingest.md"
  ".agents/skills/monitor/SKILL.md"
  ".agents/skills/monitor/references/alert-rules.md"
  ".agents/skills/monitor/references/integration-schema.md"
  ".agents/skills/monitor/references/profiles.md"
  ".agents/skills/research.md"
  ".agents/skills/review.md"
  ".agents/skills/skill-check-protocol.md"
  ".agents/skills/skill-creator/SKILL.md"
  ".agents/skills/skill-creator/GLOSSARY.md"
  ".agents/skills/stuck-detection.md"
  # Disciplinas de engenharia (ADR-0015 — adaptado de mattpocock/skills, MIT)
  ".agents/skills/grilling.md"
  ".agents/skills/codebase-design/SKILL.md"
  ".agents/skills/codebase-design/TESTABILIDADE.md"
  ".agents/skills/domain-modeling/SKILL.md"
  ".agents/skills/domain-modeling/CONTEXT-FORMAT.md"
  ".agents/skills/tdd/SKILL.md"
  ".agents/skills/tdd/tests.md"
  ".agents/skills/trace-analysis/SKILL.md"
  ".agents/skills/trace-analysis/references/blind-spot-generator.md"
  ".agents/skills/trace-analysis/references/digest-schema.md"
  ".agents/skills/trace-analysis/references/improvement-patterns.md"
  ".agents/skills/trace-analysis/references/skill-proposer.md"
  ".agents/skills/typeset.md"
  ".agents/skills/vault-maintenance.md"
  ".agents/skills/verification-gates.md"
  # Event log (absorção edge-of-chaos, Fase 1 — ADR-0001)
  ".agents/skills/event-log.md"
  ".agents/tools/event-log.sh"
  # Heartbeat v1 (absorção edge-of-chaos, Fase 4 — ADR-0004)
  ".agents/tools/heartbeat-run.sh"
  ".agents/tools/instinct-aging.sh"
  ".agents/tools/codex-delegate.sh"
  # Revisor cego com muro mecânico (ADR-0006)
  ".claude/agents/blind-reviewer.md"
  # Novos gates fail-closed (ADR-0002)
  ".agents/hooks/pre-pr-bash-gate.sh"
  ".agents/hooks/git-pre-push-gate.sh"
  ".agents/hooks/postdelegate-verify.sh"
  # Absorção edge-of-chaos, Fase 2 (auditoria 2026-08-01): briefing garantido,
  # medição de uso da memória e fold de delegações pendentes
  ".agents/tools/brief-compose.sh"
  ".agents/tools/memory-usage.sh"
  ".agents/tools/delegation-ledger.sh"
)

INSTALL_ONLY_FILES=(
  # Configuração pertencente ao projeto: o framework fornece o default apenas
  # quando ausente e nunca substitui escolhas locais em --update/--check.
  ".agents/config/gates.env"
  ".agents/heartbeats/weekly-maintenance.md"
  ".agents/heartbeats/usage-audit.md"
  ".agents/vault/_index.md"
  ".agents/vault/.obsidian/app.json"
  ".agents/vault/.obsidian/community-plugins.json"
  ".agents/vault/.obsidian/core-plugins.json"
  ".agents/vault/.obsidian/.gitignore"
  ".agents/vault/.obsidian/templates/audit-event.md"
  ".agents/vault/.obsidian/templates/component.md"
  ".agents/vault/.obsidian/templates/decision.md"
  ".agents/vault/.obsidian/templates/handoff-review.md"
  ".agents/vault/.obsidian/templates/instinct.md"
  ".agents/vault/.obsidian/templates/metric.md"
  ".agents/vault/.obsidian/templates/pending-task.md"
  ".agents/vault/.obsidian/templates/requirements.md"
  ".agents/vault/.obsidian/templates/session.md"
  ".agents/vault/bases/all-instincts.base"
  ".agents/vault/bases/all-metrics.base"
  ".agents/vault/bases/audit-by-type.base"
  ".agents/vault/bases/components-registry.base"
  ".agents/vault/bases/cost-dashboard.base"
  ".agents/vault/bases/cross-project-patterns.base"
  ".agents/vault/bases/decisions-timeline.base"
  ".agents/vault/bases/global-instincts.base"
  ".agents/vault/bases/handoff-reviews.base"
  ".agents/vault/bases/instincts-by-confidence.base"
  ".agents/vault/bases/metrics-dashboard.base"
  ".agents/vault/bases/pending-tasks.base"
  ".agents/vault/bases/provider-reliability.base"
  ".agents/vault/bases/review-threads.base"
  ".agents/vault/bases/rework-hotspots.base"
  ".agents/vault/canvas/memory-map.canvas"
  ".agents/vault/canvas/persona-flow.canvas"
  ".agents/vault/design/profile.md"
  ".agents/vault/metrics/review-scores-template.md"
  ".agents/vault/sessions/review-threads.md"
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
  ".agents/vault/handoffs"
  ".agents/vault/audit"
  ".agents/vault/metrics"
  ".agents/vault/design"
  ".agents/vault/design/components"
  ".agents/vault/bases"
  ".agents/vault/canvas"
  ".agents/vault/digests"
)

# ── ensure_shared_operating_contract_reference ─────────────────────────────
# Contract-only distribution must not pull generic hooks, personas or skills
# over a product repository. Add exactly one active reference, outside Markdown
# fences, while preserving every existing byte of project guidance.
ensure_shared_operating_contract_reference() {
  local target="$1"
  local tmp="${target}.canuto-contract.$$"

  if [ -f "$target" ] && awk '
    /^[[:space:]]{0,3}(```|~~~)/ { fenced=!fenced; next }
    !fenced && /^[[:space:]]*-[[:space:]]+Read `\.agents\/OPERATING-CONTRACT\.md` before non-trivial work;/ { found=1 }
    END { exit(found ? 0 : 1) }
  ' "$target" 2>/dev/null; then
    return 0
  fi

  if [ -f "$target" ] && awk '
    /^[[:space:]]{0,3}(```|~~~)/ { fenced=!fenced }
    END { exit(fenced ? 0 : 1) }
  ' "$target" 2>/dev/null; then
    {
      cat <<'CONTRACTREF'
## Shared Operating Contract
- Read `.agents/OPERATING-CONTRACT.md` before non-trivial work; it is the shared
  Claude/Codex contract for evidence, authorization, WIP and cross-host drift.

CONTRACTREF
      cat "$target"
    } > "$tmp" && mv "$tmp" "$target"
    warn "$target had an unclosed Markdown fence; the active contract reference was preserved in a prefix outside it."
    return 0
  fi

  cat >> "$target" <<'CONTRACTREF'

## Shared Operating Contract
- Read `.agents/OPERATING-CONTRACT.md` before non-trivial work; it is the shared
  Claude/Codex contract for evidence, authorization, WIP and cross-host drift.
CONTRACTREF
  ok "$target references the shared operating contract"
}

# ── merge_claude_md ─────────────────────────────────────────────────────────
# Creates CLAUDE.md if missing.
# If it exists: adds missing top-level sections AND patches missing rules
# inside existing sections. Safe to run multiple times (idempotent).
merge_claude_md() {
  if [ ! -f "$CLAUDE_MD" ]; then
    # Generate a clean template. NEVER download the framework repo's own
    # CLAUDE.md here: it carries canuto-specific settings (project-slug,
    # providers, memory paths) and polluted every fresh install with the
    # canuto slug, colliding vault memory across projects
    # (2026-04-17 audit follow-up #1). project-slug is intentionally omitted:
    # canuto-memory.sh falls back to the project directory basename.
    cat > "$CLAUDE_MD" << 'HEADER'
# Project AI Setup

You are my coding orchestrator for this repository.
HEADER
    ok "$CLAUDE_MD created (clean template — project-slug defaults to the directory name)"
  else
    log "$CLAUDE_MD already exists — checking for missing sections and rules..."
    if ! awk '
      /^[[:space:]]{0,3}(```|~~~)/ { fenced=!fenced; next }
      !fenced && /^[[:space:]]*-[[:space:]]+Read `\.agents\/OPERATING-CONTRACT\.md` before non-trivial work;/ { found=1 }
      END { exit(found ? 0 : 1) }
    ' "$CLAUDE_MD" 2>/dev/null && awk '
      /^[[:space:]]{0,3}(```|~~~)/ { fenced=!fenced }
      END { exit(fenced ? 0 : 1) }
    ' "$CLAUDE_MD" 2>/dev/null; then
      {
        cat <<'RECOVERY'
## Framework
- Location: .agents/
- Read `.agents/OPERATING-CONTRACT.md` before non-trivial work; it is the shared
  Claude/Codex contract for evidence, authorization, WIP and cross-host drift.

## Preferences
- tests: required
- handoff-verbosity: explicit
- session-briefing: true

## Project Rules
- Before finalizing any plan, always interview the user in detail using AskUserQuestion about implementation choices, UI/UX decisions, trade-offs, and concerns. Never assume — always ask first.
- Before planning, implementing, or reviewing ANY user-facing UI, read `.agents/design/DESIGN-RULES.md` and obey it. It is the normative design system for every runtime.
- Read-only Git and shell inspection within the active task is allowed without new confirmation.
- Ask before destructive commands, credentials or identity changes, production mutations, external communications, or material scope expansion.

## On Session Start
1. Read project context and present the session briefing.

RECOVERY
        cat "$CLAUDE_MD"
      } > "${CLAUDE_MD}.tmp" && mv "${CLAUDE_MD}.tmp" "$CLAUDE_MD"
      warn "$CLAUDE_MD had an unclosed Markdown fence; active framework rules were preserved in a prefix outside it."
    fi
  fi

  local appended=0

  # ── Section: ## Framework ──────────────────────────────────────────────
  if ! awk '
    /^[[:space:]]{0,3}(```|~~~)/ { fenced=!fenced; next }
    !fenced && /^## Framework[[:space:]]*$/ { found=1 }
    END { exit(found ? 0 : 1) }
  ' "$CLAUDE_MD" 2>/dev/null; then
    cat >> "$CLAUDE_MD" << 'SECTION'

## Framework
- Location: .agents/
- Always act as the **Maestro** persona defined in the framework.
- Delegate to other personas as defined in their playbooks.
- Read `.agents/OPERATING-CONTRACT.md` before non-trivial work; it is the shared
  Claude/Codex contract for evidence, authorization, WIP and cross-host drift.
SECTION
    ok "  added: ## Framework"
    appended=1
  fi

  # ── Rule: shared operating contract ────────────────────────────────────
  if ! awk '
    /^[[:space:]]{0,3}(```|~~~)/ { fenced=!fenced; next }
    !fenced && /^## Framework[[:space:]]*$/ { section=1; next }
    !fenced && /^## / { section=0 }
    section && /^[[:space:]]*-[[:space:]]+Read `\.agents\/OPERATING-CONTRACT\.md` before non-trivial work;/ { found=1 }
    END { exit(found ? 0 : 1) }
  ' "$CLAUDE_MD" 2>/dev/null; then
    awk '
    /^[[:space:]]{0,3}(```|~~~)/ { fenced=!fenced }
    !fenced && !inserted && /^## Framework[[:space:]]*$/ {
      print
      print "- Read `.agents/OPERATING-CONTRACT.md` before non-trivial work; it is the shared"
      print "  Claude/Codex contract for evidence, authorization, WIP and cross-host drift."
      inserted=1
      next
    }1' "$CLAUDE_MD" > "${CLAUDE_MD}.tmp" && mv "${CLAUDE_MD}.tmp" "$CLAUDE_MD"
    ok "  patched: shared operating contract added to ## Framework"
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
  if ! awk '
    /^[[:space:]]{0,3}(```|~~~)/ { fenced=!fenced; next }
    !fenced && /^## Project Rules[[:space:]]*$/ { found=1 }
    END { exit(found ? 0 : 1) }
  ' "$CLAUDE_MD" 2>/dev/null; then
    # Section missing entirely — add the full block
    cat >> "$CLAUDE_MD" << 'SECTION'

## Project Rules
- Before finalizing any plan, always interview the user in detail using AskUserQuestion about implementation choices, UI/UX decisions, trade-offs, and concerns. Never assume — always ask first.
- Before planning, implementing, or reviewing ANY user-facing UI, read `.agents/design/DESIGN-RULES.md` and obey it. It is the normative design system (density, spacing, overflow, copy) for every runtime — Claude and Codex alike.
- Read any .context.md and docs/FEATURE-MAP.md files if they exist.
- If they do not exist, have the Contextualizer create them (with approval).
- Read-only Git and shell inspection within the active task is allowed without new confirmation.
- Ask before destructive commands, credentials or identity changes, production mutations, external communications, or material scope expansion.
- When in doubt, ask questions instead of guessing.
SECTION
    ok "  added: ## Project Rules (full block)"
    appended=1
  else
    # Section exists — patch individual missing rules
    if ! awk '
      /^[[:space:]]{0,3}(```|~~~)/ { fenced=!fenced; next }
      !fenced && /^## Project Rules[[:space:]]*$/ { section=1; next }
      !fenced && /^## / { section=0 }
      section && /AskUserQuestion/ { found=1 }
      END { exit(found ? 0 : 1) }
    ' "$CLAUDE_MD" 2>/dev/null; then
      # Insert planning-interview rule as first item under ## Project Rules
      awk '
      /^[[:space:]]{0,3}(```|~~~)/ { fenced=!fenced }
      !fenced && !inserted && /^## Project Rules[[:space:]]*$/ {
        print
        print "- Before finalizing any plan, always interview the user in detail using AskUserQuestion about implementation choices, UI/UX decisions, trade-offs, and concerns. Never assume \342\200\224 always ask first."
        inserted=1
        next
      }1' "$CLAUDE_MD" > "${CLAUDE_MD}.tmp" && mv "${CLAUDE_MD}.tmp" "$CLAUDE_MD"
      ok "  patched: planning-interview rule added to ## Project Rules"
      appended=1
    fi
    if ! awk '
      /^[[:space:]]{0,3}(```|~~~)/ { fenced=!fenced; next }
      !fenced && /^## Project Rules[[:space:]]*$/ { section=1; next }
      !fenced && /^## / { section=0 }
      section && /DESIGN-RULES/ { found=1 }
      END { exit(found ? 0 : 1) }
    ' "$CLAUDE_MD" 2>/dev/null; then
      awk '
      /^[[:space:]]{0,3}(```|~~~)/ { fenced=!fenced }
      !fenced && !inserted && /^## Project Rules[[:space:]]*$/ {
        print
        print "- Before planning, implementing, or reviewing ANY user-facing UI, read `.agents/design/DESIGN-RULES.md` and obey it. It is the normative design system (density, spacing, overflow, copy) for every runtime \342\200\224 Claude and Codex alike."
        inserted=1
        next
      }1' "$CLAUDE_MD" > "${CLAUDE_MD}.tmp" && mv "${CLAUDE_MD}.tmp" "$CLAUDE_MD"
      ok "  patched: design-rules consultation rule added to ## Project Rules"
      appended=1
    fi

    # Replace the legacy blanket prohibition only inside the exact Project
    # Rules section. Read-only inspection has the same authority in Claude and
    # Codex; destructive/external actions still require confirmation.
    if awk '
      /^[[:space:]]{0,3}(```|~~~)/ { fenced=!fenced; next }
      !fenced && /^## Project Rules[[:space:]]*$/ { section=1; next }
      !fenced && /^## / { section=0 }
      section && $0 == "- Never run Git or shell commands without explicit confirmation." { found=1 }
      END { exit(found ? 0 : 1) }
    ' "$CLAUDE_MD" 2>/dev/null; then
      awk '
        /^[[:space:]]{0,3}(```|~~~)/ { fenced=!fenced }
        !fenced && /^## Project Rules[[:space:]]*$/ { section=1 }
        !fenced && section && /^## / && !/^## Project Rules[[:space:]]*$/ { section=0 }
        section && $0 == "- Never run Git or shell commands without explicit confirmation." {
          print "- Read-only Git and shell inspection within the active task is allowed without new confirmation."
          print "- Ask before destructive commands, credentials or identity changes, production mutations, external communications, or material scope expansion."
          next
        }
        { print }
      ' "$CLAUDE_MD" > "${CLAUDE_MD}.tmp" && mv "${CLAUDE_MD}.tmp" "$CLAUDE_MD"
      ok "  patched: Claude/Codex operational authority aligned"
      appended=1
    fi

    if ! awk '
      /^[[:space:]]{0,3}(```|~~~)/ { fenced=!fenced; next }
      !fenced && /^## Project Rules[[:space:]]*$/ { section=1; next }
      !fenced && /^## / { section=0 }
      section && /Read-only Git and shell inspection within the active task/ { found=1 }
      END { exit(found ? 0 : 1) }
    ' "$CLAUDE_MD" 2>/dev/null; then
      awk '
        /^[[:space:]]{0,3}(```|~~~)/ { fenced=!fenced }
        !fenced && !inserted && /^## Project Rules[[:space:]]*$/ {
          print
          print "- Read-only Git and shell inspection within the active task is allowed without new confirmation."
          print "- Ask before destructive commands, credentials or identity changes, production mutations, external communications, or material scope expansion."
          inserted=1
          next
        }1
      ' "$CLAUDE_MD" > "${CLAUDE_MD}.tmp" && mv "${CLAUDE_MD}.tmp" "$CLAUDE_MD"
      ok "  patched: scoped operational authority added to ## Project Rules"
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

# ── install_global_fallback_libs ────────────────────────────────────────────
# ~/.canuto/lib: cópia global de event-log.sh e canuto-memory.sh (contrato
# Tracks A/D, auditoria 2026-08-01). O event log morreu em ~90% dos projetos
# porque repos com install desatualizado não têm .agents/tools/event-log.sh.
# Consumidores (hooks) usam a cascata: lib do repo → ~/.canuto/lib/<arquivo> →
# stub que LOGA a ausência em ~/.canuto/vault/_health/missing-lib.jsonl.
install_global_fallback_libs() {
  local libdir="$HOME/.canuto/lib" lib src prev okd=""
  mkdir -p "$libdir"
  for lib in event-log.sh canuto-memory.sh brief-compose.sh memory-usage.sh delegation-ledger.sh; do
    src=".agents/tools/$lib"
    if [ ! -f "$src" ]; then
      warn "$lib não está em .agents/tools — lib global pulada."
      continue
    fi
    if ! bash -n "$src" 2>/dev/null; then
      warn "$lib do repo não parseia (bash -n) — NÃO copiado para ~/.canuto/lib."
      continue
    fi
    # Nunca deixar cópia quebrada em pé: uma lib global corrompida quebraria
    # hooks de TODOS os projetos de uma vez (mesmo padrão do install de hooks).
    prev=""
    if [ -f "$libdir/$lib" ]; then
      prev="$libdir/$lib.prev.$$"
      cp "$libdir/$lib" "$prev" 2>/dev/null || prev=""
    fi
    cp "$src" "$libdir/$lib"
    if bash -n "$libdir/$lib" 2>/dev/null; then
      ok "Lib global: $libdir/$lib"
      okd="$okd $lib"
      rm -f "$prev" 2>/dev/null || true
    else
      warn "$lib: cópia em $libdir não parseia — revertendo."
      if [ -n "$prev" ] && bash -n "$prev" 2>/dev/null; then
        mv "$prev" "$libdir/$lib"
      else
        rm -f "$libdir/$lib"
      fi
      rm -f "$prev" 2>/dev/null || true
    fi
  done
  if [ -n "$okd" ]; then
    {
      echo "canuto-lib"
      echo "installed-at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "source: $(pwd) ($(git rev-parse --short HEAD 2>/dev/null || echo unknown))"
      echo "files:$okd"
    } > "$libdir/VERSION" 2>/dev/null || true
  fi
}

# ── register_project_path ───────────────────────────────────────────────────
# Registro para o canuto-update-all.sh: <vault>/projects/<slug>/project-path.
# Registrar AQUI (install/update) e não só no hook SessionStart do Claude é o
# que cobre projetos usados apenas via runtime Codex — sessão Codex direta não
# roda os hooks do Claude Code (ver codex-maestro.sh) e ficaria invisível para
# o update-all. Postura de ESCRITA (canuto_require_project_slug): slug
# degradado criaria ilha nova no vault — melhor não registrar. Best-effort:
# roda em subshell (o set -euo pipefail do canuto-memory.sh não vaza) e nunca
# falha o install.
register_project_path() {
  local memlib=".agents/tools/canuto-memory.sh" slug="" regdir=""
  local gitdir="" gitcommon=""
  [ -f "$memlib" ] || return 0
  # Worktree linkado NÃO registra (git-dir != git-common-dir): o registro é
  # last-write-wins e a última sessão num worktree redirecionaria o update-all
  # — e o commit do update — para o branch de feature que estiver lá.
  gitdir=$(git rev-parse --git-dir 2>/dev/null) || gitdir=""
  gitcommon=$(git rev-parse --git-common-dir 2>/dev/null) || gitcommon=""
  if [ -n "$gitdir" ] && [ -n "$gitcommon" ] && [ "$gitdir" != "$gitcommon" ]; then
    return 0
  fi
  slug=$(CANUTO_TARGET_DIR="$(pwd)" bash -c '
    . ".agents/tools/canuto-memory.sh" 2>/dev/null || exit 1
    canuto_require_project_slug "$CANUTO_TARGET_DIR" 2>/dev/null
  ' 2>/dev/null) || slug=""
  [ -n "$slug" ] || return 0
  regdir="${CANUTO_VAULT_DIR:-$HOME/.canuto/vault}/projects/$slug"
  mkdir -p "$regdir" 2>/dev/null || return 0
  printf '%s\n' "$(pwd)" > "$regdir/project-path" 2>/dev/null || true
  ok "Projeto registrado para o update-all: $slug"
  return 0
}

update_tree_is_clean() {
  local status
  [ "$GIT_AVAILABLE" = true ] || return 0
  status=$(git status --porcelain --untracked-files=all 2>/dev/null) || return 1
  [ -z "$status" ]
}

check_result_code() {
  local outdated="$1" missing="$2" unknown="$3"
  if [ "$unknown" -gt 0 ]; then
    return 2
  fi
  if [ "$outdated" -gt 0 ] || [ "$missing" -gt 0 ]; then
    return 1
  fi
  return 0
}

# ── dedup_canuto_hook_dupes ─────────────────────────────────────────────────
# Self-heal (auditoria 2026-08-01): o merge antigo do settings.json agrupava
# por (matcher + conjunto de comandos do grupo); bastava o grupo local ter um
# hook a mais para a chave não bater e o grupo do snippet ser appendado inteiro
# de novo — 12 hooks chegaram a rodar 2x por evento. Remove duplicatas exatas
# (evento+matcher+command) de hooks CANUTO, preservando a 1ª ocorrência, e o
# caso nominal cross-matcher do codex-pretool-guard (matcher "" duplica "Bash"
# porque matcher vazio casa todo tool). Hooks não-canuto nunca são tocados.
dedup_canuto_hook_dupes() {
  local settings="$HOME/.claude/settings.json"
  [ -f "$settings" ] || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  local canuto_list="" f
  for f in .agents/hooks/*.sh; do
    [ -f "$f" ] || continue
    canuto_list="$canuto_list$(basename "$f"),"
  done
  # Fallback (instalação remota antes do download dos hooks): lista distribuída.
  if [ -z "$canuto_list" ]; then
    canuto_list="codex-pretool-guard.sh,log-commands.sh,protect-files.sh,require-tests-for-pr.sh,screenshot-guard.sh,session-save.sh,pre-compact-save.sh,session-start.sh,validation-mark.sh,validation-clear.sh,retry-detect.sh,fingerprint-gate.sh,posttooluse-universal.sh,pre-finalize.sh,pre-commit-branch-check.sh,worktree-collision-check.sh,pre-claim-grep.sh,pre-pr-bash-gate.sh,postdelegate-verify.sh,"
  fi
  python3 - "$settings" "$canuto_list" <<'PYDEDUP' || warn "self-heal de hooks duplicados falhou — settings.json intacto."
import json, os, sys
path, canuto_csv = sys.argv[1], sys.argv[2]
canuto = set(n for n in canuto_csv.split(",") if n)
HOME = os.path.expanduser("~")
def norm(c): return HOME + c[1:] if isinstance(c, str) and c.startswith("~") else c
def name(c):
    if not isinstance(c, str) or not c.strip(): return ""
    return c.split()[0].rsplit("/", 1)[-1]
data = json.load(open(path))
hooks = data.get("hooks")
if not isinstance(hooks, dict):
    raise SystemExit(0)
removed = []
for event, groups in list(hooks.items()):
    if not isinstance(groups, list):
        continue
    # R8: pré-scan — comandos do codex-pretool-guard que TÊM ocorrência com
    # matcher "Bash" neste evento. No cross-matcher, a "Bash" vence SEMPRE,
    # independente da ordem no arquivo: consolidar no matcher "" (por vir
    # primeiro) forkaria o guard em TODO tool, não só em Bash.
    guard_bash = set()
    for g in groups:
        if not isinstance(g, dict):
            continue
        if g.get("matcher", "") != "Bash":
            continue
        for h in g.get("hooks", []):
            if isinstance(h, dict):
                c = norm(h.get("command", ""))
                if name(c) == "codex-pretool-guard.sh":
                    guard_bash.add(c)
    seen, first_matcher, out = set(), {}, []
    for g in groups:
        if not isinstance(g, dict):
            out.append(g); continue
        m = g.get("matcher", "")
        kept = []
        for h in g.get("hooks", []):
            if not isinstance(h, dict):
                kept.append(h); continue
            c = norm(h.get("command", ""))
            n = name(c)
            if (m, c) in seen and n in canuto:
                removed.append((event, m, h.get("command", ""))); continue
            if n == "codex-pretool-guard.sh":
                if c in guard_bash and m != "Bash":
                    removed.append((event, m, h.get("command", ""))); continue
                if c not in guard_bash and c in first_matcher and first_matcher[c] != m:
                    removed.append((event, m, h.get("command", ""))); continue
            seen.add((m, c)); first_matcher.setdefault(c, m); kept.append(h)
        if kept:
            g2 = dict(g); g2["hooks"] = kept; out.append(g2)
    hooks[event] = out
if removed:
    tmp = path + ".canuto-dedup.tmp"
    with open(tmp, "w") as fh:
        json.dump(data, fh, indent=2, ensure_ascii=False)
        fh.write("\n")
    os.replace(tmp, path)
    for e, m, c in removed:
        print("   self-heal: removida duplicata [%s] matcher=%r %s" % (e, m, c))
PYDEDUP
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

  # Self-heal + lib global rodam SEMPRE — mesmo quando o repo trouxer um
  # .agents/hooks/install.sh antigo (sem essas proteções), a máquina sai curada.
  dedup_canuto_hook_dupes
  install_global_fallback_libs

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
    local src="$1"       # e.g. ".agents/hooks/session-save.sh"
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

    # Verificar o DESTINO, não a origem. Um hook que não parseia dispara erro a
    # cada invocação — e o posttooluse-universal tem matcher ".*", ou seja, todo
    # comando da sessão. Visto em campo: "syntax error near unexpected token '('"
    # repetido a sessão inteira, com o arquivo do repo íntegro. A cópia chegou
    # corrompida na máquina; a causa exata não importa aqui, o que importa é o
    # instalador não deixar isso em pé.
    local prev_backup=""
    if [ -f "$dst" ]; then
      prev_backup="$dst.prev.$$"
      cp "$dst" "$prev_backup" 2>/dev/null || prev_backup=""
    fi

    cp "$src" "$dst"
    chmod +x "$dst"

    if ! bash -n "$dst" 2>/dev/null; then
      warn "$filename: a cópia em $dst NÃO parseia (bash -n falhou)."
      bash -n "$dst" 2>&1 | head -3 | sed 's/^/      /'
      if [ -n "$prev_backup" ] && bash -n "$prev_backup" 2>/dev/null; then
        mv "$prev_backup" "$dst"; chmod +x "$dst"
        warn "   versão anterior (íntegra) restaurada — re-rode o instalador."
      else
        # Sem versão boa para voltar: melhor hook ausente que hook que falha em
        # todo comando. O registro no settings.json fica, e a próxima execução
        # do instalador reinstala.
        rm -f "$dst"
        warn "   arquivo removido — melhor sem hook que com hook quebrado."
      fi
      rm -f "$prev_backup" 2>/dev/null || true
      return
    fi
    rm -f "$prev_backup" 2>/dev/null || true
    ok "Installed: $dst"

    # Presença por (evento + command), em qualquer grupo/matcher do evento —
    # cobre (evento+matcher+command) e nunca re-registra hook já consolidado
    # pelo usuário sob outro matcher. O grep-substring antigo checava o
    # arquivo inteiro: nunca duplicava, mas também não sabia EM QUAL evento o
    # hook estava.
    local already
    already=$(jq -r --arg event "$event" --arg name "/$filename" '
      [ .hooks[$event]? // [] | .[] | .hooks? // [] | .[]
        | .command? // "" | select(type == "string")
        | select((split(" ")[0]) | endswith($name)) ] | length
    ' "$settings" 2>/dev/null || echo 0)
    if [ "${already:-0}" -gt 0 ] 2>/dev/null; then
      ok "Hook $event ($filename) already registered in this event — skipping."
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
  install_hook ".agents/hooks/codex-pretool-guard.sh" "PreToolUse"  240
  install_hook ".agents/hooks/screenshot-guard.sh"  "PreToolUse"    3  "mcp__playwright__browser_take_screenshot|mcp__claude-in-chrome__computer"
  install_hook ".agents/hooks/session-save.sh"      "Stop"          30
  install_hook ".agents/hooks/pre-compact-save.sh"  "Notification"  15
  # Observability + enforcement gate hooks (v1.9)
  install_hook ".agents/hooks/session-start.sh"     "SessionStart"  5
  install_hook ".agents/hooks/validation-mark.sh"   "PostToolUse"   3  "Edit|Write"
  install_hook ".agents/hooks/validation-clear.sh"  "PostToolUse"   3  "Bash"
  install_hook ".agents/hooks/retry-detect.sh"      "PostToolUse"   3  "Bash"
  install_hook ".agents/hooks/posttooluse-universal.sh" "PostToolUse" 3  ".*"
  install_hook ".agents/hooks/fingerprint-gate.sh"  "PreToolUse"    3  "Edit|Write"
  install_hook ".agents/hooks/pre-finalize.sh"      "Stop"          5
  # Retrabalho-prevention hooks (v1.7) — born from sessions 2026-04-18 e 04-18b (I-023, I-026, I-027)
  install_hook ".agents/hooks/worktree-collision-check.sh" "SessionStart" 3
  install_hook ".agents/hooks/pre-commit-branch-check.sh"  "PreToolUse"   3  "Bash"
  install_hook ".agents/hooks/pre-claim-grep.sh"           "PreToolUse"   3  "Write"

  # Git pre-push gate — costura runtime-agnóstica (vale para Claude, Codex
  # direto e push manual). Shim regenerável identificado pelo marker.
  local git_hooks_path prepush
  git_hooks_path="$(git rev-parse --git-path hooks 2>/dev/null || true)"
  if [ -n "$git_hooks_path" ] && [ -f ".agents/hooks/git-pre-push-gate.sh" ]; then
    case "$git_hooks_path" in /*) : ;; *) git_hooks_path="$(pwd)/$git_hooks_path" ;; esac
    mkdir -p "$git_hooks_path"
    prepush="$git_hooks_path/pre-push"
    if [ -f "$prepush" ] && ! grep -q "canuto:git-pre-push-gate" "$prepush" 2>/dev/null; then
      warn "pre-push existente (não-canuto) preservado em $prepush — encadeie: bash .agents/hooks/git-pre-push-gate.sh"
    else
      cat > "$prepush" <<'PREPUSH_SHIM'
#!/usr/bin/env bash
# canuto:git-pre-push-gate — shim gerado pelo install.sh (não editar).
GATE="$(git rev-parse --show-toplevel)/.agents/hooks/git-pre-push-gate.sh"
[ -f "$GATE" ] && exec bash "$GATE" "$@"
exit 0
PREPUSH_SHIM
      chmod +x "$prepush"
      ok "Installed: git pre-push gate → $prepush (runtime-agnóstico)"
    fi
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

  # Install ast-grep if missing. Não confiar em `command -v sg`: em Linux o
  # `sg` do shadow (set group) ocupa o mesmo nome e daria falso positivo.
  if command -v ast-grep &> /dev/null; then
    ok "ast-grep already installed ($(ast-grep --version 2>/dev/null | head -1))"
  elif command -v sg &> /dev/null && sg --version 2>&1 | grep -qi ast-grep; then
    ok "ast-grep already installed ($(sg --version 2>/dev/null | head -1))"
  elif command -v brew &> /dev/null; then
    log "Installing ast-grep via Homebrew..."
    brew install ast-grep 2>/dev/null && ok "ast-grep installed" || warn "Failed to install ast-grep — install manually: brew install ast-grep"
  elif command -v npm &> /dev/null; then
    log "Installing ast-grep via npm..."
    npm install -g @ast-grep/cli >/dev/null 2>&1 && ok "ast-grep installed" || warn "Failed to install ast-grep — install manually: npm install -g @ast-grep/cli"
  else
    warn "ast-grep not found. Install manually: npm install -g @ast-grep/cli  (macOS: brew install ast-grep)"
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

  mkdir -p "$vault/.obsidian/templates"
  for template_file in .agents/vault/.obsidian/templates/*.md; do
    [ -f "$template_file" ] || continue
    cp "$template_file" "$vault/.obsidian/templates/$(basename "$template_file")"
  done
  ok "Obsidian templates synced"

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
  for dir in sessions decisions instincts pending handoffs audit metrics design design/components; do
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
# project trust (Conductor-aware). Idempotent — safe to run on every update.
#
# As of 2026-04-29: Codex is invoked exclusively via CLI (`codex exec --profile <name>`).
# The codex-coder/codex-reviewer/codex-maestro MCP servers were retired — see
# .agents/skills/cost-routing.md for rationale (10-35% lower token overhead per call).
setup_codex() {
  local config_toml="$HOME/.codex/config.toml"
  local CANONICAL_MODEL="gpt-5.6-sol"

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
    local current_version
    current_version=$(codex --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "unknown")
    ok "Codex CLI $current_version"

    # Auto-update on --update or --repair
    if [[ "${MODE:-}" =~ ^(update|repair)$ ]] && command -v npm &>/dev/null; then
      local latest_version
      latest_version=$(npm show @openai/codex version 2>/dev/null || echo "")
      if [ -n "$latest_version" ] && [ "$current_version" != "$latest_version" ]; then
        log "Codex CLI $current_version → $latest_version"
        npm i -g @openai/codex@latest 2>/dev/null \
          && ok "Codex CLI updated to $latest_version" \
          || warn "Failed to update Codex CLI"
      else
        ok "Codex CLI up to date ($current_version)"
      fi
    fi
  fi

  # ── Configure config.toml with profiles ──────────────────────────────────
  mkdir -p "$HOME/.codex"
  if [ ! -f "$config_toml" ]; then
    # NÃO pinar `model` no top-level: isso sobrescreve a escolha global do
    # usuário. Até 2026-07-26 este heredoc gravava model = "gpt-5.5", ou seja,
    # uma instalação nova REBAIXAVA o modelo global da máquina.
    # NÃO gravar blocos [profiles.*]: o codex-cli 0.135+ não os lê mais
    # (semântica v2 lê ~/.codex/<role>.config.toml). Eram config morta.
    cat > "$config_toml" << 'TOMLEOF'
personality = "pragmatic"
TOMLEOF
    ok "Created $config_toml (sem pin de modelo — a escolha global é do usuário)"
  else
    # Patch-merge: add missing profiles AND update existing model/reasoning_effort
    # to the canonical hardcoded values below. Keep .agents/config/models.yaml
    # in sync manually when bumping model versions.
    local patched=false
    # Fonte de verdade do caminho de delegação é .agents/config/models.yaml,
    # não este valor. Isto só alcança os blocos [profiles.*] legados que o
    # codex-cli 0.135+ já não lê — mantido apenas para não deixar valor
    # defasado em config.toml de máquinas antigas.
    for profile in coder maestro reviewer architect fast; do
      local effort
      case "$profile" in
        maestro|architect) effort="xhigh" ;;
        coder|reviewer|fast) effort="high" ;;
        *) effort="high" ;;
      esac
      if ! grep -q "\[profiles\.$profile\]" "$config_toml" 2>/dev/null; then
        # Bloco ausente: NÃO criar. [profiles.*] é config morta (codex-cli
        # 0.135+ ignora) — só atualizamos blocos legados que JÁ existam, para
        # não deixar valor defasado. Criar bloco morto em máquina limpa dava
        # ilusão de controle (2026-07-27: instalação fresca ganhava 5 blocos
        # que nada leem).
        :
      else
        # Profile present — update model and reasoning_effort if drifted
        # Use awk to rewrite values within the [profiles.<name>] block only.
        local tmp_toml
        tmp_toml=$(mktemp)
        awk -v profile="$profile" -v model="$CANONICAL_MODEL" -v effort="$effort" '
          BEGIN { in_block = 0 }
          $0 ~ "^\\[profiles\\." profile "\\]$" { in_block = 1; print; next }
          /^\[/ && in_block { in_block = 0 }
          in_block && /^model[[:space:]]*=/ {
            sub(/=.*/, "= \"" model "\"")
            patched_model = 1
            print
            next
          }
          in_block && /^model_reasoning_effort[[:space:]]*=/ {
            sub(/=.*/, "= \"" effort "\"")
            patched_effort = 1
            print
            next
          }
          { print }
          END { if (!(patched_model && patched_effort)) exit 2 }
        ' "$config_toml" > "$tmp_toml" 2>/dev/null
        local awk_status=$?

        if [ "$awk_status" -eq 0 ]; then
          if ! cmp -s "$config_toml" "$tmp_toml"; then
            mv "$tmp_toml" "$config_toml"
            patched=true
          else
            rm -f "$tmp_toml"
          fi
        else
          # awk couldn't find both keys — leave as is, don't risk corruption
          rm -f "$tmp_toml"
        fi
      fi
    done
    if $patched; then
      ok "Updated $config_toml profiles to canonical $CANONICAL_MODEL"
    else
      ok "config.toml profiles already on canonical model"
    fi
  fi

  # ── Perfis v2: ~/.codex/<role>.config.toml ────────────────────────────────
  # ESTES são o caminho vivo do `--profile` no codex-cli 0.135+. Não confundir
  # com os blocos [profiles.*] acima (mortos). Consumidores reais hoje:
  #   - `codex exec --profile <role>` cru e o app Desktop
  #   - codex-pretool-guard.sh:431, que usa `--profile fast` no tier degradado
  #     do review de pre-commit -> por isso `fast` fica num modelo capaz, não no
  #     tier nano: review degradado ainda é review.
  # O caminho do WRAPPER (codex-delegate.sh) ignora tudo isto e lê
  # .agents/config/models.yaml. Os dois precisam ficar coerentes.
  local role effort
  for role in coder reviewer architect maestro fast; do
    case "$role" in
      architect|maestro) effort="xhigh" ;;
      coder|reviewer)    effort="xhigh" ;;
      fast)              effort="low" ;;
    esac
    local role_config="$HOME/.codex/${role}.config.toml"
    if [ ! -f "$role_config" ]; then
      printf 'model = "%s"\nmodel_reasoning_effort = "%s"\n' \
        "$CANONICAL_MODEL" "$effort" > "$role_config"
      continue
    fi

    local tmp_role_config
    tmp_role_config=$(mktemp)
    awk -v model="$CANONICAL_MODEL" -v effort="$effort" '
      BEGIN { in_top_level = 1; model_written = 0; effort_written = 0 }
      function write_missing() {
        if (!model_written) print "model = \"" model "\""
        if (!effort_written) print "model_reasoning_effort = \"" effort "\""
      }
      in_top_level && /^\[/ {
        write_missing()
        in_top_level = 0
      }
      in_top_level && /^model[[:space:]]*=/ {
        print "model = \"" model "\""
        model_written = 1
        next
      }
      in_top_level && /^model_reasoning_effort[[:space:]]*=/ {
        print "model_reasoning_effort = \"" effort "\""
        effort_written = 1
        next
      }
      { print }
      END {
        if (in_top_level) write_missing()
      }
    ' "$role_config" > "$tmp_role_config"
    if ! cmp -s "$role_config" "$tmp_role_config"; then
      mv "$tmp_role_config" "$role_config"
    else
      rm -f "$tmp_role_config"
    fi
  done
  ok "Merged per-role profiles v2: ~/.codex/{coder,reviewer,architect,maestro,fast}.config.toml"

  # ── Wrapper canônico de delegação: ~/.codex/bin/codex-delegate.sh ────────
  # Template versionado em .agents/tools/codex-delegate.sh. Instala SOMENTE
  # quando ausente — nunca sobrescreve o wrapper existente da máquina (que
  # pode carregar ajustes locais). Sem isto, máquina nova ficava sem o
  # caminho canônico de delegação que o models.yaml documenta.
  if [ -f ".agents/tools/codex-delegate.sh" ] && [ ! -f "$HOME/.codex/bin/codex-delegate.sh" ]; then
    mkdir -p "$HOME/.codex/bin"
    cp ".agents/tools/codex-delegate.sh" "$HOME/.codex/bin/codex-delegate.sh"
    chmod +x "$HOME/.codex/bin/codex-delegate.sh"
    ok "Installed: ~/.codex/bin/codex-delegate.sh (wrapper canônico — template do framework)"
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

  # ── Install Codex shared libs to ~/.claude/scripts ──────────────────────
  # Only common libs and CLI launcher (codex-common.sh, codex-diff-context.sh).
  # MCP-server wrappers (codex-coder.sh, codex-reviewer.sh, codex-agent-mcp.py)
  # were retired — Maestro now invokes Codex via `codex exec --profile <name>` directly.
  local claude_scripts_dir="$HOME/.claude/scripts"
  mkdir -p "$claude_scripts_dir"

  for src in .agents/tools/codex-common.sh .agents/tools/codex-diff-context.sh; do
    if [ -f "$src" ]; then
      cp "$src" "$claude_scripts_dir/$(basename "$src")"
      chmod +x "$claude_scripts_dir/$(basename "$src")"
      ok "Installed Codex shared lib: $claude_scripts_dir/$(basename "$src")"
    fi
  done

  # ── Remove legacy codex-* MCP entries from settings.json ────────────────
  # Cleanup for users upgrading from pre-2026-04-29 versions that registered
  # codex-coder/codex-reviewer/codex-maestro MCP servers.
  local settings="$HOME/.claude/settings.json"
  if command -v jq &> /dev/null && [ -f "$settings" ]; then
    local cleaned
    cleaned=$(jq '
      if .mcpServers then
        .mcpServers |= (
          del(.["codex-coder"])
          | del(.["codex-reviewer"])
          | del(.["codex-maestro"])
        )
      else . end
    ' "$settings")
    if [[ -n "$cleaned" ]] && ! cmp -s <(echo "$cleaned") "$settings"; then
      echo "$cleaned" > "$settings"
      ok "Removed legacy codex-* MCP entries from settings.json (Codex now invoked via CLI)"
    fi
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
- Read `.agents/OPERATING-CONTRACT.md` before non-trivial work; it is the shared
  Claude/Codex contract for evidence, authorization, WIP and cross-host drift.
- Read .context.md files in each directory for local context
- Read docs/FEATURE-MAP.md for feature status and flows
- Read .agents/tmp/context-package.md if it exists (pre-loaded context from Architect)

## Coding Rules
- Prefer the simplest implementation that fully meets the current requirement. No speculative abstraction, configuration, or indirection.
- Grow in layers: smallest version that works end to end first, each new capability on top of something that already works. Never leave the tree broken mid-refactor.
- Do not assume a library lacks a capability without checking its docs and types.
- Follow existing patterns in nearby files — match style, naming, structure
- Do NOT add new dependencies without explicit instruction in the prompt
- Include basic happy-path tests for new functions
- Use TypeScript strict mode if tsconfig.json has strict: true
- Prefer editing existing files over creating new ones
- Do NOT add comments, docstrings, or type annotations to code you didn't change

## Design Rules (mandatory for any UI work)
- Before planning, implementing, or reviewing ANY user-facing UI, read
  `.agents/design/DESIGN-RULES.md` and obey it. It is the normative design
  system: density, type scale, spacing ceilings, overflow bans, copy rules.
- On conflict with any other guidance, DESIGN-RULES.md wins.

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

**Modelo e effort NÃO são declarados aqui.** A fonte única é
`.agents/config/models.yaml` — é o arquivo que o wrapper realmente lê.
Duplicar a versão numa tabela de doc é como a defasagem começa.

| Role | Use For |
|------|---------|
| `coder` | Geração de código, refactor, edits multi-arquivo |
| `reviewer` | Review de código e plano (roda read-only) |
| `architect` | Arquitetura, decomposição complexa |
| `maestro` | Orquestração em runtime Codex direto |
| `fast` | Edits rápidos, formatação, docs (tier mais barato) |

- Caminho canônico de delegação: `~/.codex/bin/codex-delegate.sh <role> <task> <out>`.
- `--profile` não é lido pelo wrapper. Vale para `codex exec` cru e para o app
  Desktop, via `~/.codex/<role>.config.toml` (perfis v2) — **não** pelos blocos
  `[profiles.*]` de `config.toml`, que o codex-cli 0.135+ ignora.
- Nunca use `-q` (removido no codex-cli 0.135).
- Sessões Claude mantêm Claude como Maestro (alias `fable`, fallback `opus`).

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
    if ! awk '
      /^[[:space:]]{0,3}(```|~~~)/ { fenced=!fenced; next }
      !fenced && /^[[:space:]]*-[[:space:]]+Read `\.agents\/OPERATING-CONTRACT\.md` before non-trivial work;/ { found=1 }
      END { exit(found ? 0 : 1) }
    ' "$agents_md" 2>/dev/null && awk '
      /^[[:space:]]{0,3}(```|~~~)/ { fenced=!fenced }
      END { exit(fenced ? 0 : 1) }
    ' "$agents_md" 2>/dev/null; then
      {
        cat <<'CONTRACTRECOVERY'
## Shared Operating Contract
- Read `.agents/OPERATING-CONTRACT.md` before non-trivial work; it is the shared
  Claude/Codex contract for evidence, authorization, WIP and cross-host drift.

CONTRACTRECOVERY
        cat "$agents_md"
      } > "${agents_md}.tmp" && mv "${agents_md}.tmp" "$agents_md"
      warn "$agents_md had an unclosed Markdown fence; the active contract was preserved in a prefix outside it."
      patched=true
    fi
    if ! awk '
      /^[[:space:]]{0,3}(```|~~~)/ { fenced=!fenced; next }
      !fenced && /^[[:space:]]*-[[:space:]]+Read `\.agents\/OPERATING-CONTRACT\.md` before non-trivial work;/ { found=1 }
      END { exit(found ? 0 : 1) }
    ' "$agents_md" 2>/dev/null; then
      cat >> "$agents_md" << 'CONTRACTPATCH'

## Shared Operating Contract
- Read `.agents/OPERATING-CONTRACT.md` before non-trivial work; it is the shared
  Claude/Codex contract for evidence, authorization, WIP and cross-host drift.
CONTRACTPATCH
      patched=true
    fi
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

**Modelo e effort NÃO são declarados aqui.** A fonte única é
`.agents/config/models.yaml` — é o arquivo que o wrapper realmente lê.
Duplicar a versão numa tabela de doc é como a defasagem começa.

| Role | Use For |
|------|---------|
| `coder` | Geração de código, refactor, edits multi-arquivo |
| `reviewer` | Review de código e plano (roda read-only) |
| `architect` | Arquitetura, decomposição complexa |
| `maestro` | Orquestração em runtime Codex direto |
| `fast` | Edits rápidos, formatação, docs (tier mais barato) |

- Caminho canônico de delegação: `~/.codex/bin/codex-delegate.sh <role> <task> <out>`.
- `--profile` não é lido pelo wrapper. Vale para `codex exec` cru e para o app
  Desktop, via `~/.codex/<role>.config.toml` (perfis v2) — **não** pelos blocos
  `[profiles.*]` de `config.toml`, que o codex-cli 0.135+ ignora.
- Nunca use `-q` (removido no codex-cli 0.135).
- Sessões Claude mantêm Claude como Maestro (alias `fable`, fallback `opus`).
PROFILEPATCH
      patched=true
    fi
    if ! grep -q "DESIGN-RULES" "$agents_md" 2>/dev/null; then
      cat >> "$agents_md" << 'DESIGNPATCH'

## Design Rules (mandatory for any UI work)
- Before planning, implementing, or reviewing ANY user-facing UI, read
  `.agents/design/DESIGN-RULES.md` and obey it. It is the normative design
  system: density, type scale, spacing ceilings, overflow bans, copy rules.
- On conflict with any other guidance, DESIGN-RULES.md wins.
DESIGNPATCH
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
    if ! grep -q "codex-maestro.sh" "$agents_md" 2>/dev/null; then
      cat >> "$agents_md" << 'RUNTIMEPATCH'

## Codex Runtime
- Sessões Claude mantêm Claude como Maestro (alias `fable`, fallback `opus`).
- Sessões Codex diretas: `bash .agents/tools/codex-maestro.sh` ou `codex --profile maestro`.
- O perfil `maestro` é runtime-specific e não redefine `coder`, `reviewer`, `architect` ou `fast`.
- Modelo e effort vêm de `.agents/config/models.yaml`, não desta doc. Não pinar
  versão aqui — foi assim que a tabela anterior ficou 2 releases atrás do real.
RUNTIMEPATCH
      patched=true
    fi
    # Um `## Coding Rules` dentro de bloco cercado é exemplo, não seção. Este
    # repo GERA AGENTS.md, então documentar a seção num bloco de código é
    # plausível — tratá-la como real faria o patch cair dentro da cerca.
    # Rastreio de cerca CommonMark: abre com 3+ de ` ou ~, fecha só com o MESMO
    # char e comprimento >= o de abertura. Contar toda linha de crase como
    # alternância deixava a paridade presa em arquivo com cerca não fechada.
    agents_fence_awk='
      function fence_line(l,   ch, n) {
        if (l !~ /^(```+|~~~+)/) return 0
        ch = substr(l, 1, 1); n = match(l, /[^`~]|$/) - 1
        if (!fence) { fence = 1; fchar = ch; flen = n }
        else if (ch == fchar && n >= flen) { fence = 0 }
        return 1
      }'
    agents_has_section=$(awk "$agents_fence_awk"'
      { if (fence_line($0)) next }
      !fence && /^##+ Coding Rules[[:space:]]*$/{print "yes"; exit}' "$agents_md" 2>/dev/null || true)
    # Guarda de convergência, independente do rastreio de cerca: se existe
    # QUALQUER linha de heading Coding Rules, nunca anexar outra seção. Sem
    # isso, um falso negativo na deteção anexa uma seção nova a cada run.
    agents_any_section=$(grep -cE '^##+ Coding Rules[[:space:]]*$' "$agents_md" 2>/dev/null || true)
    if [ "$agents_has_section" != "yes" ] && [ "${agents_any_section:-0}" -gt 0 ]; then
      warn "AGENTS.md: '## Coding Rules' só aparece dentro de bloco de código — nada aplicado (edite a seção real e rode de novo)"
    elif [ "$agents_has_section" != "yes" ]; then
      # Section absent — append it whole. Must mirror the generation heredoc
      # above; a partial section would leave the project permanently without
      # the dependency and test rules, and no later run would repair it.
      cat >> "$agents_md" << 'RULESPATCH'

## Coding Rules
- Prefer the simplest implementation that fully meets the current requirement. No speculative abstraction, configuration, or indirection.
- Grow in layers: smallest version that works end to end first, each new capability on top of something that already works. Never leave the tree broken mid-refactor.
- Do not assume a library lacks a capability without checking its docs and types.
- Follow existing patterns in nearby files — match style, naming, structure
- Do NOT add new dependencies without explicit instruction in the prompt
- Include basic happy-path tests for new functions
- Use TypeScript strict mode if tsconfig.json has strict: true
- Prefer editing existing files over creating new ones
- Do NOT add comments, docstrings, or type annotations to code you didn't change
RULESPATCH
      patched=true
    else
      # Section exists — one sentinel PER rule, so deleting or translating a
      # single bullet never re-inserts the others as duplicates. Collect the
      # missing ones first, then insert once, to keep canonical order.
      #
      # A presença é checada DENTRO da seção, não no arquivo inteiro: uma regra
      # citada em bloco de código ou em prosa não pode contar como aplicada,
      # senão a seção real nunca a recebe e o instalador diz "up to date".
      # Encerra no próximo heading de nível IGUAL OU MAIOR — um `### Gerais`
      # dentro da seção não a termina, senão a extração sai vazia e as regras
      # já presentes são reinseridas como duplicata. Conteúdo dentro de cerca
      # não conta como presença: exemplo citado não é regra aplicada.
      agents_section=$(awk "$agents_fence_awk"'
        { if (fence_line($0)) next }
        !fence && /^##+ Coding Rules[[:space:]]*$/{ match($0,/^#+/); lvl=RLENGTH; f=1; next }
        f && !fence && /^#+ /{ match($0,/^#+/); if (RLENGTH<=lvl) exit }
        f && !fence' "$agents_md" 2>/dev/null || true)
      agents_missing=""
      while IFS= read -r rule; do
        [ -n "$rule" ] || continue
        # `--` obrigatório: a regra começa com "- " e o grep a leria como opção
        printf '%s\n' "$agents_section" | grep -qF -- "$rule" || agents_missing="${agents_missing}${rule}"$'\034'
      done << 'RULESLIST'
- Prefer the simplest implementation that fully meets the current requirement. No speculative abstraction, configuration, or indirection.
- Grow in layers: smallest version that works end to end first, each new capability on top of something that already works. Never leave the tree broken mid-refactor.
- Do not assume a library lacks a capability without checking its docs and types.
RULESLIST
      if [ -n "$agents_missing" ]; then
        # Escreve no ALVO resolvido, para não trocar um symlink por cópia local,
        # e publica com `mv` (rename atômico). Nunca redirecionar por cima do
        # arquivo do usuário: o `>` trunca antes de escrever, e uma falha no
        # meio deixaria um AGENTS.md parcial sem cópia de retorno.
        agents_dest="$agents_md"
        if [ -L "$agents_dest" ]; then
          # `readlink -f` não existe no BSD antigo; resolve manualmente na falta
          agents_dest=$(readlink -f "$agents_dest" 2>/dev/null || true)
          if [ -z "$agents_dest" ]; then
            agents_dest="$agents_md"; agents_hops=0
            while [ -L "$agents_dest" ] && [ "$agents_hops" -lt 16 ]; do
              agents_link=$(readlink "$agents_dest" 2>/dev/null || true)
              [ -n "$agents_link" ] || break
              case "$agents_link" in
                /*) agents_dest="$agents_link" ;;
                *)  agents_dest="$(dirname "$agents_dest")/$agents_link" ;;
              esac
              agents_hops=$((agents_hops + 1))
            done
          fi
        fi
        agents_tmp="${agents_dest}.canuto.$$"
        if awk -v ins="$agents_missing" "$agents_fence_awk"'
              BEGIN{n=split(ins, a, "\034")}
              { if (fence_line($0)) { print; next } }
              !fence && !seen && /^##+ Coding Rules[[:space:]]*$/{
                print; for(i=1;i<=n;i++) if(a[i]!="") print a[i]; seen=1; next
              }
              1' "$agents_dest" > "$agents_tmp"; then
          # herda o modo do original; sem isso o arquivo publicado nasce com o umask
          chmod "$(stat -c '%a' "$agents_dest" 2>/dev/null || stat -f '%Lp' "$agents_dest" 2>/dev/null || echo 644)" "$agents_tmp" 2>/dev/null || true
          if mv -f "$agents_tmp" "$agents_dest"; then
            patched=true
          else
            rm -f "$agents_tmp"
            warn "AGENTS.md: falha ao publicar ## Coding Rules — arquivo original intacto"
          fi
        else
          rm -f "$agents_tmp"
          warn "AGENTS.md: falha ao inserir regras em ## Coding Rules — arquivo original intacto"
        fi
      fi
    fi
    if $patched; then
      ok "AGENTS.md patched with missing sections"
    else
      ok "AGENTS.md already up to date"
    fi
  fi
}

render_codex_md() {
  local project_dir
  project_dir=$(resolve_project_dir "$(pwd)")
  local template="$project_dir/.agents/templates/CODEX.md"
  local output="$project_dir/CODEX.md"
  local project_slug
  local project_rules

  if [ ! -f "$template" ]; then
    warn "CODEX template missing at $template"
    return
  fi

  project_slug=$(detect_project_slug "$project_dir")
  project_rules=$(awk '
    /^## Project Rules[[:space:]]*$/ { in_section=1; next }
    /^## / && in_section { exit }
    in_section { print }
  ' "$project_dir/CLAUDE.md" 2>/dev/null)

  if [ -z "$project_rules" ]; then
    project_rules="- Follow the active project rules from CLAUDE.md."
  fi

  {
    while IFS= read -r line || [ -n "$line" ]; do
      line=${line//'{{PROJECT_SLUG}}'/$project_slug}
      if [ "$line" = "{{PROJECT_RULES}}" ]; then
        printf '%s\n' "$project_rules"
      else
        printf '%s\n' "$line"
      fi
    done < "$template"
  } > "$output"

  ok "CODEX.md rendered from template"
}

ensure_bootstrap_context_package() {
  local output_file=".agents/tmp/context-package.md"

  if [ -x ".agents/tools/codex-context-package.sh" ]; then
    if bash ".agents/tools/codex-context-package.sh" \
      --task "Bootstrap Context" \
      --task-id "bootstrap-context" \
      --goal "Create a resumable baseline handoff package for this repository." \
      --done-definition "Bootstrap context package exists at .agents/tmp/context-package.md" \
      --done-definition "Core repo rules and entrypoints are captured for Claude/Codex handoffs" \
      --output "$output_file" \
      --file "CLAUDE.md" \
      --file ".context.md" \
      --file "docs/FEATURE-MAP.md" >/dev/null 2>&1 && [ -s "$output_file" ]; then
      ok "Bootstrap context package ready"
      return 0
    fi
    warn "codex-context-package bootstrap failed — writing fallback context package"
  fi

  cat > "$output_file" <<'EOF'
# Context Package — Bootstrap Context

- generated_by: install.sh
- task_id: bootstrap-context

## Handoff Envelope
- goal: Create a resumable baseline handoff package for this repository.
- thread_id:

### Constraints
- Use existing patterns in nearby files.
- Do not add dependencies unless explicitly approved.
- Add or update happy-path tests for the touched behavior.
- If context is missing, call it out instead of guessing.

### Done Definition
- Bootstrap context package exists at `.agents/tmp/context-package.md`
- Core repo rules and entrypoints are captured for Claude/Codex handoffs

## Files and Directories in Scope
- CLAUDE.md
- .context.md
- docs/FEATURE-MAP.md

## Notes
- Generated as a fallback because the full codex-context-package flow was unavailable.
EOF
  ok "Bootstrap context package ready (fallback)"
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
  # Dependência ausente não pode pular os reparos locais (chmod, merge de
  # CLAUDE.md, bootstrap de contexto, hooks): o rc de setup_deps é lembrado
  # e reportado no RETORNO, depois de reparar tudo que não depende dela.
  local deps_rc=0
  local gardener_rc=0
  setup_deps || deps_rc=10
  setup_local_script_permissions
  merge_claude_md
  merge_agents_md
  render_codex_md
  ensure_project_bootstrap_files
  setup_hooks
  setup_search_tools
  setup_global_vault
  setup_obsidian_mcp
  setup_codex
  setup_codex_mcps
  setup_gstack
  setup_global_skills
  setup_skill_gardener || gardener_rc=20

  mkdir -p ".agents/tmp"
  if [ ! -f ".agents/tmp/.gitkeep" ]; then
    echo "# Temporary files — gitignored" > ".agents/tmp/.gitkeep"
  fi
  ensure_bootstrap_context_package
  if [ -f ".gitignore" ] && ! grep -q ".agents/tmp/" ".gitignore" 2>/dev/null; then
    echo ".agents/tmp/" >> ".gitignore"
  fi
  if [ "$deps_rc" -ne 0 ] && [ "$gardener_rc" -ne 0 ]; then return 30; fi
  if [ "$deps_rc" -ne 0 ]; then return 10; fi
  if [ "$gardener_rc" -ne 0 ]; then return 20; fi
  return 0
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
    "skill-gardener"
    # Canuto originals
    "ask-canuto"
    "co-plan"
    "office-hours"
    "investigate"
    "document-release"
    "retro"
    "auto-analysis"
    "vault-maintenance"
    "vault-sync"
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
    if [ -f "$remote" ]; then
      mkdir -p "$(dirname "$dst")"
      cp "$remote" "$dst" \
        && ok "/$skill" \
        || warn "Could not copy local skill $remote"
    else
      download "$remote" "$dst" \
        && ok "/$skill" \
        || warn "Could not download $remote"
    fi
  done
}

# ── setup_skill_gardener ────────────────────────────────────────────────────
skill_gardener_sha256_file() {
  node - "$1" <<'NODE'
const crypto = require('node:crypto');
const fs = require('node:fs');
process.stdout.write(crypto.createHash('sha256').update(fs.readFileSync(process.argv[2])).digest('hex'));
NODE
}

# Hash helper for bootstrap/check mode. Unlike Skill Gardener verification,
# this path must work before Node dependencies have been repaired.
sha256_file() {
  local file="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$file" | awk '{print $NF}'
  elif command -v node >/dev/null 2>&1; then
    skill_gardener_sha256_file "$file"
  else
    return 1
  fi
}

verify_skill_gardener_release() {
  local release_dir="$1"
  local expected_cli_hash="${2:-}"
  local expected_lib_hash="${3:-}"
  local cli_file="$release_dir/canuto-skill-gardener.js"
  local lib_file="$release_dir/canuto-skill-gardener-lib.js"
  [ -d "$release_dir" ] || return 1
  [ ! -L "$release_dir" ] || return 1
  [ -f "$cli_file" ] && [ -s "$cli_file" ] || return 1
  [ -f "$lib_file" ] && [ -s "$lib_file" ] || return 1
  if [ -n "$expected_cli_hash" ] && [ "$(skill_gardener_sha256_file "$cli_file")" != "$expected_cli_hash" ]; then return 1; fi
  if [ -n "$expected_lib_hash" ] && [ "$(skill_gardener_sha256_file "$lib_file")" != "$expected_lib_hash" ]; then return 1; fi
  if ! node --check "$cli_file" >/dev/null 2>&1; then return 1; fi
  if ! node --check "$lib_file" >/dev/null 2>&1; then return 1; fi
  if ! node - "$cli_file" "$lib_file" <<'NODE'
const fs = require('node:fs');
for (const [index, file] of process.argv.slice(2).entries()) {
  const stat = fs.lstatSync(file);
  if (!stat.isFile() || (index === 0 && (stat.mode & 0o111) === 0)) process.exit(1);
}
NODE
  then return 1; fi
  return 0
}

validate_skill_gardener_config() {
  local library_file="$1"
  local config_file="$2"
  node - "$library_file" "$config_file" <<'NODE'
const path = require('node:path');
const library = require(path.resolve(process.argv[2]));
library.loadConfig(path.resolve(process.argv[3]));
NODE
}

acquire_skill_gardener_materialize_lock() {
  local requested="$1"
  local nonce="${2:-${SKILL_GARDENER_LOCK_NONCE:-}}"
  local lock_path="$requested"
  if [ "$(basename "$requested")" != ".materialize.lock" ]; then lock_path="$requested/.materialize.lock"; fi
  [ -n "$nonce" ] || return 1
  mkdir -p "$(dirname "$lock_path")"
  if ! mkdir "$lock_path" 2>/dev/null; then return 1; fi
  if ! printf '%s\n' "{\"nonce\":\"$nonce\",\"pid\":${BASHPID:-$$},\"command\":\"${BASH_SOURCE[1]:-$0}\",\"startedAt\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > "$lock_path/owner.json"; then
    rmdir "$lock_path" 2>/dev/null || true
    return 1
  fi
  SKILL_GARDENER_LOCK_PATH="$lock_path"
  SKILL_GARDENER_LOCK_NONCE="$nonce"
  return 0
}

release_skill_gardener_materialize_lock() {
  local requested="${1:-${SKILL_GARDENER_LOCK_PATH:-}}"
  local nonce="${2:-${SKILL_GARDENER_LOCK_NONCE:-}}"
  local lock_path="$requested"
  if [ -n "$requested" ] && [ "$(basename "$requested")" != ".materialize.lock" ]; then lock_path="$requested/.materialize.lock"; fi
  local owner="$lock_path/owner.json"
  [ -n "$lock_path" ] && [ -n "$nonce" ] || return 1
  local owner_nonce
  if ! owner_nonce=$(node - "$owner" <<'NODE'
const fs = require('node:fs');
try {
  const owner = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
  if (!owner || typeof owner.nonce !== 'string') process.exit(1);
  process.stdout.write(owner.nonce);
} catch {
  process.exit(1);
}
NODE
  ); then return 1; fi
  [ "$owner_nonce" = "$nonce" ] || return 1
  rm -f "$owner" || return 1
  rmdir "$lock_path" || return 1
  return 0
}

skill_gardener_install_config_if_absent() {
  local candidate="$1"
  local destination="$2"
  local install_rc=0
  node - "$candidate" "$destination" <<'NODE' || install_rc=$?
const fs = require('node:fs');
const source = process.argv[2];
const destination = process.argv[3];
try {
  fs.linkSync(source, destination);
  fs.unlinkSync(source);
  process.exit(0);
} catch (error) {
  try { fs.unlinkSync(source); } catch {}
  process.exit(error && error.code === 'EEXIST' ? 2 : 1);
}
NODE
  return "$install_rc"
}

skill_gardener_migrate_legacy_config() {
  local library_file="$1"
  local config_file="$2"
  local candidate_file="$3"

  # A config efetiva é propriedade da máquina. O instalador valida, mas não
  # reescreve uma configuração válida — nem mesmo quando reconhece um shape
  # antigo. Correções de topologia pertencem ao onboarding/local config, não
  # ao genótipo distribuível do framework (ADR-0003).
  rm -f -- "$candidate_file" 2>/dev/null || true
  validate_skill_gardener_config "$library_file" "$config_file"
}

setup_skill_gardener() {
  local source_dir="${CANUTO_SKILL_GARDENER_SOURCE_DIR:-skill-gardener}"
  local cli_source="$source_dir/canuto-skill-gardener.js"
  local lib_source="$source_dir/canuto-skill-gardener-lib.js"
  local config_src="${CANUTO_SKILL_GARDENER_CONFIG_SOURCE:-config/skill-gardener.json}"
  local staging_dir="$TMP_DIR/skill-gardener"
  local bin_dir="$HOME/.canuto/bin"
  local lib_dir="$HOME/.canuto/lib/skill-gardener"
  local releases_dir="$lib_dir/releases"
  local config_dir="$HOME/.canuto/config"
  local cli_dst="$bin_dir/canuto-skill-gardener"
  local config_dst="$config_dir/skill-gardener.json"
  local nonce="skill-gardener-$(date +%s)-$$-${RANDOM}"
  local staged_cli="$staging_dir/canuto-skill-gardener.js"
  local staged_lib="$staging_dir/canuto-skill-gardener-lib.js"
  local staged_config="$staging_dir/skill-gardener.json"
  local release_tmp="$releases_dir/.tmp-$nonce"
  local release_dir=""
  local link_tmp="$bin_dir/.canuto-skill-gardener-$nonce"
  local migration_tmp="$config_dst.tmp-migrate-$nonce"
  local config_created=0
  local config_created_hash=""
  local lock_acquired=0
  local config_present_initial=0
  local cli_hash=""
  local lib_hash=""
  local digest=""
  local config_validated_hash=""
  local config_source_hash=""

  mkdir -p "$staging_dir" "$bin_dir" "$releases_dir" "$config_dir" "$HOME/.canuto/logs" || { warn "Could not prepare Skill Gardener staging."; return 1; }
  if [ -f "$cli_source" ]; then
    cp "$cli_source" "$staged_cli" || { warn "Could not stage Skill Gardener CLI."; return 1; }
  else
    download "skill-gardener/canuto-skill-gardener.js" "$staged_cli" || { warn "Skill gardener CLI source unavailable."; return 1; }
  fi
  if [ -f "$lib_source" ]; then
    cp "$lib_source" "$staged_lib" || { warn "Could not stage Skill Gardener library."; return 1; }
  else
    download "skill-gardener/canuto-skill-gardener-lib.js" "$staged_lib" || { warn "Skill gardener library source unavailable."; return 1; }
  fi
  if [ -f "$config_src" ]; then
    cp "$config_src" "$staged_config" || { warn "Could not stage Skill Gardener config."; return 1; }
  elif ! download "config/skill-gardener.json" "$staged_config"; then
    rm -f "$staged_config" 2>/dev/null || true
  fi

  if [ ! -f "$staged_cli" ] || [ ! -s "$staged_cli" ] || [ ! -f "$staged_lib" ] || [ ! -s "$staged_lib" ]; then
    warn "Skill Gardener release files are missing or empty."
    return 1
  fi
  if ! node --check "$staged_cli" >/dev/null 2>&1 || ! node --check "$staged_lib" >/dev/null 2>&1; then
    warn "Skill Gardener release contains invalid JavaScript."
    return 1
  fi
  if [ -e "$config_dst" ]; then config_present_initial=1; fi
  if [ "$config_present_initial" -eq 0 ] && [ -f "$staged_config" ] && ! validate_skill_gardener_config "$staged_lib" "$staged_config" >/dev/null 2>&1; then
    warn "Skill Gardener config candidate is invalid."
    return 1
  fi
  if ! node "$staged_cli" --help >/dev/null 2>&1; then
    warn "Staged Skill Gardener CLI help failed."
    return 1
  fi

  cli_hash=$(skill_gardener_sha256_file "$staged_cli") || { warn "Could not hash Skill Gardener CLI."; return 1; }
  lib_hash=$(skill_gardener_sha256_file "$staged_lib") || { warn "Could not hash Skill Gardener library."; return 1; }
  digest=$(node - "$cli_hash" "$lib_hash" <<'NODE'
const crypto = require('node:crypto');
const payload = `canuto-skill-gardener-release-v1\0${process.argv[2]}\0${process.argv[3]}`;
process.stdout.write(crypto.createHash('sha256').update(payload).digest('hex'));
NODE
  ) || { warn "Could not derive Skill Gardener release digest."; return 1; }
  release_dir="$releases_dir/$digest"
  if ! mkdir "$release_tmp" 2>/dev/null; then warn "Could not create immutable Skill Gardener release staging."; return 1; fi
  if ! cp "$staged_cli" "$release_tmp/canuto-skill-gardener.js" || ! cp "$staged_lib" "$release_tmp/canuto-skill-gardener-lib.js" || ! chmod 0755 "$release_tmp/canuto-skill-gardener.js"; then
    rm -rf "$release_tmp"
    warn "Could not materialize Skill Gardener release files."
    return 1
  fi
  if ! verify_skill_gardener_release "$release_tmp" "$cli_hash" "$lib_hash"; then
    rm -rf "$release_tmp"
    warn "Staged Skill Gardener release failed verification."
    return 1
  fi

  if ! acquire_skill_gardener_materialize_lock "$releases_dir" "$nonce"; then
    rm -rf "$release_tmp"
    warn "Skill Gardener materialization is already locked."
    return 1
  fi
  lock_acquired=1

  if [ -e "$config_dst" ]; then
    if ! validate_skill_gardener_config "$staged_lib" "$config_dst" >/dev/null 2>&1; then
      warn "Existing Skill Gardener config is invalid; preserving it and aborting activation."
      rm -f -- "$migration_tmp"
      rm -rf "$release_tmp"
      release_skill_gardener_materialize_lock "$releases_dir" "$nonce" >/dev/null 2>&1 || true
      return 1
    fi
    config_source_hash=$(skill_gardener_sha256_file "$config_dst") || {
      warn "Could not hash the existing Skill Gardener config."
      rm -f -- "$migration_tmp"
      rm -rf "$release_tmp"
      release_skill_gardener_materialize_lock "$releases_dir" "$nonce" >/dev/null 2>&1 || true
      return 1
    }
    if ! skill_gardener_migrate_legacy_config "$staged_lib" "$config_dst" "$migration_tmp"; then
      warn "Legacy Skill Gardener config migration failed; preserving the existing runtime."
      rm -f -- "$migration_tmp"
      rm -rf "$release_tmp"
      release_skill_gardener_materialize_lock "$releases_dir" "$nonce" >/dev/null 2>&1 || true
      return 1
    fi
    if [ -f "$migration_tmp" ] && ! validate_skill_gardener_config "$staged_lib" "$migration_tmp" >/dev/null 2>&1; then
      warn "Migrated Skill Gardener config candidate is invalid; preserving the existing runtime."
      rm -f -- "$migration_tmp"
      rm -rf "$release_tmp"
      release_skill_gardener_materialize_lock "$releases_dir" "$nonce" >/dev/null 2>&1 || true
      return 1
    fi
    if [ "$(skill_gardener_sha256_file "$config_dst")" != "$config_source_hash" ]; then
      warn "Skill Gardener config changed during migration staging; preserving the existing runtime."
      rm -f -- "$migration_tmp"
      rm -rf "$release_tmp"
      release_skill_gardener_materialize_lock "$releases_dir" "$nonce" >/dev/null 2>&1 || true
      return 1
    fi
  else
    if [ ! -f "$staged_config" ] || [ ! -s "$staged_config" ]; then
      warn "Skill Gardener config is unavailable."
      rm -f -- "$migration_tmp"
      rm -rf "$release_tmp"
      release_skill_gardener_materialize_lock "$releases_dir" "$nonce" >/dev/null 2>&1 || true
      return 1
    fi
    local config_tmp="$config_dst.tmp-$nonce"
    if ! cp "$staged_config" "$config_tmp"; then
      rm -f "$config_tmp" 2>/dev/null || true
      rm -f -- "$migration_tmp"
      rm -rf "$release_tmp"
      release_skill_gardener_materialize_lock "$releases_dir" "$nonce" >/dev/null 2>&1 || true
      return 1
    fi
    local config_rc=0
    skill_gardener_install_config_if_absent "$config_tmp" "$config_dst" || config_rc=$?
    if [ "$config_rc" -eq 0 ]; then
      config_created=1
      config_created_hash=$(skill_gardener_sha256_file "$config_dst")
    elif [ "$config_rc" -eq 2 ]; then
      if ! validate_skill_gardener_config "$staged_lib" "$config_dst" >/dev/null 2>&1; then
        warn "Concurrent Skill Gardener config winner is invalid; aborting activation."
        rm -f -- "$migration_tmp"
        rm -rf "$release_tmp"
        release_skill_gardener_materialize_lock "$releases_dir" "$nonce" >/dev/null 2>&1 || true
        return 1
      fi
    else
      warn "Could not install Skill Gardener config atomically."
      rm -f -- "$migration_tmp"
      rm -rf "$release_tmp"
      release_skill_gardener_materialize_lock "$releases_dir" "$nonce" >/dev/null 2>&1 || true
      return 1
    fi
  fi
  if ! validate_skill_gardener_config "$staged_lib" "$config_dst" >/dev/null 2>&1; then
    warn "Skill Gardener config is invalid after materialization; preserving it and aborting activation."
    if [ "$config_created" -eq 1 ] && [ "$(skill_gardener_sha256_file "$config_dst")" = "$config_created_hash" ]; then rm -f "$config_dst"; fi
    rm -f -- "$migration_tmp"
    rm -rf "$release_tmp"
    release_skill_gardener_materialize_lock "$releases_dir" "$nonce" >/dev/null 2>&1 || true
    return 1
  fi
  config_validated_hash=$(skill_gardener_sha256_file "$config_dst") || {
    warn "Could not hash the validated Skill Gardener config."
    if [ "$config_created" -eq 1 ] && [ "$(skill_gardener_sha256_file "$config_dst")" = "$config_created_hash" ]; then rm -f "$config_dst"; fi
    rm -f -- "$migration_tmp"
    rm -rf "$release_tmp"
    release_skill_gardener_materialize_lock "$releases_dir" "$nonce" >/dev/null 2>&1 || true
    return 1
  }

  if [ -e "$release_dir" ]; then
    if ! verify_skill_gardener_release "$release_dir" "$cli_hash" "$lib_hash"; then
      warn "Existing immutable Skill Gardener release failed verification."
      if [ "$config_created" -eq 1 ] && [ "$(skill_gardener_sha256_file "$config_dst")" = "$config_created_hash" ]; then rm -f "$config_dst"; fi
      rm -f -- "$migration_tmp"
      rm -rf "$release_tmp"
      release_skill_gardener_materialize_lock "$releases_dir" "$nonce" >/dev/null 2>&1 || true
      return 1
    fi
    rm -rf "$release_tmp"
  else
    if ! node - "$release_tmp" "$release_dir" <<'NODE'
const fs = require('node:fs');
fs.renameSync(process.argv[2], process.argv[3]);
NODE
    then
      warn "Could not atomically materialize immutable Skill Gardener release."
      if [ "$config_created" -eq 1 ] && [ "$(skill_gardener_sha256_file "$config_dst")" = "$config_created_hash" ]; then rm -f "$config_dst"; fi
      rm -f -- "$migration_tmp"
      rm -rf "$release_tmp"
      release_skill_gardener_materialize_lock "$releases_dir" "$nonce" >/dev/null 2>&1 || true
      return 1
    fi
  fi
  if ! verify_skill_gardener_release "$release_dir" "$cli_hash" "$lib_hash"; then
    warn "Final Skill Gardener release failed verification."
    if [ "$config_created" -eq 1 ] && [ "$(skill_gardener_sha256_file "$config_dst")" = "$config_created_hash" ]; then rm -f "$config_dst"; fi
    rm -f -- "$migration_tmp"
    release_skill_gardener_materialize_lock "$releases_dir" "$nonce" >/dev/null 2>&1 || true
    return 1
  fi
  rm -f "$link_tmp"
  if ! ln -s "../lib/skill-gardener/releases/$digest/canuto-skill-gardener.js" "$link_tmp"; then
    warn "Could not prepare Skill Gardener activation link."
    if [ "$config_created" -eq 1 ] && [ "$(skill_gardener_sha256_file "$config_dst")" = "$config_created_hash" ]; then rm -f "$config_dst"; fi
    rm -f -- "$migration_tmp"
    release_skill_gardener_materialize_lock "$releases_dir" "$nonce" >/dev/null 2>&1 || true
    return 1
  fi
  if [ "${CANUTO_SKILL_GARDENER_TEST_SWAP_CONFIG_BEFORE_ACTIVATION:-0}" = "1" ]; then
    printf '%s\n' '{"schemaVersion":2}' > "$config_dst"
  fi
  if [ ! -f "$config_dst" ] || ! validate_skill_gardener_config "$staged_lib" "$config_dst" >/dev/null 2>&1 || [ "$(skill_gardener_sha256_file "$config_dst")" != "$config_validated_hash" ]; then
    warn "Skill Gardener config changed before activation; preserving the old runtime."
    rm -f "$link_tmp"
    if [ "$config_created" -eq 1 ] && [ "$(skill_gardener_sha256_file "$config_dst")" = "$config_created_hash" ]; then rm -f "$config_dst"; fi
    rm -f -- "$migration_tmp"
    rm -rf "$release_tmp"
    release_skill_gardener_materialize_lock "$releases_dir" "$nonce" >/dev/null 2>&1 || true
    return 1
  fi
  if [ "${CANUTO_SKILL_GARDENER_TEST_FAIL_ACTIVATION:-0}" = "1" ] || ! node - "$link_tmp" "$cli_dst" <<'NODE'
const fs = require('node:fs');
fs.renameSync(process.argv[2], process.argv[3]);
NODE
  then
    warn "Could not atomically activate Skill Gardener CLI."
    rm -f "$link_tmp"
    if [ "$config_created" -eq 1 ] && [ "$(skill_gardener_sha256_file "$config_dst")" = "$config_created_hash" ]; then rm -f "$config_dst"; fi
    rm -f -- "$migration_tmp"
    release_skill_gardener_materialize_lock "$releases_dir" "$nonce" >/dev/null 2>&1 || true
    return 1
  fi
  if [ -f "$migration_tmp" ]; then
    if ! node - "$migration_tmp" "$config_dst" "$config_validated_hash" <<'NODE'
const fs = require('node:fs');
const crypto = require('node:crypto');
const candidate = process.argv[2];
const destination = process.argv[3];
const expectedHash = process.argv[4];
const currentHash = crypto.createHash('sha256').update(fs.readFileSync(destination)).digest('hex');
if (currentHash !== expectedHash) process.exit(2);
fs.renameSync(candidate, destination);
NODE
    then
      warn "Could not atomically publish migrated Skill Gardener config; the new runtime remains active with the original config."
      rm -f -- "$migration_tmp"
      release_skill_gardener_materialize_lock "$releases_dir" "$nonce" >/dev/null 2>&1 || true
      return 1
    fi
  fi
  if ! release_skill_gardener_materialize_lock "$releases_dir" "$nonce" >/dev/null 2>&1; then
    warn "Skill Gardener materialization lock cleanup failed after activation; the active release is usable, but lock cleanup requires review."
    return 1
  fi
  lock_acquired=0
  ok "Installed immutable Skill Gardener release: $cli_dst"
  return 0
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

# Test-only library seam: source installer helpers without entering an install
# mode. It performs no setup and is used by framework smoke tests.
if [ "${CANUTO_INSTALL_LIBRARY_ONLY:-0}" = "1" ]; then
  return 0 2>/dev/null || exit 0
fi

# ── CONTRACT ONLY ───────────────────────────────────────────────────────────
# Deliberately narrower than --update: product-owned hooks, personas, skills,
# models, gates and installers remain untouched. This is the safe rollout path
# for repositories whose local framework contains domain-specific wiring.
if [ "$MODE" = "contract" ]; then
  echo ""
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${CYAN}  Canuto Framework — Shared Contract Only${RESET}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo ""

  if ! update_tree_is_clean; then
    error "Refusing --contract-only in a dirty worktree. Preserve WIP and retry from a clean isolated worktree."
  fi

  download ".agents/OPERATING-CONTRACT.md" ".agents/OPERATING-CONTRACT.md" \
    || error "Could not download the shared operating contract."
  ensure_shared_operating_contract_reference "$CLAUDE_MD"
  ensure_shared_operating_contract_reference "AGENTS.md"

  if [ "$GIT_AVAILABLE" = true ]; then
    # Some consumers intentionally ignore `.agents/*` or Markdown entrypoints.
    # Force-add exactly the three contract paths; never force-add a directory or
    # any runtime/product implementation file.
    git add -f ".agents/OPERATING-CONTRACT.md" "$CLAUDE_MD" "AGENTS.md"
    git ls-files --error-unmatch \
      ".agents/OPERATING-CONTRACT.md" "$CLAUDE_MD" "AGENTS.md" >/dev/null 2>&1 \
      || error "Shared contract files were written but are not all tracked by Git."

    if confirm_yes "Commit shared operating contract? [Y/n] " "Y"; then
      if git diff --cached --quiet; then
        log "Nothing to commit — shared operating contract already synchronized."
      elif git commit -m "docs: sync shared Canuto operating contract"; then
        ok "Committed shared operating contract."
      else
        error "Git commit failed; contract files remain staged for inspection."
      fi
    else
      warn "Contract files are staged but not committed."
    fi
  fi

  local_contract_hash=$(sha256_file ".agents/OPERATING-CONTRACT.md" 2>/dev/null || true)
  [ -n "$local_contract_hash" ] || error "Could not calculate the shared contract hash."
  ok "Shared contract active in Claude and Codex (sha256: ${local_contract_hash:0:12})."
  echo ""
  exit 0
fi

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
  UNKNOWN=0

  for file in "${FRAMEWORK_FILES[@]}"; do
    if [ ! -f "$file" ]; then
      echo -e "  ${RED}\u2717 MISSING${RESET}    $file"
      MISSING=$((MISSING + 1))
    elif [ "$file" = ".agents/VERSION" ]; then
      # O carimbo \u00c9 a vers\u00e3o (conte\u00fado cru, sem frontmatter) \u2014 o grep
      # "^version:" abaixo o rotularia UNKNOWN em todo --check.
      LOCAL_VER=$(head -1 "$file" 2>/dev/null | tr -d '[:space:]' || true)
      REMOTE_VER=$(fetch_content "$file" | head -1 | tr -d '[:space:]' || true)
      if [ -z "$LOCAL_VER" ] || [ -z "$REMOTE_VER" ]; then
        # Mesmo contrato do bra\u00e7o gen\u00e9rico: sem os DOIS lados (offline, 404),
        # \u00e9 UNKNOWN \u2014 nunca um OUTDATED fantasma.
        echo -e "  ${YELLOW}? UNKNOWN${RESET}    $file (version unavailable)"
        UNKNOWN=$((UNKNOWN + 1))
      elif [ "$LOCAL_VER" = "$REMOTE_VER" ]; then
        echo -e "  ${GREEN}\u2713 OK${RESET}        $file (v$LOCAL_VER)"
        UP_TO_DATE=$((UP_TO_DATE + 1))
      else
        echo -e "  ${YELLOW}\u26a0 OUTDATED${RESET}   $file (local: v$LOCAL_VER \u2192 remote: v$REMOTE_VER)"
        OUTDATED=$((OUTDATED + 1))
      fi
    elif [ "$file" = ".agents/OPERATING-CONTRACT.md" ]; then
      contract_remote=$(mktemp)
      if fetch_content "$file" > "$contract_remote" 2>/dev/null && [ -s "$contract_remote" ]; then
        LOCAL_HASH=$(sha256_file "$file" 2>/dev/null || true)
        REMOTE_HASH=$(sha256_file "$contract_remote" 2>/dev/null || true)
        if [ -z "$LOCAL_HASH" ] || [ -z "$REMOTE_HASH" ]; then
          echo -e "  ${YELLOW}? UNKNOWN${RESET}    $file (sha256 unavailable)"
          UNKNOWN=$((UNKNOWN + 1))
        elif [ "$LOCAL_HASH" = "$REMOTE_HASH" ]; then
          echo -e "  ${GREEN}✓ OK${RESET}        $file (sha256: ${LOCAL_HASH:0:12})"
          UP_TO_DATE=$((UP_TO_DATE + 1))
        else
          echo -e "  ${YELLOW}⚠ OUTDATED${RESET}   $file (content hash drift)"
          OUTDATED=$((OUTDATED + 1))
        fi
      else
        echo -e "  ${YELLOW}? UNKNOWN${RESET}    $file (remote content unavailable)"
        UNKNOWN=$((UNKNOWN + 1))
      fi
      rm -f "$contract_remote"
    else
      generic_remote=$(mktemp)
      if fetch_content "$file" > "$generic_remote" 2>/dev/null && [ -s "$generic_remote" ]; then
        LOCAL_VER=$(grep "^version:" "$file" 2>/dev/null | head -1 | awk '{print $2}' || true)
        REMOTE_VER=$(grep "^version:" "$generic_remote" 2>/dev/null | head -1 | awk '{print $2}' || true)
        if [ -n "$LOCAL_VER" ] && [ -n "$REMOTE_VER" ]; then
          if [ "$LOCAL_VER" = "$REMOTE_VER" ]; then
            echo -e "  ${GREEN}\u2713 OK${RESET}        $file (v$LOCAL_VER)"
            UP_TO_DATE=$((UP_TO_DATE + 1))
          else
            echo -e "  ${YELLOW}\u26a0 OUTDATED${RESET}   $file (local: v$LOCAL_VER \u2192 remote: v$REMOTE_VER)"
            OUTDATED=$((OUTDATED + 1))
          fi
        elif [ -z "$LOCAL_VER" ] && [ -z "$REMOTE_VER" ]; then
          LOCAL_HASH=$(sha256_file "$file" 2>/dev/null || true)
          REMOTE_HASH=$(sha256_file "$generic_remote" 2>/dev/null || true)
          if [ -z "$LOCAL_HASH" ] || [ -z "$REMOTE_HASH" ]; then
            echo -e "  ${YELLOW}? UNKNOWN${RESET}    $file (sha256 unavailable)"
            UNKNOWN=$((UNKNOWN + 1))
          elif [ "$LOCAL_HASH" = "$REMOTE_HASH" ]; then
            echo -e "  ${GREEN}\u2713 OK${RESET}        $file (sha256: ${LOCAL_HASH:0:12})"
            UP_TO_DATE=$((UP_TO_DATE + 1))
          else
            echo -e "  ${YELLOW}\u26a0 OUTDATED${RESET}   $file (content hash drift)"
            OUTDATED=$((OUTDATED + 1))
          fi
        else
          echo -e "  ${YELLOW}? UNKNOWN${RESET}    $file (version metadata differs)"
          UNKNOWN=$((UNKNOWN + 1))
        fi
      else
        echo -e "  ${YELLOW}? UNKNOWN${RESET}    $file (remote content unavailable)"
        UNKNOWN=$((UNKNOWN + 1))
      fi
      rm -f "$generic_remote"
    fi
  done

  echo ""
  echo -e "  Summary: ${GREEN}${UP_TO_DATE} up-to-date${RESET}  ${YELLOW}${OUTDATED} outdated${RESET}  ${RED}${MISSING} missing${RESET}  ${YELLOW}${UNKNOWN} unknown${RESET}"
  echo ""

  CHECK_RC=0
  check_result_code "$OUTDATED" "$MISSING" "$UNKNOWN" || CHECK_RC=$?
  if [ "$CHECK_RC" -eq 2 ]; then
    warn "Version check is incomplete; UNKNOWN is never a green result."
  elif [ "$CHECK_RC" -eq 1 ]; then
    log "Run 'bash install.sh --update' to update outdated/missing files."
  else
    ok "All framework files are up to date."
  fi
  echo ""
  rm -rf "$TMP_DIR"
  exit "$CHECK_RC"
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
    skill_files=()
    while IFS= read -r skill_file; do
      [ -n "$skill_file" ] || continue
      skill_files+=("$skill_file")
    done < <(skill_remote_files "$skill_name")
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

# ── DEPS ONLY ───────────────────────────────────────────────────────────────
if [ "$MODE" = "deps" ]; then
  if setup_deps; then
    rm -rf "$TMP_DIR"
    exit 0
  fi
  rm -rf "$TMP_DIR"
  exit 1
fi

# ── REPAIR ──────────────────────────────────────────────────────────────────
if [ "$MODE" = "repair" ]; then
  echo ""
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo -e "${CYAN}  Canuto Framework — Repair${RESET}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo ""

  REPAIR_RC=0
  repair_runtime || REPAIR_RC=$?
  handle_repair_outcome repair "$REPAIR_RC" 0 || REPAIR_OUTCOME_RC=$?
  REPAIR_OUTCOME_RC="${REPAIR_OUTCOME_RC:-0}"

  rm -rf "$TMP_DIR"
  exit "$REPAIR_OUTCOME_RC"
fi

# ── DOCTOR ──────────────────────────────────────────────────────────────────
if [ "$MODE" = "doctor" ]; then
  REPAIR_RC=0
  repair_runtime || REPAIR_RC=$?
  VALIDATION_RC=0
  run_install_validation || VALIDATION_RC=$?
  DOCTOR_OUTCOME_RC=0
  handle_repair_outcome doctor "$REPAIR_RC" "$VALIDATION_RC" || DOCTOR_OUTCOME_RC=$?
  rm -rf "$TMP_DIR"
  exit "$DOCTOR_OUTCOME_RC"
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
  MIGRATE_REPAIR_RC=0
  repair_runtime || MIGRATE_REPAIR_RC=$?
  MIGRATE_OUTCOME_RC=0
  handle_repair_outcome migrate "$MIGRATE_REPAIR_RC" 0 || MIGRATE_OUTCOME_RC=$?
  if [ "$MIGRATE_OUTCOME_RC" -ne 0 ]; then
    rm -rf "$TMP_DIR"
    exit "$MIGRATE_OUTCOME_RC"
  fi

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
    git add "$AGENTS_DIR/" "$CLAUDE_MD" "AGENTS.md" "CODEX.md" ".context.md" "docs/" 2>/dev/null || true
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

  INSTALL_REPAIR_RC=0
  repair_runtime || INSTALL_REPAIR_RC=$?
  INSTALL_OUTCOME_RC=0
  handle_repair_outcome install "$INSTALL_REPAIR_RC" 0 || INSTALL_OUTCOME_RC=$?
  if [ "$INSTALL_OUTCOME_RC" -ne 0 ]; then
    exit "$INSTALL_OUTCOME_RC"
  fi
  register_project_path

  if [ "$GIT_AVAILABLE" = true ]; then
    echo ""
    log "Staging files for git..."
    # Um path POR VEZ: `git add` com vários pathspecs é tudo-ou-nada — um
    # único ausente (.context.md só existe com aprovação) fazia o comando
    # inteiro falhar em silêncio e NADA era stageado; o commit em seguida
    # falhava e o update saía não-zero com os arquivos na verdade aplicados.
    # (install.sh e .claude/agents/ entram no add: estão em FRAMEWORK_FILES e
    # ficavam untracked/modified para sempre no consumidor.)
    for add_path in "$AGENTS_DIR" "$CLAUDE_MD" "AGENTS.md" ".context.md" "docs" "CODEX.md" "install.sh" ".claude/agents"; do
      [ -e "$add_path" ] && git add "$add_path" 2>/dev/null || true
    done
    echo ""
    if confirm_yes "Commit now? [Y/n] " "Y"; then
      # Versão real do carimbo recém-baixado — "v1.6" hardcoded aqui nascia
      # defasado no mesmo release que criou .agents/VERSION para evitar isso.
      INSTALL_FW_VER=$(head -1 "$AGENTS_DIR/VERSION" 2>/dev/null | tr -d '[:space:]')
      [ -n "$INSTALL_FW_VER" ] || INSTALL_FW_VER="?"
      git commit -m "chore: add Canuto Framework v$INSTALL_FW_VER" \
        && ok "Committed!" \
        || warn "Nada para commitar."
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

  echo -e "${GREEN}  Done! v${INSTALL_FW_VER:-?} installed.${RESET}"
  echo -e "${GREEN}  Claude keeps Opus as Maestro by default.${RESET}"
  echo -e "${GREEN}  For direct Codex Maestro mode: bash .agents/tools/codex-maestro.sh${RESET}"
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
  if ! update_tree_is_clean; then
    error "Refusing --update in a dirty worktree. Preserve WIP and retry from a clean isolated worktree."
  fi
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

  # No modo update, dependência ausente não pode abortar o fluxo inteiro
  # (set -e + return 1 do setup_deps matava merge de CLAUDE.md, registro de
  # hooks e validação — atualização pela metade sem aviso). Falha dura de
  # ambiente continua sendo papel do --doctor.
  UPDATE_REPAIR_RC=0
  repair_runtime || UPDATE_REPAIR_RC=$?
  UPDATE_OUTCOME_RC=0
  handle_repair_outcome update "$UPDATE_REPAIR_RC" 0 || UPDATE_OUTCOME_RC=$?
  if [ "$UPDATE_OUTCOME_RC" -ne 0 ]; then
    exit "$UPDATE_OUTCOME_RC"
  fi
  register_project_path

  # Versão recém-baixada em .agents/VERSION — mensagens de commit e de saída
  # deixam de carregar "v1.6" hardcoded (estava defasado desde que a lista
  # passou de 1.6; versão escrita em string vira mentira no release seguinte).
  FW_VER=$(head -1 "$AGENTS_DIR/VERSION" 2>/dev/null | tr -d '[:space:]')
  [ -n "$FW_VER" ] || FW_VER="?"

  if [ "$GIT_AVAILABLE" = true ]; then
    echo ""
    log "Staging updated files..."
    # Um path POR VEZ: `git add` com vários pathspecs é tudo-ou-nada — um
    # único ausente (.context.md só existe com aprovação) fazia o comando
    # inteiro falhar em silêncio e NADA era stageado; o commit em seguida
    # falhava e o update saía não-zero com os arquivos na verdade aplicados.
    # (install.sh e .claude/agents/ entram no add: estão em FRAMEWORK_FILES e
    # ficavam untracked/modified para sempre no consumidor.)
    for add_path in "$AGENTS_DIR" "$CLAUDE_MD" "AGENTS.md" ".context.md" "docs" "CODEX.md" "install.sh" ".claude/agents"; do
      [ -e "$add_path" ] && git add "$add_path" 2>/dev/null || true
    done

    # Estado de runtime NUNCA entra no commit do consumidor. `git add .agents/`
    # varre o diretório inteiro e arrastava junto o event log da máquina — que
    # carrega o slug de QUEM gerou o evento. Foi assim que um evento com
    # "project":"canuto-framework-v1" foi parar dentro de um repo de produto:
    # vazamento de identidade exatamente do tipo que o ADR-0003 veta.
    for runtime_path in \
      "$AGENTS_DIR/vault/events" \
      "$AGENTS_DIR/tmp" \
      "$AGENTS_DIR/.cache" \
      "$AGENTS_DIR/memory"; do
      git reset -q -- "$runtime_path" 2>/dev/null || true
    done

    # E ignora daqui para frente, para não reaparecer no próximo `git add -A`
    # que alguém rodar à mão.
    if [ -f ".gitignore" ] && ! grep -q "^\.agents/vault/events/" .gitignore 2>/dev/null; then
      printf '\n# Canuto — estado de runtime por máquina (nunca versionar)\n.agents/vault/events/\n.agents/tmp/\n.agents/.cache/\n' >> .gitignore
      git add .gitignore 2>/dev/null || true
      ok "Runtime do Canuto adicionado ao .gitignore"
    fi
    echo ""
    if confirm_yes "Commit now? [Y/n] " "Y"; then
      # Guardado: sem diff (re-run com --force, ou nada mudou) o commit sai
      # não-zero e, sob set -e, derrubava um update que deu certo.
      git commit -m "chore: update Canuto Framework to v$FW_VER" \
        && ok "Committed!" \
        || warn "Nada novo para commitar (arquivos já em dia)."
    else
      warn "Files staged but not committed. Run 'git commit' when ready."
    fi
  fi

  if ! run_install_validation; then
    warn "Post-update validation reported issues. Re-run: bash install.sh --doctor"
  fi

  echo ""
  echo -e "${GREEN}\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501\u2501${RESET}"
  echo -e "${GREEN}  Framework updated to v$FW_VER successfully.${RESET}"
  echo -e "${GREEN}  Claude remains the default Maestro runtime.${RESET}"
  echo -e "${GREEN}  Direct Codex Maestro launcher: bash .agents/tools/codex-maestro.sh${RESET}"
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
