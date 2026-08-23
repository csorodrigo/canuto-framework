#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION = "1.8.0"


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


# Canonical version and release metadata -------------------------------------
write(".agents/VERSION", f"{VERSION}\n")

release_manifest = {
    "schemaVersion": 1,
    "version": VERSION,
    "releaseRef": f"releases/{VERSION}",
    "channels": {
        "stable": "refs/heads/stable",
        "edge": "refs/heads/main",
        "release": f"refs/heads/releases/{VERSION}",
    },
    "requiredReceipts": [
        {
            "id": "framework-suite",
            "platforms": ["ubuntu-latest", "macos-14"],
            "finalShaRequired": True,
        },
        {
            "id": "skill-gardener-suite",
            "platforms": ["ubuntu-latest", "macos-14"],
            "finalShaRequired": True,
        },
        {
            "id": "cross-consumer-e2e",
            "consumers": 2,
            "requirements": [
                "different-project-slugs",
                "path-with-space",
                "rendered-codex-divergence",
                "source-receipt",
                "check-idempotency",
                "dirty-tree-refusal",
            ],
        },
        {
            "id": "vault-integrity",
            "checks": ["references", "orphans"],
        },
    ],
    "promotion": {
        "order": ["main", f"releases/{VERSION}", "stable"],
        "stableRequires": [
            "main-matrix-green",
            "release-matrix-green",
            "cross-consumer-green",
            "final-sha-consistent",
        ],
        "rollback": "bash install.sh --rollback <version>",
        "strongestPin": "bash install.sh --update --ref <commit-sha>",
    },
}
write("distribution/release.json", json.dumps(release_manifest, indent=2) + "\n")

promotion_doc = f"""# Canuto release promotion\n\nCurrent release: **v{VERSION}**.\n\n## Channels\n\n- `main` is **edge**. A merge makes the change available only to callers that\n  explicitly select `--channel edge` or pin that SHA.\n- `releases/{VERSION}` is the release branch for this version.\n- `stable` is the default source used by the installer. It moves only after the\n  release branch has passed the same final-SHA checks.\n\n## Promotion order\n\n1. Merge the reviewed PR into `main`.\n2. Require the Ubuntu and macOS matrix, the complete framework suite, Skill\n   Gardener suite, cross-consumer E2E, and vault integrity checks to pass on the\n   merge SHA.\n3. Create or fast-forward `releases/{VERSION}` to that exact SHA.\n4. Require the release-branch matrix to pass.\n5. Fast-forward `stable` to the same SHA. Never promote a different rebuild.\n6. Require the stable-branch matrix to pass and record the SHA in the release\n   notes.\n\n## Pinning and rollback\n\n```bash\nbash install.sh --update                    # stable\nbash install.sh --update --channel edge     # main\nbash install.sh --update --version {VERSION}    # releases/{VERSION}\nbash install.sh --update --ref <commit-sha> # strongest pin\nbash install.sh --rollback <version>        # explicit release rollback\n```\n\nBranches are movable Git refs. The exact SHA is the strongest provenance.\n`canuto-update-all.sh` therefore runs the complete `--check` before reporting a\nconsumer as current, even when its version and source-ref receipt already match.\n\n## Failure policy\n\n- A failed platform, consumer, reference, orphan, or source-receipt check blocks\n  promotion.\n- Do not force-update `stable` over a non-fast-forward history.\n- Do not describe a release as promoted until `main`, the release branch, and\n  `stable` all point to the same green SHA.\n"""
write("docs/RELEASE-PROMOTION.md", promotion_doc)

