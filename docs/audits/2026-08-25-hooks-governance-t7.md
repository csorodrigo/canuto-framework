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

O próprio Canuto agora é um consumidor versionado em
`.agents/hooks/manifest.json`. Ele declara somente o fluxo de receipt, commit e
pull request, com o argv canônico exato `bash test-framework.sh`; não declara
um comando de deploy inexistente. A suíte direcionada carrega esse manifesto,
recusa argv diferente e prova record, verificação Stop e vínculo à identidade
remota em repositório hermético.

O inventário `audit/t7-repo-policy-consumer-inventory.json` delimita os dois
consumidores conhecidos por cada política. Canuto registra explicitamente
`deploy-target` como `no-policy/not-applicable`, pois não possui comando de
deploy do repositório. Papiro permanece pendente até versionar seu próprio
`.agents/hooks/manifest.json` com `npm run typecheck:codex`,
`npm run deploy:prod`, o argv de validação
`npm run test -- tests/dobra-compose-writer-guard.test.ts` e as políticas de
commit/PR ligadas aos cinco arquivos do owner. Portanto o receipt geral de
consumidores continua `blocked` independentemente do estado de CU-23.

Um item permanece explicitamente bloqueado:

- CU-23 pertence a Papiro/Dobra. O owner candidato está no PR Papiro #849, head
  `74f1462b021535aea9a7bfee8f27b6a924e47e43`, mas o PR ainda está aberto e o
  `origin/main` observado (`bd8c248b6bd4177bb2fd26f86a436026fe984fb5`)
  divergiu e não contém esse head. O receipt versionado permanece `blocked`; CU-23 não entra
  nos manifests de aposentadoria até merge, containment e hashes do owner serem
  revalidados.

O gate do owner CU-23 é deliberadamente separado do receipt geral de
consumidores. Quando estiver comprovado, CU-23 deve entrar em um manifest de
aposentadoria próprio, com precondition apontando apenas para
`audit/t7-papiro-dobra-owner-receipt.json`. O reconciliador já aceita múltiplas
preconditions, mas CU-23 não foi incluído enquanto o receipt permanece
`blocked`.

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
