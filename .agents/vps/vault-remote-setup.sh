#!/usr/bin/env bash
# vault-remote-setup.sh — coloca o vault Canuto oficial na VPS e deixa o Mac
# como cópia/backup.
#
# Direção (pedida em 2026-07-27): a VPS passa a hospedar o vault de verdade —
# é lá que as sessões vão rodar. O Mac vira um clone que espelha o conteúdo,
# não a fonte da verdade.
#
#   VPS  /srv/canuto/vault.git   (bare — hub canônico, para onde todos empurram)
#   VPS  ~/.canuto/vault         (working vault OFICIAL, usado pelas sessões)
#   Mac  ~/.canuto/vault         (clone/backup — Obsidian abre este)
#
# Uso:
#   # 1) na VPS:
#   bash vault-remote-setup.sh --server
#   # 2) no Mac (URL impressa pelo passo 1):
#   bash vault-remote-setup.sh --client ssh://user@papiro/srv/canuto/vault.git
#
# Opções:
#   --hub <path>       caminho do bare repo na VPS (default /srv/canuto/vault.git)
#   --vault <path>     working vault (default ~/.canuto/vault)
#   --interval <min>   autosync do lado servidor (default 10; 0 desativa)
#   --merge-unrelated  permite unir históricos independentes no --client
#
# NUNCA apaga nem sobrescreve conteúdo: se os dois lados divergirem, o script
# relata e para. Resolver merge é decisão sua, não do instalador.

set -euo pipefail

MODE=""
CLIENT_URL=""
HUB="/srv/canuto/vault.git"
VAULT="${CANUTO_VAULT_DIR:-$HOME/.canuto/vault}"
INTERVAL=10
MERGE_UNRELATED=false

usage() { sed -n '2,28p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0; }

while [ $# -gt 0 ]; do
  case "$1" in
    --server) MODE="server"; shift ;;
    --client) MODE="client"; CLIENT_URL="${2:-}"; shift 2 ;;
    --hub) HUB="${2:-}"; shift 2 ;;
    --vault) VAULT="${2:-}"; shift 2 ;;
    --interval) INTERVAL="${2:-}"; shift 2 ;;
    --merge-unrelated) MERGE_UNRELATED=true; shift ;;
    -h|--help) usage ;;
    *) echo "Argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done

die() { echo "❌ $*" >&2; exit 1; }
log() { echo "→ $*"; }
ok()  { echo "✅ $*"; }
warn(){ echo "⚠️  $*" >&2; }

command -v git >/dev/null 2>&1 || die "git é necessário."
[ -n "$MODE" ] || usage

# ── Working vault: cria ou adota, sempre sem destruir ───────────────────────
ensure_vault_repo() {
  mkdir -p "$VAULT"
  if [ -d "$VAULT/.git" ]; then
    ok "Vault já é um repositório git: $VAULT"
  else
    log "Inicializando git em $VAULT..."
    git -C "$VAULT" init -b main >/dev/null
    ok "Repositório criado."
  fi

  if [ ! -f "$VAULT/.gitignore" ]; then
    cat > "$VAULT/.gitignore" <<'GITIGNORE'
.obsidian/workspace*
.obsidian/cache/
.trash/
*.tmp
.DS_Store
GITIGNORE
    ok ".gitignore criado."
  fi

  if [ -z "$(git -C "$VAULT" status --porcelain 2>/dev/null)" ] && \
     git -C "$VAULT" rev-parse HEAD >/dev/null 2>&1; then
    return 0
  fi
  git -C "$VAULT" add -A
  git -C "$VAULT" -c user.name="canuto" -c user.email="canuto@localhost" \
    commit -q -m "vault: snapshot inicial antes do sync com a VPS" 2>/dev/null || true
}

case "$MODE" in

