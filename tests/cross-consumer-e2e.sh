#!/usr/bin/env bash
set -euo pipefail

FRAMEWORK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE_SHA="${CANUTO_E2E_SOURCE_SHA:-$(git -C "$FRAMEWORK_DIR" rev-parse HEAD)}"
E2E_ROOT=$(mktemp -d)
E2E_HOME="$E2E_ROOT/home"
mkdir -p "$E2E_HOME"

export HOME="$E2E_HOME"
export CANUTO_INSTALL_LIBRARY_ONLY=1
export CANUTO_SOURCE_DIR="$FRAMEWORK_DIR"
export CANUTO_SOURCE_KIND=ref
export CANUTO_SOURCE_REF="$SOURCE_SHA"
export CANUTO_SOURCE_TRANSPORT=local
export CANUTO_BOOTSTRAPPED=1
# shellcheck source=/dev/null
source "$FRAMEWORK_DIR/install.sh"
unset CANUTO_INSTALL_LIBRARY_ONLY

cleanup() {
  rm -rf "$E2E_ROOT"
  [ -n "${TMP_DIR:-}" ] && rm -rf "$TMP_DIR"
}
trap cleanup EXIT

fail() {
  echo "cross-consumer-e2e: FAIL: $*" >&2
  exit 1
}

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

copy_declared_files() {
  local destination="$1" file=""
  for file in "${FRAMEWORK_FILES[@]}" "${INSTALL_ONLY_FILES[@]}"; do
    [ -f "$FRAMEWORK_DIR/$file" ] || fail "declared source missing: $file"
    mkdir -p "$destination/$(dirname "$file")"
    cp -p "$FRAMEWORK_DIR/$file" "$destination/$file"
  done
}

build_consumer() {
  local destination="$1" slug="$2" unique_rule="$3"
  local vault_dir=""

  mkdir -p "$destination"
  git -C "$destination" init -q
  git -C "$destination" config user.name "Canuto Cross Consumer"
  git -C "$destination" config user.email "cross-consumer@example.invalid"
  copy_declared_files "$destination"

  cat > "$destination/CLAUDE.md" <<EOF
# $slug

project-slug: $slug

## Project Rules
- $unique_rule
EOF
  cat > "$destination/AGENTS.md" <<EOF
# $slug agents

## Product Notes
- $unique_rule
EOF
  printf '# %s context\n\nConsumer-specific context.\n' "$slug" > "$destination/.context.md"
  printf '# %s product\n' "$slug" > "$destination/product.md"
  printf '# Consumer-local ignores\n.agents/tmp/\n.agents/.cache/\n.agents/vault/events/\n' > "$destination/.gitignore"

  mkdir -p "$destination/.agents/plugins" "$destination/.agents/tmp" "$destination/.agents/vault/digests"
  touch "$destination/.agents/plugins/.gitkeep"
  for vault_dir in "${VAULT_DIRS[@]}"; do
    mkdir -p "$destination/$vault_dir"
    touch "$destination/$vault_dir/.gitkeep"
  done
  printf '# E2E digest\n\nslug: %s\n' "$slug" > "$destination/.agents/vault/digests/e2e.md"

  (
    cd "$destination"
    CLAUDE_MD=CLAUDE.md
    merge_claude_md >/dev/null
    merge_agents_md >/dev/null
    ensure_shared_operating_contract_reference "$CLAUDE_MD" >/dev/null
    ensure_shared_operating_contract_reference "AGENTS.md" >/dev/null
    ensure_project_bootstrap_files >/dev/null
    render_codex_md >/dev/null
    setup_local_script_permissions
    write_source_receipt .agents/SOURCE-RECEIPT.json framework install "${FRAMEWORK_FILES[@]}" >/dev/null
  )

  grep -qF -- "- $unique_rule" "$destination/CODEX.md" || fail "$slug rule missing from rendered CODEX.md"
  grep -qF "project-slug: $slug" "$destination/CLAUDE.md" || fail "$slug identity not preserved"
  git -C "$destination" add -A
  git -C "$destination" commit -q -m "test: build $slug consumer"
}

