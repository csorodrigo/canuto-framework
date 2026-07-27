# ADR-0007 — O framework roda onde a sessão roda; a VPS deixa de ser periferia

Data: 2026-07-27 · Status: aceito

## Contexto

Duas pressões independentes chegaram na mesma semana:

1. A cota de GitHub Actions da conta esgotou. Os jobs passaram a "falhar" em
   2 segundos com `runner_id: 0`, sem log — assinatura de runner nunca alocado.
   O PR #90 do plomes ficou 10h bloqueado por isso, sem nenhuma falha de código.
2. O desenvolvimento começou a migrar para a VPS (papiro) para aliviar disco e
   RAM do Mac.

O ponto 2 quebra uma premissa que estava embutida em todo o framework: a de que
a sessão roda no Mac. O `install.sh` recusava Linux explicitamente ("apt/yum are
not used by this installer") e o vault global vivia em `~/.canuto/vault` do Mac
como fonte da verdade.

Havia ainda um bug latente que só aparece em Linux: `ensure_brew_formula sg
ast-grep` dava falso positivo porque `/usr/bin/sg` é o `sg` do shadow (set
group), homônimo do alias do ast-grep. O instalador reportaria "ast-grep já
instalado" e o MCP quebraria silenciosamente.

## Opções consideradas

1. **Manter o Mac como única máquina de sessão** e usar a VPS só como servidor
   burro (deploy, banco) — rejeitada: é exatamente o que está sendo desfeito, e
   deixaria o instalador quebrado justamente na máquina que vai crescer.
2. **Um instalador separado para Linux** (`install-linux.sh`) — rejeitada: dois
   instaladores divergem em silêncio, e a lista de dependências é a mesma. É a
   mesma classe de erro do `models.yaml` versus a doc (ADR de defasagem).
3. **Abstrair o gerenciador de pacotes no instalador único** e classificar as
   dependências em obrigatórias e opcionais — aceita.

## Decisão

- `install.sh` detecta o gerenciador em runtime: `brew` (macOS) ou `apt`/`dnf`
  (Linux). Mesma lista de dependências, `ensure_dep <cmd> <label> <brew>
  <linux_pkg> <npm> <req|opt>` como ponto único.
- `rtk`, `bun`, `gh` e `gcloud` viram **opcionais**: não têm caminho de
  instalação fora do Homebrew e o framework roda sem eles. Marcá-los como
  obrigatórios fazia toda instalação Linux terminar em falha — um sinal falso
  que treina o usuário a ignorar o relatório de dependências.
- Presença de dependência é verificada por `dep_present`, que valida a
  identidade da ferramenta quando o nome é ambíguo (`sg`), em vez de confiar só
  em `command -v`.
- A infraestrutura de VPS mora em `.agents/vps/` e **fora de
  `FRAMEWORK_FILES`**: é infra de máquina, não artefato de projeto. Nenhum repo
  de consumidor carrega cópia dela.
- O vault Canuto inverte a direção: a VPS hospeda o working vault oficial, o Mac
  vira espelho. Ambos empurram para um hub bare (`/srv/canuto/vault.git`).
- CI dos repos privados passa a rodar em runner self-hosted na VPS. Runner em
  repo público é vetado no script (execução arbitrária via PR), sem flag de
  escape.

## Consequências

- (+) O framework instala e roda na VPS; a migração deixa de depender de
  trabalho manual em cada máquina.
- (+) O CI deixa de depender de cota — a falha que bloqueou o #90 não se repete.
- (+) A memória sobrevive ao Mac: o vault oficial está fora dele.
- (−) O `--doctor` em Linux relata `rtk` ausente como aviso permanente. É
  honesto (o RTK realmente não está lá) e preferível a falhar a instalação.
- (−) Duas máquinas escrevendo no mesmo vault podem divergir. Mitigação: o
  `--client` nunca resolve merge sozinho — relata os dois SHAs e para, exigindo
  `--merge-unrelated` explícito. Conflito de vault é decisão humana.
