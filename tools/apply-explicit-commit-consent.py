#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one exact match, found {count}")
    return text.replace(old, new, 1)


def sub_once(text: str, pattern: str, replacement: str, label: str, flags: int = 0) -> str:
    # Use a callable replacement so backslashes intended for Bash (for example
    # \u2713 and \033) are copied literally instead of parsed by Python's
    # regex replacement-template grammar.
    result, count = re.subn(pattern, lambda _match: replacement, text, count=1, flags=flags)
    if count != 1:
        raise SystemExit(f"{label}: expected one regex match, found {count}")
    return result


install = read("install.sh")

header_pattern = r"#!/usr/bin/env bash\n# ={10,}\n# Canuto Framework — Installer / Updater\n# Usage:\n.*?# ={10,}\n"
header = """#!/usr/bin/env bash
# =============================================================================
# Canuto Framework — Installer / Updater
#
# Common usage:
#   Fresh install:    bash install.sh [--yes] [--commit]
#   Update:           bash install.sh --update [--yes] [--commit]
#   Contract only:    bash install.sh --contract-only [--yes] [--commit]
#   Install skills:   bash install.sh --skill NAME [--skill NAME] [--commit]
#   Preview:          bash install.sh --dry-run [MODE]
#   Help:             bash install.sh --help
#
# Consent boundary:
#   --yes confirms operational prompts. It NEVER authorizes a Git commit.
#   --commit is the only flag that authorizes staging and committing declared
#   framework paths. The default, and --no-commit, leave changes unstaged.
# =============================================================================
"""
install = sub_once(install, header_pattern, header, "installer usage header", re.S)

