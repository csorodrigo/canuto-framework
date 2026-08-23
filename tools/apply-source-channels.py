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


def insert_before(text: str, marker: str, content: str, label: str) -> str:
    if marker not in text:
        raise SystemExit(f"{label}: marker not found")
    return text.replace(marker, content + marker, 1)


# ---------------------------------------------------------------------------
# install.sh
# ---------------------------------------------------------------------------
install = read("install.sh")

install = replace_once(
    install,
    'REPO_URL="${CANUTO_REPO_URL:-https://raw.githubusercontent.com/csorodrigo/canuto-framework/main}"\nSOURCE_DIR="${CANUTO_SOURCE_DIR:-}"\n',
    '''REPO_BASE="${CANUTO_REPO_BASE:-https://raw.githubusercontent.com/csorodrigo/canuto-framework}"
REPO_URL_OVERRIDE="${CANUTO_REPO_URL:-}"
REPO_URL=""
SOURCE_DIR="${CANUTO_SOURCE_DIR:-}"
SOURCE_KIND=""
SOURCE_REF=""
SOURCE_CHANNEL=""
SOURCE_VERSION=""
SOURCE_TRANSPORT=""
CLI_SOURCE_CHANNEL=""
CLI_SOURCE_VERSION=""
CLI_SOURCE_REF=""
CLI_SOURCE_SELECTOR_COUNT=0
ROLLBACK_REQUESTED=false
REFRESH_ARGS=()
''',
    "installer source variables",
)

install = replace_once(
    install,
    '  --dry-run            report the selected mutating operation without changes\n  --api-key VALUE      Obsidian API key used by migration/setup\n',
    '''  --dry-run            report the selected mutating operation without changes
  --channel VALUE       stable (default) or edge; edge resolves to main
  --version VERSION     pin releases/VERSION (for example 1.8.0)
  --ref REF             pin an exact branch, tag, or commit SHA
  --rollback VERSION    update from releases/VERSION and record rollback intent
  --api-key VALUE      Obsidian API key used by migration/setup
''',
    "installer help source options",
)

install = replace_once(
    install,
    '  bash install.sh --contract-only --commit\n  bash install.sh --skill health-check --no-commit\n  bash install.sh --dry-run --update\n',
    '''  bash install.sh --contract-only --commit
  bash install.sh --skill health-check --no-commit
  bash install.sh --update --channel edge
  bash install.sh --update --version 1.8.0
  bash install.sh --rollback 1.7.0 --commit
  bash install.sh --dry-run --update
''',
    "installer help examples",
)

source_helpers = r'''
validate_source_channel() {
  case "$1" in stable|edge) return 0 ;; *) return 1 ;; esac
}

validate_release_version() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9][A-Za-z0-9.-]*)?$ ]]
}

validate_source_ref() {
  local ref="$1"
  [ -n "$ref" ] || return 1
  [ "${#ref}" -le 160 ] || return 1
  case "$ref" in
    /*|*..*|*//*|*[^A-Za-z0-9._/-]*) return 1 ;;
  esac
  return 0
}

set_cli_source_selector() {
  local kind="$1"
  local value="$2"
  CLI_SOURCE_SELECTOR_COUNT=$((CLI_SOURCE_SELECTOR_COUNT + 1))
  [ "$CLI_SOURCE_SELECTOR_COUNT" -le 1 ] || usage_error "Use only one of --channel, --version, --ref, or --rollback"
  case "$kind" in
    channel) CLI_SOURCE_CHANNEL="$value" ;;
    version) CLI_SOURCE_VERSION="$value" ;;
    ref) CLI_SOURCE_REF="$value" ;;
    *) usage_error "Internal source selector error: $kind" ;;
  esac
}

resolve_source_selection() {
  local env_kind="${CANUTO_SOURCE_KIND:-}"
  local env_ref="${CANUTO_SOURCE_REF:-}"
  local env_channel="${CANUTO_SOURCE_CHANNEL:-${CANUTO_CHANNEL:-}}"
  local env_version="${CANUTO_SOURCE_VERSION:-${CANUTO_VERSION:-}}"

  if [ -n "$REPO_URL_OVERRIDE" ]; then
    [ "$CLI_SOURCE_SELECTOR_COUNT" -eq 0 ] || usage_error "CANUTO_REPO_URL cannot be combined with a CLI source selector"
    SOURCE_KIND="${env_kind:-custom}"
    SOURCE_REF="${env_ref:-custom}"
    SOURCE_CHANNEL="$env_channel"
    SOURCE_VERSION="$env_version"
    REPO_URL="${REPO_URL_OVERRIDE%/}"
    SOURCE_TRANSPORT="custom-url"
    return 0
  fi

  if [ -n "$CLI_SOURCE_CHANNEL" ]; then
    validate_source_channel "$CLI_SOURCE_CHANNEL" || usage_error "--channel must be stable or edge"
    SOURCE_CHANNEL="$CLI_SOURCE_CHANNEL"
    SOURCE_KIND="$CLI_SOURCE_CHANNEL"
    case "$CLI_SOURCE_CHANNEL" in stable) SOURCE_REF="stable" ;; edge) SOURCE_REF="main" ;; esac
  elif [ -n "$CLI_SOURCE_VERSION" ]; then
    validate_release_version "$CLI_SOURCE_VERSION" || usage_error "Invalid release version: $CLI_SOURCE_VERSION"
    SOURCE_VERSION="$CLI_SOURCE_VERSION"
    SOURCE_KIND="version"
    SOURCE_REF="releases/$CLI_SOURCE_VERSION"
  elif [ -n "$CLI_SOURCE_REF" ]; then
    validate_source_ref "$CLI_SOURCE_REF" || usage_error "Invalid source ref: $CLI_SOURCE_REF"
    SOURCE_KIND="ref"
    SOURCE_REF="$CLI_SOURCE_REF"
  elif [ -n "$env_ref" ]; then
    validate_source_ref "$env_ref" || usage_error "Invalid CANUTO_SOURCE_REF: $env_ref"
    SOURCE_KIND="${env_kind:-ref}"
    SOURCE_REF="$env_ref"
    SOURCE_CHANNEL="$env_channel"
    SOURCE_VERSION="$env_version"
  elif [ -n "$env_version" ]; then
    validate_release_version "$env_version" || usage_error "Invalid CANUTO_VERSION: $env_version"
    SOURCE_VERSION="$env_version"
    SOURCE_KIND="version"
    SOURCE_REF="releases/$env_version"
  else
    SOURCE_CHANNEL="${env_channel:-stable}"
    validate_source_channel "$SOURCE_CHANNEL" || usage_error "CANUTO_CHANNEL must be stable or edge"
    SOURCE_KIND="$SOURCE_CHANNEL"
    case "$SOURCE_CHANNEL" in stable) SOURCE_REF="stable" ;; edge) SOURCE_REF="main" ;; esac
  fi

  validate_source_ref "$SOURCE_REF" || usage_error "Resolved source ref is invalid: $SOURCE_REF"
  REPO_URL="${REPO_BASE%/}/$SOURCE_REF"
  if [ -n "$SOURCE_DIR" ]; then SOURCE_TRANSPORT="local"; else SOURCE_TRANSPORT="raw-github"; fi
}

build_refresh_args() {
  local skip_next=0
  local arg=""
  REFRESH_ARGS=()
  for arg in "${ORIGINAL_ARGS[@]}"; do
    if [ "$skip_next" -eq 1 ]; then
      skip_next=0
      continue
    fi
    case "$arg" in
      --channel|--version|--ref|--rollback) skip_next=1 ;;
      *) REFRESH_ARGS+=("$arg") ;;
    esac
  done
  if [ "$ROLLBACK_REQUESTED" = true ]; then
    local has_update=false
    for arg in "${REFRESH_ARGS[@]}"; do [ "$arg" = "--update" ] && has_update=true; done
    [ "$has_update" = true ] || REFRESH_ARGS=(--update "${REFRESH_ARGS[@]}")
  fi
}

'''
install = insert_before(
    install,
    "# ── Strict argument parsing ─────────────────────────────────────────────────\n",
    source_helpers,
    "installer source helpers",
)

