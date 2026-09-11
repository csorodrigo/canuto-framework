#!/usr/bin/env bash
# vault-integrator-setup.sh — instala o spool e o integrador single-publisher.
#
# Nada é ativado implicitamente: cron, commit e push exigem flags explícitas.
# O servidor instala o integrador; clientes instalam apenas o submit/flush.

set -euo pipefail

ROLE=""
PREFIX="${HOME}/.local"
VAULT="${CANUTO_VAULT_DIR:-$HOME/.canuto/vault}"
STATE="${CANUTO_VAULT_INTEGRATOR_STATE:-$HOME/.canuto/vault-integrator}"
INBOX="${CANUTO_VAULT_INBOX:-$HOME/.canuto/vault-spool/inbox}"
OUTBOX="${CANUTO_VAULT_OUTBOX:-$HOME/.canuto/vault-spool/outbox}"
REMOTE_HOST=""
REMOTE_INBOX=""
BRANCH="${CANUTO_VAULT_BRANCH:-main}"
INTERVAL=0
ENABLE_COMMIT=false
ENABLE_PUSH=false
DRY_RUN=false

usage() {
  cat <<'EOF'
Uso:
  bash vault-integrator-setup.sh --server [opções]
  bash vault-integrator-setup.sh --client [opções]

Opções comuns:
  --prefix PATH          default: ~/.local
  --vault PATH           default: ~/.canuto/vault
  --state PATH           default: ~/.canuto/vault-integrator
  --inbox PATH           default: ~/.canuto/vault-spool/inbox
  --outbox PATH          default: ~/.canuto/vault-spool/outbox
  --branch NAME          branch canônica (default: main)
  --dry-run

Servidor:
  --interval MIN         agenda o runner; 0 não agenda (default)
  --commit               autoriza commit por envelope
  --push                 autoriza push; exige --commit

Cliente:
  --remote-host HOST     alias SSH do integrador
  --remote-inbox PATH    caminho absoluto do inbox no servidor

Exemplos:
  bash vault-integrator-setup.sh --server --commit --push --interval 2
  bash vault-integrator-setup.sh --client \
    --remote-host papiro --remote-inbox /home/rodrigo/.canuto/vault-spool/inbox
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --server) ROLE="server"; shift ;;
    --client) ROLE="client"; shift ;;
    --prefix) PREFIX="${2:-}"; shift 2 ;;
    --vault) VAULT="${2:-}"; shift 2 ;;
    --state) STATE="${2:-}"; shift 2 ;;
    --inbox) INBOX="${2:-}"; shift 2 ;;
    --outbox) OUTBOX="${2:-}"; shift 2 ;;
    --remote-host) REMOTE_HOST="${2:-}"; shift 2 ;;
    --remote-inbox) REMOTE_INBOX="${2:-}"; shift 2 ;;
    --branch) BRANCH="${2:-}"; shift 2 ;;
    --interval) INTERVAL="${2:-}"; shift 2 ;;
    --commit) ENABLE_COMMIT=true; shift ;;
    --push) ENABLE_PUSH=true; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "argumento desconhecido: $1" >&2; exit 64 ;;
  esac
done

[ -n "$ROLE" ] || { usage >&2; exit 64; }
case "$INTERVAL" in ''|*[!0-9]*) echo "--interval deve ser inteiro entre 0 e 59" >&2; exit 64 ;; esac
[ "$INTERVAL" -le 59 ] || { echo "--interval deve ser inteiro entre 0 e 59" >&2; exit 64; }
[ "$ENABLE_PUSH" = false ] || [ "$ENABLE_COMMIT" = true ] || { echo "--push exige --commit" >&2; exit 64; }
if [ "$ROLE" = client ] && { [ -n "$REMOTE_HOST" ] || [ -n "$REMOTE_INBOX" ]; }; then
  [ -n "$REMOTE_HOST" ] && [ -n "$REMOTE_INBOX" ] || {
    echo "--remote-host e --remote-inbox devem ser usados juntos" >&2
    exit 64
  }