bootstrap_pattern = r"set -euo pipefail\n.*?\n(?=emit_repair_warnings\(\) \{)"
bootstrap = r'''set -euo pipefail

REPO_URL="${CANUTO_REPO_URL:-https://raw.githubusercontent.com/csorodrigo/canuto-framework/main}"
SOURCE_DIR="${CANUTO_SOURCE_DIR:-}"
AGENTS_DIR=".agents"
CLAUDE_MD="CLAUDE.md"
TMP_DIR=""
MODE="auto" # auto | install | update | contract | check | skill | migrate | repair | doctor | test | deps
ORIGINAL_ARGS=("$@")
SCRIPT_SOURCE="${BASH_SOURCE[0]:-$0}"
SKILLS_TO_INSTALL=()
JSON_OUTPUT=false
AUTO_YES=false
COMMIT_CHANGES=false
COMMIT_POLICY="default" # default | commit | no-commit
DRY_RUN=false
OBSIDIAN_API_KEY_ARG=""

# ── Colors ─────────────────────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
RESET='\033[0m'

log()    { echo -e "${CYAN}[canuto]${RESET} $1"; }
ok()     { echo -e "${GREEN}[canuto]${RESET} \u2713 $1"; }
warn()   { echo -e "${YELLOW}[canuto]${RESET} \u26a0 $1"; }
error()  { echo -e "${RED}[canuto]${RESET} \u2717 $1" >&2; exit 1; }

print_help() {
  cat <<'HELPEOF'
Canuto Framework installer/updater

Usage:
  bash install.sh [MODE] [OPTIONS]

Modes (choose at most one):
  --update             update an existing Canuto consumer
  --contract-only      synchronize only the shared operating contract
  --check              compare installed framework files with the source
  --test               run consumer validation
  --migrate            migrate a legacy installation
  --repair             repair the local runtime
  --doctor, --health   repair and validate the runtime
  --deps, --deps-only  provision runtime dependencies
  --skill NAME         install one skill; may be repeated

Options:
  --yes                accept operational prompts; never commits
  --commit             explicitly stage and commit declared framework paths
  --no-commit          leave changes unstaged and uncommitted (default)
  --dry-run            report the selected mutating operation without changes
  --api-key VALUE      Obsidian API key used by migration/setup
  --json               machine-readable output where supported
  -h, --help           show this help without modifying the repository

Examples:
  bash install.sh --update --yes
  bash install.sh --update --yes --commit
  bash install.sh --contract-only --commit
  bash install.sh --skill health-check --no-commit
  bash install.sh --dry-run --update
HELPEOF
}

usage_error() {
  echo -e "${RED}[canuto]${RESET} \u2717 $1" >&2
  echo "" >&2
  print_help >&2
  exit 64
}

set_requested_mode() {
  local requested="$1"
  if [ "$MODE" != "auto" ] && [ "$MODE" != "$requested" ]; then
    usage_error "Conflicting modes: --$MODE and --$requested"
  fi
  MODE="$requested"
}

# ── Strict argument parsing ─────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --update) set_requested_mode "update" ;;
    --contract-only) set_requested_mode "contract" ;;
    --check) set_requested_mode "check" ;;
    --test) set_requested_mode "test" ;;
    --migrate) set_requested_mode "migrate" ;;
    --repair) set_requested_mode "repair" ;;
    --deps-only|--deps) set_requested_mode "deps" ;;
    --doctor|--health) set_requested_mode "doctor" ;;
    --json) JSON_OUTPUT=true ;;
    --yes) AUTO_YES=true ;;
    --commit)
      [ "$COMMIT_POLICY" != "no-commit" ] || usage_error "--commit conflicts with --no-commit"
      COMMIT_POLICY="commit"
      COMMIT_CHANGES=true
      ;;
    --no-commit)
      [ "$COMMIT_POLICY" != "commit" ] || usage_error "--no-commit conflicts with --commit"
      COMMIT_POLICY="no-commit"
      COMMIT_CHANGES=false
      ;;
    --dry-run) DRY_RUN=true ;;
    --skill)
      [ $# -ge 2 ] || usage_error "--skill requires a value"
      case "$2" in ""|-*) usage_error "--skill requires a non-option value" ;; esac
      SKILLS_TO_INSTALL+=("$2")
      shift
      ;;
    --api-key)
      [ $# -ge 2 ] || usage_error "--api-key requires a value"
      case "$2" in ""|--*) usage_error "--api-key requires a value" ;; esac
      OBSIDIAN_API_KEY_ARG="$2"
      shift
      ;;
    -h|--help)
      print_help
      exit 0
      ;;
    --)
      shift
      [ $# -eq 0 ] || usage_error "Positional arguments are not supported: $*"
      break
      ;;
    -*) usage_error "Unknown option: $1" ;;
    *) usage_error "Unexpected positional argument: $1" ;;
  esac
  shift
done

if [ "${#SKILLS_TO_INSTALL[@]}" -gt 0 ]; then
  if [ "$MODE" != "auto" ] && [ "$MODE" != "skill" ]; then
    usage_error "--skill cannot be combined with another mode"
  fi
  MODE="skill"
fi

# ── Detect implicit install/update mode ─────────────────────────────────────
if [ "$MODE" = "auto" ]; then
  if [ -d "$AGENTS_DIR" ]; then MODE="update"; else MODE="install"; fi
fi

if [ "$COMMIT_CHANGES" = true ]; then
  case "$MODE" in
    install|update|contract|skill|migrate) ;;
    *) usage_error "--commit is not valid with mode '$MODE'" ;;
  esac
fi

if [ "$DRY_RUN" = true ]; then
  [ "$COMMIT_CHANGES" = false ] || usage_error "--dry-run conflicts with --commit"
  case "$MODE" in
    install|update|contract|skill|migrate)
      echo "Canuto dry-run"
      echo "mode=$MODE"
      echo "commit=false"
      if [ "${#SKILLS_TO_INSTALL[@]}" -gt 0 ]; then
        printf 'skills=%s\n' "$(IFS=,; echo "${SKILLS_TO_INSTALL[*]}")"
      fi
      exit 0
      ;;
    *) usage_error "--dry-run is supported only for install, update, contract, skill, or migrate" ;;
  esac
fi

TMP_DIR=$(mktemp -d) || error "Could not create a temporary directory."

'''
install = sub_once(install, bootstrap_pattern, bootstrap, "installer bootstrap/parser", re.S)