# Single version in user-facing summaries -----------------------------------
readme = read("README.md")
readme = replace_once(readme, "# Canuto Framework v1.6\n", "# Canuto Framework v1.8\n", "README title")
readme = replace_once(
    readme,
    "This release keeps the v1.6 Obsidian-native runtime and adds a sharper learning-loop layer: project diagnosis, rework detection, session-end learning, pending triage, and safe vault write-back preview.\n",
    "Version 1.8 hardens the operational platform: machine-blind defaults, explicit Git consent, stable/edge source pinning, deterministic receipts, and cross-platform consumer validation now sit alongside the Obsidian-native learning loop.\n",
    "README release summary",
)
readme = readme.replace(
    "`bash install.sh --update` is now the standard path. The installer refreshes itself from `main` before applying the update, so it still works even if the local `install.sh` is stale.",
    "`bash install.sh --update` is the standard stable path. The installer refreshes itself from the selected source ref before applying the update, so a stale local copy does not silently choose another channel.",
)
if "docs/RELEASE-PROMOTION.md" not in readme:
    docs_marker = "- [`registry.md`](registry.md): core, optional, and global skill registry.\n"
    readme = replace_once(
        readme,
        docs_marker,
        docs_marker + "- [`docs/RELEASE-PROMOTION.md`](docs/RELEASE-PROMOTION.md): stable/edge promotion, pinning, receipts, and rollback.\n",
        "README release docs link",
    )
write("README.md", readme)

summary = f"""# Canuto Framework v1.8 Summary\n\nCanuto is a multi-agent operating framework for AI-assisted software work. It\nshares one operational contract across Claude and Codex, preserves project WIP,\nuses an Obsidian-native two-tier memory, and records lifecycle evidence in an\nappend-only event log.\n\n## Runtime flow\n\n```text\nMaestro → Architect → Coder → Reviewer\n                  ↘ /test or /fix when deeper validation is needed\n```\n\nThe active personas are Maestro, Architect, Coder, Reviewer, Contextualizer, and\nInvestigator. Tester and Debugger remain archived; their workflows are covered\nby explicit test/fix paths rather than always-loaded personas.\n\n## v1.8 operational guarantees\n\n- Distributed defaults contain no machine-specific projects, users, hosts, or\n  workspace paths. Effective Skill Gardener configuration belongs only to the\n  local machine and valid local bytes are preserved.\n- `--yes` confirms operational prompts but never authorizes staging or commit.\n  Only `--commit` can create a framework commit, and it uses declared paths\n  without absorbing unrelated staging.\n- `stable` is the default distribution channel; `main` is explicit edge.\n  Version, release-ref, exact-SHA pinning, and rollback are supported.\n- Install/update publish deterministic source receipts. The multi-project updater\n  verifies complete content before reporting a consumer as current.\n- The final release gate runs on Ubuntu and macOS with `/bin/bash`, plus two\n  distinct consumer fixtures including a path with spaces and different rendered\n  `CODEX.md` outputs.\n\n## Memory and evidence\n\n- Hypothesis tier: sessions, metrics, pending tasks, and low-confidence instinct\n  candidates may be written mechanically.\n- Curated tier: decisions and promoted instincts require explicit human approval.\n- `events/log.jsonl` is the session-event source of truth; notes and dashboards\n  are projections.\n- Code, test, commit, push, PR, merge, deploy, and runtime health remain separate\n  states with separate receipts.\n\n## Release usage\n\n```bash\nbash install.sh --update                    # stable\nbash install.sh --update --channel edge     # main\nbash install.sh --update --version {VERSION}    # pinned release\nbash install.sh --update --ref <commit-sha> # exact pin\nbash install.sh --rollback <version>        # rollback\n```\n\nPromotion and rollback policy: [`docs/RELEASE-PROMOTION.md`](docs/RELEASE-PROMOTION.md).\n"""
write("SUMMARY.md", summary)

# Stable URL in current operational tutorials, not in historical ADR/vault data.
stable_url = "https://raw.githubusercontent.com/csorodrigo/canuto-framework/stable/install.sh"
main_url = "https://raw.githubusercontent.com/csorodrigo/canuto-framework/main/install.sh"
for rel in ["README.md", "SUMMARY.md", "TUTORIAL.md", ".agents/TUTORIAL.md", "docs/TUTORIAL.md", "docs/TROUBLESHOOTING.md"]:
    target = ROOT / rel
    if target.exists():
        text = target.read_text(encoding="utf-8").replace(main_url, stable_url)
        target.write_text(text, encoding="utf-8")