install = replace_once(
    install,
    '    --dry-run) DRY_RUN=true ;;\n    --skill)\n',
    '''    --dry-run) DRY_RUN=true ;;
    --channel)
      [ $# -ge 2 ] || usage_error "--channel requires stable or edge"
      case "$2" in ""|-*) usage_error "--channel requires stable or edge" ;; esac
      set_cli_source_selector channel "$2"
      shift
      ;;
    --version)
      [ $# -ge 2 ] || usage_error "--version requires a semantic version"
      case "$2" in ""|-*) usage_error "--version requires a semantic version" ;; esac
      set_cli_source_selector version "$2"
      shift
      ;;
    --ref)
      [ $# -ge 2 ] || usage_error "--ref requires a Git ref"
      case "$2" in ""|-*) usage_error "--ref requires a Git ref" ;; esac
      set_cli_source_selector ref "$2"
      shift
      ;;
    --rollback)
      [ $# -ge 2 ] || usage_error "--rollback requires a semantic version"
      case "$2" in ""|-*) usage_error "--rollback requires a semantic version" ;; esac
      ROLLBACK_REQUESTED=true
      set_requested_mode "update"
      set_cli_source_selector version "$2"
      shift
      ;;
    --skill)
''',
    "installer source parser",
)

install = replace_once(
    install,
    '''# ── Detect implicit install/update mode ─────────────────────────────────────
if [ "$MODE" = "auto" ]; then
  if [ -d "$AGENTS_DIR" ]; then MODE="update"; else MODE="install"; fi
fi

if [ "$COMMIT_CHANGES" = true ]; then
''',
    '''# ── Detect implicit install/update mode ─────────────────────────────────────
if [ "$MODE" = "auto" ]; then
  if [ -d "$AGENTS_DIR" ]; then MODE="update"; else MODE="install"; fi
fi

resolve_source_selection
build_refresh_args

if [ "$COMMIT_CHANGES" = true ]; then
''',
    "installer resolve source",
)

install = replace_once(
    install,
    '''      echo "Canuto dry-run"
      echo "mode=$MODE"
      echo "commit=false"
''',
    '''      echo "Canuto dry-run"
      echo "mode=$MODE"
      echo "commit=false"
      echo "source_kind=$SOURCE_KIND"
      echo "source_ref=$SOURCE_REF"
      echo "source_transport=$SOURCE_TRANSPORT"
      [ -n "$SOURCE_CHANNEL" ] && echo "source_channel=$SOURCE_CHANNEL"
      [ -n "$SOURCE_VERSION" ] && echo "source_version=$SOURCE_VERSION"
      [ "$ROLLBACK_REQUESTED" = true ] && echo "rollback=true"
''',
    "installer dry-run source receipt",
)

install = install.replace(
    'warn "Could not refresh installer from main (curl/wget missing). Continuing with local copy."',
    'warn "Could not refresh installer from $SOURCE_REF (curl/wget missing). Continuing with local copy."',
)
install = install.replace(
    'log "Refreshing installer from main before proceeding..."',
    'log "Refreshing installer from source ref $SOURCE_REF before proceeding..."',
)
install = replace_once(
    install,
    '    CANUTO_BOOTSTRAPPED=1 bash "$remote_installer" "${ORIGINAL_ARGS[@]}"\n',
    '''    CANUTO_BOOTSTRAPPED=1 \
      CANUTO_REPO_URL="$REPO_URL" \
      CANUTO_SOURCE_KIND="$SOURCE_KIND" \
      CANUTO_SOURCE_REF="$SOURCE_REF" \
      CANUTO_SOURCE_CHANNEL="$SOURCE_CHANNEL" \
      CANUTO_SOURCE_VERSION="$SOURCE_VERSION" \
      bash "$remote_installer" "${REFRESH_ARGS[@]}"
''',
    "installer refresh propagation",
)
install = install.replace(
    'warn "Failed to refresh installer from main. Continuing with local copy."',
    'warn "Failed to refresh installer from $SOURCE_REF. Continuing with local copy."',
)

