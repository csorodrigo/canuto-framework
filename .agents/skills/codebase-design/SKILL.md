---
name: codebase-design
description: Vocabulário compartilhado para desenhar módulos profundos. Use ao desenhar ou melhorar a interface de um módulo, decidir onde vai um seam, tornar código testável ou navegável pelo agente, ou quando outra skill precisar do vocabulário de profundidade.
skill: codebase-design
trigger: /codebase-design
persona: architect
version: 1.0.0
lastUpdated: 2026-08-03
invocacao: model
shortDescription: >
  Léxico fechado de design — module, interface, depth, seam, adapter, leverage,
  locality — mais o teste da deleção e as regras de colocação de seam.
usedBy: [architect, coder, reviewer]
requires:
  bins: []
  env: []
  config: []
evals:
  - prompt: "esse service tem 14 métodos e cada um chama um helper, tá certo isso?"
    should_trigger: true
  - prompt: "onde eu coloco a fronteira entre o parser e o validador?"
    should_trigger: true
  - prompt: "esse arquivo tá difícil de testar, como eu quebro ele?"
    should_trigger: true
  - prompt: "roda os testes do módulo de billing"
    should_trigger: false
  - prompt: "qual biblioteca de datas a gente usa?"
    should_trigger: false
---

## Quando Usar

**Gatilhos:**
- Desenhar ou refazer a interface de um módulo
- Decidir **onde** colocar um seam
- "Isso está difícil de testar" / "o agente se perde nesse código"
- Outra skill (`/tdd`, `/improve-codebase-architecture`, `/review`) precisa do
  vocabulário

**Não é para:**
- Escolher biblioteca ou stack → `stack.md`
- Desenhar contrato HTTP/JSON → `api-design`
- Rodar ou consertar testes → `tdd`

---

## Propósito

Desenhe **módulos profundos**: muito comportamento atrás de uma interface
pequena, colocada num seam limpo, testável através dessa interface. O alvo é
**alavancagem** para quem chama, **localidade** para quem mantém, e
testabilidade para todo mundo.

Esta skill é vocabulário. Use estes termos **exatamente** — a linguagem
consistente é o ponto inteiro.

---

## Glossário

**Module** — qualquer coisa com interface e implementação. Deliberadamente
agnóstico de escala: uma função, uma classe, um pacote, uma fatia que atravessa
camadas.
*Evitar*: unidade, componente, serviço.

**Interface** — **tudo** que quem chama precisa saber para usar o módulo
corretamente: a assinatura de tipo, mas também invariantes, ordem de chamada,
modos de erro, configuração obrigatória e características de performance.
*Evitar*: API, assinatura (estreitos demais — falam só da superfície de tipo).

**Implementation** — o que está dentro do módulo. Distinta de **Adapter**: uma
coisa pode ser um adapter pequeno com implementação grande (um repositório
Postgres) ou um adapter grande com implementação pequena (um fake em memória).
Puxe "adapter" quando o assunto for o seam; "implementação" no resto.

**Depth** — alavancagem na interface: quanto comportamento quem chama (ou o
teste) consegue exercitar por unidade de interface que precisa aprender. Um
módulo é **deep** quando muito comportamento senta atrás de pouca interface, e
**shallow** quando a interface é quase tão complexa quanto a implementação.

**Seam** *(Michael Feathers)* — um lugar onde você consegue alterar
comportamento sem editar naquele lugar; a **localização** onde a interface de um
módulo vive. **Onde** colocar o seam é uma decisão de design própria, distinta de
**o que** vai atrás dele.
*Evitar*: boundary (sobrecarregado com bounded context do DDD).

**Adapter** — coisa concreta que satisfaz uma interface num seam. Descreve
**papel** (que vaga preenche), não substância (o que tem dentro).

**Leverage** — o que quem chama ganha com profundidade: mais capacidade por
unidade de interface aprendida. Uma implementação se paga em N call sites e M
testes.