commit_helper_marker = "# Test-only library seam: source installer helpers without entering an install\n"
commit_helper = r'''# Commit only explicitly declared framework paths. Unrelated staged changes are
# ignored by `git commit --only` and remain staged. Without --commit this helper
# does not touch the index at all.
commit_declared_paths() {
  local message="$1"
  shift

  [ "${GIT_AVAILABLE:-false}" = true ] || return 0
  if [ "$COMMIT_CHANGES" != true ]; then
    warn "Changes were applied but left unstaged and uncommitted. Re-run with --commit to authorize a framework commit."
    return 0
  fi

  local requested_paths=("$@")
  local commit_paths=()
  local path=""
  for path in "${requested_paths[@]}"; do
    [ -n "$path" ] || continue
    if [ -e "$path" ] || [ -L "$path" ] || git ls-files --error-unmatch -- "$path" >/dev/null 2>&1; then
      commit_paths+=("$path")
    fi
  done

  if [ "${#commit_paths[@]}" -eq 0 ]; then
    log "No declared framework paths exist or are tracked; nothing to commit."
    return 0
  fi

  for path in "${commit_paths[@]}"; do
    git add -f -A -- "$path" || {
      warn "Could not stage declared framework path: $path"
      return 1
    }
  done

  if git diff --cached --quiet -- "${commit_paths[@]}"; then
    log "Nothing to commit — declared framework paths are already synchronized."
    return 0
  fi

  if git commit --only -m "$message" -- "${commit_paths[@]}"; then
    ok "Committed declared framework paths only."
    return 0
  fi
  warn "Git commit failed; declared framework paths remain staged for inspection."
  return 1
}

'''
if commit_helper_marker not in install:
    raise SystemExit("commit helper insertion marker not found")
install = install.replace(commit_helper_marker, commit_helper + commit_helper_marker, 1)

contract_pattern = r'''  if \[ "\$GIT_AVAILABLE" = true \]; then\n    # Some consumers intentionally ignore.*?\n  fi\n\n  local_contract_hash='''
contract_replacement = r'''  if [ "$GIT_AVAILABLE" = true ]; then
    commit_declared_paths "docs: sync shared Canuto operating contract" \
      ".agents/OPERATING-CONTRACT.md" "$CLAUDE_MD" "AGENTS.md" \
      || error "Shared contract commit failed; inspect the staged paths."
  fi

  local_contract_hash='''
install = sub_once(install, contract_pattern, contract_replacement, "contract commit block", re.S)

install = replace_once(
    install,
    "  INSTALLED=()\n  for skill_name in \"${SKILLS_TO_INSTALL[@]}\"; do",
    "  INSTALLED=()\n  INSTALLED_FILES=()\n  for skill_name in \"${SKILLS_TO_INSTALL[@]}\"; do",
    "skill installed file accumulator",
)
install = replace_once(
    install,
    "    installed_skill=true\n    for skill_file in \"${skill_files[@]}\"; do\n      if ! download \"$skill_file\" \"$skill_file\"; then\n        installed_skill=false\n        break\n      fi\n    done",
    "    installed_skill=true\n    skill_downloaded_files=()\n    for skill_file in \"${skill_files[@]}\"; do\n      if ! download \"$skill_file\" \"$skill_file\"; then\n        installed_skill=false\n        break\n      fi\n      skill_downloaded_files+=(\"$skill_file\")\n    done",
    "skill download tracking",
)
install = replace_once(
    install,
    "      INSTALLED+=(\"$skill_name\")\n",
    "      INSTALLED+=(\"$skill_name\")\n      INSTALLED_FILES+=(\"${skill_downloaded_files[@]}\")\n",
    "skill successful file tracking",
)
skill_commit_pattern = r'''  if \[ "\$\{#INSTALLED\[@\]\}" -gt 0 \] && \[ "\$GIT_AVAILABLE" = true \]; then\n    git add .*?\n  fi\n'''
skill_commit_replacement = r'''  if [ "${#INSTALLED[@]}" -gt 0 ] && [ "$GIT_AVAILABLE" = true ]; then
    SKILL_LIST=$(IFS=', '; echo "${INSTALLED[*]}")
    commit_declared_paths "chore: install Canuto skills ($SKILL_LIST)" "${INSTALLED_FILES[@]}" \
      || error "Skill installation commit failed; inspect the staged paths."
  fi
'''
install = sub_once(install, skill_commit_pattern, skill_commit_replacement, "skill commit block", re.S)