receipt_helpers = r'''# Source receipts are deterministic and atomic. They prove which logical ref
# supplied a scope and bind it to the SHA-256 digest of the installed files.
write_source_receipt() {
  local output="$1"
  local scope="$2"
  local operation="$3"
  shift 3
  local manifest="$TMP_DIR/source-receipt-manifest.tsv"
  local tmp="${output}.canuto-receipt.$$"
  local framework_version=""
  local manifest_hash=""
  local file_count=0
  local file=""
  local hash=""

  : > "$manifest" || return 1
  for file in "$@"; do
    [ -f "$file" ] || { warn "Source receipt cannot include missing file: $file"; rm -f "$manifest"; return 1; }
    hash=$(sha256_file "$file" 2>/dev/null || true)
    [ -n "$hash" ] || { warn "Source receipt could not hash: $file"; rm -f "$manifest"; return 1; }
    printf '%s\t%s\n' "$file" "$hash" >> "$manifest" || return 1
    file_count=$((file_count + 1))
  done
  manifest_hash=$(sha256_file "$manifest" 2>/dev/null || true)
  [ -n "$manifest_hash" ] || { warn "Source receipt manifest hash unavailable."; rm -f "$manifest"; return 1; }
  framework_version=$(head -1 "$AGENTS_DIR/VERSION" 2>/dev/null | tr -d '[:space:]' || true)
  mkdir -p "$(dirname "$output")" || return 1

  python3 - "$tmp" "$scope" "$operation" "$SOURCE_KIND" "$SOURCE_REF" \
    "$SOURCE_CHANNEL" "$SOURCE_VERSION" "$SOURCE_TRANSPORT" \
    "$framework_version" "$manifest_hash" "$file_count" <<'PYRECEIPT'
import json
import sys

(output, scope, operation, source_kind, source_ref, channel, release_version,
 transport, framework_version, manifest_hash, file_count) = sys.argv[1:]
receipt = {
    "schemaVersion": 1,
    "scope": scope,
    "operation": operation,
    "sourceKind": source_kind,
    "sourceRef": source_ref,
    "transport": transport,
    "frameworkVersion": framework_version,
    "manifestSha256": manifest_hash,
    "fileCount": int(file_count),
}
if channel:
    receipt["channel"] = channel
if release_version:
    receipt["releaseVersion"] = release_version
with open(output, "x", encoding="utf-8") as fh:
    json.dump(receipt, fh, ensure_ascii=True, indent=2, sort_keys=True)
    fh.write("\n")
PYRECEIPT
  local rc=$?
  rm -f "$manifest"
  [ "$rc" -eq 0 ] || { rm -f "$tmp"; return "$rc"; }
  mv "$tmp" "$output" || { rm -f "$tmp"; return 1; }
  ok "Source receipt: $output ($SOURCE_KIND:$SOURCE_REF, ${manifest_hash:0:12})"
}

source_receipt_ref() {
  local receipt="$1"
  [ -f "$receipt" ] || return 1
  python3 - "$receipt" <<'PYREF'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        value = json.load(fh).get("sourceRef", "")
except (OSError, ValueError, TypeError):
    value = ""
if value:
    print(value)
else:
    raise SystemExit(1)
PYREF
}

'''
install = insert_before(
    install,
    "# Test-only library seam: source installer helpers without entering an install\n",
    receipt_helpers,
    "source receipt helpers",
)

install = replace_once(
    install,
    '''  ensure_shared_operating_contract_reference "$CLAUDE_MD"
  ensure_shared_operating_contract_reference "AGENTS.md"

  if [ "$GIT_AVAILABLE" = true ]; then
    commit_declared_paths "docs: sync shared Canuto operating contract" \
      ".agents/OPERATING-CONTRACT.md" "$CLAUDE_MD" "AGENTS.md" \
''',
    '''  ensure_shared_operating_contract_reference "$CLAUDE_MD"
  ensure_shared_operating_contract_reference "AGENTS.md"
  write_source_receipt ".agents/CONTRACT-RECEIPT.json" "contract" "contract" \
    ".agents/OPERATING-CONTRACT.md" "$CLAUDE_MD" "AGENTS.md" \
    || error "Could not publish the contract source receipt."

  if [ "$GIT_AVAILABLE" = true ]; then
    commit_declared_paths "docs: sync shared Canuto operating contract" \
      ".agents/OPERATING-CONTRACT.md" "$CLAUDE_MD" "AGENTS.md" ".agents/CONTRACT-RECEIPT.json" \
''',
    "contract source receipt",
)

# Add provenance check before CHECK summary.
check_marker = '  echo ""\n  echo -e "  Summary: ${GREEN}${UP_TO_DATE} up-to-date${RESET}'
check_block = r'''  if git remote -v 2>/dev/null | grep -q "canuto-framework"; then
    log "Source receipt check skipped in the framework source repository."
  elif [ ! -f ".agents/SOURCE-RECEIPT.json" ]; then
    echo -e "  ${YELLOW}? UNKNOWN${RESET}    .agents/SOURCE-RECEIPT.json (legacy install; provenance absent)"
    UNKNOWN=$((UNKNOWN + 1))
  else
    RECEIPT_REF=$(source_receipt_ref ".agents/SOURCE-RECEIPT.json" 2>/dev/null || true)
    if [ "$RECEIPT_REF" = "$SOURCE_REF" ]; then
      echo -e "  ${GREEN}✓ OK${RESET}        .agents/SOURCE-RECEIPT.json (source: $RECEIPT_REF)"
      UP_TO_DATE=$((UP_TO_DATE + 1))
    elif [ -n "$RECEIPT_REF" ]; then
      echo -e "  ${YELLOW}⚠ OUTDATED${RESET}   .agents/SOURCE-RECEIPT.json (local: $RECEIPT_REF → selected: $SOURCE_REF)"
      OUTDATED=$((OUTDATED + 1))
    else
      echo -e "  ${YELLOW}? UNKNOWN${RESET}    .agents/SOURCE-RECEIPT.json (invalid receipt)"
      UNKNOWN=$((UNKNOWN + 1))
    fi
  fi

'''
install = insert_before(install, check_marker, check_block, "check source receipt")

