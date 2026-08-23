# ADR-0016 — `--yes` não autoriza commit

Data: 2026-08-23 · Status: aceito

## Contexto

O instalador usava a mesma confirmação para prosseguir com uma operação e para
criar um commit Git. Em stdin não interativo, `confirm_yes` adotava o default
positivo; portanto `curl | bash`, `--yes` e o update multi-projeto podiam criar
commits sem uma autorização específica para o estado Git. Isso contradiz o
contrato operacional: código aplicado, staging e commit são estados distintos.

## Decisão

- `--yes` responde somente a prompts operacionais.
- O default é `--no-commit`: mudanças ficam no working tree, sem tocar o index.
- Somente `--commit` autoriza staging e commit.
- O commit usa uma lista explícita de paths pertencentes ao framework e
  `git commit --only`; mudanças staged não relacionadas ficam fora do commit e
  permanecem staged depois dele.
- Flags desconhecidas, modos conflitantes e valores ausentes falham com exit 64
  antes de qualquer mutação.
- `--dry-run` resolve o modo e encerra antes de criar arquivos no projeto.
- `canuto-update-all.sh` encaminha `--commit` somente quando recebeu essa flag e,
  sem ela, registra no relatório que as mudanças aplicadas ficaram não
  commitadas.

## Provas exigidas

- `--yes` sem `--commit` preserva HEAD e index, deixando apenas o working-tree
  diff inspecionável.
- `--commit` cria commit apenas com os paths declarados pelo fluxo.
- Um arquivo do usuário já staged antes do helper não entra no commit do
  framework e continua staged depois dele.
- `--help`, `--dry-run` e erros de uso não deixam artefatos no diretório.
- O update multi-projeto só encaminha `--commit` após autorização explícita.

## Consequências

- (+) automação não transforma confirmação genérica em autorização Git.
- (+) o usuário inspeciona o diff antes de decidir publicar um commit.
- (+) commits do framework não absorvem nem desmarcam staging alheio.
- (-) fluxos que dependiam do commit implícito precisam acrescentar `--commit`.