# Ship release metadata/policy to consumers ---------------------------------
install_path = ROOT / "install.sh"
install = install_path.read_text(encoding="utf-8")
match = re.search(r"(?ms)^FRAMEWORK_FILES=\(\n(?P<body>.*?)^\)\n", install)
if not match:
    raise SystemExit("FRAMEWORK_FILES block not found")
body = match.group("body")
for entry in ["distribution/release.json", "docs/RELEASE-PROMOTION.md"]:
    quoted = f'  "{entry}"\n'
    if quoted not in body:
        body += quoted
install = install[: match.start("body")] + body + install[match.end("body") :]
install_path.write_text(install, encoding="utf-8")

# Cross-consumer E2E ---------------------------------------------------------
cross_consumer = r'''#!/usr/bin/env bash
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
    render_codex_md >/dev/null
    write_source_receipt .agents/SOURCE-RECEIPT.json framework install "${FRAMEWORK_FILES[@]}" >/dev/null
  )

  grep -qF -- "- $unique_rule" "$destination/CODEX.md" || fail "$slug rule missing from rendered CODEX.md"
  grep -qF "project-slug: $slug" "$destination/CLAUDE.md" || fail "$slug identity not preserved"
  git -C "$destination" add -A
  git -C "$destination" commit -q -m "test: build $slug consumer"
}

assert_consumer_green() {
  local destination="$1" slug="$2" smoke_json="$E2E_ROOT/$slug-smoke.json" check_log="$E2E_ROOT/$slug-check.log"

  HOME="$E2E_HOME" CLAUDE_PROJECT_DIR="$destination" \
    /bin/bash "$destination/.agents/tools/canuto-consumer-smoke.sh" --json > "$smoke_json" \
    || fail "$slug consumer smoke failed"
  python3 - "$smoke_json" <<'PYEOF' || fail "$slug consumer smoke was not HEALTHY"
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    result = json.load(fh)
assert result["verdict"] == "HEALTHY", result
assert result["counts"]["fail"] == 0, result
PYEOF

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
  grep -q "All framework files are up to date" "$check_log" || fail "$slug check lacked green receipt"
}

assert_idempotent() {
  local destination="$1" slug="$2"
  (
    cd "$destination"
    CLAUDE_MD=CLAUDE.md
    merge_claude_md >/dev/null
    merge_agents_md >/dev/null
    render_codex_md >/dev/null
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
'''
write("tests/cross-consumer-e2e.sh", cross_consumer)

