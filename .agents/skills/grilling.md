---
name: grilling
description: Entrevistar o usuário de forma implacável sobre um plano, decisão ou ideia até resolver cada ramo da árvore de decisão. Use antes de finalizar qualquer plano, quando o usuário quiser estressar o próprio raciocínio, ou quando outra skill precisar do loop de entrevista.
skill: grilling
trigger: /grill, /grilling
persona: maestro
version: 1.0.0
lastUpdated: 2026-08-03
invocacao: model
shortDescription: >
  Entrevista implacável, uma decisão por vez, descendo cada ramo da árvore até
  entendimento compartilhado. É o playbook da regra "nunca assuma" do CLAUDE.md.
usedBy: [maestro, architect, contextualizer, investigator]
requires:
  bins: []
  env: []
  config: []
evals:
  - prompt: "quero adicionar autenticação no app, me ajuda a pensar"
    should_trigger: true
  - prompt: "me questiona sobre esse plano antes da gente começar"
    should_trigger: true
  - prompt: "acho que essa arquitetura tá certa mas não tenho certeza"
    should_trigger: true
  - prompt: "roda o build e me diz se quebrou"
    should_trigger: false
  - prompt: "renomeia a variável userId pra accountId nesse arquivo"
    should_trigger: false
---

## Quando Usar

**Obrigatório antes de:**
- Finalizar qualquer plano do Architect (tasks S, M e L)
- Qualquer decisão que vá virar ADR
- Charting de trabalho que não cabe numa sessão

**Também dispara em:**
- "me questiona", "me entrevista", "estressa isso", "grill me"
- Pedido vago em que o usuário claramente ainda não decidiu

**Não é para:**
- Tasks XS com arquivo e mudança já nomeados — ali a entrevista é overhead
- Execução de plano já aprovado — aí é `/implement`, não entrevista

---

## Propósito

O modo de falha mais comum em desenvolvimento é **desalinhamento**. Você acha que
o dev entendeu o que você quer. Aí você vê o que foi construído e percebe que ele
não entendeu nada.

Na era do agente é idêntico. O `CLAUDE.md` já manda: *"Before finalizing any plan,
always interview the user in detail. Never assume — always ask first."* Isso é a
**regra**. Esta skill é o **método**.

> "Ninguém sabe exatamente o que quer."
> — David Thomas & Andrew Hunt, *The Pragmatic Programmer*

---

## O loop

Entreviste o usuário de forma **implacável** sobre cada aspecto disto até
alcançarem entendimento compartilhado. Desça cada ramo da árvore de decisão,
resolvendo as dependências entre decisões uma a uma.

### Uma decisão por vez

Pergunte **uma decisão por vez** e espere a resposta antes de continuar. Despejar
várias perguntas de uma vez é atordoante — e a resposta à segunda frequentemente
depende da primeira.

No canuto o veículo é o `AskUserQuestion`. Ele aceita até 4 perguntas por
chamada; **use isso para as facetas de uma mesma decisão**, não para empilhar
decisões independentes. Uma chamada = um nó da árvore.

### Sempre recomende

Para cada pergunta, dê a **sua resposta recomendada** e o porquê. Uma pergunta
sem recomendação transfere trabalho ao usuário em vez de afiar o raciocínio dele.
Marque a recomendada como primeira opção.

### Fato você busca, decisão você pergunta

Se um **fato** pode ser encontrado explorando o ambiente — filesystem, git log,
`CONTEXT.md`, event log, o próprio código — **busque, não pergunte**. Perguntar o
que você poderia ter lido queima a paciência que você vai precisar para as
decisões de verdade.

As **decisões** são do usuário. Ponha cada uma na frente dele e espere.

### Não aja antes da confirmação

Não implemente, não edite, não delegue enquanto o usuário não confirmar que vocês
chegaram a entendimento compartilhado.

**Critério de conclusão:** todo ramo da árvore de decisão está resolvido ou
explicitamente marcado como fora de escopo, e o usuário confirmou o entendimento
compartilhado.

---

## HITL é literal

Um grilling é **human in the loop** por definição. O agente nunca fala pelo lado
humano da conversa.

> Um agente de grilling que responde as próprias perguntas quebrou o contrato.

Isso vale especialmente em modo autônomo (heartbeat, cron, delegação AFK): se não
há humano para responder, o grilling **não roda** — ele para e registra a
pendência. Perguntar e responder sozinho produz um plano que parece validado e
não foi.

---

## Composição

O grilling raramente roda puro. As composições canônicas:

| Composição | O que soma | Quando |
|---|---|---|
| `/grilling` + `/domain-modeling` | escreve `CONTEXT.md` e ADR enquanto entrevista | qualquer decisão de domínio — **o padrão** |
| `/grilling` + `/codebase-design` | vocabulário de module/seam/depth na conversa | decisão de arquitetura |
| `/grilling` + `/co-review` | grilling primeiro, revisão cega depois | tasks M/L |

A primeira linha é o que o `mattpocock/skills` chama de `grill-with-docs`, e é a
composição que ele descreve como a técnica mais valiosa do conjunto: você sai da
entrevista com **alinhamento e documentação**, em vez de só alinhamento.

---

## Anti-padrões

- **Rajada de perguntas.** Cinco perguntas num bloco viram uma resposta rasa a
  cada uma. Uma decisão por vez.
- **Pergunta sem recomendação.** "O que você prefere, A ou B?" sem sua posição é
  trabalho empurrado, não entrevista.
- **Perguntar o que está no repo.** Se `git log` responde, `git log` responde.
- **Parar no primeiro nível.** A decisão A quase sempre abre B e C. Desça.
- **Encerrar sem confirmação.** "Entendi, vou implementar" não é entendimento
  compartilhado — é você declarando vitória sozinho.

---

## Guardrails

- Uma decisão por chamada de `AskUserQuestion`
- Toda pergunta carrega recomendação
- Fato se busca; decisão se pergunta
- Sem humano na linha, o grilling não roda — registre a pendência e pare
- Nenhuma edição, delegação ou commit antes da confirmação explícita
