---
name: tdd
description: Desenvolvimento guiado por testes no loop red-green. Use ao construir feature ou corrigir bug test-first, quando o usuário mencionar red-green-refactor, ou quando precisar decidir em que seam o teste vai.
skill: tdd
trigger: /tdd
persona: coder
version: 1.0.0
lastUpdated: 2026-08-03
invocacao: model
shortDescription: >
  O loop red → green, e o que faz o teste sobreviver ao refactor — seams
  pré-acordados, fatias verticais, e os três anti-padrões que matam suíte.
usedBy: [coder, architect, reviewer]
requires:
  bins: []
  env: []
  config: []
evals:
  - prompt: "implementa o cálculo de comissão, com testes"
    should_trigger: true
  - prompt: "esse bug do desconto tá voltando toda semana, quero cobrir com teste"
    should_trigger: true
  - prompt: "os testes quebram toda vez que eu mexo em qualquer coisa"
    should_trigger: true
  - prompt: "roda a suíte inteira e me mostra o output"
    should_trigger: false
  - prompt: "configura o vitest nesse projeto"
    should_trigger: false
---

## Quando Usar

**Gatilhos:**
- Construir feature ou corrigir bug com teste primeiro
- "red-green-refactor", "test-first", "cobre isso com teste"
- Suíte frágil que quebra a cada refactor sem mudança de comportamento
- Decidir **onde** o teste vai (o seam)

**Não é para:**
- Rodar a suíte e reportar → comando direto, sob `verification-gates`
- Configurar test runner → tarefa de setup, não de método
- Provar causa raiz de bug → `/investigate` (o teste vem *depois* da raiz
  confirmada)

---

## Propósito

O canuto declara `tests: required` no `CLAUDE.md` e tem o hook
`require-tests-for-pr.sh` mais o `verification-gates` (nenhuma alegação de teste
sem output cru). Isso é **fiscalização**. Faltava o **método**.

TDD é o loop red → green. Esta skill é a referência que faz esse loop produzir
testes que valem a pena manter: o que é um teste bom, onde os testes moram, os
anti-padrões, e as regras do loop. **Toda seção se aplica a todo ciclo** — leia
antes e durante, não depois.

> "Sempre dê passos pequenos e deliberados. A taxa de feedback é o seu limite de
> velocidade."
> — David Thomas & Andrew Hunt, *The Pragmatic Programmer*

Ao explorar o código, leia o `CONTEXT.md` (skill `domain-modeling`) para que
nomes de teste e vocabulário de interface batam com a linguagem do projeto, e
respeite os ADRs da área que você está tocando.

---

## O que é um teste bom

Testes verificam **comportamento através de interfaces públicas**, não detalhes
de implementação. O código pode mudar inteiro; os testes não deveriam.

Um teste bom lê como especificação — `"usuário consegue finalizar compra com
carrinho válido"` diz exatamente que capacidade existe — e sobrevive a refactor
porque não liga para estrutura interna.

Exemplos concretos em [tests.md](tests.md).

---

## Seams — onde os testes moram

Um **seam** é a fronteira pública em que você testa: a interface onde você
observa comportamento sem enfiar a mão dentro. Testes moram em seams, nunca
contra internals. O vocabulário completo está em `/codebase-design`.

**Teste só em seams pré-acordados.** Antes de escrever qualquer teste, escreva
quais seams estão sob teste e **confirme com o usuário**. Nenhum teste é escrito
num seam não confirmado.

Você não consegue testar tudo. Acordar os seams antes é como o esforço de teste
cai nos caminhos críticos e na lógica complexa em vez de em toda borda
imaginável.

Pergunte: *"Qual é a interface pública, e quais seams a gente testa?"*

**Critério de conclusão:** a lista de seams sob teste está escrita e confirmada
pelo usuário antes do primeiro `test(`.

---

## Anti-padrões

- **Acoplado à implementação** — mocka colaborador interno, testa método privado,
  ou verifica por canal lateral (consultando o banco em vez de usar a interface).
  **O sinal:** o teste quebra quando você refatora, mas o comportamento não
  mudou.

- **Tautológico** — a asserção recalcula o valor esperado do mesmo jeito que o
  código calcula (`expect(add(a, b)).toBe(a + b)`, um snapshot derivado à mão pela
  mesma fórmula, uma constante comparada consigo mesma). Passa por construção e
  **nunca consegue discordar do código**. O valor esperado tem que vir de fonte
  independente: um literal conhecido, um exemplo trabalhado à mão, a spec.

- **Fatiamento horizontal** — escrever todos os testes primeiro, depois toda a
  implementação. Testes em lote verificam comportamento **imaginado**: você testa
  a *forma* das coisas em vez do comportamento que o usuário enxerga, os testes
  ficam insensíveis a mudança real, e você se compromete com a estrutura de teste
  antes de entender a implementação.

  Trabalhe em **fatias verticais**: um teste → uma implementação → repete. Cada
  teste é uma **bala traçante** que responde ao que o ciclo anterior ensinou.

---

## Regras do loop

- **Red antes de green.** Escreva o teste que falha primeiro, depois só o código
  suficiente para passar. Não antecipe testes futuros nem adicione feature
  especulativa.

- **Uma fatia por vez.** Um seam, um teste, uma implementação mínima por ciclo.

- **Refactor não faz parte do loop.** Ele pertence ao estágio de revisão
  (`/review`), não ao ciclo red → green.

- **O red tem que ser visto.** Um teste que nunca foi observado falhando não
  provou nada. Isso é a mesma regra do `verification-gates` aplicada ao loop:
  output cru do red, output cru do green.

---

## Integração com o canuto

- **Coder** roda o loop; **Architect** acorda os seams no plano, junto com
  `/codebase-design`
- Fatia vertical casa com o **staged mode** do Maestro para tasks L: um passo do
  plano = uma fatia = um ciclo verificável
- `verification-gates` continua valendo: nenhuma alegação de teste passando sem
  o output cru do comando
- `require-tests-for-pr.sh` é o piso, não o teto — o hook checa que **existe**
  teste; esta skill decide se ele **presta**

---

## Guardrails

- Nenhum teste em seam não confirmado pelo usuário
- Valor esperado sempre de fonte independente do código sob teste
- Uma fatia vertical por ciclo; nada de escrever a suíte inteira antes
- Refactor sai do loop e vai para a revisão
- Alegação de verde exige output cru
