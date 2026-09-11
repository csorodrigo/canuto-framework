#!/usr/bin/env bash
# Smoke the opt-in installer without touching the real HOME or vault.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP_ROOT=$(mktemp -d)
cleanup() { rm -rf "$TMP_ROOT"; }
trap cleanup EXIT

SERVER_PREFIX="$TMP_ROOT/server-prefix"
SERVER_HOME="$TMP_ROOT/server-home"
SERVER_CONFIG="$TMP_ROOT/server-config"
VAULT="$TMP_ROOT/vault"
STATE="$TMP_ROOT/state"
INBOX="$TMP_ROOT/inbox"
OUTBOX="$TMP_ROOT/outbox"
mkdir -p "$VAULT"

HOME="$SERVER_HOME" XDG_CONFIG_HOME="$SERVER_CONFIG" \
  bash "$ROOT_DIR/.agents/vps/vault-integrator-setup.sh" \
    --server \
    --prefix "$SERVER_PREFIX" \
    --vault "$VAULT" \
    --state "$STATE" \
    --inbox "$INBOX" \
    --outbox "$OUTBOX" >/dev/null

STATUS=$(
  "$SERVER_PREFIX/bin/canuto-vault-integrator" status \
    --state "$STATE" --inbox "$INBOX"
)
python3 - "$STATUS" <<'PY'
import json, sys
value = json.loads(sys.argv[1])
assert value == {
    "inbox": 0,
    "pending_publish": 0,
    "processed": 0,
    "receipts": 0,
    "rejected": 0,
}
PY

test -x "$SERVER_PREFIX/bin/canuto-vault-integrator"
test -x "$SERVER_PREFIX/bin/canuto-vault-submit"
test -x "$SERVER_PREFIX/bin/canuto-vault-integrator-run"
test -f "$SERVER_PREFIX/lib/canuto-vault/vault_integrator_engine.py"
test -f "$SERVER_PREFIX/lib/canuto-vault/schemas/write-envelope.schema.json"

CLIENT_PREFIX="$TMP_ROOT/client-prefix"
HOME="$TMP_ROOT/client-home" XDG_CONFIG_HOME="$TMP_ROOT/client-config" \
  bash "$ROOT_DIR/.agents/vps/vault-integrator-setup.sh" \
    --client \
    --prefix "$CLIENT_PREFIX" \
    --vault "$TMP_ROOT/client-vault" \
    --state "$TMP_ROOT/client-state" \
    --inbox "$TMP_ROOT/client-inbox" \
    --outbox "$TMP_ROOT/client-outbox" \
    --remote-host papiro \
    --remote-inbox /home/test/.canuto/vault-spool/inbox >/dev/null

test -x "$CLIENT_PREFIX/bin/canuto-vault-submit"
test -x "$CLIENT_PREFIX/bin/canuto-vault-flush"

echo "vault-integrator setup smoke: OK"
