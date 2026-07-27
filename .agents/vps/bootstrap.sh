#!/usr/bin/env bash
# bootstrap.sh — ponto único de entrada da camada VPS.
#
# Roda os passos na ordem certa, cada um idempotente, e no fim diz exatamente
# o que ficou pendente de ação humana. Feito para ser colado de uma vez na VPS:
#
#   git clone https://github.com/csorodrigo/canuto-framework.git ~/canuto-framework
#   sudo bash ~/canuto-framework/.agents/vps/bootstrap.sh \
#        --repo csorodrigo/plomes-route-optimizer --dry-run
#
# Confira o plano no --dry-run e repita sem a flag para aplicar.
#
# Opções:
#   --repo owner/name    repositório privado que ganha runner (pode repetir)
#   --skip <lista>       pula etapas: runner,vault,kuma,signoz (separadas por vírgula)
#   --bind <ip>          IP privado (Tailscale) usado nos exemplos do SigNoz
#   --dry-run            mostra o plano, não altera nada
#   --assume-private     pula a confirmação de visibilidade (use só se tiver certeza)
#
# O que NÃO é feito aqui, de propósito:
#   • instalar o SigNoz — o projeto migrou para o Foundry; ver signoz-setup.sh
#   • trocar `runs-on` nos workflows — é commit no repo da aplicação, não na VPS
#   • apontar o Mac para o vault — o passo --client roda no Mac, não aqui

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOS=()
SKIP=""
BIND_ADDR=""
DRY_RUN=false
ASSUME_PRIVATE=false

usage() { sed -n '2,26p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0; }

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPOS+=("${2:-}"); shift 2 ;;
    --skip) SKIP="${2:-}"; shift 2 ;;
    --bind) BIND_ADDR="${2:-}"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --assume-private) ASSUME_PRIVATE=true; shift ;;
    -h|--help) usage ;;
    *) echo "Argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done