migrate_pattern = r'''  # ── Step 7: Commit ─+\n  if \[ "\$GIT_AVAILABLE" = true \]; then\n.*?\n  fi\n\n  echo ""\n  echo -e "\$\{GREEN\}━'''
migrate_replacement = r'''  # ── Step 7: Optional explicit commit ─────────────────────────────────────
  if [ "$GIT_AVAILABLE" = true ]; then
    MIGRATE_COMMIT_PATHS=("${FRAMEWORK_FILES[@]}" "${INSTALL_ONLY_FILES[@]}" \
      "$CLAUDE_MD" "AGENTS.md" "CODEX.md" ".context.md" ".gitignore" ".agents/memory")
    commit_declared_paths "chore: migrate Canuto Framework to the Obsidian vault" \
      "${MIGRATE_COMMIT_PATHS[@]}" \
      || error "Migration commit failed; inspect the staged paths."
  fi

  echo ""
  echo -e "${GREEN}━'''
install = sub_once(install, migrate_pattern, migrate_replacement, "migration commit block", re.S)

install_pattern = r'''  if \[ "\$GIT_AVAILABLE" = true \]; then\n    echo ""\n    log "Staging files for git\.\.\.".*?\n  fi\n\n  echo ""\n  echo -e "\$\{GREEN\}━'''
install_replacement = r'''  INSTALL_FW_VER=$(head -1 "$AGENTS_DIR/VERSION" 2>/dev/null | tr -d '[:space:]')
  [ -n "$INSTALL_FW_VER" ] || INSTALL_FW_VER="?"
  if [ "$GIT_AVAILABLE" = true ]; then
    INSTALL_COMMIT_PATHS=("${FRAMEWORK_FILES[@]}" "${INSTALL_ONLY_FILES[@]}" \
      "$CLAUDE_MD" "AGENTS.md" "CODEX.md" ".context.md" ".gitignore" \
      ".agents/plugins/.gitkeep")
    for install_vault_dir in "${VAULT_DIRS[@]}"; do
      INSTALL_COMMIT_PATHS+=("$install_vault_dir/.gitkeep")
    done
    commit_declared_paths "chore: add Canuto Framework v$INSTALL_FW_VER" \
      "${INSTALL_COMMIT_PATHS[@]}" \
      || error "Framework installation commit failed; inspect the staged paths."
  fi

  echo ""
  echo -e "${GREEN}━'''
install = sub_once(install, install_pattern, install_replacement, "fresh install commit block", re.S)

