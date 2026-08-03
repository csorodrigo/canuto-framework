# Glossário — Anatomia de uma Skill

Referência divulgada de [`skill-creator`](SKILL.md). Adaptado de
`mattpocock/skills` (`writing-great-skills/GLOSSARY.md`, MIT) para o modelo de
orquestração do canuto.

Uma skill existe para arrancar determinismo de um sistema estocástico. A virtude
raiz é **Previsibilidade**; todo termo abaixo é uma alavanca sobre ela. Custo e
manutenibilidade são sintomas dela, não rivais.

Termos em **negrito** dentro de uma definição têm entrada própria — procure pelo
título.

---

## Previsibilidade

O grau em que a skill faz o agente se comportar do mesmo **jeito** a cada rodada
— o mesmo processo, não o mesmo output. Uma skill de brainstorm deve
*previsivelmente* divergir: os tokens variam, o comportamento não.

*Evitar*: consistência, confiabilidade, robustez, determinismo-de-saída.

---

# Eixo 1 — Invocação

Como a skill é alcançada, e as duas cargas que se paga pela escolha.

## Model-Invoked

Skill que mantém o campo `description`, então o agente pode dispará-la sozinho —
e o humano continua podendo digitar o nome. **Não existe estado "só modelo"**:
a description apenas *soma* descoberta pelo agente, nunca remove o alcance
humano. Paga **carga de contexto** permanente, todo turno, em troca dessa
descoberta. É também alcançável por outras skills — a description que a torna
descobrível a torna invocável.

*Evitar*: habilidade, ferramenta, capacidade.

## User-Invoked

Skill com a `description` removida — invisível ao agente, alcançável só pelo
humano digitando o nome. Troca descoberta por **carga de contexto zero**. Como
não tem description, **nenhuma outra skill consegue disparar**.

*Evitar*: procedimento, workflow, comando.

## Description

O gatilho legível por máquina, e o único **ponteiro de contexto** que uma skill
model-invoked é obrigada a manter carregado o tempo todo. **A mera presença dela
é o eixo de invocação**: mantenha e a skill é model-invoked; remova e vira
user-invoked. É a fonte da carga de contexto.

> **No canuto:** `description` (uma linha, voltada ao modelo) é o campo que
> decide o eixo. `shortDescription` é a linha voltada ao humano e ao registry —
> ela **não** substitui `description` nem paga o custo dela.

*Evitar*: frontmatter, resumo.

## Ponteiro de Contexto

Uma referência que vive no contexto do agente, nomeia material fora do contexto
e codifica a condição para alcançá-lo. A `description` é o ponteiro de topo
(janela → skill); ponteiros para arquivos divulgados são o mesmo objeto um nível
abaixo.

**A redação do ponteiro, não o alvo, decide quando o agente alcança — e com que
confiabilidade.** Material obrigatório atrás de um ponteiro mal redigido é um bug
de variância: conserte a redação primeiro; só inline o material se afiar a
redação falhar.

*Evitar*: link, referência, import.

## Carga de Contexto

O custo que uma skill **model-invoked** impõe à janela do agente — sua
`description`, sempre carregada, gastando tokens *e atenção*. É o que as
**user-invoked** escapam, e o freio para dividir em mais skills model-invoked.

*Evitar*: custo de token, inchaço de contexto.

## Carga Cognitiva

O custo que uma skill **user-invoked** impõe ao humano — o que ele precisa
segurar na cabeça: quais skills existem e quando puxar cada uma. **O humano é o
índice.** É o que a model-invocation remove, e o freio para dividir em mais
skills user-invoked.

Não é um custo a minimizar: é o preço da agência humana, e a razão de algumas
skills continuarem user-invoked. Gaste onde o julgamento humano importa; remova
onde não importa.

