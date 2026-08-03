---
name: skill-creator
description: Criar, revisar ou podar uma skill do canuto. Use quando o usuário quiser adicionar uma skill nova, melhorar uma existente, escrever evals, ou auditar o conjunto de skills por sedimento e sprawl.
skill: skill-creator
trigger: /skill-creator
persona: maestro
version: 2.0.0
lastUpdated: 2026-08-03
invocacao: model
shortDescription: >
  Autoria e poda de skills do canuto com modelo de custo explícito — decide o eixo
  de invocação, arruma a hierarquia de informação, escreve evals e poda sedimento.
usedBy: [maestro, architect, reviewer]
evals:
  - prompt: "quero criar uma skill pra automatizar as migrations do projeto"
    should_trigger: true
  - prompt: "a skill de commit tá inchada demais, dá uma enxugada nela"
    should_trigger: true
  - prompt: "por que a gente tem 54 skills e ninguém usa metade?"
    should_trigger: true
  - prompt: "a skill de commit tá dando erro, me ajuda a debugar"
    should_trigger: false
  - prompt: "como é que eu uso a skill experiment-loop?"
    should_trigger: false
---

## Quando Usar

**Gatilhos:**
- Criar skill nova: "cria uma skill pra X", "adiciona uma skill que faz Y"
- Melhorar existente: "a skill X não tá pegando", "atualiza a Y pra também fazer Z"
- Adicionar `evals` a uma skill que não tem
- **Podar**: auditar o conjunto por sedimento, sprawl, duplicação e no-ops

**Não é para:**
- Debugar por que uma skill não dispara → `/investigate`
- Rodar uma skill existente → invoque direto
- Criar templates do vault Obsidian → `knowledge-ingest`

---

## Propósito

Uma skill existe para arrancar determinismo de um sistema estocástico. A virtude
raiz é **previsibilidade** — o agente tomando o mesmo *processo* a cada rodada,
não produzindo o mesmo output.

Esta skill garante que toda skill que entra no canuto declare o que **custa**, e
que o conjunto seja podado com a mesma disciplina com que é escrito.

> **Toda skill custa.** As 42 skills em `_archive/` não morreram por serem ruins —
> morreram porque foram distribuídas sem ninguém checar se algum caminho real as
> alcançava. Duas auditorias (200 sessões) mediram zero leituras em runtime. Isso
> é **sedimento**, e é o destino padrão de qualquer conjunto sem poda.

Termos em **negrito** neste arquivo estão definidos em
[`GLOSSARY.md`](GLOSSARY.md) — leia lá quando precisar do significado completo.

---

## Passo 1 — Decida o eixo de invocação (antes de escrever qualquer linha)

Duas escolhas, cada uma pagando uma carga diferente:

| | **Model-invoked** | **User-invoked** |
|---|---|---|
| Mecânica | tem `description:` | não tem `description:` |
| Frontmatter | `invocacao: model` | `invocacao: user` |
| Quem alcança | agente **e** humano | só o humano |
| Outra skill alcança? | sim | **não** |
| Custo | **carga de contexto** — a description ocupa a janela todo turno | **carga cognitiva** — você é o índice |

**Escolha model-invocation só quando o agente precisa alcançar sozinho, ou outra
skill precisa alcançar.** Se ela só dispara na mão, torne user-invoked e não pague
carga de contexto nenhuma.

Quando as user-invoked se multiplicam além do que você lembra, a cura dessa carga
cognitiva empilhada é o **router** (`/ask-canuto`) — não mais uma regra.

**Critério de conclusão:** o campo `invocacao:` está preenchido e a presença ou
ausência de `description:` bate com ele.

---

## Passo 2 — Entrevista de intenção

Rode `/grilling` — uma pergunta por vez — até ter as cinco respostas:

1. **O que essa skill habilita?** (tarefa concreta, não objetivo abstrato)
2. **Quando dispara?** 3–5 frases reais de usuário
3. **Quando NÃO dispara?** 2–3 quase-acertos que parecem, mas pedem outra coisa
4. **Qual o output esperado?** (arquivo, decisão, relatório, gate)
5. **Qual persona executa?**

