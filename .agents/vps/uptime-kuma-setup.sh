#!/usr/bin/env bash
# uptime-kuma-setup.sh — monitoramento de uptime dos apps em produção.
#
# Complementa o SigNoz: o SigNoz observa as *sessões de desenvolvimento*
# (tokens, custo, tool calls); o Uptime Kuma observa os *produtos no ar*
# (plomes, dashboards, papiro) e avisa quando caem. Leve — roda em ~100MB.
#
# Uso (na VPS):
#   bash uptime-kuma-setup.sh                  # 127.0.0.1:3001 (via SSH tunnel)
#   bash uptime-kuma-setup.sh --bind 100.x.y.z # IP privado (Tailscale)
#   bash uptime-kuma-setup.sh --down

set -euo pipefail

BIND_ADDR="127.0.0.1"
PORT="3001"
STACK_DIR="${UPTIME_KUMA_DIR:-$HOME/uptime-kuma}"
DOWN=false

usage() { sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0; }

while [ $# -gt 0 ]; do
  case "$1" in
    --bind) BIND_ADDR="${2:-}"; shift 2 ;;
    --port) PORT="${2:-}"; shift 2 ;;
    --dir) STACK_DIR="${2:-}"; shift 2 ;;
    --down) DOWN=true; shift ;;
    -h|--help) usage ;;
    *) echo "Argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done

die() { echo "❌ $*" >&2; exit 1; }
log() { echo "→ $*"; }
ok()  { echo "✅ $*"; }

command -v docker >/dev/null 2>&1 || die "docker é necessário."
docker compose version >/dev/null 2>&1 || die "docker compose (plugin v2) é necessário."

mkdir -p "$STACK_DIR"
COMPOSE="$STACK_DIR/docker-compose.yml"

if [ "$DOWN" = true ]; then
  [ -f "$COMPOSE" ] || die "Stack não encontrada em $STACK_DIR."
  (cd "$STACK_DIR" && docker compose down)
  ok "Uptime Kuma derrubado (dados preservados no volume)."
  exit 0
fi

cat > "$COMPOSE" <<COMPOSE_EOF
# Gerado por .agents/vps/uptime-kuma-setup.sh — não editar à mão.
services:
  uptime-kuma:
    image: louislam/uptime-kuma:1
    container_name: uptime-kuma
    restart: unless-stopped
    ports:
      - "$BIND_ADDR:$PORT:3001"
    volumes:
      - uptime-kuma-data:/app/data

volumes:
  uptime-kuma-data:
COMPOSE_EOF
ok "Compose escrito: $COMPOSE"

cd "$STACK_DIR"
docker compose config >/dev/null 2>&1 || die "compose inválido."
log "Subindo Uptime Kuma..."
docker compose up -d

echo ""
ok "Uptime Kuma no ar em http://$BIND_ADDR:$PORT"
if [ "$BIND_ADDR" = "127.0.0.1" ]; then
  echo "   (só local — acesse do Mac com: ssh -L $PORT:127.0.0.1:$PORT <vps>)"
fi
echo ""
echo "Primeiro acesso: crie a conta admin na própria UI (não há usuário padrão)."
echo ""
echo "Monitores que valem a pena cadastrar:"
echo "   • HTTP(s) da home de cada app em produção — intervalo 60s"
echo "   • HTTP(s) de um endpoint de health/API, não só da home (a home pode ser"
echo "     estática e continuar respondendo com o backend morto)"
echo "   • TCP na porta do banco, se ele for externo"
echo "   • Notificação: Telegram ou e-mail (Settings → Notifications)"
echo ""
echo "Derrubar: bash $0 --down"
