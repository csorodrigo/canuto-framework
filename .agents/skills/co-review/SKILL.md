---
name: co-review
description: Revisão independente de planos e diffs, com eixos Standards e Spec e rodadas limitadas.
version: 3.0.0
invocacao: model
usedBy: [maestro, architect]
---

## Quando usar

- `/co-brainstorm <tema>`: alternativas independentes.
- `/co-plan <tarefa>`: plano independente para comparação.
- `/co-validate <plano>`: revisão antes da implementação de tarefa M/L.
- XS/S não ativa revisão automática. `CO_REVIEW=false` desliga o trigger de plano.
- `plan-review.sh` está aposentado; não depende de ExitPlanMode.

## Execução e política

Modelo, effort, sandbox e fallback vêm de `.agents/config/models.yaml`.
A interface CLI canônica é:

```bash
~/.codex/bin/codex-delegate.sh reviewer /tmp/review-task.txt /tmp/review-result.md
```

Use `architect` para criar alternativas de plano e `reviewer` para avaliar um
artefato. Ambos são somente leitura. O modelo pedido não comprova o modelo
efetivo: registre `effective_model: UNVERIFIED` se o executor não o comprovar.
Reviewer nunca troca automaticamente de papel, modelo, sessão CCB ou provider.
Falha, timeout, saída parcial/vazia/inválida são `NAO_AVALIADO`; registre causa
sem produzir aprovação. Uma alternativa explicitamente escolhida é outra
execução, com identidade e contexto próprios, e preserva os achados abertos.

Complete sua análise antes de ler a segunda opinião. Use agentes independentes
em paralelo quando disponíveis; entregue só a tarefa e as fontes necessárias.
A revisão sem outro executor disponível permanece não avaliada no respectivo eixo.

## Eixos e modos

| Modo | Trabalho independente | Fonte |
| --- | --- | --- |
| co-brainstorm | Alternativas, custos e restrições | Brief e restrições explícitas |
| co-plan | Passos, dependências e estratégia de prova | Pedido original e contexto técnico pertinente |
| co-validate — Standards | Contratos, riscos e convenções | Padrões, ADRs e código citado |
| co-validate — Spec | Fidelidade ao pedido | Pedido original/plano aprovado, verbatim |

Mantenha Standards e Spec separados. Se falta a fonte original de Spec, marque
esse eixo como não avaliado; não derive a spec do próprio diff. Compare achados
convergentes e exclusivos, exigindo cenário e evidência antes de alterar código.
Os prompts e formatos ficam em [modes.md](references/modes.md).

## Blind Reviewer e limites de isolamento

A persona `.claude/agents/blind-reviewer.md` restringe ferramentas a
Read/Grep/Glob; não executa testes nem escreve correções. Uma conversa nova
isola o histórico do pai quando o adapter oferece esse recurso. Não comprova
exclusão de instruções do host, memória, configuração nem leitura de arquivos.
A proibição de consultar vault/cache é disciplina de prompt, não isolamento
mecânico do filesystem. Registre separadamente o que foi configurado e observado.

Para compreensão de spec, use o piloto de documento isolado descrito em
[egm-pilot.md](references/egm-pilot.md). Ele complementa a revisão técnica e é
opt-in; não cria outro gate nem exige o ciclo completo do EGM.

## Rodadas: quando a revisão para

Protocolo sincronizado seletivamente com Canuto PR #122, origem
`a1c87443d2b24d82ce5d9fc1e834b50591648e40`. Regras do projeto prevalecem.

1. No máximo **3 rodadas por contagem**, incluindo todos os pushes de uma mudança.
   Reabrir a mesma mudança em outra PR preserva a contagem. Plano e PR têm
   contagens distintas; a série é revisada inteira no PR de integração.
2. Quem orquestra atribui IDs estáveis (A1, A2…) aos achados bloqueantes, sem
   reaproveitar IDs. A partir da segunda rodada, e na primeira de nova contagem,
   envie delta desde a rodada anterior e o texto completo dos achados abertos.
   O revisor devolve `FECHADO` com evidência ou `ABERTO` com o cenário e local;
   novos achados vêm sem ID. Os abertos mantêm IDs ao replanejar/dividir.
3. STRIKE exige cenário concreto, ponto do plano ou arquivo:linha e o que quebra.
   RESSALVA não bloqueia. Quem produziu não reclassifica nem fecha o STRIKE;
   o revisor julga a evidência ou o usuário decide sobre o risco.
4. Pare na terceira rodada, ou antes quando um bloqueante continua ABERTO na
   rodada seguinte. Não repita a mesma pergunta sobre o mesmo candidato sem
   mudança de evidência. Falha de infraestrutura não é rodada limpa.
5. Ciclo parado com bloqueante aberto vai ao usuário: aceitar risco registrado,
   replanejar ou dividir. Só o usuário abre outra contagem. Sem bloqueantes,
   a revisão fecha; não exija duas rodadas limpas adicionais.
6. Marcação de pronto só após fechar revisão. Push posterior reabre, ressalvadas
   as exceções explícitas do projeto para atualização da base. Remova a marcação
   antes desse push e preserve o registro dos achados.

O hook de pre-commit tem política própria; seus modos e ativação não são
alterados por esta skill. Saída de processo zero não comprova revisão realizada.

## Contexto e resultado de diff

Use `.agents/tools/codex-diff-context.sh --staged` ou `--base <base-do-projeto>`.
`--commit-candidate all-tracked` congela arquivos tracked da working tree;
`--uncommitted` compara o índice congelado com essa árvore. Untracked ficam fora.
Patch, lista de caminhos e assinaturas usam a mesma árvore. O receipt opcional
`--receipt <arquivo>` contém árvores, commits de base, hash do payload e cobertura.
A identidade do candidato é distinta do hash do texto mascarado enviado ao modelo.

O orçamento inclui metadados, lista de omissões, patch e assinaturas. Arquivos
sensíveis têm prioridade; só entram hunks completos. Assinaturas de arquivos
omitidos também ficam fora. O payload final do executor tem seu próprio teto;
se não cabe, a revisão fica não avaliada. Cobertura parcial nunca vale como
aprovação da mudança inteira; não lance revisões por arquivo automaticamente.

O adapter do hook mantém stdin, schema, cwd externo, sessão efêmera e deadline
curto. O tier fast reduz somente o prazo; usa a mesma política do reviewer.
Resultados pertencem a uma tentativa, com receipt próprio. Parciais ficam como
diagnóstico e não viram veredito de outra tentativa.

## Continuidade

Guarde candidato, pergunta, fontes/limites, IDs abertos, veredito e evidência da
execução. Prefira deltas na rodada seguinte; não reutilize conversa com respostas
anteriores como se fosse revisão cega. Memória e contexto-package são handoff do
autor, não entrada automática do teste de compreensão.