# Full framework receipts at migrate/install/update boundaries.
install = replace_once(
    install,
    '''  if [ "$MIGRATE_OUTCOME_RC" -ne 0 ]; then
    rm -rf "$TMP_DIR"
    exit "$MIGRATE_OUTCOME_RC"
  fi

  # ── Step 6: Clean up old memory dir''',
    '''  if [ "$MIGRATE_OUTCOME_RC" -ne 0 ]; then
    rm -rf "$TMP_DIR"
    exit "$MIGRATE_OUTCOME_RC"
  fi
  write_source_receipt ".agents/SOURCE-RECEIPT.json" "framework" "migrate" \
    "${FRAMEWORK_FILES[@]}" || error "Could not publish the framework source receipt."

  # ── Step 6: Clean up old memory dir''',
    "migration source receipt",
)
install = replace_once(
    install,
    '      "$CLAUDE_MD" "AGENTS.md" "CODEX.md" ".context.md" ".gitignore" ".agents/memory")\n',
    '      "$CLAUDE_MD" "AGENTS.md" "CODEX.md" ".context.md" ".gitignore" ".agents/memory" ".agents/SOURCE-RECEIPT.json")\n',
    "migration receipt commit path",
)
install = replace_once(
    install,
    '''  fi
  register_project_path

  INSTALL_FW_VER=$(head -1 "$AGENTS_DIR/VERSION"''',
    '''  fi
  register_project_path
  write_source_receipt ".agents/SOURCE-RECEIPT.json" "framework" "install" \
    "${FRAMEWORK_FILES[@]}" || error "Could not publish the framework source receipt."

  INSTALL_FW_VER=$(head -1 "$AGENTS_DIR/VERSION"''',
    "install source receipt",
)
install = replace_once(
    install,
    '      ".agents/plugins/.gitkeep")\n',
    '      ".agents/plugins/.gitkeep" ".agents/SOURCE-RECEIPT.json")\n',
    "install receipt commit path",
)
install = replace_once(
    install,
    '''  FW_VER=$(head -1 "$AGENTS_DIR/VERSION" 2>/dev/null | tr -d '[:space:]')
  [ -n "$FW_VER" ] || FW_VER="?"

  if [ "$GIT_AVAILABLE" = true ]; then
''',
    '''  FW_VER=$(head -1 "$AGENTS_DIR/VERSION" 2>/dev/null | tr -d '[:space:]')
  [ -n "$FW_VER" ] || FW_VER="?"
  UPDATE_OPERATION="update"
  [ "$ROLLBACK_REQUESTED" = true ] && UPDATE_OPERATION="rollback"
  write_source_receipt ".agents/SOURCE-RECEIPT.json" "framework" "$UPDATE_OPERATION" \
    "${FRAMEWORK_FILES[@]}" || error "Could not publish the framework source receipt."

  if [ "$GIT_AVAILABLE" = true ]; then
''',
    "update source receipt",
)
install = replace_once(
    install,
    '      "$CLAUDE_MD" "AGENTS.md" "CODEX.md" ".context.md" ".gitignore")\n    commit_declared_paths "chore: update Canuto Framework to v$FW_VER"',
    '      "$CLAUDE_MD" "AGENTS.md" "CODEX.md" ".context.md" ".gitignore" ".agents/SOURCE-RECEIPT.json")\n    commit_declared_paths "chore: update Canuto Framework to v$FW_VER"',
    "update receipt commit path",
)

write("install.sh", install)

# ---------------------------------------------------------------------------
# canuto-update-all.sh
# ---------------------------------------------------------------------------
update_all = read(".agents/tools/canuto-update-all.sh")
update_all = update_all.replace(
    "#   bash .agents/tools/canuto-update-all.sh --commit     # autoriza commit por projeto\n",
    "#   bash .agents/tools/canuto-update-all.sh --commit     # autoriza commit por projeto\n#   bash .agents/tools/canuto-update-all.sh --channel edge # usa main explicitamente\n#   bash .agents/tools/canuto-update-all.sh --version 1.8.0 # fixa releases/1.8.0\n#   bash .agents/tools/canuto-update-all.sh --rollback 1.7.0 # rollback fixado\n",
    1,
)
update_all = update_all.replace(
    "# Por projeto: compara .agents/VERSION local com o VERSION remoto do main e,\n",
    "# Por projeto: compara versão E source receipt local com o source selecionado e,\n",
    1,
)
update_all = replace_once(
    update_all,
    'REPO_RAW="${CANUTO_REPO_URL:-https://raw.githubusercontent.com/csorodrigo/canuto-framework/main}"\nVAULT_ROOT=',
    '''REPO_BASE="${CANUTO_REPO_BASE:-https://raw.githubusercontent.com/csorodrigo/canuto-framework}"
REPO_URL_OVERRIDE="${CANUTO_REPO_URL:-}"
REPO_RAW=""
SOURCE_KIND=""
SOURCE_REF=""
SOURCE_CHANNEL=""
SOURCE_VERSION=""
CLI_SOURCE_SELECTOR_COUNT=0
CLI_SOURCE_CHANNEL=""
CLI_SOURCE_VERSION=""
CLI_SOURCE_REF=""
ROLLBACK=0
VAULT_ROOT=''',
    "update-all source variables",
)