update_pattern = r'''  if \[ "\$GIT_AVAILABLE" = true \]; then\n    echo ""\n    log "Staging updated files\.\.\.".*?\n  fi\n\n  if ! run_install_validation; then'''
update_replacement = r'''  if [ "$GIT_AVAILABLE" = true ]; then
    # Runtime state is never a declared commit path. Keep ignore rules current
    # so a later manual `git add -A` does not absorb machine-local state.
    if [ -f ".gitignore" ] && ! grep -q "^\.agents/vault/events/" .gitignore 2>/dev/null; then
      printf '\n# Canuto — estado de runtime por máquina (nunca versionar)\n.agents/vault/events/\n.agents/tmp/\n.agents/.cache/\n' >> .gitignore
      ok "Runtime do Canuto adicionado ao .gitignore"
    fi
    UPDATE_COMMIT_PATHS=("${FRAMEWORK_FILES[@]}" "${INSTALL_ONLY_FILES[@]}" \
      "$CLAUDE_MD" "AGENTS.md" "CODEX.md" ".context.md" ".gitignore")
    commit_declared_paths "chore: update Canuto Framework to v$FW_VER" \
      "${UPDATE_COMMIT_PATHS[@]}" \
      || error "Framework update commit failed; inspect the staged paths."
  fi

  if ! run_install_validation; then'''
install = sub_once(install, update_pattern, update_replacement, "update commit block", re.S)

write("install.sh", install)

update_all = read(".agents/tools/canuto-update-all.sh")
update_all = replace_once(
    update_all,
    "#   bash .agents/tools/canuto-update-all.sh --force      # atualiza mesmo em dia\n",
    "#   bash .agents/tools/canuto-update-all.sh --force      # atualiza mesmo em dia\n#   bash .agents/tools/canuto-update-all.sh --commit     # autoriza commit por projeto\n",
    "update-all usage",
)
update_all = replace_once(
    update_all,
    "# Contrato de segurança: NUNCA faz push. O commit local é o do próprio\n# install.sh (--yes). Projetos com working tree sujo são PULADOS — update no\n",
    "# Contrato de segurança: NUNCA faz push. Por padrão também NÃO commita;\n# `--commit` é a autorização explícita encaminhada ao install.sh. Projetos com\n# working tree sujo são PULADOS — update no\n",
    "update-all consent comment",
)
update_all = replace_once(
    update_all,
    "DRY_RUN=0\nFORCE=0\nEXTRA_PATHS=()",
    "DRY_RUN=0\nFORCE=0\nCOMMIT=0\nCOMMIT_POLICY=\"default\"\nEXTRA_PATHS=()",
    "update-all commit state",
)
update_all = replace_once(
    update_all,
    "    --dry-run) DRY_RUN=1 ;;\n    --force)   FORCE=1 ;;",
    "    --dry-run) DRY_RUN=1 ;;\n    --force)   FORCE=1 ;;\n    --commit)\n      [ \"$COMMIT_POLICY\" != \"no-commit\" ] || { err \"--commit conflita com --no-commit\"; exit 64; }\n      COMMIT=1; COMMIT_POLICY=\"commit\"\n      ;;\n    --no-commit)\n      [ \"$COMMIT_POLICY\" != \"commit\" ] || { err \"--no-commit conflita com --commit\"; exit 64; }\n      COMMIT=0; COMMIT_POLICY=\"no-commit\"\n      ;;",
    "update-all parser",
)
update_all = replace_once(
    update_all,
    "  if (cd \"$proj\" && bash \"$FRESH_INSTALLER\" --update --yes </dev/null) >\"$plog\" 2>&1; then",
    "  UPDATE_INSTALL_ARGS=(--update --yes)\n  [ \"$COMMIT\" -eq 1 ] && UPDATE_INSTALL_ARGS+=(--commit)\n  if (cd \"$proj\" && bash \"$FRESH_INSTALLER\" \"${UPDATE_INSTALL_ARGS[@]}\" </dev/null) >\"$plog\" 2>&1; then",
    "update-all installer invocation",
)
write(".agents/tools/canuto-update-all.sh", update_all)

