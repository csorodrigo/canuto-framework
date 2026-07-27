#!/usr/bin/env bash
# signoz-setup.sh — sobe o SigNoz (observabilidade das sessões) na VPS.
#
# O que o SigNoz mostra: cada tool call com duração, tokens por modelo
# (claude_code.token.usage), custo em USD (claude_code.cost.usage) e as métricas
# próprias do framework (canuto.session.rework_loop_rate, memory_miss_rate...).
# Claude Code e Codex emitem isso via OpenTelemetry; o SigNoz é quem coleta.
#
# Por que na VPS: o dashboard fica de pé mesmo com o Mac desligado e o histórico
# sobrevive à máquina. Com o desenvolvimento migrando para cá, é também onde as
# sessões passam a rodar — telemetria e sessão no mesmo host.
#
# ⚠️  O endpoint OTLP (4317/4318) carrega metadados das suas sessões. Por padrão
# este script publica as portas SOMENTE em 127.0.0.1. Para receber telemetria do
# Mac, use uma rede privada (Tailscale/WireGuard) e passe --bind <ip-privado>.
# NUNCA aponte para 0.0.0.0 numa VPS com IP público.
#
# Uso (na VPS):
#   bash signoz-setup.sh                      # só local (127.0.0.1)
#   bash signoz-setup.sh --bind 100.x.y.z     # IP Tailscale da VPS
#   bash signoz-setup.sh --down               # derruba (preserva dados)

set -euo pipefail

BIND_ADDR="127.0.0.1"
INSTALL_DIR="${SIGNOZ_DIR:-$HOME/signoz}"
DOWN=false

usage() { sed -n '2,24p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0; }

while [ $# -gt 0 ]; do
  case "$1" in
    --bind) BIND_ADDR="${2:-}"; shift 2 ;;
    --dir) INSTALL_DIR="${2:-}"; shift 2 ;;
    --down) DOWN=true; shift ;;
    -h|--help) usage ;;
    *) echo "Argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done

die() { echo "❌ $*" >&2; exit 1; }
log() { echo "→ $*"; }
ok()  { echo "✅ $*"; }
warn(){ echo "⚠️  $*" >&2; }

command -v docker >/dev/null 2>&1 || die "docker é necessário. Instale: https://docs.docker.com/engine/install/"
docker compose version >/dev/null 2>&1 || die "docker compose (plugin v2) é necessário."

DEPLOY_DIR="$INSTALL_DIR/deploy/docker"

if [ "$DOWN" = true ]; then
  [ -d "$DEPLOY_DIR" ] || die "SigNoz não encontrado em $DEPLOY_DIR."
  (cd "$DEPLOY_DIR" && docker compose down)
  ok "SigNoz derrubado (volumes preservados)."
  exit 0
fi

# ── Recursos ────────────────────────────────────────────────────────────────
# O ClickHouse por trás do SigNoz é o componente pesado: abaixo de ~4GB de RAM
# ele é morto pelo OOM killer no meio de queries e a stack parece "instável".
TOTAL_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)
if [ "$TOTAL_MB" -gt 0 ] && [ "$TOTAL_MB" -lt 3500 ]; then
  warn "RAM total: ${TOTAL_MB}MB. O SigNoz pede ~4GB — espere OOM e queries lentas."
  warn "Considere manter o SigNoz no Mac e usar a VPS só para runner/vault/uptime."
elif [ "$TOTAL_MB" -gt 0 ]; then
  ok "RAM total: ${TOTAL_MB}MB."
fi

AVAIL_GB=$(df -BG --output=avail "$HOME" 2>/dev/null | tail -1 | tr -dc '0-9' || echo 0)
if [ "${AVAIL_GB:-0}" -gt 0 ] && [ "$AVAIL_GB" -lt 20 ]; then
  warn "Disco livre: ${AVAIL_GB}GB. Telemetria cresce — configure retenção curta na UI (Settings → Retention)."