# Final CI matrix -------------------------------------------------------------
workflow = r'''name: Validate Framework

on:
  pull_request:
    branches: [main]
  push:
    branches:
      - main
      - stable
      - 'releases/**'
  workflow_dispatch:

permissions:
  contents: read

jobs:
  validate:
    name: validate (${{ matrix.os }})
    strategy:
      fail-fast: false
      matrix:
        os:
          - ubuntu-latest
          - macos-14
    runs-on: ${{ matrix.os }}
    timeout-minutes: 45
    defaults:
      run:
        shell: /bin/bash --noprofile --norc -e -o pipefail {0}

    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Install dependencies
        run: |
          if [ "$RUNNER_OS" = "Linux" ]; then
            sudo apt-get update -qq
            sudo apt-get install -y -qq jq
          elif ! command -v jq >/dev/null 2>&1; then
            brew install jq
          fi
          /bin/bash --version | head -1
          node --version
          jq --version

      - name: Syntax check all shell scripts
        run: |
          echo "── Checking shell script syntax with /bin/bash ──"
          errors=0
          while IFS= read -r script; do
            if /bin/bash -n "$script"; then
              echo "  ✓ $script"
            else
              echo "  ✗ $script"
              errors=$((errors + 1))
            fi
          done < <(find . -name "*.sh" -type f -not -path './.git/*' | LC_ALL=C sort)
          [ "$errors" -eq 0 ]

      - name: Validate skill frontmatter
        run: |
          errors=0
          while IFS= read -r skill; do
            name=$(basename "$skill")
            [ "$name" = "CLAUDE.md" ] && continue
            first=$(head -1 "$skill")
            if echo "$first" | grep -q '^shortDescription:'; then
              :
            elif [ "$first" = "---" ] && awk '
                NR == 1 { next }
                /^---$/ { closed = 1; exit (found && closed ? 0 : 1) }
                /^(shortDescription|description|skill):/ { found = 1 }
                END { exit (found && closed ? 0 : 1) }
              ' "$skill"; then
              :
            else
              echo "missing frontmatter: $skill"
              errors=$((errors + 1))
            fi
          done < <(find .agents/skills -type f -name '*.md' -not -path '*/_archive/*' | LC_ALL=C sort)
          [ "$errors" -eq 0 ]

      - name: Run focused Node suites
        run: |
          node --test skill-gardener/canuto-skill-gardener.test.js
          node --test .agents/tools/framework-session-audit.test.js

      - name: Run complete framework gate
        run: /bin/bash test-framework.sh --verbose

      - name: Run two-consumer E2E
        env:
          CANUTO_E2E_SOURCE_SHA: ${{ github.sha }}
        run: /bin/bash tests/cross-consumer-e2e.sh

      - name: Pinned source check
        env:
          CANUTO_SOURCE_DIR: ${{ github.workspace }}
          CANUTO_SOURCE_KIND: ref
          CANUTO_SOURCE_REF: ${{ github.sha }}
          CANUTO_SOURCE_TRANSPORT: local
          CANUTO_BOOTSTRAPPED: '1'
        run: /bin/bash install.sh --check

      - name: Check vault references
        run: /bin/bash .agents/hooks/check-references.sh

      - name: Check vault orphans
        run: /bin/bash .agents/hooks/check-orphans.sh
'''
write(".github/workflows/validate-framework.yml", workflow)

# Regression gate for version/release/CI consistency -------------------------
tests_path = ROOT / "test-framework.sh"
tests = tests_path.read_text(encoding="utf-8")
summary_marker = "# ═══════════════════════════════════════════════════════════════════════════\n# SUMMARY\n"
if summary_marker not in tests:
    raise SystemExit("test-framework SUMMARY marker not found")