server)
  # ── Hub bare ──────────────────────────────────────────────────────────────
  if [ -d "$HUB" ]; then
    ok "Hub já existe: $HUB"
  else
    log "Criando hub bare em $HUB..."
    mkdir -p "$(dirname "$HUB")"
    git init --bare -b main "$HUB" >/dev/null
    ok "Hub criado."
  fi

  ensure_vault_repo

  if git -C "$VAULT" remote get-url origin >/dev/null 2>&1; then
    CURRENT=$(git -C "$VAULT" remote get-url origin)
    if [ "$CURRENT" != "$HUB" ]; then
      warn "origin já aponta para $CURRENT (mantido). Para trocar: git -C $VAULT remote set-url origin $HUB"
    fi
  else
    git -C "$VAULT" remote add origin "$HUB"
    ok "origin → $HUB"
  fi

  BRANCH=$(git -C "$VAULT" symbolic-ref --short HEAD 2>/dev/null || echo main)
  if git -C "$VAULT" push -u origin "$BRANCH" >/dev/null 2>&1; then
    ok "Vault oficial publicado no hub (branch $BRANCH)."
  else
    warn "push inicial falhou — o hub pode já ter histórico. Verifique: git -C $VAULT fetch origin && git -C $VAULT status"
  fi

  # ── Autosync ──────────────────────────────────────────────────────────────
  SYNC_SCRIPT="/usr/local/bin/canuto-vault-autosync"
  cat > "$SYNC_SCRIPT" <<AUTOSYNC
#!/usr/bin/env bash
# canuto-vault-autosync — commit+push periódico do vault oficial (gerado por
# .agents/vps/vault-remote-setup.sh; não editar à mão).
set -uo pipefail
VAULT="$VAULT"
cd "\$VAULT" 2>/dev/null || exit 0
git add -A
if ! git diff --cached --quiet; then
  git -c user.name="canuto" -c user.email="canuto@localhost" \\
    commit -q -m "vault: autosync \$(date -u +%Y-%m-%dT%H:%M:%SZ)"
fi
git push -q origin HEAD 2>/dev/null || exit 0
AUTOSYNC
  chmod +x "$SYNC_SCRIPT"
  ok "Autosync instalado: $SYNC_SCRIPT"

  if [ "$INTERVAL" -gt 0 ] 2>/dev/null; then
    MARKER="# canuto-vault-autosync"
    LINE="*/$INTERVAL * * * * $SYNC_SCRIPT >/dev/null 2>&1 $MARKER"
    if command -v crontab >/dev/null 2>&1; then
      CURRENT_CRON=$(crontab -l 2>/dev/null || true)
      printf '%s\n' "$CURRENT_CRON" | grep -vF "$MARKER" | sed '/^$/d' > /tmp/canuto-cron.$$
      printf '%s\n' "$LINE" >> /tmp/canuto-cron.$$
      crontab /tmp/canuto-cron.$$ && rm -f /tmp/canuto-cron.$$
      ok "cron: autosync a cada ${INTERVAL}min."
    else
      warn "crontab indisponível — agende $SYNC_SCRIPT manualmente."
    fi
  else
    ok "Autosync agendado desativado (--interval 0)."
  fi

  HOSTNAME_FQDN=$(hostname -f 2>/dev/null || hostname)
  echo ""
  ok "VPS pronta. O vault oficial é $VAULT."
  echo ""
  echo "No Mac, rode:"
  echo "    bash .agents/vps/vault-remote-setup.sh --client ssh://\$USER@$HOSTNAME_FQDN$HUB"
  echo ""
  echo "(ajuste usuário/host conforme o seu ~/.ssh/config — ex.: ssh://papiro$HUB)"
  ;;