Fatos que dá pra achar explorando o repo — ache. As **decisões** são do usuário.

**Critério de conclusão:** as cinco respostas registradas, nenhuma inferida.

---

## Passo 3 — Pesquisa antes de escrever

- `ls .agents/skills/` — procure nomes e propósitos próximos
- Leia as 1–2 skills mais parecidas: convenções e sobreposição
- `SPEC.md § 4` — taxonomia de skills

**Se uma skill existente já cobre 80%+ da intenção, estenda em vez de criar.** Uma
skill nova gasta uma das duas cargas; estender não gasta nenhuma.

---

## Passo 4 — Arrume a hierarquia de informação

O conteúdo é feito de **passos** e **referência**, que se misturam livremente.
A escada, do que o agente precisa mais imediatamente para o menos:

1. **Passo in-file** — ação ordenada no SKILL.md. Tier primário.
2. **Referência in-file** — definição, regra ou fato consultado sob demanda.
3. **Referência divulgada** — empurrada para arquivo irmão, atrás de um
   **ponteiro de contexto**, carregada só quando o ponteiro dispara.

Empurre pouco demais e o topo incha; empurre demais e você esconde o que o agente
precisa. Essa tensão é a decisão inteira.

**O teste mais limpo de divulgação é o ramo:** deixe inline o que *todo* caminho
precisa; empurre para trás de ponteiro o que só *alguns* alcançam.

| Tamanho esperado | Estrutura |
|---|---|
| ≤200 linhas | `skill-name.md` (arquivo plano) |
| >200 linhas | `skill-name/SKILL.md` + arquivos irmãos divulgados |

