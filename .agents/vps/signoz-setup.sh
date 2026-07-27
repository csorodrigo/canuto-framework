#!/usr/bin/env bash
# signoz-setup.sh — preflight e verificação de segurança do SigNoz na VPS.
#
# O que o SigNoz mostra: cada tool call com duração, tokens por modelo
# (claude_code.token.usage), custo em USD (claude_code.cost.usage) e as métricas
# próprias do framework (canuto.session.rework_loop_rate, memory_miss_rate...).
# Claude Code e Codex emitem isso via OpenTelemetry; o SigNoz é quem coleta.
#
# ⚠️  Este script NÃO instala o SigNoz. Em 2026 o projeto descontinuou o
# `install.sh` e os manifests docker-compose de `deploy/` em favor do Foundry
# (`foundryctl`) — automatizar por cima disso seria chutar um contrato que muda.
# O que ele faz é o que dá para garantir daqui:
#   • preflight  — a VPS aguenta? (RAM, disco, docker)
#   • guidance   — o comando oficial + a configuração de endpoint do Mac/Codex
#   • --verify   — a porta OTLP está exposta na internet? (esta é a que morde)
#
# Uso (na VPS):
#   bash signoz-setup.sh                    # preflight + instruções
#   bash signoz-setup.sh --bind 100.x.y.z   # idem, já com o IP privado nos exemplos
#   bash signoz-setup.sh --verify           # audita uma instalação existente

set -euo pipefail

BIND_ADDR=""
VERIFY=false

usage() { sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0; }

while [ $# -gt 0 ]; do
  case "$1" in
    --bind) BIND_ADDR="${2:-}"; shift 2 ;;
    --verify) VERIFY=true; shift ;;
    -h|--help) usage ;;
    *) echo "Argumento desconhecido: $1" >&2; exit 2 ;;
  esac
done

die() { echo "❌ $*" >&2; exit 1; }
log() { echo "→ $*"; }
ok()  { echo "✅ $*"; }
warn(){ echo "⚠️  $*" >&2; }

PORTS="4317 4318 8080"

# ── Verificação de exposição ────────────────────────────────────────────────
# O endpoint OTLP carrega metadados das suas sessões (prompts redigidos, mas
# nomes de ferramenta, custos e paths não). Numa VPS com IP público, subir a
# stack com bind 0.0.0.0 — que é o default de quase todo compose — publica isso
# para a internet inteira. Esta é a única parte que dá para checar mecanicamente.
verify_exposure() {
  local found_listener=false exposed=false

  if ! command -v ss >/dev/null 2>&1 && ! command -v netstat >/dev/null 2>&1; then
    die "ss/netstat indisponíveis — instale iproute2 para auditar as portas."
  fi

  local listing=""
  if command -v ss >/dev/null 2>&1; then
    listing=$(ss -ltnH 2>/dev/null || true)
  else
    listing=$(netstat -ltn 2>/dev/null || true)
  fi

  for port in $PORTS; do
    local lines
    lines=$(printf '%s\n' "$listing" | awk -v p=":$port" '$0 ~ p" " || $4 ~ p"$" {print $4}' | sort -u)
    [ -n "$lines" ] || continue
    found_listener=true
    while IFS= read -r addr; do
      [ -n "$addr" ] || continue
      case "$addr" in
        127.0.0.1:*|\[::1\]:*)
          ok "porta $port escutando só em loopback ($addr)" ;;
        0.0.0.0:*|\[::\]:*|*\*:*)
          exposed=true
          warn "porta $port escutando em TODAS as interfaces ($addr) — telemetria exposta" ;;
        *)
          ok "porta $port escutando em $addr (confirme que é IP de rede privada)" ;;
      esac
    done <<< "$lines"
  done

  if [ "$found_listener" = false ]; then
    warn "Nenhuma das portas $PORTS está escutando — SigNoz não parece estar rodando aqui."
    return 0
  fi

  if [ "$exposed" = true ]; then
    echo ""
    echo "Como fechar:"
    echo "   1) reconfigure o bind para o IP da rede privada (Tailscale/WireGuard)"
    echo "   2) bloqueie as portas na borda:"
    for port in $PORTS; do echo "        ufw deny ${port}/tcp"; done
    return 1
  fi

  ok "Nenhuma porta do SigNoz exposta em interface pública."
  return 0
}

