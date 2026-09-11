# Vault Integrator — rollout seguro

Esta é a fundação do modelo **leitura local, escrita serializada**. Ela não faz
merge, não apaga notas e não reorganiza o vault.

## Componentes

- `vault-submit.py`: cria envelopes no outbox e faz flush local/SSH.
- `vault-integrator.py`: aplica envelopes sob lock exclusivo, valida CAS e gera
  receipts.
- `vault-integrator-setup.sh`: instala server/client sem ativar publicação por
  padrão.
- `schemas/`: contratos JSON documentais para envelopes e receipts.

## Instalar no Papiro

```bash
cd ~/canuto-framework
bash .agents/vps/vault-integrator-setup.sh --server
```

Isso instala os binários e cria inbox/state, mas **não agenda cron, não commita e
não faz push**. Primeiro valide manualmente:

```bash
canuto-vault-integrator status
canuto-vault-integrator process
```

Para ativar publicação, depois de confirmar que o vault é um clone Git limpo,
está na branch `main` e que os writers legados foram identificados. O runner
recusa branch diferente ou qualquer WIP tracked/untracked:

```bash
bash .agents/vps/vault-integrator-setup.sh \
  --server --commit --push --interval 2
```

## Instalar na Dobra ou no Mac

Use o caminho absoluto do inbox no Papiro:

```bash
bash .agents/vps/vault-integrator-setup.sh \
  --client \
  --remote-host papiro \
  --remote-inbox /home/USUARIO/.canuto/vault-spool/inbox
```

Criar uma nota de sessão:

```bash
canuto-vault-submit create \
  --target projects/papiro/sessions/2026-08-23.md \
  --content-file /tmp/session.md \
  --tier hypothesis \
  --source-agent codex \
  --session-id "$CLAUDE_SESSION_ID"

canuto-vault-flush
```

Substituir uma nota existente exige o hash observado:

```bash
HASH=$(sha256sum ~/.canuto/vault/projects/papiro/pending/task.md | awk '{print $1}')
canuto-vault-submit replace \
  --target projects/papiro/pending/task.md \
  --content-file /tmp/task-new.md \
  --expected-sha256 "$HASH" \
  --tier hypothesis
```

No macOS, use `shasum -a 256` no lugar de `sha256sum`.

## Tier curado

Decisões, instincts, design e digests exigem aprovação explícita:

```bash
canuto-vault-submit create \
  --target projects/papiro/decisions/2026-08-23-single-publisher.md \
  --content-file /tmp/decision.md \
  --tier curated \
  --approval-by rodrigo
```

## Estados e recuperação

```text
~/.canuto/vault-spool/outbox/       propostas ainda no host de origem
~/.canuto/vault-spool/inbox/        propostas recebidas no integrador
~/.canuto/vault-integrator/receipts/
~/.canuto/vault-integrator/processed/
~/.canuto/vault-integrator/rejected/
~/.canuto/vault-integrator/collisions/
~/.canuto/vault-integrator/journal/       transações preparadas
~/.canuto/vault-integrator/recovery/      interrupções que exigem revisão
```

- Falha de entrega mantém o arquivo no outbox.
- Envelope rejeitado preserva payload e razão.
- Mesmo `id` + mesmo hash é idempotente.
- Mesmo `id` + hash diferente vai para `collisions/`.
- Push falho deixa receipt com `publish.status: failed`; rode
  `canuto-vault-integrator publish` para tentar novamente.
- Queda entre mutação e receipt deixa journal e envelope em `recovery/`; o
  integrador não reaplica silenciosamente.

## Limites desta fase

- Somente Markdown em `projects/<slug>/<area>/`.
- Sem delete, move, merge, anexos ou escrita global.
- O integrador não torna writers legados impossíveis sozinho. Não declare o
  vault single-writer até hooks/cron/Obsidian Git terem sido migrados ou
  bloqueados.
