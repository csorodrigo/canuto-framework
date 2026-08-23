#!/usr/bin/env bash

set -euo pipefail

fail() { echo "FAIL: $1" >&2; exit 1; }
pass() { echo "PASS: $1"; }

FRAMEWORK_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SOURCE_SYNC="$FRAMEWORK_ROOT/.agents/tools/vault-sync.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
ROOT="$TMP/repo"

mkdir -p "$ROOT/.agents/tools" "$TMP/pending" "$TMP/vault/projects/demo"
git -C "$TMP" init -q repo
cp "$SOURCE_SYNC" "$ROOT/.agents/tools/vault-sync.sh"
cat > "$ROOT/.agents/tools/canuto-memory.sh" <<'LIB'
canuto_project_dir() { printf '%s\n' "$1"; }
canuto_project_slug() { printf 'demo\n'; }
canuto_pending_sync_dir() { printf '%s\n' "$CANUTO_TEST_PENDING"; }
canuto_resolve_memory_backend() { printf '%s\t%s\n' "$CANUTO_TEST_BACKEND_KIND" "$CANUTO_TEST_BACKEND_DIR"; }
LIB
cat > "$ROOT/.agents/tools/event-log.sh" <<'EVENT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${CANUTO_TEST_EVENT_LOG:?}"
EVENT
chmod +x "$ROOT/.agents/tools/"*.sh

export CLAUDE_PROJECT_DIR="$ROOT"
export CANUTO_TEST_PENDING="$TMP/pending"
export CANUTO_TEST_BACKEND_KIND=vault
export CANUTO_TEST_BACKEND_DIR="$TMP/vault/projects/demo"
export CANUTO_TEST_EVENT_LOG="$TMP/events.log"

candidate() {
  local path="$1" id="$2" extra="${3:-}"
  cat > "$path" <<CANDIDATE
---
schema: canuto-memory-candidate/v1
type: memory-candidate
id: $id
project: demo
tier: hypothesis
authority: memory
status: proposed
confidence: low
target-kind: instinct
source-system: canuto
source-session: sessions/2026-08-23
source-evidence: test:line-1
$extra
---

# Candidate $id

Pattern: test evidence.
Learning: preserve the boundary.
CANDIDATE
}

VALID="$TMP/valid.md"
candidate "$VALID" MC-001
bash "$ROOT/.agents/tools/vault-sync.sh" validate-candidate "$VALID" >/dev/null || fail "valid candidate rejected"
pass "valid candidate"

bash "$ROOT/.agents/tools/vault-sync.sh" stage-candidate "$VALID" >/dev/null || fail "valid candidate not staged"
TARGET="$TMP/vault/projects/demo/memory-candidates/MC-001.md"
[ -f "$TARGET" ] || fail "candidate target missing"
[ ! -e "$TMP/vault/projects/demo/instincts/MC-001.md" ] || fail "candidate leaked into active instincts"
pass "candidate isolated from curated memory"

bash "$ROOT/.agents/tools/vault-sync.sh" stage-candidate "$VALID" >/dev/null || fail "idempotent stage failed"
pass "idempotent stage"

CONFLICT="$TMP/conflict.md"
candidate "$CONFLICT" MC-001
printf '\nconflict\n' >> "$CONFLICT"
if bash "$ROOT/.agents/tools/vault-sync.sh" stage-candidate "$CONFLICT" >/dev/null 2>&1; then
  fail "conflicting candidate overwrote existing ID"
fi
pass "conflicting ID rejected"

CURATED="$TMP/curated.md"
candidate "$CURATED" MC-002
sed -i.bak 's/tier: hypothesis/tier: curated/' "$CURATED" && rm -f "$CURATED.bak"
if bash "$ROOT/.agents/tools/vault-sync.sh" validate-candidate "$CURATED" >/dev/null 2>&1; then
  fail "curated candidate accepted"
fi
pass "curated write rejected"

WRONG_PROJECT="$TMP/wrong-project.md"
candidate "$WRONG_PROJECT" MC-003
sed -i.bak 's/project: demo/project: other/' "$WRONG_PROJECT" && rm -f "$WRONG_PROJECT.bak"
if bash "$ROOT/.agents/tools/vault-sync.sh" validate-candidate "$WRONG_PROJECT" >/dev/null 2>&1; then
  fail "cross-project candidate accepted"
fi
pass "cross-project candidate rejected"

SECRET="$TMP/secret.md"
candidate "$SECRET" MC-004 'api_key: sk_live_12345678901234567890'
if bash "$ROOT/.agents/tools/vault-sync.sh" validate-candidate "$SECRET" >/dev/null 2>&1; then
  fail "secret candidate accepted"
fi
pass "secret candidate rejected"

if bash "$ROOT/.agents/tools/vault-sync.sh" promote "$VALID" >/dev/null 2>&1; then
  fail "promotion command accepted"
fi
pass "automatic promotion impossible"

PENDING="$TMP/pending/memory-candidate-MC-005.md"
candidate "$PENDING" MC-005
bash "$ROOT/.agents/tools/vault-sync.sh" sync >/dev/null || fail "pending candidate sync failed"
[ -f "$TMP/vault/projects/demo/memory-candidates/MC-005.md" ] || fail "pending candidate not routed"
[ ! -f "$PENDING" ] || fail "pending candidate not cleared"
pass "pending candidate routed to quarantine"

export CANUTO_TEST_BACKEND_KIND=none
QUEUED="$TMP/queued.md"
candidate "$QUEUED" MC-006
bash "$ROOT/.agents/tools/vault-sync.sh" stage-candidate "$QUEUED" >/dev/null || fail "offline candidate not queued"
[ -f "$TMP/pending/memory-candidate-MC-006.md" ] || fail "offline candidate queue missing"
pass "offline candidate queued"

[ "$(grep -c 'MEMORY_CANDIDATE_STAGED' "$TMP/events.log")" -ge 3 ] || fail "candidate events missing"
pass "candidate events emitted"

echo "memory governance tests passed"