client)
  [ -n "$CLIENT_URL" ] || die "--client precisa da URL do hub (ssh://user@host/srv/canuto/vault.git)."

  # Vault local vazio (primeira vez): clone direto. Sem isto, o bootstrap
  # criaria um commit local só com .gitignore e o script acusaria "históricos
  # divergentes" no caso mais comum de todos.
  if [ ! -d "$VAULT" ] || [ -z "$(find "$VAULT" -mindepth 1 -maxdepth 1 ! -name '.git' -print -quit 2>/dev/null)" ]; then
    if [ -d "$VAULT/.git" ]; then
      log "Vault local vazio mas já versionado — sincronizando pelo caminho normal."
    else
      log "Vault local vazio — clonando o vault oficial da VPS..."
      rmdir "$VAULT" 2>/dev/null || true
      git clone "$CLIENT_URL" "$VAULT" >/dev/null 2>&1 \
        || die "clone falhou — confira SSH (ssh <host> deve funcionar sem senha) e o caminho do hub."
      ok "Mac clonado a partir do vault oficial: $VAULT"
      echo ""
      echo "No Obsidian (plugin Obsidian Git), para manter o espelho fresco:"
      echo "   autoPullInterval: 10   (puxa da VPS)"
      echo "   autoPushInterval: 10   (devolve edições feitas no Mac)"
      exit 0
    fi
  fi

  ensure_vault_repo

  if git -C "$VAULT" remote get-url origin >/dev/null 2>&1; then
    CURRENT=$(git -C "$VAULT" remote get-url origin)
    if [ "$CURRENT" != "$CLIENT_URL" ]; then
      log "origin: $CURRENT → $CLIENT_URL"
      git -C "$VAULT" remote set-url origin "$CLIENT_URL"
    fi
  else
    git -C "$VAULT" remote add origin "$CLIENT_URL"
  fi
  ok "origin → $CLIENT_URL"

  log "Buscando o hub..."
  git -C "$VAULT" fetch origin >/dev/null 2>&1 || die "fetch falhou — confira SSH (ssh <host> deve funcionar sem senha) e o caminho do hub."

  REMOTE_HEAD=$(git -C "$VAULT" rev-parse origin/main 2>/dev/null || true)
  LOCAL_HEAD=$(git -C "$VAULT" rev-parse HEAD 2>/dev/null || true)

  if [ -z "$REMOTE_HEAD" ]; then
    warn "O hub está vazio. Rode --server na VPS primeiro (ou empurre: git -C $VAULT push -u origin HEAD)."
    exit 0
  fi

  if [ "$REMOTE_HEAD" = "$LOCAL_HEAD" ]; then
    ok "Mac já espelha o vault oficial. Nada a fazer."
  elif git -C "$VAULT" merge-base --is-ancestor HEAD origin/main 2>/dev/null; then
    log "Local está atrás do oficial — atualizando (fast-forward)..."
    git -C "$VAULT" merge --ff-only origin/main >/dev/null
    ok "Mac atualizado a partir da VPS."
  elif [ "$MERGE_UNRELATED" = true ]; then
    log "Unindo históricos independentes (--merge-unrelated)..."
    git -C "$VAULT" merge --allow-unrelated-histories --no-edit origin/main || \
      die "Merge com conflitos. Resolva em $VAULT e finalize com: git -C $VAULT commit"
    ok "Históricos unidos. Publique com: git -C $VAULT push origin HEAD"
  else
    warn "Mac e VPS têm históricos divergentes — NADA foi alterado."
    echo ""
    echo "   local:  $LOCAL_HEAD"
    echo "   oficial: $REMOTE_HEAD"
    echo ""
    echo "   Se o conteúdo local ainda não está na VPS, una os dois:"
    echo "       bash $0 --client $CLIENT_URL --merge-unrelated"
    echo "   Se o local é descartável, clone limpo em outro diretório e compare antes de trocar."
    exit 1
  fi

  echo ""
  echo "No Obsidian (plugin Obsidian Git), para manter o espelho fresco:"
  echo "   autoPullInterval: 10   (puxa da VPS)"
  echo "   autoPushInterval: 10   (devolve edições feitas no Mac)"
  ;;

esac