update_source_helpers = r'''
validate_channel() { case "$1" in stable|edge) return 0 ;; *) return 1 ;; esac; }
validate_version() { [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9][A-Za-z0-9.-]*)?$ ]]; }
validate_ref() {
  [ -n "$1" ] && [ "${#1}" -le 160 ] || return 1
  case "$1" in /*|*..*|*//*|*[^A-Za-z0-9._/-]*) return 1 ;; esac
  return 0
}
set_source_selector() {
  CLI_SOURCE_SELECTOR_COUNT=$((CLI_SOURCE_SELECTOR_COUNT + 1))
  [ "$CLI_SOURCE_SELECTOR_COUNT" -le 1 ] || { err "use só um entre --channel, --version, --ref e --rollback"; exit 64; }
  case "$1" in channel) CLI_SOURCE_CHANNEL="$2" ;; version) CLI_SOURCE_VERSION="$2" ;; ref) CLI_SOURCE_REF="$2" ;; esac
}
resolve_source() {
  local env_kind="${CANUTO_SOURCE_KIND:-}"
  local env_ref="${CANUTO_SOURCE_REF:-}"
  local env_channel="${CANUTO_SOURCE_CHANNEL:-${CANUTO_CHANNEL:-}}"
  local env_version="${CANUTO_SOURCE_VERSION:-${CANUTO_VERSION:-}}"
  if [ -n "$REPO_URL_OVERRIDE" ]; then
    [ "$CLI_SOURCE_SELECTOR_COUNT" -eq 0 ] || { err "CANUTO_REPO_URL não combina com seletor CLI"; exit 64; }
    SOURCE_KIND="${env_kind:-custom}"; SOURCE_REF="${env_ref:-custom}"
    SOURCE_CHANNEL="$env_channel"; SOURCE_VERSION="$env_version"
    REPO_RAW="${REPO_URL_OVERRIDE%/}"
    return 0
  fi
  if [ -n "$CLI_SOURCE_CHANNEL" ]; then
    validate_channel "$CLI_SOURCE_CHANNEL" || { err "--channel deve ser stable ou edge"; exit 64; }
    SOURCE_CHANNEL="$CLI_SOURCE_CHANNEL"; SOURCE_KIND="$CLI_SOURCE_CHANNEL"
    [ "$CLI_SOURCE_CHANNEL" = stable ] && SOURCE_REF=stable || SOURCE_REF=main
  elif [ -n "$CLI_SOURCE_VERSION" ]; then
    validate_version "$CLI_SOURCE_VERSION" || { err "versão inválida: $CLI_SOURCE_VERSION"; exit 64; }
    SOURCE_VERSION="$CLI_SOURCE_VERSION"; SOURCE_KIND=version; SOURCE_REF="releases/$CLI_SOURCE_VERSION"
  elif [ -n "$CLI_SOURCE_REF" ]; then
    validate_ref "$CLI_SOURCE_REF" || { err "ref inválida: $CLI_SOURCE_REF"; exit 64; }
    SOURCE_KIND=ref; SOURCE_REF="$CLI_SOURCE_REF"
  elif [ -n "$env_ref" ]; then
    validate_ref "$env_ref" || { err "CANUTO_SOURCE_REF inválida"; exit 64; }
    SOURCE_KIND="${env_kind:-ref}"; SOURCE_REF="$env_ref"; SOURCE_CHANNEL="$env_channel"; SOURCE_VERSION="$env_version"
  elif [ -n "$env_version" ]; then
    validate_version "$env_version" || { err "CANUTO_VERSION inválida"; exit 64; }
    SOURCE_VERSION="$env_version"; SOURCE_KIND=version; SOURCE_REF="releases/$env_version"
  else
    SOURCE_CHANNEL="${env_channel:-stable}"
    validate_channel "$SOURCE_CHANNEL" || { err "CANUTO_CHANNEL deve ser stable ou edge"; exit 64; }
    SOURCE_KIND="$SOURCE_CHANNEL"; [ "$SOURCE_CHANNEL" = stable ] && SOURCE_REF=stable || SOURCE_REF=main
  fi
  validate_ref "$SOURCE_REF" || { err "source ref resolvida é inválida: $SOURCE_REF"; exit 64; }
  REPO_RAW="${REPO_BASE%/}/$SOURCE_REF"
}
receipt_ref() {
  local receipt="$1"
  [ -f "$receipt" ] || return 1
  sed -n 's/^[[:space:]]*"sourceRef":[[:space:]]*"\([^"]*\)".*/\1/p' "$receipt" | head -1
}

'''
update_all = insert_before(update_all, "DRY_RUN=0\n", update_source_helpers, "update-all source helpers")
update_all = replace_once(
    update_all,
    '    --no-commit)\n      [ "$COMMIT_POLICY" != "commit" ] || { err "--no-commit conflita com --commit"; exit 64; }\n      COMMIT=0; COMMIT_POLICY="no-commit"\n      ;;\n    --scan)\n',
    '''    --no-commit)
      [ "$COMMIT_POLICY" != "commit" ] || { err "--no-commit conflita com --commit"; exit 64; }
      COMMIT=0; COMMIT_POLICY="no-commit"
      ;;
    --channel)
      shift; [ -n "${1:-}" ] || { err "--channel exige stable ou edge"; exit 64; }
      set_source_selector channel "$1"
      ;;
    --version)
      shift; [ -n "${1:-}" ] || { err "--version exige semver"; exit 64; }
      set_source_selector version "$1"
      ;;
    --ref)
      shift; [ -n "${1:-}" ] || { err "--ref exige uma ref Git"; exit 64; }
      set_source_selector ref "$1"
      ;;
    --rollback)
      shift; [ -n "${1:-}" ] || { err "--rollback exige semver"; exit 64; }
      ROLLBACK=1
      set_source_selector version "$1"
      ;;
    --scan)
''',
    "update-all source parser",
)
update_all = insert_before(
    update_all,
    "# ── Versão remota (uma busca só para a rodada inteira) ──────────────────────\n",
    "resolve_source\nlog \"source selecionado: $SOURCE_KIND ($SOURCE_REF)\"\n\n",
    "update-all source resolution",
)
update_all = update_all.replace(
    'log "versão remota do framework: $REMOTE_VERSION"',
    'log "versão remota do framework: $REMOTE_VERSION — source: $SOURCE_REF"',
    1,
)
update_all = update_all.replace(
    'err "não consegui obter um install.sh íntegro do main. Abortando sem tocar em nada."',
    'err "não consegui obter um install.sh íntegro de $SOURCE_REF. Abortando sem tocar em nada."',
    1,
)
update_all = replace_once(
    update_all,
    '# O instalador que RODA já é o fresco — ele não precisa se auto-renovar.\nexport CANUTO_BOOTSTRAPPED=1\n',
    '''# O instalador que RODA já é o fresco — ele não precisa se auto-renovar.
export CANUTO_BOOTSTRAPPED=1
export CANUTO_REPO_URL="$REPO_RAW"
export CANUTO_SOURCE_KIND="$SOURCE_KIND"
export CANUTO_SOURCE_REF="$SOURCE_REF"
export CANUTO_SOURCE_CHANNEL="$SOURCE_CHANNEL"
export CANUTO_SOURCE_VERSION="$SOURCE_VERSION"
SOURCE_SUPPORTS_RECEIPT=0
grep -q 'SOURCE-RECEIPT.json' "$FRESH_INSTALLER" 2>/dev/null && SOURCE_SUPPORTS_RECEIPT=1
''',
    "update-all source propagation",
)
update_all = replace_once(
    update_all,
    '''  local_ver="$(head -1 "$proj/.agents/VERSION" 2>/dev/null | tr -d '[:space:]')"
  [ -n "$local_ver" ] || local_ver="?"

  # Trabalho em curso''',
    '''  local_ver="$(head -1 "$proj/.agents/VERSION" 2>/dev/null | tr -d '[:space:]')"
  [ -n "$local_ver" ] || local_ver="?"
  local_ref="$(receipt_ref "$proj/.agents/SOURCE-RECEIPT.json" 2>/dev/null || true)"
  source_current=0
  if [ "$SOURCE_SUPPORTS_RECEIPT" -eq 1 ]; then
    [ "$local_ref" = "$SOURCE_REF" ] && source_current=1
  else
    source_current=1
  fi

  # Trabalho em curso''',
    "update-all local receipt",
)
update_all = update_all.replace(
    'if [ "$local_ver" = "$REMOTE_VERSION" ] && [ "$FORCE" = 0 ]; then',
    'if [ "$local_ver" = "$REMOTE_VERSION" ] && [ "$source_current" -eq 1 ] && [ "$FORCE" = 0 ]; then',
    2,
)
update_all = update_all.replace(
    '"já na versão remota (árvore suja) — $proj"',
    '"já na versão e source remotos (árvore suja; source=$SOURCE_REF) — $proj"',
    1,
)
update_all = update_all.replace(
    '"já na versão remota — $proj"',
    '"já na versão e source remotos (source=$SOURCE_REF) — $proj"',
    1,
)
update_all = update_all.replace(
    'add_report "PENDENTE" "$name" "$local_ver" "$REMOTE_VERSION" "dry-run: atualizaria — $proj"',
    'add_report "PENDENTE" "$name" "$local_ver" "$REMOTE_VERSION" "dry-run: atualizaria $local_ref → $SOURCE_REF — $proj"',
    1,
)
update_all = update_all.replace(
    'log "atualizando $name ($local_ver → $REMOTE_VERSION)…"',
    'log "atualizando $name ($local_ver/$local_ref → $REMOTE_VERSION/$SOURCE_REF)…"',
    1,
)
update_all = replace_once(
    update_all,
    '''    new_ver="$(head -1 "$proj/.agents/VERSION" 2>/dev/null | tr -d '[:space:]')"
    commit_note=""
''',
    '''    new_ver="$(head -1 "$proj/.agents/VERSION" 2>/dev/null | tr -d '[:space:]')"
    new_ref="$(receipt_ref "$proj/.agents/SOURCE-RECEIPT.json" 2>/dev/null || true)"
    receipt_ok=1
    if [ "$SOURCE_SUPPORTS_RECEIPT" -eq 1 ] && [ "$new_ref" != "$SOURCE_REF" ]; then receipt_ok=0; fi
    commit_note=""
''',
    "update-all post-update receipt",
)
update_all = update_all.replace(
    '    if [ "$new_ver" = "$REMOTE_VERSION" ]; then\n',
    '    if [ "$new_ver" = "$REMOTE_VERSION" ] && [ "$receipt_ok" -eq 1 ]; then\n',
    1,
)
update_all = update_all.replace(
    '"log: $plog$commit_note"',
    '"source: ${new_ref:-legacy}/$SOURCE_REF; log: $plog$commit_note"',
    1,
)
update_all = update_all.replace(
    '"instalador aplicado, mas VERSION não chegou a $REMOTE_VERSION — rode de novo (o install.sh do projeto foi renovado nesta rodada); log: $plog$commit_note"',
    '"instalador aplicado, mas VERSION/receipt não convergiu para $REMOTE_VERSION/$SOURCE_REF; obtido ${new_ver:-?}/${new_ref:-ausente}; log: $plog$commit_note"',
    1,
)
update_all = update_all.replace(
    'echo -e "${CYAN}━━━ canuto update-all — relatório (remoto: $REMOTE_VERSION) ━━━${RESET}"',
    'echo -e "${CYAN}━━━ canuto update-all — relatório ($SOURCE_KIND:$SOURCE_REF, versão: $REMOTE_VERSION) ━━━${RESET}"',
    1,
)
write(".agents/tools/canuto-update-all.sh", update_all)

