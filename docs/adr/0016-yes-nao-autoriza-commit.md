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
  `git commit --only`; mudanças staged não relacionadas ficam fora do commit.
- Flags desconhecidas, modos conflitantes e valores ausentes falham com exit 64
  antes de qualquer mutação.
- `--dry-run` resolve o modo e encerra antes de criar arquivos no projeto.
- `canuto-update-all.sh` encaminha `--commit` somente quando recebeu essa flag.

## Consequências

- (+) automação não transforma confirmação genérica em autorização Git.
- (+) o usuário inspeciona o diff antes de decidir publicar um commit.
- (+) commits do framework não absorvem staging alheio.
- (-) fluxos que dependiam do commit implícito precisam acrescentar `--commit`.