log()  { echo ""; echo "━━━ $* ━━━"; }
ok()   { echo "✅ $*"; }
warn() { echo "⚠️  $*"; }
skip_step() { case ",$SKIP," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

PENDING=()
FAILED=()

step() {
  # step <nome> <descrição> <comando...>
  local name="$1" desc="$2"; shift 2
  if skip_step "$name"; then
    warn "$desc — pulado (--skip $name)"
    return 0
  fi
  log "$desc"
  if "$@"; then
    ok "$desc"
  else
    FAILED+=("$desc")
    warn "$desc — FALHOU (veja a saída acima; os demais passos continuam)"
  fi
}

DRY_FLAG=()
[ "$DRY_RUN" = true ] && DRY_FLAG=(--dry-run)
[ "$ASSUME_PRIVATE" = true ] && DRY_FLAG+=(--assume-private)

echo "Canuto — bootstrap da VPS"
[ "$DRY_RUN" = true ] && echo "(dry-run: nada será alterado)"
echo "host: $(hostname)  ·  usuário: $(whoami)"

# ── Preflight ───────────────────────────────────────────────────────────────
log "Preflight"
# Só o runner exige root (systemd + usuário dedicado). Vault e Uptime Kuma
# rodam no espaço do usuário. Abortar tudo por falta de privilégio deixaria
# duas etapas perfeitamente viáveis sem rodar.
IS_ROOT=false
[ "$(id -u)" -eq 0 ] && IS_ROOT=true
if [ "$IS_ROOT" = true ]; then
  ok "privilégio de root disponível"
else
  warn "sem root — etapa de runner será pulada; vault e uptime kuma seguem normalmente"
fi
for dep in git curl tar; do
  if command -v "$dep" >/dev/null 2>&1; then
    ok "$dep disponível"
  else
    echo "❌ $dep é necessário. Instale e re-rode." >&2
    exit 1
  fi
done

# ── 1. Runner de CI ─────────────────────────────────────────────────────────
if [ "$IS_ROOT" != true ] && [ "$DRY_RUN" != true ]; then
  warn "Runner exige root (cria usuário dedicado e serviço systemd) — pulado."
  for repo in "${REPOS[@]:-}"; do
    [ -n "$repo" ] && PENDING+=("Como root, registrar o runner: bash $SCRIPT_DIR/runner-setup.sh --repo $repo")
  done
  [ "${#REPOS[@]}" -eq 0 ] && PENDING+=("Como root: bash $SCRIPT_DIR/runner-setup.sh --repo owner/name")
elif [ "${#REPOS[@]}" -eq 0 ]; then
  warn "Nenhum --repo informado — etapa de runner pulada."
  PENDING+=("Registrar runner: bash $SCRIPT_DIR/runner-setup.sh --repo owner/name")
elif ! command -v gh >/dev/null 2>&1 || ! gh api user >/dev/null 2>&1; then
  # A sonda é `gh api user`, não `gh auth status`: o status sai com rc=0 mesmo
  # relatando "the token is invalid" — um token expirado na VPS passaria batido
  # e o erro só apareceria lá na frente, sem relação aparente com autenticação.
  # Sem `gh` autenticado o runner-setup morre na guarda de repo público (é o
  # único jeito de confirmar que o repo é privado) e também não consegue buscar
  # o token de registro. Melhor dizer isso aqui do que deixar cada repo falhar.
  warn "gh não autenticado — etapa de runner adiada."
  echo "   O runner precisa do gh para (a) confirmar que o repo é privado e"
  echo "   (b) obter o token de registro. Resolva com: gh auth login"
  for repo in "${REPOS[@]}"; do
    PENDING+=("Autenticar gh e rodar: bash $SCRIPT_DIR/runner-setup.sh --repo $repo")
  done
else
  for repo in "${REPOS[@]}"; do
    if step runner "GitHub Actions runner para $repo" \
         bash "$SCRIPT_DIR/runner-setup.sh" --repo "$repo" "${DRY_FLAG[@]}" \
       && [ "${#FAILED[@]}" -eq 0 ]; then
      PENDING+=("Em $repo, trocar 'runs-on: ubuntu-latest' por 'runs-on: [self-hosted, linux, canuto-vps]'")
    else
      # Falha aqui quase sempre é a guarda de visibilidade não conseguindo
      # confirmar que o repo é privado. Dizer o próximo passo vale mais que
      # deixar só a linha vermelha no resumo.
      PENDING+=("Resolver o runner de $repo — se tiver certeza de que é privado: bash $SCRIPT_DIR/runner-setup.sh --repo $repo --assume-private")
    fi
  done
fi

# ── 2. Vault oficial ────────────────────────────────────────────────────────
if skip_step vault; then
  warn "Vault — pulado (--skip vault)"
elif [ "$DRY_RUN" = true ]; then
  log "Vault oficial na VPS"
  echo "   [dry-run] bash $SCRIPT_DIR/vault-remote-setup.sh --server"
  ok "Vault oficial na VPS (planejado)"
else
  step vault "Vault oficial na VPS" \
    bash "$SCRIPT_DIR/vault-remote-setup.sh" --server
fi
# O hub muda de lugar conforme haja root ou não (ver vault-remote-setup.sh) —
# a pendência precisa apontar para o caminho que realmente foi criado.
if [ "$IS_ROOT" = true ]; then HUB_PATH="/srv/canuto/vault.git"; else HUB_PATH="$HOME/canuto/vault.git"; fi
PENDING+=("No MAC: bash .agents/vps/vault-remote-setup.sh --client ssh://$(whoami)@$(hostname -f 2>/dev/null || hostname)$HUB_PATH")

# ── 3. Uptime Kuma ──────────────────────────────────────────────────────────
if skip_step kuma; then
  warn "Uptime Kuma — pulado (--skip kuma)"
elif ! command -v docker >/dev/null 2>&1; then
  warn "docker ausente — Uptime Kuma pulado."
  PENDING+=("Instalar docker e rodar: bash $SCRIPT_DIR/uptime-kuma-setup.sh")
elif [ "$DRY_RUN" = true ]; then
  log "Uptime Kuma"
  echo "   [dry-run] bash $SCRIPT_DIR/uptime-kuma-setup.sh"
  ok "Uptime Kuma (planejado)"
else
  step kuma "Uptime Kuma" bash "$SCRIPT_DIR/uptime-kuma-setup.sh"
  PENDING+=("Criar a conta admin do Uptime Kuma e cadastrar os monitores")
fi

# ── 4. SigNoz (preflight apenas) ────────────────────────────────────────────
if skip_step signoz; then
  warn "SigNoz — pulado (--skip signoz)"
else
  log "SigNoz — preflight"
  BIND_ARGS=()
  [ -n "$BIND_ADDR" ] && BIND_ARGS=(--bind "$BIND_ADDR")
  bash "$SCRIPT_DIR/signoz-setup.sh" "${BIND_ARGS[@]}" || true
  PENDING+=("Instalar o SigNoz pelo Foundry (https://signoz.io/docs/install/docker/) e depois: bash $SCRIPT_DIR/signoz-setup.sh --verify")
fi

# ── Resumo ──────────────────────────────────────────────────────────────────
echo ""
echo "════════════════════════════════════════════════════════════"
if [ "${#FAILED[@]}" -gt 0 ]; then
  echo "Etapas que falharam (${#FAILED[@]}):"
  for f in "${FAILED[@]}"; do echo "   ❌ $f"; done
  echo ""
fi

echo "Pendências que exigem você (${#PENDING[@]}):"
i=1
for p in "${PENDING[@]}"; do
  echo "   $i) $p"
  i=$((i + 1))
done
echo "════════════════════════════════════════════════════════════"

[ "$DRY_RUN" = true ] && echo "" && echo "Dry-run: nada foi alterado. Repita sem --dry-run para aplicar."
[ "${#FAILED[@]}" -gt 0 ] && exit 1
exit 0