assert_consumer_green() {
  local destination="$1"
  local slug="$2"
  local smoke_json="$E2E_ROOT/$slug-smoke.json"
  local check_log="$E2E_ROOT/$slug-check.log"

  local smoke_rc=0
  local smoke_parse_rc=0
  HOME="$E2E_HOME" CLAUDE_PROJECT_DIR="$destination" \
    /bin/bash "$destination/.agents/tools/canuto-consumer-smoke.sh" --json > "$smoke_json" \
    || smoke_rc=$?
  if [ "$smoke_rc" -ne 0 ]; then
    cat "$smoke_json" >&2 || true
    fail "$slug consumer smoke failed (rc=$smoke_rc)"
  fi
  python3 - "$smoke_json" <<'PYEOF' || smoke_parse_rc=$?
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    result = json.load(fh)
assert result["verdict"] == "HEALTHY", result
assert result["counts"]["fail"] == 0, result
PYEOF
  if [ "$smoke_parse_rc" -ne 0 ]; then
    cat "$smoke_json" >&2 || true
    fail "$slug consumer smoke was not HEALTHY"
  fi

  (
    cd "$destination"
    HOME="$E2E_HOME" \
    CANUTO_SOURCE_DIR="$FRAMEWORK_DIR" \
    CANUTO_SOURCE_KIND=ref \
    CANUTO_SOURCE_REF="$SOURCE_SHA" \
    CANUTO_SOURCE_TRANSPORT=local \
    CANUTO_BOOTSTRAPPED=1 \
      /bin/bash install.sh --check
  ) > "$check_log" 2>&1 || {
    cat "$check_log" >&2
    fail "$slug pinned source check failed"
  }
  if ! grep -q "All framework files are up to date" "$check_log"; then
    cat "$check_log" >&2 || true
    fail "$slug check lacked green receipt"
  fi
}

assert_idempotent() {
  local destination="$1" slug="$2"
  (
    cd "$destination"
    CLAUDE_MD=CLAUDE.md
    merge_claude_md >/dev/null
    merge_agents_md >/dev/null
    ensure_shared_operating_contract_reference "$CLAUDE_MD" >/dev/null
    ensure_shared_operating_contract_reference "AGENTS.md" >/dev/null
    ensure_project_bootstrap_files >/dev/null
    render_codex_md >/dev/null
    setup_local_script_permissions
    write_source_receipt .agents/SOURCE-RECEIPT.json framework install "${FRAMEWORK_FILES[@]}" >/dev/null
  )
  [ -z "$(git -C "$destination" status --porcelain)" ] || {
    git -C "$destination" status --short >&2
    fail "$slug second render/receipt was not idempotent"
  }
}

assert_dirty_refusal() {
  local destination="$1" slug="$2" before_head before_receipt output rc=0
  before_head=$(git -C "$destination" rev-parse HEAD)
  before_receipt=$(hash_file "$destination/.agents/SOURCE-RECEIPT.json")
  printf '\ntracked user WIP\n' >> "$destination/product.md"
  output=$(
    cd "$destination"
    HOME="$E2E_HOME" \
    CANUTO_SOURCE_DIR="$FRAMEWORK_DIR" \
    CANUTO_SOURCE_KIND=ref \
    CANUTO_SOURCE_REF="$SOURCE_SHA" \
    CANUTO_SOURCE_TRANSPORT=local \
    CANUTO_BOOTSTRAPPED=1 \
      /bin/bash install.sh --update --yes </dev/null 2>&1
  ) || rc=$?
  [ "$rc" -ne 0 ] || fail "$slug dirty update unexpectedly succeeded"
  grep -q "Refusing --update in a dirty worktree" <<< "$output" || fail "$slug dirty refusal was not explicit"
  [ "$(git -C "$destination" rev-parse HEAD)" = "$before_head" ] || fail "$slug dirty refusal changed HEAD"
  [ "$(hash_file "$destination/.agents/SOURCE-RECEIPT.json")" = "$before_receipt" ] || fail "$slug dirty refusal changed receipt"
  grep -q "tracked user WIP" "$destination/product.md" || fail "$slug dirty refusal lost user WIP"
  git -C "$destination" checkout -- product.md
}

CONSUMER_A="$E2E_ROOT/consumer-alpha"
CONSUMER_B="$E2E_ROOT/consumer beta with space"
build_consumer "$CONSUMER_A" "consumer-alpha-e2e" "Alpha keeps compact domain rules."
build_consumer "$CONSUMER_B" "consumer-beta-e2e" "Beta preserves its own spaced-path rules."

[ "$(hash_file "$CONSUMER_A/CODEX.md")" != "$(hash_file "$CONSUMER_B/CODEX.md")" ] \
  || fail "two consumers rendered identical CODEX.md despite different project rules"

assert_consumer_green "$CONSUMER_A" alpha
assert_consumer_green "$CONSUMER_B" beta
assert_idempotent "$CONSUMER_A" alpha
assert_idempotent "$CONSUMER_B" beta
assert_dirty_refusal "$CONSUMER_A" alpha
assert_dirty_refusal "$CONSUMER_B" beta

echo "cross-consumer-e2e: PASS ($SOURCE_SHA)"
