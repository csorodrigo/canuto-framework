# T7 — políticas locais por manifesto

O T7 troca automações globais que escreviam ou liberavam ações por políticas
opt-in do repositório. O manifesto `.agents/hooks/manifest.json` declara os
comandos de build/typecheck e deploy permitidos; commit e pull request exigem
receipt ligado a worktree, sessão, SHA, tree e, para PR, origem remota.
O CLI local `validation-receipt-cli.mjs` executa argv após `--` sem shell e só
grava receipt quando o processo realmente retorna zero. Ele também verifica e
limpa cobertura por arquivo; `--remote` consulta `origin` e só emite prova
quando a branch remota aponta para o mesmo HEAD. `--command` não existe e não
pode autodeclarar sucesso.
O manifesto mantém uma allowlist `allowedArgv` exata; receipt gravado ou
forjado com argv diferente é recusado no CLI, no commit/PR e no Stop.

O estado desejado Claude deixa de publicar CU-01, CU-02, CU-03, CU-05, CU-06,
CU-25, CU-28, CU-33 e CU-37, publica o runner CU-58 e o gate final CU-59. O
lote Codex remove CX-11/CX-13 e adiciona CX-18. Os manifests de aposentadoria
são plan-only e possuem uma precondition verificável: enquanto
`audit/t7-consumer-migration-receipt.json` não estiver `ready` com o hash
fixado, até o preview é recusado. Nenhuma configuração instalada é alterada por
este commit.

Um item permanece explicitamente bloqueado:

- CU-23 pertence a Papiro/Dobra. Ele só entra em uma futura revisão do manifest
  depois do receipt do owner; não houve importação ou aposentadoria por
  inferência nesta worktree.

CU-01 é inline e não possui artefato a remover. O reconciliador passou a aceitar
comandos inline somente em aposentadorias registration-only, que fazem match
exato e jamais executam o texto; comandos ativos continuam restritos a um único
executável `~/...` com hash e modo declarados.

O wrapper de merge e a biblioteca anti-clobber agora têm fonte no framework em
`.agents/tools/`. O instalador copia os mesmos bytes para
`~/.claude/scripts/`, preservando o caminho operacional existente. O wrapper
consulta origem e PR remotos, fixa o head SHA, revalida head/base antes do PUT e
não toca a branch local.

Validação direcionada cobre opt-in exato, repositório não participante,
worktrees/sessões diferentes, receipt stale, clearing seletivo, prova remota,
comando de validação falhando/forjado, Stop com receipt atual, preservação de
entradas externas, precondition bloqueada, idempotência e rollback sintético.