test23 = r'''# ═══════════════════════════════════════════════════════════════════════════
# TEST 23: Release v1.8.0 e prova cross-platform
# ═══════════════════════════════════════════════════════════════════════════
echo "── Test 23: Release v1.8.0 e prova cross-platform ──"

RELEASE_VERSION=$(tr -d '[:space:]' < "$FRAMEWORK_DIR/.agents/VERSION")
MANIFEST_VERSION=$(python3 - "$FRAMEWORK_DIR/distribution/release.json" <<'PYEOF'
import json, sys
with open(sys.argv[1], encoding="utf-8") as fh:
    print(json.load(fh)["version"])
PYEOF
)
if [ "$RELEASE_VERSION" = "1.8.0" ] \
  && [ "$MANIFEST_VERSION" = "$RELEASE_VERSION" ] \
  && grep -q '^# Canuto Framework v1\.8$' "$FRAMEWORK_DIR/README.md" \
  && grep -q '^# Canuto Framework v1\.8 Summary$' "$FRAMEWORK_DIR/SUMMARY.md"; then
  pass "23a VERSION, release manifest, README e SUMMARY convergem em 1.8.0"
else
  fail "23a superfícies de versão divergiram: VERSION=$RELEASE_VERSION manifest=$MANIFEST_VERSION"
fi

CI_RELEASE_FILE="$FRAMEWORK_DIR/.github/workflows/validate-framework.yml"
if grep -q 'ubuntu-latest' "$CI_RELEASE_FILE" \
  && grep -q 'macos-14' "$CI_RELEASE_FILE" \
  && grep -q "'releases/\*\*'" "$CI_RELEASE_FILE" \
  && grep -q '^[[:space:]]*- stable$' "$CI_RELEASE_FILE" \
  && grep -q '/bin/bash tests/cross-consumer-e2e.sh' "$CI_RELEASE_FILE" \
  && grep -q 'shell: /bin/bash' "$CI_RELEASE_FILE"; then
  pass "23b CI declara Ubuntu, macOS, release/stable e E2E com /bin/bash"
else
  fail "23b matriz ou triggers cross-platform incompletos"
fi

if grep -A2 'Check vault references' "$CI_RELEASE_FILE" | grep -q 'continue-on-error' \
  || grep -A2 'Check vault orphans' "$CI_RELEASE_FILE" | grep -q 'continue-on-error'; then
  fail "23c integridade do vault ainda é informativa"
else
  pass "23c referências e órfãos bloqueiam a release"
fi

if [ -x "$FRAMEWORK_DIR/tests/cross-consumer-e2e.sh" ] \
  && grep -q 'consumer beta with space' "$FRAMEWORK_DIR/tests/cross-consumer-e2e.sh" \
  && grep -q 'rendered identical CODEX.md' "$FRAMEWORK_DIR/tests/cross-consumer-e2e.sh" \
  && grep -q 'Refusing --update in a dirty worktree' "$FRAMEWORK_DIR/tests/cross-consumer-e2e.sh"; then
  pass "23d E2E cobre dois consumidores, path com espaço, CODEX divergente e WIP"
else
  fail "23d cross-consumer E2E ausente, não executável ou incompleto"
fi

RELEASE_FRAMEWORK_BLOCK=$(sed -n '/^FRAMEWORK_FILES=(/,/^)/p' "$FRAMEWORK_DIR/install.sh")
if printf '%s\n' "$RELEASE_FRAMEWORK_BLOCK" | grep -qF '"distribution/release.json"' \
  && printf '%s\n' "$RELEASE_FRAMEWORK_BLOCK" | grep -qF '"docs/RELEASE-PROMOTION.md"' \
  && python3 -m json.tool "$FRAMEWORK_DIR/distribution/release.json" >/dev/null; then
  pass "23e manifesto e política de promoção são distribuídos e válidos"
else
  fail "23e manifesto/política fora da distribuição ou JSON inválido"
fi

CURRENT_DOCS=(README.md SUMMARY.md TUTORIAL.md .agents/TUTORIAL.md docs/TUTORIAL.md docs/TROUBLESHOOTING.md)
STALE_MAIN_URL=""
for current_doc in "${CURRENT_DOCS[@]}"; do
  [ -f "$FRAMEWORK_DIR/$current_doc" ] || continue
  if grep -q 'raw.githubusercontent.com/csorodrigo/canuto-framework/main/install.sh' "$FRAMEWORK_DIR/$current_doc"; then
    STALE_MAIN_URL="$current_doc"
    break
  fi
done
if [ -z "$STALE_MAIN_URL" ]; then
  pass "23f documentação operacional usa stable, não main implícito"
else
  fail "23f URL de instalação edge ainda aparece como default em $STALE_MAIN_URL"
fi

echo ""
'''
if "TEST 23: Release v1.8.0" not in tests:
    tests = tests.replace(summary_marker, test23 + summary_marker, 1)
tests_path.write_text(tests, encoding="utf-8")

# Documentation inventory includes the promotion policy.
tests = tests_path.read_text(encoding="utf-8")
tests = replace_once(
    tests,
    "DOCS=(TUTORIAL.md TROUBLESHOOTING.md PLUGIN-REGISTRY.md CLAUDE-EXAMPLES.md FEATURE-MAP.md)\n",
    "DOCS=(TUTORIAL.md TROUBLESHOOTING.md PLUGIN-REGISTRY.md CLAUDE-EXAMPLES.md FEATURE-MAP.md RELEASE-PROMOTION.md)\n",
    "test documentation inventory",
)
tests_path.write_text(tests, encoding="utf-8")

print("cross-platform release v1.8.0 applied")