feature_map = read("docs/FEATURE-MAP.md")
feature_map = feature_map.replace(
    "| Fresh install | implemented | `install.sh` | Bootstraps `.agents/`, hooks, vault, Codex, and docs |",
    "| Fresh install | implemented | `install.sh` | Bootstraps `.agents/`, hooks, vault, Codex, and docs; leaves changes unstaged unless `--commit` is explicit |",
)
feature_map = feature_map.replace(
    "| Update flow | implemented | `install.sh --update` | Refreshes installer logic from `main`, persists the updated `install.sh`, then applies framework updates |",
    "| Update flow | implemented | `install.sh --update` | Refreshes installer logic, applies framework updates, and never treats `--yes` as commit authorization |",
)
write("docs/FEATURE-MAP.md", feature_map)

readme = read("README.md")
needle = "`bash install.sh --update` is now the standard path. The installer refreshes itself from `main` before applying the update, so it still works even if the local `install.sh` is stale.\n"
if needle in readme:
    readme = readme.replace(
        needle,
        needle + "\nBy default, install/update changes remain **unstaged and uncommitted**. `--yes` only answers operational prompts. Use `--commit` separately when a local framework commit is intended.\n",
        1,
    )
else:
    raise SystemExit("README update paragraph not found")
write("README.md", readme)

write(
    "docs/adr/0016-yes-nao-autoriza-commit.md",
    """# ADR-0016 — `--yes` não autoriza commit\n\nData: 2026-08-23 · Status: aceito\n\n## Contexto\n\nO instalador usava a mesma confirmação para prosseguir com uma operação e para\ncriar um commit Git. Em stdin não interativo, `confirm_yes` adotava o default\npositivo; portanto `curl | bash`, `--yes` e o update multi-projeto podiam criar\ncommits sem uma autorização específica para o estado Git. Isso contradiz o\ncontrato operacional: código aplicado, staging e commit são estados distintos.\n\n## Decisão\n\n- `--yes` responde somente a prompts operacionais.\n- O default é `--no-commit`: mudanças ficam no working tree, sem tocar o index.\n- Somente `--commit` autoriza staging e commit.\n- O commit usa uma lista explícita de paths pertencentes ao framework e\n  `git commit --only`; mudanças staged não relacionadas ficam fora do commit.\n- Flags desconhecidas, modos conflitantes e valores ausentes falham com exit 64\n  antes de qualquer mutação.\n- `--dry-run` resolve o modo e encerra antes de criar arquivos no projeto.\n- `canuto-update-all.sh` encaminha `--commit` somente quando recebeu essa flag.\n\n## Consequências\n\n- (+) automação não transforma confirmação genérica em autorização Git.\n- (+) o usuário inspeciona o diff antes de decidir publicar um commit.\n- (+) commits do framework não absorvem staging alheio.\n- (-) fluxos que dependiam do commit implícito precisam acrescentar `--commit`.\n""",
)

# Behavioral regression suite appended immediately before SUMMARY.
tests = read("test-framework.sh")
summary_marker = "# ═══════════════════════════════════════════════════════════════════════════\n# SUMMARY\n"
if summary_marker not in tests:
    raise SystemExit("test-framework SUMMARY marker not found")