# ---------------------------------------------------------------------------
# Consumer smoke, docs, ADR
# ---------------------------------------------------------------------------
smoke = read(".agents/tools/canuto-consumer-smoke.sh")
smoke_marker = 'if [ -d "$ROOT_DIR/.agents/tmp" ]; then\n'
smoke_block = r'''if [ -f "$ROOT_DIR/.agents/SOURCE-RECEIPT.json" ] \
  && python3 - "$ROOT_DIR/.agents/SOURCE-RECEIPT.json" <<'PYEOF' >/dev/null 2>&1
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    receipt = json.load(fh)
assert receipt.get("schemaVersion") == 1
assert receipt.get("scope") == "framework"
assert receipt.get("sourceRef")
assert receipt.get("manifestSha256")
PYEOF
then
  pass "framework source receipt is structurally valid"
else
  warn "framework source receipt missing or invalid (legacy consumer)"
fi

'''
smoke = insert_before(smoke, smoke_marker, smoke_block, "consumer source receipt")
write(".agents/tools/canuto-consumer-smoke.sh", smoke)

readme = read("README.md")
readme = readme.replace(
    "curl -fsSL https://raw.githubusercontent.com/csorodrigo/canuto-framework/main/install.sh | bash",
    "curl -fsSL https://raw.githubusercontent.com/csorodrigo/canuto-framework/stable/install.sh | bash",
    1,
)
source_docs = '''
### Release channels, pinning and rollback

The default source is **`stable`**. `main` is the explicit **edge** channel:

```bash
bash install.sh --update                    # stable
bash install.sh --update --channel edge     # main
bash install.sh --update --version 1.8.0    # releases/1.8.0
bash install.sh --update --ref <commit-sha> # exact pin
bash install.sh --rollback 1.7.0            # explicit rollback
```

A full install/update writes `.agents/SOURCE-RECEIPT.json`, binding the selected
ref and framework version to a deterministic SHA-256 manifest of the installed
framework files. `canuto-update-all.sh` compares both version and source ref, so
switching from stable to edge (or between pinned releases with equal version
text) is not reported as already current.

'''
needle = "### Update an existing project that already uses Canuto\n"
if needle not in readme:
    raise SystemExit("README update heading not found")
