# Camada VPS — infraestrutura do framework fora do Mac

> Scripts para rodar **na VPS** (papiro), não em projeto de consumidor.
> Por isso eles **não** entram em `FRAMEWORK_FILES`: nenhum projeto precisa
> carregar uma cópia disto. Use um clone do `canuto-framework` na VPS.

## Por que existe

Duas pressões chegaram juntas em 2026-07:

1. **A cota de GitHub Actions da conta esgotou** e travou o CI de todos os
   repos privados — jobs "falhavam" em 2 segundos com `runner_id: 0` e sem log,
   sintoma de runner nunca alocado (não é erro de código).
2. **O desenvolvimento está migrando para a VPS** para aliviar disco e RAM do
   Mac. Isso muda uma premissa do framework: a sessão deixa de rodar sempre no
   Mac, então instalador, heartbeats e memória precisam funcionar em Linux.

## Ordem recomendada

| # | Script | Ganho | Custo |
|---|--------|-------|-------|
| 1 | `runner-setup.sh` | CI volta a rodar, sem consumir cota | ~15 min |
| 2 | `vault-remote-setup.sh` | Vault oficial na VPS, Mac vira espelho | ~10 min |
| 3 | `uptime-kuma-setup.sh` | Alerta quando um app em produção cai | ~5 min |
| 4 | `signoz-setup.sh` | Painel de custo/tokens/latência das sessões | ~20 min, pede ~4GB de RAM |

O SigNoz é o último de propósito: é o mais pesado e o único que pode não caber,
dependendo do tamanho da VPS. O script avisa se a RAM for insuficiente.

## 1. GitHub Actions self-hosted runner

```bash
bash .agents/vps/runner-setup.sh --repo csorodrigo/plomes-route-optimizer
```

Cria um usuário dedicado sem privilégios, baixa o runner, registra como serviço
systemd. Sem `--token`, busca o token de registro via `gh` autenticado.

**Só repositório privado.** Em repo público, qualquer um abre um PR que executa
código arbitrário na sua VPS — o script recusa e não há flag que valha o risco.

Depois de registrar, os workflows precisam pedir o runner:

```yaml
runs-on: [self-hosted, linux, canuto-vps]   # era: ubuntu-latest
```

O usuário do runner **não** entra no grupo `docker` (seria equivalente a root).
Se um job precisar de docker, decida isso conscientemente.

## 2. Vault Canuto: oficial na VPS, espelho no Mac

```bash
# na VPS
bash .agents/vps/vault-remote-setup.sh --server

# no Mac (URL impressa pelo passo acima)
bash .agents/vps/vault-remote-setup.sh --client ssh://papiro/srv/canuto/vault.git
```

Topologia:

```
VPS  /srv/canuto/vault.git   bare — hub canônico
VPS  ~/.canuto/vault         working vault OFICIAL (sessões da VPS)  ──┐
Mac  ~/.canuto/vault         clone/espelho (Obsidian abre este)     ──┘ ambos empurram para o hub
```

O autosync na VPS commita e empurra a cada 10 min (`--interval`). No Mac, o
plugin Obsidian Git faz o mesmo — ligue `autoPullInterval: 10`.

**O script nunca destrói nada.** Se os dois lados divergirem, ele relata os dois
SHAs e para; unir históricos exige `--merge-unrelated` explícito.

## 3. Uptime Kuma

```bash
bash .agents/vps/uptime-kuma-setup.sh
```

Monitora os **produtos no ar** (plomes, dashboards, papiro) — complementar ao
SigNoz, que monitora as **sessões de desenvolvimento**. Sobe em `127.0.0.1:3001`;
acesse por túnel SSH ou passe `--bind` com um IP de rede privada.

Dica de monitor: aponte para um endpoint de health real, não só para a home —
uma home estática continua respondendo 200 com o backend morto.

## 4. SigNoz

```bash
bash .agents/vps/signoz-setup.sh                    # só local
bash .agents/vps/signoz-setup.sh --bind 100.x.y.z   # IP Tailscale
```

**Nunca exponha 4317/4318 no IP público.** O endpoint OTLP carrega metadados das
suas sessões. O default do script é `127.0.0.1`; para receber telemetria do Mac,
use Tailscale/WireGuard e passe o IP privado em `--bind`.

Os nomes dos serviços mudam entre releases do SigNoz, então o script descobre o
coletor com `docker compose config --services` em vez de chutar, e desfaz o
override se o compose resultante não validar.

## Rede privada (pré-requisito do SigNoz remoto)

```bash
# nos dois: VPS e Mac
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up
tailscale ip -4      # o IP 100.x.y.z da VPS é o que vai em --bind
```

## O que **não** vai para a VPS

- **Hooks de sessão** (`~/.claude/hooks/`): vivem onde a sessão roda. Migram
  junto com você — rodando `install.sh` na VPS, não copiando à mão.
- **Heartbeats**: `heartbeat-run.sh --install-cron` já cobre Linux (o
  `--install-launchd` é o caminho macOS). Instale onde a sessão roda.
- **Segredos**: nada de `.env` ou `BW_SESSION` nestes scripts. Use
  `env-bitwarden-sync.sh`.

## Instalar o framework na própria VPS

Desde 2026-07-27 o `install.sh` funciona em Linux: detecta `apt`/`dnf` quando
não há Homebrew e degrada `rtk`/`gcloud`/`bun` para opcionais em vez de falhar a
instalação inteira. Na VPS:

```bash
curl -fsSL https://raw.githubusercontent.com/csorodrigo/canuto-framework/main/install.sh | bash
```
