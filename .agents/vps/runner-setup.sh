#!/usr/bin/env bash
# runner-setup.sh — registra um GitHub Actions self-hosted runner como serviço
# systemd nesta máquina (VPS).
#
# Motivação: a cota de Actions da conta esgotou e travou o CI de todos os repos
# privados (jobs "falham" em 2s com runner_id 0, sem log). Runner self-hosted
# em repo privado não consome minutos da cota — o CI volta a rodar de graça.
#
# ⚠️  SOMENTE REPOSITÓRIOS PRIVADOS. Num repo público qualquer pessoa abre um
# PR que executa código arbitrário nesta máquina. O script recusa repo público.
#
# Uso (como root ou com sudo, NA VPS):
#   bash runner-setup.sh --repo csorodrigo/plomes-route-optimizer
#   bash runner-setup.sh --repo owner/name --token <REGISTRATION_TOKEN>
#   bash runner-setup.sh --repo owner/name --remove
#
# Sem --token, o script tenta obter um token de registro via `gh` autenticado.
# Token de registro expira em 1h; pegue um novo em
# Settings → Actions → Runners → New self-hosted runner, se preferir manual.

set -euo pipefail

REPO=""
TOKEN=""
RUNNER_USER="canuto-runner"
LABELS=""
BASE_DIR="/opt/actions-runner"
REMOVE=false
ASSUME_PRIVATE=false

usage() { sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0; }

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --token) TOKEN="${2:-}"; shift 2 ;;
    --user) RUNNER_USER="${2:-}"; shift 2 ;;
    --labels) LABELS="${2:-}"; shift 2 ;;
    --dir) BASE_DIR="${2:-}"; shift 2 ;;
    --remove) REMOVE=true; shift ;;
    --assume-private) ASSUME_PRIVATE=true; shift ;;
    -h|--help) usage ;;
    *) echo "Argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done

die() { echo "❌ $*" >&2; exit 1; }
log() { echo "→ $*"; }
ok()  { echo "✅ $*"; }
warn(){ echo "⚠️  $*" >&2; }