readme = readme.replace(needle, source_docs + needle, 1)
write("README.md", readme)

feature = read("docs/FEATURE-MAP.md")
feature = feature.replace(
    "| Update flow | implemented | `install.sh --update` | Refreshes installer logic, applies framework updates, and never treats `--yes` as commit authorization |",
    "| Update flow | implemented | `install.sh --update` | Defaults to `stable`; supports explicit edge, release/version and exact-ref pinning; never treats `--yes` as commit authorization |",
    1,
)
feature = feature.replace(
    "| Consumer smoke test | implemented | `install.sh --test`, `.agents/tools/canuto-consumer-smoke.sh` | Validates project-facing install state |",
    "| Consumer smoke test | implemented | `install.sh --test`, `.agents/tools/canuto-consumer-smoke.sh` | Validates project-facing install state and source receipt structure |",
    1,
)
write("docs/FEATURE-MAP.md", feature)

write(
    "docs/adr/0017-stable-edge-e-source-receipt.md",
    """# ADR-0017 — Stable por padrão, edge explícito e source receipt\n\nData: 2026-08-23 · Status: aceito\n\n## Contexto\n\nO instalador e o update multi-projeto baixavam diretamente de `main`. Um merge\nrecém-publicado podia alcançar vários consumidores antes de canário e, como\nversão textual e source ref eram estados comprimidos, dois conteúdos distintos\npodiam parecer igualmente atualizados.\n\n## Decisão\n\n- `stable` é o canal padrão; `edge` resolve explicitamente para `main`.\n- `--version X` resolve para `releases/X`; `--ref` aceita pin exato.\n- `--rollback X` é update explícito a partir de `releases/X`.\n- O bootstrap remove os seletores da argv do instalador filho e propaga o\n  endpoint/ref por ambiente, mantendo compatibilidade com instaladores antigos.\n- Install/update completos gravam `.agents/SOURCE-RECEIPT.json` de forma\n  atômica e determinística, com source ref, versão e digest SHA-256 do manifesto.\n- `update-all` compara versão e receipt; source divergente não é `OK`.\n- URL customizada continua suportada, mas não pode ser combinada com seletor\n  CLI porque isso produziria provenance ambígua.\n\n## Consequências\n\n- (+) `main` deixa de ser rollout implícito.\n- (+) pin e rollback não dependem do estado atual de `main`.\n- (+) provenance fica verificável e idempotente.\n- (-) a branch `stable` e os refs `releases/*` passam a exigir promoção\n  deliberada depois dos receipts de CI/canário.\n""",
)

# ---------------------------------------------------------------------------
# Regression tests (Test 22)
# ---------------------------------------------------------------------------
tests = read("test-framework.sh")
summary_marker = "# ═══════════════════════════════════════════════════════════════════════════\n# SUMMARY\n"
if summary_marker not in tests:
    raise SystemExit("test summary marker not found")

