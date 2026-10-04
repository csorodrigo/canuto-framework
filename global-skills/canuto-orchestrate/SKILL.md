---
name: canuto-orchestrate
description: >
  Avalia automaticamente se trabalho substancial deve usar uma ou duas folhas
  independentes para coleta de evidência ou revisão, em Codex ou Claude. Use
  quando houver pelo menos duas perguntas verificáveis em paralelo, uma operação
  longa autorizada que não deva bloquear o root, ou risco material que justifique
  revisão independente. Não use para tarefas pequenas, etapas fortemente
  sequenciais, escritores sobrepostos ou para substituir Maestro, aprovações,
  modelo canônico, gates ou verificação de estado real.
metadata:
  canuto-type: "global-skill"
  canuto-version: "0.3.0"
  canuto-updated: "2026-10-04"
  canuto-invocation: "model"
  canuto-runtimes: "claude,codex"
  source-revision: "rafaelquintanilha/skills@8c4991b"
  provenance: "Implementação clean-room; nenhum texto upstream foi copiado porque o repositório não declarava licença."
---

# Orquestração passiva do Canuto

O Maestro ou root continua responsável por decomposição, comunicação, síntese,
autorizações e conclusão. Esta skill apenas decide quando uma folha isolada
melhora evidência ou independência de revisão.

## Gate de delegação

Delegue somente quando o benefício for concreto e ao menos uma condição valer:

- duas perguntas podem ser respondidas independentemente;
- uma coleta, teste ou monitor autorizado é lento e pode avançar em separado;
- uma investigação delimitada preserva o contexto principal;
- uma revisão independente reduz risco de produção, segurança, pagamentos,
  dados, especificação ou release.

Fique no root quando a tarefa for pequena, a próxima etapa depender do resultado
imediatamente anterior, o custo de coordenação se aproximar do trabalho direto ou
as folhas precisarem escrever na mesma superfície.

## Contrato com o harness

- Resolva runtime, ferramentas, modelo e effort da configuração executável
  atual. Nunca fixe versões de modelo nesta skill.
- Confira o papel aceito pelo executor instalado, suas ferramentas, a política
  efetiva de leitura e a disponibilidade conhecida na conta. Catálogo local não
  comprova acesso. Não altere perfis impostos pelo runtime para fazê-los caber.
- Para coleta, inventário, leitura e checagem mecânica, escolha o menor perfil
  configurado compatível com as ferramentas necessárias (`leaf` pelo
  `codex-delegate.sh`; subagente `canuto-leaf` numa sessão Claude ou
  `mcp__claude-architect__spawn_cheap_agent` quando Codex for o root). Essas
  rotas aplicam read-only mecanicamente. Escale para reviewer/architect quando
  independência ou risco material exigir mais capacidade.
- `leaf` coleta; `reviewer` revisa; `architect` analisa contratos. Os três exigem
  leitura efetiva. `fast` e `coder` são escritores e não substituem uma folha.
  O Maestro é o root atual; não o recrie como filho para supervisionar folhas.
- Use no máximo duas folhas na primeira onda e prefira uma quando suficiente.
- Antes de iniciar processos, respeite o guard de capacidade. Guard ativo ou
  evidência inválida exige atualização da capacidade; timestamp antigo não
  autoriza ignorar pressão nem iniciar uma validação pesada.
- As folhas desta skill são somente leitura, não delegam e não tomam a decisão
  final. A implementação mutável volta ao Coder e ao wrapper canônico do Canuto.
- Não envie a conversa inteira. Passe objetivo, escopo, fonte de verdade,
  restrições, padrão de evidência, formato de retorno e condição de parada.
- Não crie uma segunda camada de Maestro, não replique `adaptive-routing` ou
  `co-review` e não transforme concordância entre agentes em prova.
- Se o runtime não oferecer delegação compatível com essas restrições, trabalhe
  no root e registre a limitação; não improvise outro caminho.
- Uma falha de modelo indisponível admite no máximo uma alternativa explícita,
  compatível e registrada pelo executor. Não derive nomes trocando sufixos.
  Reviewer não faz fallback automático. Não repita a mesma rota indisponível;
  sem alternativa segura, continue no root.
- Timeout, saída vazia e conclusão parcial não autorizam nova execução
  automática. Preserve o artefato e confira alterações antes de reatribuir um
  trabalho com escrita. Sucesso exige conclusão válida e artefato útil.
- Registre separadamente modelo pedido, configuração usada e identidade
  informada pelo executor. Alias ou comando lançado não comprova identidade
  efetiva; sem evidência, marque `UNVERIFIED`.
- A folha devolve um único artefato ao root. Atualizações ao usuário e a barra de
  progresso pertencem ao root/Maestro; a folha não interrompe a execução para
  narrar etapas parciais.

Leia [os contratos](references/contracts.md) antes de criar uma folha.

Quando a tarefa exigir coordenação estruturada na Orca, use a skill
`orchestration` e o guia servido pelo binário selecionado. Ferramentas nativas
de subagentes não representam tarefas ou workers da Orca.

## Integração dos resultados

Classifique cada retorno como completo, parcial, conflitante ou rejeitado.
Reabra a fonte autoritativa quando houver conflito; não faça votação nem média de
confiança. Código, teste, commit, merge, deploy e runtime ativo continuam sendo
estados separados e exigem receipts próprios.

Depois da síntese, use o fluxo canônico para qualquer mudança. Aprovação humana,
um escritor por checkout e gates do projeto permanecem obrigatórios.

Para mudança substancial, rollout, release ou propagação, faça um review
adversarial independente antes de publicar. Registre artefato, `fixed_point`,
pergunta, reviewer real e veredito; um hook ou review manual satisfaz a mesma
fronteira, sem repetir a pergunta sobre o mesmo objeto.
