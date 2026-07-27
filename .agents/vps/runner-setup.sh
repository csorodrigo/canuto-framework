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
#   bash runner-setup.sh --repo owner/name --dry-run   # mostra o plano, não altera nada
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
DRY_RUN=false
VERSION=""

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
    --dry-run) DRY_RUN=true; shift ;;
    --runner-version) VERSION="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done

die() { echo "❌ $*" >&2; exit 1; }
log() { echo "→ $*"; }
ok()  { echo "✅ $*"; }
warn(){ echo "⚠️  $*" >&2; }
# Em --dry-run nada muda no sistema: cada passo com efeito colateral vira uma
# linha "[dry-run]". Serve para conferir o plano antes de mexer na VPS.
run() { if [ "$DRY_RUN" = true ]; then echo "   [dry-run] $*"; else eval "$@"; fi; }

[ -n "$REPO" ] || die "--repo owner/name é obrigatório."
case "$REPO" in */*) : ;; *) die "--repo deve ser no formato owner/name." ;; esac

if [ "$(id -u)" -ne 0 ] && [ "$DRY_RUN" != true ]; then
  die "Rode como root (ou com sudo): o serviço systemd exige privilégio."
fi

REPO_SLUG="${REPO//\//-}"
RUNNER_DIR="$BASE_DIR/$REPO_SLUG"

# ── Token de registro ───────────────────────────────────────────────────────
fetch_token() {
  # Valida o FORMATO do que voltou: quando a chamada falha (proxy, permissão,
  # rate limit), `gh` devolve o corpo de erro em JSON e isso seria passado
  # adiante como --token, fazendo config.sh falhar com um erro sem relação com
  # a causa real. Token de registro é alfanumérico, ~29 chars, sem espaços.
  local kind="$1"  # registration | remove
  local candidate=""
  command -v gh >/dev/null 2>&1 || return 1
  candidate=$(gh api -X POST "repos/$REPO/actions/runners/${kind}-token" --jq .token 2>/dev/null || true)
  case "$candidate" in
    ""|*[!A-Za-z0-9_-]*) return 1 ;;
  esac
  [ "${#candidate}" -ge 20 ] || return 1
  printf '%s' "$candidate"
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
  run "useradd -m -s /bin/bash '$RUNNER_USER'"
  [ "$DRY_RUN" = true ] || ok "Usuário $RUNNER_USER criado."
fi

# ── Download do runner ──────────────────────────────────────────────────────
case "$(uname -m)" in
  x86_64|amd64) ARCH="x64" ;;
  aarch64|arm64) ARCH="arm64" ;;
  *) die "Arquitetura não suportada: $(uname -m)" ;;
esac

# `|| true` é load-bearing: sob `set -euo pipefail`, uma falha de rede aqui
# encerrava o script SEM imprimir nada — o operador via um comando que
# simplesmente saía mudo, sem saber que o problema era a API do GitHub.
if [ -z "$VERSION" ]; then
  VERSION=$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest 2>/dev/null \
    | grep -m1 '"tag_name"' | sed -E 's/.*"v?([^"]+)".*/\1/' || true)
fi
[ -n "$VERSION" ] || die "Não consegui descobrir a versão do runner (API do GitHub inacessível). Passe --runner-version <X.Y.Z> — veja https://github.com/actions/runner/releases."

TARBALL="actions-runner-linux-${ARCH}-${VERSION}.tar.gz"
URL="https://github.com/actions/runner/releases/download/v${VERSION}/${TARBALL}"

run "mkdir -p '$RUNNER_DIR'"
if [ -x "$RUNNER_DIR/config.sh" ]; then
  ok "Runner já extraído em $RUNNER_DIR (v$VERSION disponível)."
else
  log "Baixando actions-runner v$VERSION ($ARCH)..."
  run "curl -fsSL -o '/tmp/$TARBALL' '$URL'"
  run "tar -xzf '/tmp/$TARBALL' -C '$RUNNER_DIR'"
  run "rm -f '/tmp/$TARBALL'"
  [ "$DRY_RUN" = true ] || ok "Runner extraído em $RUNNER_DIR."
fi
run "chown -R '$RUNNER_USER:$RUNNER_USER' '$RUNNER_DIR'"

# Dependências nativas do runner (libicu etc.)
if [ -x "$RUNNER_DIR/bin/installdependencies.sh" ]; then
  log "Instalando dependências nativas do runner..."
  run "'$RUNNER_DIR/bin/installdependencies.sh' >/dev/null 2>&1" || \
    warn "installdependencies.sh falhou — se o runner não subir, rode-o manualmente."
elif [ "$DRY_RUN" = true ]; then
  echo "   [dry-run] \$RUNNER_DIR/bin/installdependencies.sh (após extrair o tarball)"
fi

# ── Configuração ────────────────────────────────────────────────────────────
if [ -z "$TOKEN" ]; then
  log "Obtendo token de registro via gh..."
  TOKEN=$(fetch_token registration || true)
  if [ -z "$TOKEN" ]; then
    [ "$DRY_RUN" = true ] || die "Sem token. Passe --token <TOKEN> (Settings → Actions → Runners → New self-hosted runner)."
    warn "Sem token de registro (gh não autenticado) — em execução real isto abortaria aqui."
    TOKEN="<TOKEN>"
  fi
fi

LABELS="${LABELS:-self-hosted,linux,${ARCH},canuto-vps}"
RUNNER_NAME="$(hostname -s)-${REPO_SLUG}"

log "Registrando runner '$RUNNER_NAME' em $REPO..."
run "su - '$RUNNER_USER' -c \"cd '$RUNNER_DIR' && ./config.sh \
  --url 'https://github.com/$REPO' \
  --token '$TOKEN' \
  --name '$RUNNER_NAME' \
  --labels '$LABELS' \
  --work '_work' \
  --unattended --replace\"" || die "config.sh falhou."

# ── Serviço systemd ─────────────────────────────────────────────────────────
log "Instalando serviço systemd..."
run "cd '$RUNNER_DIR' && ./svc.sh install '$RUNNER_USER' && ./svc.sh start"

echo ""
if [ "$DRY_RUN" = true ]; then
  ok "Dry-run concluído — nada foi alterado. Repita sem --dry-run para aplicar."
else
  ok "Runner ativo para $REPO."
fi
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