[ -n "$REPO" ] || die "--repo owner/name é obrigatório."
case "$REPO" in */*) : ;; *) die "--repo deve ser no formato owner/name." ;; esac

if [ "$(id -u)" -ne 0 ]; then
  die "Rode como root (ou com sudo): o serviço systemd exige privilégio."
fi

REPO_SLUG="${REPO//\//-}"
RUNNER_DIR="$BASE_DIR/$REPO_SLUG"

# ── Token de registro ───────────────────────────────────────────────────────
fetch_token() {
  local kind="$1"  # registration | remove
  command -v gh >/dev/null 2>&1 || return 1
  gh api -X POST "repos/$REPO/actions/runners/${kind}-token" --jq .token 2>/dev/null
}

# ── Remoção ─────────────────────────────────────────────────────────────────
if [ "$REMOVE" = true ]; then
  [ -d "$RUNNER_DIR" ] || die "Runner não encontrado em $RUNNER_DIR."
  log "Parando e desinstalando o serviço..."
  (cd "$RUNNER_DIR" && ./svc.sh stop 2>/dev/null || true; ./svc.sh uninstall 2>/dev/null || true)
  RM_TOKEN="${TOKEN:-$(fetch_token remove || true)}"
  if [ -n "$RM_TOKEN" ]; then
    su - "$RUNNER_USER" -c "cd '$RUNNER_DIR' && ./config.sh remove --token '$RM_TOKEN'" || \
      warn "config.sh remove falhou — remova o runner órfão em Settings → Actions → Runners."
  else
    warn "Sem token de remoção — o runner continuará listado no GitHub. Remova pela UI."
  fi
  rm -rf "$RUNNER_DIR"
  ok "Runner de $REPO removido."
  exit 0
fi

# ── Guarda de repositório público ───────────────────────────────────────────
if [ "$ASSUME_PRIVATE" != true ]; then
  if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
    VISIBILITY=$(gh api "repos/$REPO" --jq '.private' 2>/dev/null || echo "unknown")
    case "$VISIBILITY" in
      true)  ok "$REPO é privado — seguro para runner self-hosted." ;;
      false) die "$REPO é PÚBLICO. Runner self-hosted em repo público permite execução de código arbitrário via PR. Abortando." ;;
      *)     die "Não foi possível confirmar a visibilidade de $REPO. Confirme que é privado e re-rode com --assume-private." ;;
    esac
  else
    die "gh não autenticado — não dá para confirmar que $REPO é privado. Autentique (gh auth login) ou re-rode com --assume-private se tiver certeza."
  fi
fi

# ── Dependências ────────────────────────────────────────────────────────────
for dep in curl tar; do
  command -v "$dep" >/dev/null 2>&1 || die "$dep é necessário."
done

# ── Usuário dedicado (não-privilegiado) ─────────────────────────────────────
if id "$RUNNER_USER" >/dev/null 2>&1; then
  ok "Usuário $RUNNER_USER já existe."
else
  log "Criando usuário $RUNNER_USER (sem sudo, sem docker)..."
  useradd -m -s /bin/bash "$RUNNER_USER"
  ok "Usuário $RUNNER_USER criado."
fi

# ── Download do runner ──────────────────────────────────────────────────────
case "$(uname -m)" in
  x86_64|amd64) ARCH="x64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) die "Arquitetura não suportada: $(uname -m)" ;;
esac

VERSION=$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest 2>/dev/null \
  | grep -m1 '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/')
[ -n "$VERSION" ] || die "Não consegui descobrir a versão do runner (rede/API do GitHub)."

TARBALL="actions-runner-linux-${ARCH}-${VERSION}.tar.gz"
URL="https://github.com/actions/runner/releases/download/v${VERSION}/${TARBALL}"

mkdir -p "$RUNNER_DIR"
if [ -x "$RUNNER_DIR/config.sh" ]; then
  ok "Runner já extraído em $RUNNER_DIR (v$VERSION disponível)."
else
  log "Baixando actions-runner v$VERSION ($ARCH)..."
  curl -fsSL -o "/tmp/$TARBALL" "$URL" || die "Download falhou: $URL"
  tar -xzf "/tmp/$TARBALL" -C "$RUNNER_DIR"
  rm -f "/tmp/$TARBALL"
  ok "Runner extraído em $RUNNER_DIR."
fi
chown -R "$RUNNER_USER:$RUNNER_USER" "$RUNNER_DIR"

# Dependências nativas do runner (libicu etc.)
if [ -x "$RUNNER_DIR/bin/installdependencies.sh" ]; then
  log "Instalando dependências nativas do runner..."
  "$RUNNER_DIR/bin/installdependencies.sh" >/dev/null 2>&1 || \
    warn "installdependencies.sh falhou — se o runner não subir, rode-o manualmente."
fi

# ── Configuração ────────────────────────────────────────────────────────────
if [ -z "$TOKEN" ]; then
  log "Obtendo token de registro via gh..."
  TOKEN=$(fetch_token registration || true)
  [ -n "$TOKEN" ] || die "Sem token. Passe --token <TOKEN> (Settings → Actions → Runners → New self-hosted runner)."
fi

LABELS="${LABELS:-self-hosted,linux,${ARCH},canuto-vps}"
RUNNER_NAME="$(hostname -s)-${REPO_SLUG}"

log "Registrando runner '$RUNNER_NAME' em $REPO..."
su - "$RUNNER_USER" -c "cd '$RUNNER_DIR' && ./config.sh \
  --url 'https://github.com/$REPO' \
  --token '$TOKEN' \
  --name '$RUNNER_NAME' \
  --labels '$LABELS' \
  --work '_work' \
  --unattended --replace" || die "config.sh falhou."

# ── Serviço systemd ─────────────────────────────────────────────────────────
log "Instalando serviço systemd..."
(cd "$RUNNER_DIR" && ./svc.sh install "$RUNNER_USER" && ./svc.sh start)

echo ""
ok "Runner ativo para $REPO."
echo ""
echo "Estado:      cd $RUNNER_DIR && ./svc.sh status"
echo "Logs:        journalctl -u \$(systemctl list-units --type=service --no-legend 'actions.runner.*' | awk '{print \$1}' | head -1) -f"
echo "Remover:     bash $0 --repo $REPO --remove"
echo ""
echo "Falta um passo NO REPOSITÓRIO: os workflows precisam pedir este runner."
echo "Em cada .github/workflows/*.yml troque:"
echo "    runs-on: ubuntu-latest"
echo "para:"
echo "    runs-on: [self-hosted, linux, canuto-vps]"
echo ""
echo "⚠️  O usuário $RUNNER_USER NÃO está no grupo docker (seria equivalente a root)."
echo "   Se algum job precisar de docker, avalie o risco antes de adicionar."