**Locality** — o que quem mantém ganha com profundidade: mudança, bug,
conhecimento e verificação se concentram num lugar em vez de se espalharem pelos
callers. Conserta uma vez, consertado em todo lugar.

---

## Deep vs shallow

**Deep** = interface pequena + muita implementação. **Shallow** = interface
grande + pouca implementação, evitar.

Ao desenhar uma interface, pergunte:

- Dá para reduzir o número de métodos?
- Dá para simplificar os parâmetros?
- Dá para esconder mais complexidade dentro?

Um módulo com dezenas de exports é interface grande por definição: cada caller
precisa aprender todas antes de usar qualquer uma.

---

## Princípios

- **Profundidade é propriedade da interface, não da implementação.** Um módulo
  deep pode ser internamente composto de partes pequenas, mockáveis e trocáveis —
  elas só não fazem parte da interface. Um módulo tem **seams internos**
  (privados à implementação, usados pelos próprios testes dele) além do **seam
  externo** na interface.

- **O teste da deleção.** Imagine deletar o módulo. Se a complexidade **some**,
  era pass-through. Se ela **reaparece espalhada por N callers**, o módulo estava
  pagando aluguel. "Reaparece concentrada" é o sinal que você quer.

- **A interface é a superfície de teste.** Callers e testes atravessam o mesmo
  seam. Se você quer testar **além** da interface, o módulo provavelmente tem a
  forma errada.

- **Um adapter significa seam hipotético. Dois adapters significam seam real.**
  Não introduza seam a menos que algo de fato varie através dele.

---

## Desenhando para testabilidade

Três regras, com exemplos e o diagnóstico de módulo raso em
[TESTABILIDADE.md](TESTABILIDADE.md):

1. **Receba dependências, não as crie.**
2. **Devolva resultados, não produza efeitos colaterais.**
3. **Superfície pequena** — menos métodos, menos testes; menos parâmetros, setup
   mais simples.

---

## Relações

- Um **Module** tem exatamente uma **Interface** (a superfície que apresenta a
  callers e testes)
- **Depth** é propriedade de um **Module**, medida contra sua **Interface**
- Um **Seam** é onde a **Interface** de um **Module** vive
- Um **Adapter** senta num **Seam** e satisfaz a **Interface**
- **Depth** produz **Leverage** para callers e **Locality** para mantenedores

---

## Enquadramentos rejeitados

- **Profundidade como razão linhas-de-implementação / linhas-de-interface**
  (Ousterhout): premia inflar a implementação. Usamos profundidade-como-alavancagem.
- **"Interface" como a keyword `interface` do TypeScript, ou os métodos públicos
  de uma classe**: estreito demais — interface aqui inclui todo fato que quem
  chama precisa saber.
- **"Boundary"**: sobrecarregado com bounded context do DDD. Diga **seam** ou
  **interface**.

---

## Integração com o canuto

- **Architect**: use estes termos em todo plano M/L. Um plano que diz "componente"
  ou "camada" onde deveria dizer **module** e **seam** perde a precisão que faz o
  Coder acertar de primeira.
- **`domain-modeling`**: o `CONTEXT.md` dá **nomes** aos bons seams. Se o
  glossário define **Pedido**, fale do "module de entrada de Pedido" — não do
  "OrderHandlerService".
- **`tdd`**: os seams desta skill são exatamente os seams pré-acordados em que os
  testes são escritos.
- **`review`**: o teste da deleção é um critério de revisão. Módulo novo que não
  passa nele é pass-through disfarçado.

---

## Guardrails

- Use os sete termos exatamente; substituição por "componente", "serviço", "API"
  ou "boundary" derruba a precisão que a skill existe para dar
- Aplique o teste da deleção antes de propor extrair qualquer módulo
- Introduza seam só com dois adapters reais à vista
- Profundidade não é desculpa para *God object*: muito comportamento atrás de
  interface pequena, com **uma** responsabilidade — não muitas escondidas