fi
command -v python3 >/dev/null 2>&1 || { echo "python3 é obrigatório" >&2; exit 1; }
for path_value in "$PREFIX" "$VAULT" "$STATE" "$INBOX" "$OUTBOX"; do
  case "$path_value" in
    /*) ;;
    *) echo "paths devem ser absolutos: $path_value" >&2; exit 64 ;;
  esac
  case "$path_value" in *$'\n'*) echo "path contém newline" >&2; exit 64 ;; esac
done
case "$BRANCH" in
  ''|*[^A-Za-z0-9._/-]*|*..*|/*) echo "--branch inválida: $BRANCH" >&2; exit 64 ;;
esac
if [ "$ROLE" = client ]; then
  [ "$ENABLE_COMMIT" = false ] && [ "$ENABLE_PUSH" = false ] && [ "$INTERVAL" -eq 0 ] || {
    echo "--commit, --push e --interval são opções de servidor" >&2
    exit 64
  }
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$PREFIX/lib/canuto-vault"
BIN_DIR="$PREFIX/bin"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/canuto"
CONFIG_FILE="$CONFIG_DIR/vault-integrator.env"
CRON_MARKER="# canuto-vault-integrator"

run() {
  if [ "$DRY_RUN" = true ]; then
    printf 'DRY-RUN:'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

write_file() {
  local target="$1" mode="$2"
  shift 2
  if [ "$DRY_RUN" = true ]; then
    echo "DRY-RUN: escrever $target (mode $mode)"
    cat >/dev/null
    return 0
  fi
  mkdir -p "$(dirname "$target")"
  local tmp="${target}.tmp.$$"
  cat > "$tmp"
  chmod "$mode" "$tmp"
  mv "$tmp" "$target"
}

for required in vault-submit.py schemas/write-envelope.schema.json schemas/write-receipt.schema.json; do
  [ -f "$SCRIPT_DIR/$required" ] || { echo "arquivo ausente: $SCRIPT_DIR/$required" >&2; exit 1; }
done
if [ "$ROLE" = server ]; then
  for required in vault-integrator.py vault_integrator_common.py vault_integrator_git.py vault_integrator_engine.py; do
    [ -f "$SCRIPT_DIR/$required" ] || { echo "$required ausente" >&2; exit 1; }
  done
fi

run mkdir -p "$LIB_DIR/schemas" "$BIN_DIR" "$CONFIG_DIR" "$OUTBOX"
run install -m 0755 "$SCRIPT_DIR/vault-submit.py" "$LIB_DIR/vault-submit.py"
run install -m 0644 "$SCRIPT_DIR/schemas/write-envelope.schema.json" "$LIB_DIR/schemas/write-envelope.schema.json"
run install -m 0644 "$SCRIPT_DIR/schemas/write-receipt.schema.json" "$LIB_DIR/schemas/write-receipt.schema.json"

write_file "$BIN_DIR/canuto-vault-submit" 0755 <<EOF
#!/usr/bin/env bash
exec python3 "$LIB_DIR/vault-submit.py" "\$@"
EOF

if [ "$ROLE" = server ]; then
  run mkdir -p "$INBOX" "$STATE/receipts" "$STATE/processed" "$STATE/rejected" "$STATE/collisions" "$STATE/journal" "$STATE/recovery" "$STATE/locks"
  run install -m 0755 "$SCRIPT_DIR/vault-integrator.py" "$LIB_DIR/vault-integrator.py"
  run install -m 0644 "$SCRIPT_DIR/vault_integrator_common.py" "$LIB_DIR/vault_integrator_common.py"
  run install -m 0644 "$SCRIPT_DIR/vault_integrator_git.py" "$LIB_DIR/vault_integrator_git.py"
  run install -m 0644 "$SCRIPT_DIR/vault_integrator_engine.py" "$LIB_DIR/vault_integrator_engine.py"
  write_file "$BIN_DIR/canuto-vault-integrator" 0755 <<EOF
#!/usr/bin/env bash
exec python3 "$LIB_DIR/vault-integrator.py" "\$@"
EOF

  write_file "$CONFIG_FILE" 0600 <<EOF
CANUTO_VAULT_DIR=$(printf '%q' "$VAULT")
CANUTO_VAULT_INTEGRATOR_STATE=$(printf '%q' "$STATE")
CANUTO_VAULT_INBOX=$(printf '%q' "$INBOX")
CANUTO_VAULT_OUTBOX=$(printf '%q' "$OUTBOX")
CANUTO_VAULT_BRANCH=$(printf '%q' "$BRANCH")
EOF

  PROCESS_ARGS=(process --vault "$VAULT" --state "$STATE" --inbox "$INBOX" --branch "$BRANCH")
  [ "$ENABLE_COMMIT" = true ] && PROCESS_ARGS+=(--commit)
  [ "$ENABLE_PUSH" = true ] && PROCESS_ARGS+=(--push)
  RUNNER="$BIN_DIR/canuto-vault-integrator-run"
  write_file "$RUNNER" 0755 <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "$BIN_DIR/canuto-vault-integrator"$(printf ' %q' "${PROCESS_ARGS[@]}")
EOF

  if [ "$INTERVAL" -gt 0 ]; then
    command -v crontab >/dev/null 2>&1 || { echo "crontab indisponível" >&2; exit 1; }
    if [ "$DRY_RUN" = true ]; then
      echo "DRY-RUN: cron a cada ${INTERVAL}min → $RUNNER"
    else
      CURRENT_CRON=$(crontab -l 2>/dev/null || true)
      TMP_CRON=$(mktemp)
      printf '%s\n' "$CURRENT_CRON" | grep -vF "$CRON_MARKER" | sed '/^$/d' > "$TMP_CRON"
      printf '*/%s * * * * %q >> %q 2>&1 %s\n' \
        "$INTERVAL" "$RUNNER" "$STATE/integrator.log" "$CRON_MARKER" >> "$TMP_CRON"
      crontab "$TMP_CRON"
      rm -f "$TMP_CRON"
    fi
  fi

  echo "Integrador instalado."
  echo "  inbox:  $INBOX"
  echo "  state:  $STATE"
  echo "  runner: $RUNNER"
  [ "$ENABLE_COMMIT" = true ] || echo "  publicação Git DESATIVADA; reconfigure com --commit [--push]."
else
  run mkdir -p "$OUTBOX"
  write_file "$CONFIG_FILE" 0600 <<EOF
CANUTO_VAULT_OUTBOX=$(printf '%q' "$OUTBOX")
CANUTO_VAULT_REMOTE_HOST=$(printf '%q' "$REMOTE_HOST")
CANUTO_VAULT_REMOTE_INBOX=$(printf '%q' "$REMOTE_INBOX")
EOF

  if [ -n "$REMOTE_HOST" ] || [ -n "$REMOTE_INBOX" ]; then
    write_file "$BIN_DIR/canuto-vault-flush" 0755 <<EOF
#!/usr/bin/env bash
set -euo pipefail
exec "$BIN_DIR/canuto-vault-submit" flush \
  --outbox $(printf '%q' "$OUTBOX") \
  --ssh-host $(printf '%q' "$REMOTE_HOST") \
  --remote-inbox $(printf '%q' "$REMOTE_INBOX") "\$@"
EOF
  fi
  echo "Cliente instalado."
  echo "  outbox: $OUTBOX"
  [ -z "$REMOTE_HOST" ] || echo "  flush:  $BIN_DIR/canuto-vault-flush"
fi