if "TEST 21: Consentimento explícito para commit" not in tests:
    test_block = r'''# ═══════════════════════════════════════════════════════════════════════════
# TEST 21: Consentimento explícito para commit (ADR-0016)
# ═══════════════════════════════════════════════════════════════════════════
echo "── Test 21: Consentimento explícito para commit ──"

CONSENT_ROOT=$(mktemp -d)
CONSENT_HOME="$CONSENT_ROOT/home"
mkdir -p "$CONSENT_HOME"

make_contract_consumer() {
  local repo="$1"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.name "Canuto Consent Test"
  git -C "$repo" config user.email "consent@example.invalid"
  printf '# Consumer Claude\n' > "$repo/CLAUDE.md"
  printf '# Consumer Agents\n' > "$repo/AGENTS.md"
  git -C "$repo" add CLAUDE.md AGENTS.md
  git -C "$repo" commit -q -m "test: initial consumer"
}

NO_COMMIT_REPO="$CONSENT_ROOT/no-commit"
make_contract_consumer "$NO_COMMIT_REPO"
NO_COMMIT_BEFORE=$(git -C "$NO_COMMIT_REPO" rev-parse HEAD)
if (cd "$NO_COMMIT_REPO" && HOME="$CONSENT_HOME" CANUTO_SOURCE_DIR="$FRAMEWORK_DIR" \
    /bin/bash "$FRAMEWORK_DIR/install.sh" --contract-only --yes </dev/null >/dev/null 2>&1); then
  NO_COMMIT_AFTER=$(git -C "$NO_COMMIT_REPO" rev-parse HEAD)
  if [ "$NO_COMMIT_AFTER" = "$NO_COMMIT_BEFORE" ] \
     && git -C "$NO_COMMIT_REPO" diff --cached --quiet \
     && [ -n "$(git -C "$NO_COMMIT_REPO" status --porcelain)" ]; then
    pass "21a --yes aplica o contrato sem stage nem commit"
  else
    fail "21a --yes alterou HEAD/index ou não deixou diff inspecionável"
  fi
else
  fail "21a contract-only sem --commit falhou"
fi

COMMIT_REPO="$CONSENT_ROOT/explicit-commit"
make_contract_consumer "$COMMIT_REPO"
COMMIT_COUNT_BEFORE=$(git -C "$COMMIT_REPO" rev-list --count HEAD)
if (cd "$COMMIT_REPO" && HOME="$CONSENT_HOME" CANUTO_SOURCE_DIR="$FRAMEWORK_DIR" \
    /bin/bash "$FRAMEWORK_DIR/install.sh" --contract-only --yes --commit </dev/null >/dev/null 2>&1); then
  COMMIT_COUNT_AFTER=$(git -C "$COMMIT_REPO" rev-list --count HEAD)
  COMMIT_PATHS=$(git -C "$COMMIT_REPO" diff-tree --no-commit-id --name-only -r HEAD | LC_ALL=C sort | tr '\n' ' ')
  if [ "$COMMIT_COUNT_AFTER" -eq $((COMMIT_COUNT_BEFORE + 1)) ] \
     && [ -z "$(git -C "$COMMIT_REPO" status --porcelain)" ] \
     && [ "$COMMIT_PATHS" = ".agents/OPERATING-CONTRACT.md AGENTS.md CLAUDE.md " ]; then
    pass "21b --commit cria um commit limitado aos três paths declarados"
  else
    fail "21b commit explícito não convergiu ou incluiu paths indevidos: $COMMIT_PATHS"
  fi
else
  fail "21b contract-only com --commit falhou"
fi

PARSER_DIR="$CONSENT_ROOT/parser"
mkdir -p "$PARSER_DIR"
if (cd "$PARSER_DIR" && /bin/bash "$FRAMEWORK_DIR/install.sh" --help >/dev/null 2>&1) \
   && [ -z "$(find "$PARSER_DIR" -mindepth 1 -print -quit)" ]; then
  pass "21c --help sai 0 sem mutar o diretório"
else
  fail "21c --help falhou ou criou artefatos"
fi

if (cd "$PARSER_DIR" && HOME="$CONSENT_HOME" CANUTO_SOURCE_DIR="$FRAMEWORK_DIR" \
    /bin/bash "$FRAMEWORK_DIR/install.sh" --dry-run --yes >/dev/null 2>&1) \
   && [ -z "$(find "$PARSER_DIR" -mindepth 1 -print -quit)" ]; then
  pass "21d --dry-run resolve o modo sem mutação"
else
  fail "21d --dry-run falhou ou criou artefatos"
fi

for PARSER_CASE in unknown missing-skill missing-api conflicting-mode conflicting-commit commit-readonly positional; do
  PARSER_RC=0
  case "$PARSER_CASE" in
    unknown) PARSER_ARGS=(--definitely-unknown) ;;
    missing-skill) PARSER_ARGS=(--skill) ;;
    missing-api) PARSER_ARGS=(--api-key) ;;
    conflicting-mode) PARSER_ARGS=(--update --check) ;;
    conflicting-commit) PARSER_ARGS=(--commit --no-commit) ;;
    commit-readonly) PARSER_ARGS=(--check --commit) ;;
    positional) PARSER_ARGS=(unexpected-positional) ;;
  esac
  (cd "$PARSER_DIR" && /bin/bash "$FRAMEWORK_DIR/install.sh" "${PARSER_ARGS[@]}" >/dev/null 2>&1) || PARSER_RC=$?
  if [ "$PARSER_RC" -eq 64 ] && [ -z "$(find "$PARSER_DIR" -mindepth 1 -print -quit)" ]; then
    pass "21e parser rejeita $PARSER_CASE antes de mutar"
  else
    fail "21e parser $PARSER_CASE retornou $PARSER_RC ou criou artefatos"
  fi
done

UPDATE_SOURCE="$CONSENT_ROOT/update-source"
UPDATE_TMP="$CONSENT_ROOT/update-tmp"
mkdir -p "$UPDATE_SOURCE/.agents" "$UPDATE_TMP"
printf '9.9.9\n' > "$UPDATE_SOURCE/.agents/VERSION"
cat > "$UPDATE_SOURCE/install.sh" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > .captured-installer-args
mkdir -p .agents
printf '9.9.9\n' > .agents/VERSION
STUBEOF
chmod +x "$UPDATE_SOURCE/install.sh"

make_update_consumer() {
  local repo="$1"
  mkdir -p "$repo/.agents"
  git -C "$repo" init -q
  git -C "$repo" config user.name "Canuto Update Test"
  git -C "$repo" config user.email "update@example.invalid"
  printf '1.0.0\n' > "$repo/.agents/VERSION"
  git -C "$repo" add .agents/VERSION
  git -C "$repo" commit -q -m "test: old framework"
}

UPDATE_DEFAULT_REPO="$CONSENT_ROOT/update-default"
make_update_consumer "$UPDATE_DEFAULT_REPO"
if CANUTO_SOURCE_DIR="$UPDATE_SOURCE" CANUTO_VAULT_DIR="$CONSENT_ROOT/empty-vault" TMPDIR="$UPDATE_TMP" \
   /bin/bash "$FRAMEWORK_DIR/.agents/tools/canuto-update-all.sh" "$UPDATE_DEFAULT_REPO" >/dev/null 2>&1 \
   && ! grep -qx -- '--commit' "$UPDATE_DEFAULT_REPO/.captured-installer-args"; then
  pass "21f update-all não encaminha --commit por padrão"
else
  fail "21f update-all encaminhou commit implícito ou falhou"
fi

UPDATE_COMMIT_REPO="$CONSENT_ROOT/update-commit"
make_update_consumer "$UPDATE_COMMIT_REPO"
if CANUTO_SOURCE_DIR="$UPDATE_SOURCE" CANUTO_VAULT_DIR="$CONSENT_ROOT/empty-vault" TMPDIR="$UPDATE_TMP" \
   /bin/bash "$FRAMEWORK_DIR/.agents/tools/canuto-update-all.sh" --commit "$UPDATE_COMMIT_REPO" >/dev/null 2>&1 \
   && grep -qx -- '--commit' "$UPDATE_COMMIT_REPO/.captured-installer-args"; then
  pass "21g update-all encaminha --commit somente quando explícito"
else
  fail "21g update-all não respeitou autorização explícita"
fi

rm -rf "$CONSENT_ROOT"
echo ""
'''
    tests = tests.replace(summary_marker, test_block + summary_marker, 1)
write("test-framework.sh", tests)

print("explicit commit consent hardening applied")