if [ "$VERIFY" = true ]; then
  echo "Auditando exposição das portas do SigNoz..."
  verify_exposure
  exit $?
fi

# ── Preflight ───────────────────────────────────────────────────────────────
echo "Preflight do SigNoz nesta máquina"
echo ""

if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    ok "docker disponível e daemon no ar ($(docker version --format '{{.Server.Version}}' 2>/dev/null || echo '?'))"
  else
    warn "docker instalado mas o daemon não responde (systemctl start docker)"
  fi
else
  warn "docker não instalado — https://docs.docker.com/engine/install/"
fi

# O ClickHouse por trás do SigNoz é o componente pesado: abaixo de ~4GB de RAM
# ele é morto pelo OOM killer no meio de queries e a stack parece "instável".
TOTAL_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo 2>/dev/null || echo 0)
if [ "$TOTAL_MB" -gt 0 ] && [ "$TOTAL_MB" -lt 3500 ]; then
  warn "RAM total: ${TOTAL_MB}MB — o SigNoz pede ~4GB. Espere OOM e queries lentas."
  warn "Com esta RAM, o melhor custo-benefício é manter o SigNoz no Mac e usar a VPS para runner/vault/uptime."
elif [ "$TOTAL_MB" -gt 0 ]; then
  ok "RAM total: ${TOTAL_MB}MB (suficiente)."
fi

AVAIL_GB=$(df -BG --output=avail "$HOME" 2>/dev/null | tail -1 | tr -dc '0-9' || echo 0)
if [ "${AVAIL_GB:-0}" -gt 0 ]; then
  if [ "$AVAIL_GB" -lt 20 ]; then
    warn "Disco livre: ${AVAIL_GB}GB — telemetria cresce rápido; configure retenção curta."
  else
    ok "Disco livre: ${AVAIL_GB}GB."
  fi
fi

EXAMPLE_ADDR="${BIND_ADDR:-<ip-tailscale-da-vps>}"

cat <<INSTRUCTIONS

── Instalação ────────────────────────────────────────────────────────────────

O SigNoz descontinuou o install.sh e os manifests docker-compose de deploy/.
O caminho suportado hoje é o Foundry:

    https://signoz.io/docs/install/docker/

Siga a doc oficial (o comando do foundryctl muda entre versões — por isso este
script não o reproduz: uma linha chumbada aqui viraria defasagem silenciosa,
exatamente o que .agents/config/models.yaml existe para evitar).

── Rede privada primeiro ─────────────────────────────────────────────────────

Antes de subir, tenha Tailscale nos dois lados:

    curl -fsSL https://tailscale.com/install.sh | sh && tailscale up
    tailscale ip -4        # o 100.x.y.z desta VPS

Configure o SigNoz para escutar nesse IP, NUNCA em 0.0.0.0.

── Depois de subir, no Mac ───────────────────────────────────────────────────

~/.claude/settings.json → env:
    "OTEL_EXPORTER_OTLP_ENDPOINT": "http://$EXAMPLE_ADDR:4317"

~/.codex/config.toml:
    [otel] exporter = { otlp-grpc = { endpoint = "http://$EXAMPLE_ADDR:4317" } }

── Confira que não vazou ─────────────────────────────────────────────────────

    bash $0 --verify

Roda ss/netstat e falha se 4317/4318/8080 estiverem escutando em 0.0.0.0.
Vale rodar de novo depois de qualquer upgrade do SigNoz.

INSTRUCTIONS
