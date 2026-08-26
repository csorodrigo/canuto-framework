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
deploy do repositório. Papiro versionou seu próprio
`.agents/hooks/manifest.json` com `npm run typecheck:codex`,
`npm run deploy:prod`, o argv de validação
`npm run test -- tests/dobra-compose-writer-guard.test.ts` e as políticas de
commit/PR ligadas aos cinco arquivos operacionais do owner. O PR #850 passou o
gate oficial com 355 arquivos, 6.232 testes aprovados e 5 skips; foi merged em
`676a3124429546cd9e7780dded9ff32e496547f5`, com tree idêntica ao candidato
`a8a6e1bbe95ffd33a5492283fd6e9afe71b110a2`. O receipt geral de consumidores
está `ready`, sem blockers, e fixa o hash do inventário que contém essa prova.
Os manifests gerais declaram `repo-policy-consumers-v1`: o reconciliador lê o
inventário real dentro de `.agents/hooks`, confere seu SHA-256, o conjunto exato
de consumidores/políticas, ausência de pendências e o vínculo cruzado entre PR,
candidate/merge trees, hash do manifesto e gate verde. O receipt inclui a prova
do run `tc-MacBook-Air-2-t7-papiro-policy-94394`; repinar apenas arquivos JSON
contraditórios continua falhando antes de `plan` ou `apply`. Receipt e inventário
são distribuídos byte a byte pelo instalador e pelo E2E de consumidores.

O owner CU-23 está comprovado. O PR Papiro #849 foi merged a partir do head
`23e5bc067d700d19473e9a6aebe5deff1fd05102` no commit
`5e7ddf90ca31313947ba2697c695dfa306f83d88`. Candidate e merge têm a mesma tree
`9124f2c617b251fa54fcaa2675d146a2bca58b05`; o `origin/main` observado aponta
para o merge, a comparação é `identical` e o conteúdo está contido. Os hashes
verificados no merge são `c5c3d973...965d` para o manifest e
`d4ecea86...84b6` para o source. O receipt owner está `ready`, sem blockers.

O gate do owner CU-23 é deliberadamente separado do receipt geral de
consumidores. O manifest `managed-hooks-retirement-t7-cu23.claude.json` contém
somente CU-23 e sua única precondition aponta para
`audit/t7-papiro-dobra-owner-receipt.json`, com hash fixado e status requerido
`ready`. O contrato `merged-owner-artifact-v1` também exige PR `MERGED`, SHA do
merge, containment verdadeiro, comparação `ahead`/`identical`, blockers vazios
e prova dos hashes do manifest e source vinculada ao commit de merge e ao
repositório. As expectativas de artifact ID `CU-23`, repository
`csorodrigo/papiro`, owner `repository:Papiro/Dobra` e package `dobra` ficam no
próprio precondition e são comparadas com receipt, canonical repository e hash
proof. Mudar apenas `status` para `ready` não libera o manifest. Manifest e
receipt owner integram `FRAMEWORK_FILES`, portanto install/update e o export de
consumidores preservam o par inseparável. O receipt real agora satisfaz o
contrato, então plan/apply do manifest CU-23 são permitidos e continuam sujeitos
ao fingerprint explícito. O receipt geral de consumidores não referencia CU-23;
ele governa somente a conclusão independente da migração das políticas locais.

CU-01 é inline e não possui artefato a remover. O reconciliador passou a aceitar
comandos inline somente em aposentadorias registration-only, que fazem match
exato e jamais executam o texto. Evento, matcher, comando, presença/valor de
timeout e metadados declarados precisam coincidir; variantes permanecem
externas. O metadata `async: true` do lote ccgram anterior foi explicitado para
preservar a compatibilidade desse retirement. Comandos ativos continuam
restritos a um único executável `~/...` com hash e modo declarados.

O wrapper de merge e a biblioteca anti-clobber agora têm fonte no framework em
`.agents/tools/`. O instalador copia os mesmos bytes para
`~/.claude/scripts/`, preservando o caminho operacional existente. O wrapper
consulta origem e PR remotos, fixa o head SHA, revalida head/base antes do PUT e
não toca a branch local.

Validação direcionada cobre opt-in exato, repositório não participante,
worktrees/sessões diferentes, receipt stale, clearing seletivo, prova remota,
comando de validação falhando/forjado, Stop com receipt atual, preservação de
entradas externas, precondition bloqueada, idempotência e rollback sintético.