Todo passo termina num **critério de conclusão**. Faça-o *checável* (o agente
distingue pronto de não-pronto?) e, onde importa, *exaustivo* ("toda model
modificada contabilizada", não "produza uma lista"). Critério vago convida
**conclusão prematura**.

---

## Passo 5 — Escreva o corpo

### Frontmatter canônico

```yaml
---
name: skill-name                  # Claude Code
description: >                    # SÓ se invocacao: model — este campo É o custo
  O que faz — e os gatilhos, um por ramo.
skill: skill-name                 # canuto
trigger: /skill-name
persona: maestro
version: 1.0.0
lastUpdated: YYYY-MM-DD
invocacao: model                  # model | user
shortDescription: >               # humano/registry — não substitui description
  Uma linha para o registry.md.
usedBy: [maestro]
requires:
  bins: []                        # ["codex", "jq"]
  env: []                         # ["OPENAI_API_KEY"]
  config: []                      # ["codex.profiles.coder"]
evals:
  - prompt: "..."
    should_trigger: true
---
```

### Escrevendo a `description` (só para model-invoked)

Ela faz dois trabalhos: dizer o que a skill é, e listar os **ramos** que devem
disparar. Cada palavra aumenta a carga de contexto, então ela merece poda ainda
mais dura que o corpo:

- **Comece pela palavra condutora** — é ali que ela faz o trabalho de invocação.
- **Um gatilho por ramo.** Sinônimos que renomeiam o mesmo ramo são
  **duplicação** — "constrói features com TDD… pede desenvolvimento test-first" é
  um ramo escrito duas vezes. Colapse.
- **Corte identidade que já está no corpo.** Só gatilhos, mais a cláusula de
  alcance ("quando outra skill precisar de…").

### Palavras condutoras

Uma **palavra condutora** é um conceito compacto que já vive no pré-treino e com
o qual o agente pensa enquanto roda a skill (*implacável*, *névoa de guerra*,
*balas traçantes*, *seam*). Repetida como **token, nunca como frase**, ela ancora
uma região inteira de comportamento com pouquíssimos tokens.

Cace oportunidades de colapsar prosa em palavra condutora:

- "rápido, determinístico, de baixo overhead" → *tight* (um loop *tight*)
- "um loop em que você acredita" → *red* (o loop fica *red* no bug, ou não fica)

> A ponte com `domain-modeling`: quando a mesma palavra vive nos seus prompts, no
> `CONTEXT.md` e no código, o agente liga essa linguagem à skill e dispara com
> mais confiabilidade. **O glossário do projeto é uma fábrica de palavras
> condutoras.**

### Prompte o positivo

Dirigir por proibição fracassa: *não pense num elefante* nomeia o elefante e o
torna mais disponível. Descreva o comportamento-alvo para o proibido nunca ser
pronunciado. Mantenha proibição só como guardrail duro que você não consegue
formular positivamente — e mesmo aí, emparelhe com o que fazer no lugar.

**Ao editar skill existente:** cada item de `Anti-Patterns — DO NOT` é candidato a
reescrita positiva.

---

## Passo 6 — Evals

Evals boas testam a fronteira real entre "usa esta skill" e "não usa".

**`should_trigger: true`** — 1 caso óbvio + 1 caso de borda em que o usuário
precisa da skill mas não a nomeia.

**`should_trigger: false`** — ambos **quase-acertos**: compartilham palavras ou
domínio, mas pedem outra skill ou nenhuma. Prompt obviamente irrelevante não
testa nada.

Formate realista: contexto do projeto, fala casual, typos, nomes de arquivo
reais.

---

## Passo 7 — Poda

Rode isto ao criar **e** periodicamente sobre o conjunto. Na ordem:

1. **Fonte única de verdade** — cada significado num lugar só. Mudar o
   comportamento é uma edição em um lugar.
2. **Relevância** — cada linha ainda diz respeito ao que a skill faz?
3. **No-ops, frase por frase** — não linha por linha. Rode o teste em cada frase
   isolada: *isto muda o comportamento em relação ao padrão do modelo?* Quando
   uma falha, **delete a frase inteira** em vez de aparar palavras. Seja
   agressivo — a maior parte da prosa que falha deve sair, não ser reescrita.
4. **Sprawl** — mesmo com toda linha viva e única, longa demais é longa demais.
   Cura: divulgue referência, divida por ramo.

**Critério de conclusão:** cada frase do SKILL.md passou pelo teste do no-op.

### Auditoria do conjunto

Quando o gatilho for "temos skills demais":

1. Monte o **grafo de invocação**: para cada skill, existe caminho real que a
   alcança? (persona citando, hook disparando, `CLAUDE.md`, outra skill, router)
2. Skill sem caminho é **sedimento** — não importa quão bem escrita esteja.
3. Meça uso real: event log (`<vault>/events/log.jsonl`) e métricas.
4. Apresente o veredito ao usuário **antes** de mover qualquer arquivo.

---

## Passo 8 — Integração

1. **Coloque o arquivo** em `.agents/skills/`
2. **Registre em `registry.md`** — skill fora do registry é invisível ao humano
3. **Re-sincronize o router** `/ask-canuto` se a skill for user-invoked — router
   que aponta para skill removida, ou que não menciona skill nova, é um **router
   que mente**
4. **Se for crítica** (fluxo central, dispara sempre): adicione à lista do
   `health-check.md`
5. **Se representar decisão arquitetural**: crie nota `D-XXX` no vault
6. **Se modificou skill existente**: suba `version` e `lastUpdated`
7. **Anuncie**: o que foi criado, o trigger, o eixo de invocação e as evals

---

## Ciclo de vida

Skill nova entra em `_incubando/` e só é promovida quando um caminho real de
invocação existir e tiver sido exercitado. Skill promovida vive em
`.agents/skills/` **e** está no `registry.md`. Skill sem caminho volta para
`_archive/`.

Skill distribuída sem caminho de invocação é a fábrica de sedimento — é
exatamente como as 42 morreram.

---

## Guardrails

- Complete a entrevista de intenção antes de escrever — suposição vira retrabalho
- Estenda a skill existente quando ela cobrir 80%+ da intenção
- Explique o *porquê*; use MUST/NEVER só depois de tentar o raciocínio
- Escreva para a categoria, não para os exemplos que você imaginou
- Detecção de lacuna **sugere**; o usuário decide