test22 = r'''# ═══════════════════════════════════════════════════════════════════════════
# TEST 22: Stable/edge, pinning e source receipts (ADR-0017)
# ═══════════════════════════════════════════════════════════════════════════
echo "── Test 22: Stable/edge e source receipts ──"

SOURCE_ROOT=$(mktemp -d)
SOURCE_HOME="$SOURCE_ROOT/home"
SOURCE_EMPTY="$SOURCE_ROOT/empty"
mkdir -p "$SOURCE_HOME" "$SOURCE_EMPTY"

assert_dry_source() {
  local expected_kind="$1" expected_ref="$2"
  shift 2
  local output rc=0
  output=$(cd "$SOURCE_EMPTY" && HOME="$SOURCE_HOME" /bin/bash "$FRAMEWORK_DIR/install.sh" --dry-run "$@" 2>&1) || rc=$?
  if [ "$rc" -eq 0 ] \
    && grep -q "^source_kind=$expected_kind$" <<< "$output" \
    && grep -q "^source_ref=$expected_ref$" <<< "$output" \
    && [ -z "$(find "$SOURCE_EMPTY" -mindepth 1 -print -quit)" ]; then
    pass "22a source $expected_kind resolve para $expected_ref sem mutação"
  else
    fail "22a source $expected_kind não resolveu para $expected_ref (rc=$rc): $output"
  fi
}

assert_dry_source stable stable --update
assert_dry_source edge main --update --channel edge
assert_dry_source version releases/1.8.0 --update --version 1.8.0
assert_dry_source ref 0123456789abcdef0123456789abcdef01234567 --update --ref 0123456789abcdef0123456789abcdef01234567
ROLLBACK_OUT=$(cd "$SOURCE_EMPTY" && HOME="$SOURCE_HOME" /bin/bash "$FRAMEWORK_DIR/install.sh" --dry-run --rollback 1.7.0 2>&1 || true)
if grep -q '^mode=update$' <<< "$ROLLBACK_OUT" \
   && grep -q '^source_ref=releases/1.7.0$' <<< "$ROLLBACK_OUT" \
   && grep -q '^rollback=true$' <<< "$ROLLBACK_OUT"; then
  pass "22b rollback resolve release fixado e modo update"
else
  fail "22b rollback não resolveu release/mode: $ROLLBACK_OUT"
fi

for SOURCE_CASE in bad-channel bad-version bad-ref selector-conflict custom-conflict; do
  SOURCE_RC=0
  case "$SOURCE_CASE" in
    bad-channel) SOURCE_ARGS=(--dry-run --update --channel beta); SOURCE_ENV=() ;;
    bad-version) SOURCE_ARGS=(--dry-run --update --version latest); SOURCE_ENV=() ;;
    bad-ref) SOURCE_ARGS=(--dry-run --update --ref ../main); SOURCE_ENV=() ;;
    selector-conflict) SOURCE_ARGS=(--dry-run --update --channel edge --version 1.8.0); SOURCE_ENV=() ;;
    custom-conflict) SOURCE_ARGS=(--dry-run --update --channel edge); SOURCE_ENV=(CANUTO_REPO_URL=https://example.invalid/canuto) ;;
  esac
  (cd "$SOURCE_EMPTY" && env HOME="$SOURCE_HOME" "${SOURCE_ENV[@]}" /bin/bash "$FRAMEWORK_DIR/install.sh" "${SOURCE_ARGS[@]}" >/dev/null 2>&1) || SOURCE_RC=$?
  if [ "$SOURCE_RC" -eq 64 ] && [ -z "$(find "$SOURCE_EMPTY" -mindepth 1 -print -quit)" ]; then
    pass "22c parser rejeita $SOURCE_CASE antes de mutar"
  else
    fail "22c parser $SOURCE_CASE retornou $SOURCE_RC ou criou artefatos"
  fi
done

RECEIPT_REPO="$SOURCE_ROOT/receipt"
mkdir -p "$RECEIPT_REPO/.agents"
printf '1.8.0\n' > "$RECEIPT_REPO/.agents/VERSION"
printf 'alpha\n' > "$RECEIPT_REPO/a.txt"
printf 'beta\n' > "$RECEIPT_REPO/b.txt"
if (
  cd "$RECEIPT_REPO"
  export HOME="$SOURCE_HOME" CANUTO_INSTALL_LIBRARY_ONLY=1
  source "$FRAMEWORK_DIR/install.sh"
  FRAMEWORK_FILES=(a.txt b.txt)
  SOURCE_KIND=edge; SOURCE_REF=main; SOURCE_CHANNEL=edge; SOURCE_VERSION=""; SOURCE_TRANSPORT=local
  write_source_receipt .agents/SOURCE-RECEIPT.json framework update "${FRAMEWORK_FILES[@]}"
  FIRST_HASH=$(sha256_file .agents/SOURCE-RECEIPT.json)
  write_source_receipt .agents/SOURCE-RECEIPT.json framework update "${FRAMEWORK_FILES[@]}"
  SECOND_HASH=$(sha256_file .agents/SOURCE-RECEIPT.json)
  [ "$FIRST_HASH" = "$SECOND_HASH" ]
  rm -rf "$TMP_DIR"
); then
  if python3 - "$RECEIPT_REPO/.agents/SOURCE-RECEIPT.json" <<'PYEOF'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    r = json.load(fh)
assert r["schemaVersion"] == 1
assert r["scope"] == "framework"
assert r["sourceKind"] == "edge"
assert r["sourceRef"] == "main"
assert r["frameworkVersion"] == "1.8.0"
assert r["fileCount"] == 2
assert len(r["manifestSha256"]) == 64
PYEOF
  then
    pass "22d source receipt é atômico, determinístico e estruturalmente válido"
  else
    fail "22d source receipt JSON inválido"
  fi
else
  fail "22d source receipt não foi idempotente"
fi

UPDATE_SOURCE="$SOURCE_ROOT/update-source"
UPDATE_TMP="$SOURCE_ROOT/update-tmp"
mkdir -p "$UPDATE_SOURCE/.agents" "$UPDATE_TMP"
printf '9.9.9\n' > "$UPDATE_SOURCE/.agents/VERSION"
cat > "$UPDATE_SOURCE/install.sh" <<'STUBEOF'
#!/usr/bin/env bash
# SOURCE-RECEIPT.json support marker
printf '%s|%s|%s|%s\n' "${CANUTO_SOURCE_KIND:-}" "${CANUTO_SOURCE_REF:-}" "${CANUTO_SOURCE_CHANNEL:-}" "${CANUTO_SOURCE_VERSION:-}" > .captured-source
mkdir -p .agents
printf '9.9.9\n' > .agents/VERSION
python3 - <<'PYEOF'
import json, os
with open('.agents/SOURCE-RECEIPT.json', 'w', encoding='utf-8') as fh:
    json.dump({'schemaVersion': 1, 'scope': 'framework', 'sourceRef': os.environ.get('CANUTO_SOURCE_REF', '')}, fh)
    fh.write('\n')
PYEOF
STUBEOF
chmod +x "$UPDATE_SOURCE/install.sh"

make_source_consumer() {
  local repo="$1" version="$2" receipt_ref_value="$3"
  mkdir -p "$repo/.agents"
  git -C "$repo" init -q
  git -C "$repo" config user.name "Canuto Source Test"
  git -C "$repo" config user.email "source@example.invalid"
  printf '%s\n' "$version" > "$repo/.agents/VERSION"
  if [ -n "$receipt_ref_value" ]; then
    printf '{"schemaVersion":1,"scope":"framework","sourceRef":"%s"}\n' "$receipt_ref_value" > "$repo/.agents/SOURCE-RECEIPT.json"
  fi
  git -C "$repo" add .agents
  git -C "$repo" commit -q -m "test: source consumer"
}

EDGE_REPO="$SOURCE_ROOT/edge-consumer"
make_source_consumer "$EDGE_REPO" 9.9.9 stable
if CANUTO_SOURCE_DIR="$UPDATE_SOURCE" CANUTO_VAULT_DIR="$SOURCE_ROOT/empty-vault" TMPDIR="$UPDATE_TMP" \
   /bin/bash "$FRAMEWORK_DIR/.agents/tools/canuto-update-all.sh" --channel edge "$EDGE_REPO" >/dev/null 2>&1 \
   && [ "$(cat "$EDGE_REPO/.captured-source")" = "edge|main|edge|" ]; then
  pass "22e update-all troca source mesmo com VERSION igual"
else
  fail "22e update-all não propagou edge/main ou pulou por VERSION igual"
fi

ROLLBACK_REPO="$SOURCE_ROOT/rollback-consumer"
make_source_consumer "$ROLLBACK_REPO" 1.0.0 main
if CANUTO_SOURCE_DIR="$UPDATE_SOURCE" CANUTO_VAULT_DIR="$SOURCE_ROOT/empty-vault" TMPDIR="$UPDATE_TMP" \
   /bin/bash "$FRAMEWORK_DIR/.agents/tools/canuto-update-all.sh" --rollback 1.7.0 "$ROLLBACK_REPO" >/dev/null 2>&1 \
   && [ "$(cat "$ROLLBACK_REPO/.captured-source")" = "version|releases/1.7.0||1.7.0" ]; then
  pass "22f update-all propaga rollback fixado"
else
  fail "22f update-all não propagou rollback fixado"
fi

rm -rf "$SOURCE_ROOT"
echo ""
'''
if "TEST 22: Stable/edge" not in tests:
    tests = tests.replace(summary_marker, test22 + summary_marker, 1)
write("test-framework.sh", tests)

print("source channels and receipts applied")