fi

# ── Clone ───────────────────────────────────────────────────────────────────
if [ -d "$DEPLOY_DIR" ]; then
  ok "SigNoz já presente em $INSTALL_DIR."
else
  command -v git >/dev/null 2>&1 || die "git é necessário para clonar o SigNoz."
  log "Clonando SigNoz em $INSTALL_DIR..."
  git clone --depth 1 https://github.com/SigNoz/signoz.git "$INSTALL_DIR" >/dev/null 2>&1 \
    || die "clone falhou."
  [ -d "$DEPLOY_DIR" ] || die "Layout inesperado: $DEPLOY_DIR não existe neste release do SigNoz."
  ok "SigNoz clonado."
fi

cd "$DEPLOY_DIR"

# ── Override de bind ────────────────────────────────────────────────────────
# Os nomes dos serviços mudam entre releases do SigNoz (otel-collector,
# signoz-otel-collector...). Em vez de chutar, descobrimos no compose real.
log "Descobrindo o serviço coletor..."
COLLECTOR=$(docker compose config --services 2>/dev/null | grep -iE 'otel.*collector' | grep -v migrator | head -1 || true)
[ -n "$COLLECTOR" ] || die "Não encontrei o serviço do OTel collector. Rode 'docker compose config --services' em $DEPLOY_DIR e ajuste o override manualmente."
ok "Coletor: $COLLECTOR"

UI=$(docker compose config --services 2>/dev/null | grep -iE '^(signoz|frontend|query-service)$' | head -1 || echo "signoz")

OVERRIDE="$DEPLOY_DIR/docker-compose.override.yaml"
cat > "$OVERRIDE" <<OVERRIDE_EOF
# Gerado por .agents/vps/signoz-setup.sh — não editar à mão (re-rode o script).
# Publica as portas em um endereço específico em vez de 0.0.0.0: numa VPS com
# IP público, 0.0.0.0 expõe a telemetria das sessões para a internet inteira.
services:
  $COLLECTOR:
    ports:
      - "$BIND_ADDR:4317:4317"
      - "$BIND_ADDR:4318:4318"
  $UI:
    ports:
      - "$BIND_ADDR:8080:8080"
OVERRIDE_EOF
ok "Override escrito: $OVERRIDE (bind $BIND_ADDR)"

if ! docker compose config >/dev/null 2>&1; then
  rm -f "$OVERRIDE"
  die "O override não bateu com este release do SigNoz (compose inválido). Override removido; nada foi alterado."
fi
ok "docker compose config válido."

log "Subindo a stack (pode demorar no primeiro boot)..."
docker compose up -d

echo ""
ok "SigNoz no ar."
echo ""
echo "UI:       http://$BIND_ADDR:8080"
if [ "$BIND_ADDR" = "127.0.0.1" ]; then
  echo "          (só local — para acessar do Mac: ssh -L 8080:127.0.0.1:8080 <vps>)"
fi
echo "OTLP:     http://$BIND_ADDR:4317  (gRPC)"
echo ""
echo "Para o Mac enviar telemetria, em ~/.claude/settings.json → env:"
echo "    \"OTEL_EXPORTER_OTLP_ENDPOINT\": \"http://$BIND_ADDR:4317\""
echo "e em ~/.codex/config.toml:"
echo "    [otel] exporter = { otlp-grpc = { endpoint = \"http://$BIND_ADDR:4317\" } }"
echo ""
if [ "$BIND_ADDR" != "127.0.0.1" ]; then
  echo "⚠️  Confirme que $BIND_ADDR é de rede privada (Tailscale/WireGuard) e feche a porta pública:"
  echo "    ufw deny 4317/tcp && ufw deny 4318/tcp && ufw deny 8080/tcp"
fi
echo "Retenção:  UI → Settings → Retention (default guarda demais para VPS pequena)."
echo "Derrubar:  bash $0 --down"