> **No canuto:** a **Regra do 1%** ("se há 1% de chance de uma skill se aplicar,
> ela DEVE ser checada") é carga cognitiva empurrada para o Maestro. Ela escala
> mal com 50+ skills — a cura é o **router**, não mais uma regra.

*Evitar*: índice humano, fardo, overhead.

## Router Skill

Skill **user-invoked** cujo trabalho é apontar para as outras user-invoked —
nomeando cada uma e quando puxá-la — para o humano ter **uma** skill para
lembrar em vez de muitas. Só consegue sugerir, nunca disparar. É a cura da
**carga cognitiva** quando as user-invoked se multiplicam.

Um router que aponta para skill removida, ou que não menciona skill nova, é um
**router que mente** — re-sincronizar faz parte de adicionar/remover skill.

*Evitar*: dispatcher, menu, registry, índice.

## Granularidade

Quão finamente você divide skills. Divisão mais fina gasta uma das duas cargas.
Dois cortes:

- **Por invocação** — separe uma skill model-invoked quando houver uma **palavra
  condutora** distinta que deva dispará-la sozinha, ou quando outra skill
  precisar alcançá-la. Você paga carga de contexto pela description nova.
- **Por sequência** — divida uma corrida de **passos** quando os passos adiante
  (**passos pós-conclusão**) tentarem o agente a apressar o passo da frente.

Cuidado com o inverso: fundir sequências expõe os passos pós-conclusão de cada
passo ao que vem depois, convidando **conclusão prematura**.

*Evitar*: chunking, modularidade.

---

# Eixo 2 — Hierarquia de Informação

Como o conteúdo é arranjado, e quão fundo cada peça senta.

## Hierarquia de Informação

O conteúdo da skill ranqueado por quão imediatamente o agente precisa dele — uma
escada só, produzida por dois cortes (no arquivo ou atrás de ponteiro; passo ou
referência). Os degraus:

1. **Passos** — no arquivo, primário.
2. **Referência**, no arquivo — secundário.
3. **Referência**, divulgada — atrás de um **ponteiro de contexto**.

Uma skill sem passos usa só os dois degraus de baixo — frequentemente um
conjunto de pares legitimamente plano (toda regra de uma revisão no mesmo
degrau). Isso é um arranjo válido, não um cheiro.

Quando a skill *tem* passos, referência in-file que deveria estar divulgada
soterra os passos e transforma prestar atenção neles num cara-ou-coroa — é uma
alavanca de **variância**, não só de legibilidade.

*Evitar*: estrutura, organização, layout.

## Passos

As ações ordenadas que o agente executa — o tier primário quando existem. Nem
toda skill tem passos: pode ser toda de passos (`tdd`), toda de **referência**
(uma revisão), ou ambas. Todo passo termina num **critério de conclusão**, claro
ou vago.

*Evitar*: workflow, instruções, coreografia.

## Referência

Material consultado sob demanda — definições, fatos, parâmetros, exemplos,
instruções condicionais. Quando há **passos**, é secundária a eles; quando não
há, é o conteúdo inteiro. É a candidata principal a **divulgação progressiva**.

*Evitar*: material de apoio, docs, background.

## Referência Externa

**Referência** que vive fora do sistema de skills — arquivo comum, sem
description, sem passos, não invocável — para o qual qualquer skill pode
apontar. É o lar de referência compartilhada que não precisa disparar sozinha, e
o **único lar compartilhado que duas skills user-invoked conseguem usar**, já que
nenhuma tem description para disparar a outra.

> **No canuto:** `docs/adr/`, `.context.md`, `CONTEXT.md` e `stack.md` são
> referência externa.

*Evitar*: doc, recurso, base de conhecimento.

## Divulgação Progressiva

Mover **referência** escada abaixo — para fora do SKILL.md e atrás de um
**ponteiro de contexto** — para o topo continuar legível. Não é primariamente
otimização de token; é como a **hierarquia de informação** é protegida.

Licenciada pelo **ramo**: divulgue o que só alguns ramos precisam, deixe inline o
que todo caminho precisa. Se um ponteiro dispara de forma não-confiável sobre
material obrigatório, afie a redação — e só puxe de volta para inline se afiar
falhar.

*Evitar*: lazy loading, chunking.

## Co-locação

Manter junto o material que o agente precisa de uma vez — definição, regras e
ressalvas de um conceito sob um único cabeçalho, não espalhados. É a companheira
*dentro do arquivo* da hierarquia: a escada ranqueia **quão fundo** uma peça
senta; a co-locação decide **o que senta ao lado dela**.

Não há fórmula para o formato certo de um corpo de referência; o teste é que a
skill leia como *documentação escrita para o agente* — material agrupado lê
assim, material espalhado não.

Distinta de **duplicação**: aquela repete um significado em dois lugares; esta
fragmenta um significado só por muitos.

*Evitar*: agrupamento, coesão.

## Sprawl

*Modo de falha.* Skill simplesmente longa demais — independente de estar velha ou
repetida. Mesmo uma skill 100% viva e 100% única pode sprawl.

Custa legibilidade (o agente atravessa mais antes de poder agir, e a atenção
afina no excesso), manutenção (cada linha extra é mais uma para manter
**relevante**) e tokens. A cura é a **hierarquia**: empurre referência para trás
de ponteiros, e divida por **ramo** ou sequência.

Distinta de **sedimento** (comprimento por acúmulo velho) e **duplicação**
(comprimento por significado repetido) — sprawl é o comprimento em si.

*Evitar*: inchaço, tamanho, verbosidade.

---

# Eixo 3 — Direção

As alavancas que moldam o comportamento do agente em runtime.

## Ramo

Um jeito distinto pelo qual a skill pode ser invocada — um caso que ela trata —
de modo que rodadas diferentes tomam caminhos diferentes. Skill linear não tem
ramos.

*Evitar*: caminho, caso, fork.

## Palavra Condutora

Um conceito compacto — um *Leitwort* — que **já vive no pré-treino do modelo** e
com o qual o agente pensa enquanto roda a skill. Codifica um princípio
comportamental no menor número possível de tokens, recrutando priors que o modelo
já tem (ex.: *lição*, *névoa de guerra*, *balas traçantes*, *implacável*).

Repetida **como token, nunca como frase**, ela acumula uma definição distribuída
ao longo do texto e ancora uma região inteira de comportamento.

Cunhar a sua própria funciona se você definir com clareza — mas palavra inventada
não recruta prior nenhum: você paga em tokens de definição o que uma palavra
pré-treinada dá de graça. **Busque a palavra existente primeiro.**

Ela serve à previsibilidade duas vezes:

- **No corpo** ancora a *execução* — o agente puxa o mesmo comportamento toda vez
  que o conceito aparece.
- **Na description** ancora a *invocação* — e não só dentro da skill: quando a
  mesma palavra vive nos seus prompts, nos seus docs e no seu código, o agente
  liga essa linguagem compartilhada à skill e dispara com mais confiabilidade.

> Redija a description com as palavras que você **de fato usa** quando quer a
> skill. É a ponte direta com o `CONTEXT.md` da skill `domain-modeling`: o
> glossário do projeto é uma fábrica de palavras condutoras.

*Evitar*: keyword, termo, motivo.

## Critério de Conclusão

A condição que diz ao agente que a unidade de trabalho acabou. Dois eixos, e são
independentes:

- **Clareza** (o agente distingue pronto de não-pronto?) resiste a **conclusão
  prematura**. Um limite vago ("entendimento alcançado") deixa o agente declarar
  pronto e escorregar. Esse eixo precisa de *passos* para morder.
- **Exigência** (quanto ele demanda) define o **trabalho de campo** — "toda
  model modificada contabilizada" força trabalho exaustivo onde "produza uma
  lista de mudanças" não força. Esse eixo **não** depende de passos: ele consegue
  amarrar um corpo de referência plana ("toda regra aplicada"), que é como uma
  skill sem passos ainda carrega uma barra de exaustividade.

Os critérios mais fortes são checáveis **e** exaustivos.

*Evitar*: condição de pronto, critério de saída.

## Trabalho de Campo

O que o agente faz nos bastidores dentro de um único passo — ler arquivos,
explorar o código, cavar o que precisa em vez de terceirizar para o usuário. Vive
*abaixo* da estrutura de passos: nunca escrito como passo próprio, latente na
redação, controlado pelo agente e não pela skill.

Elevado por uma **palavra condutora** (*abrangente*, *implacável*) ou por um
**critério de conclusão** que exige exaustividade. Fica raso quando a exigência
falta, ou quando a **conclusão prematura** corta o passo.

*Evitar*: escopo, esforço, diligência.

## Passos Pós-Conclusão

Os **passos** que vêm depois do atual. Visíveis, puxam o agente para a
**conclusão prematura** — quanto mais ele vê, mais forte o puxão.

*Evitar*: horizonte, lookahead.

## Conclusão Prematura

*Modo de falha.* Terminar o passo atual antes de ele estar genuinamente pronto,
porque a atenção do agente escorregou para *estar pronto* em vez de para o
trabalho. É uma falha *entre passos*: precisa de passos para acontecer. Skill sem
passos que para cedo não é conclusão prematura — é **trabalho de campo raso** sob
exigência não atendida.

É um cabo de guerra entre duas forças: **passos pós-conclusão** visíveis (o
puxão) e a *clareza* do **critério de conclusão** (a resistência). A vagueza é a
condição necessária — um limite afiado resiste ao puxão por mais passos que
estejam à vista.

**Duas alavancas, nesta ordem:**

1. **Afie o limite primeiro** — é local e barato.
2. Só quando o critério for irredutivelmente vago **e** você *observar* a pressa,
   **esconda os passos seguintes**. E esconder só funciona atravessando uma
   fronteira real de contexto (delegação a subagente, handoff, spawn via
   `codex-delegate.sh`) — chamada model-invoked inline deixa os passos seguintes
   no contexto e não limpa nada.

*Evitar*: fechamento prematuro, pressa, atalho.

## Negação

*Modo de falha.* Dirigir por proibição — dizer ao agente o que **não** fazer —
arrasta o comportamento proibido para o contexto e o torna *mais* disponível, não
menos. *Não pense num elefante*, e o elefante é tudo que existe. *Nunca escreva
comentários verbosos*, e verbosidade é o padrão que o agente acabou de ler.

A negação é um modificador fraco que o conceito fortemente ativado atropela — a
proibição meio-lê como instrução para fazer a coisa.

**Cura: prompte o positivo.** Descreva o comportamento-alvo ("escreva comentários
de uma linha") para o proibido nunca ser pronunciado. Uma proibição só ganha seu
lugar como guardrail duro sobre comportamento que você não consegue formular
positivamente — e mesmo aí, emparelhe com o alvo positivo.

> **No canuto:** seções `Anti-Patterns — DO NOT` são negação em escala. O
> `maestro.md` carrega 11 proibições. Cada uma é candidata a reescrita positiva;
> as que sobrarem devem vir emparelhadas com o alvo.

*Evitar*: rebote irônico, elefante rosa.

---

# Eixo 4 — Poda

Manter a skill enxuta — cada remédio ao lado da falha que cura.

## Fonte Única de Verdade

O estado desejado em que cada significado mora em exatamente um lugar
autoritativo, de modo que mudar o comportamento é uma edição em um lugar.
**Duplicação** é a violação disso.

*Evitar*: lar, local canônico.

## Duplicação

*Modo de falha.* O mesmo significado com mais de uma fonte única de verdade.
Custa manutenção, custa tokens e **infla a proeminência** — repetir um
significado o pesa na escada acima do posto real.

É o inverso acidental da **palavra condutora**, que eleva atenção de propósito
repetindo *o token*, nunca *o significado*.

*Evitar*: repetição, redundância.

## Relevância

Se a linha ainda diz respeito ao que a skill faz — a lente do que manter. Uma
linha perde relevância por nunca ter dito respeito (mera exposição, ou um **ramo**
que deveria estar divulgado) ou por envelhecer.

Skills curtas são mais fáceis de manter relevantes, porque cada linha é mais
barata de checar.

Distinta de **no-op**: relevância pergunta se a linha *diz respeito*; no-op
pergunta se ela *muda comportamento*.

*Evitar*: sustentação, frescor.

## Sedimento

*Modo de falha.* Camadas de conteúdo velho que assentam e nunca são limpas,
porque **adicionar parece seguro e remover parece arriscado** — então linhas
obsoletas se acumulam e você precisa perfurar até o que ainda está vivo.

É o destino padrão de qualquer skill sem disciplina de poda.

> **No canuto:** as 42 skills em `.agents/skills/_archive/` (auditorias 2026-06-11
> e 2026-07-26: zero leituras em runtime em 200 sessões, zero caminho real de
> invocação) são sedimento medido. Elas não morreram por serem ruins — morreram
> por terem sido distribuídas sem ninguém checar se algum caminho as alcançava.

*Evitar*: acreção, cruft, apodrecimento.

## No-Op

*Modo de falha.* Instrução que não muda nada porque o modelo já faz aquilo por
padrão — você paga carga para dizer ao agente o que ele faria de qualquer jeito.

**O teste:** essa linha muda o comportamento *em relação ao padrão*? Uma linha
pode ser perfeitamente **relevante** e ainda ser no-op.

Palavra condutora e no-op se cruzam: uma palavra condutora fraca demais para
vencer o padrão *é* um no-op (*seja minucioso*, quando o agente já é
minucioso-ish) — e a correção é uma palavra mais forte (*implacável*), não outra
técnica. O teste do no-op é também como você avalia se uma palavra condutora está
pagando as próprias repetições.

Isto é **relativo ao modelo, não ao leitor**: duas pessoas que discordam se uma
linha é no-op estão discordando sobre o *padrão* — e resolvem isso **rodando a
skill**, não debatendo.

*Evitar*: instrução redundante, reafirmar o óbvio.
