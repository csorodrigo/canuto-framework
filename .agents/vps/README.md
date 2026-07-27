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

## Comando único

```bash
git clone https://github.com/csorodrigo/canuto-framework.git ~/canuto-framework
sudo bash ~/canuto-framework/.agents/vps/bootstrap.sh \
     --repo csorodrigo/plomes-route-optimizer --dry-run
```

O `bootstrap.sh` roda as etapas abaixo na ordem certa, cada uma idempotente, e
termina com a lista numerada do que ainda exige você. Confira no `--dry-run` e
repita sem a flag para aplicar. Uma etapa que falha **não** aborta as outras.

### Rodando de fora (do Mac, via ssh)

Use `ssh -t` — o `-t` aloca o TTY para o `sudo` pedir a senha:

```bash
ssh -t papiro 'sudo bash ~/canuto-framework/.agents/vps/bootstrap.sh \
    --repo csorodrigo/plomes-route-optimizer --dry-run'
```

> **Não habilite `NOPASSWD: ALL` para contornar o prompt de senha.** É uma
> troca ruim: converte uma senha digitada uma vez numa escalada permanente para
> root disponível a qualquer processo rodando como o seu usuário — postinstall
> de npm, dependência comprometida, agente que escorregou. Esta é justamente a
> máquina que hospeda produção e roda um runner de CI que **executa código dos
> repositórios**. Se um dia precisar mesmo de automação sem senha, escope por
> comando, nunca `ALL`:
>
> ```
> rodrigo ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart actions.runner.*
> ```

Flags: `--repo` (repetível), `--skip runner,vault,kuma,signoz`, `--bind <ip>`,
`--assume-private`, `--dry-run`.

## Ordem recomendada

| # | Script | Ganho | Custo |
|---|--------|-------|-------|
| 1 | `runner-setup.sh` | CI volta a rodar, sem consumir cota | ~15 min |
| 2 | `vault-remote-setup.sh` | Vault oficial na VPS, Mac vira espelho | ~10 min |
| 3 | `uptime-kuma-setup.sh` | Alerta quando um app em produção cai | ~5 min |
| 4 | `signoz-setup.sh` | Preflight + auditoria de exposição do SigNoz | ~20 min, pede ~4GB de RAM |

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
bash .agents/vps/signoz-setup.sh --bind 100.x.y.z   # preflight + instruções
bash .agents/vps/signoz-setup.sh --verify           # audita exposição das portas
```

**Este script não instala o SigNoz** — e isso é deliberado. Ao testá-lo contra o
repositório real descobrimos que o projeto **descontinuou o `install.sh` e os
manifests docker-compose de `deploy/`** em favor do Foundry (`foundryctl`). Uma
automação por cima de um contrato que acabou de mudar viraria defasagem
silenciosa; a instalação segue a [doc oficial](https://signoz.io/docs/install/docker/).

O que o script faz é o que dá para garantir mecanicamente:

- **preflight** — docker no ar, RAM (o ClickHouse morre por OOM abaixo de ~4GB), disco;
- **guidance** — os trechos exatos de `~/.claude/settings.json` e `~/.codex/config.toml`;
- **`--verify`** — roda `ss`/`netstat` e **falha com exit 1** se 4317/4318/8080
  estiverem escutando em `0.0.0.0`.

Essa última é a que mais importa: o endpoint OTLP carrega metadados das suas
sessões e o default de quase todo compose é `0.0.0.0`. Numa VPS com IP público
isso publica sua telemetria. Rode `--verify` depois de instalar e depois de cada
upgrade.

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
