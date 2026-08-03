# Formato do CONTEXT.md

Referência divulgada de [`domain-modeling`](SKILL.md). Adaptado de
`mattpocock/skills` (MIT).

## Estrutura

```md
# {Nome do Contexto}

{Uma ou duas frases: o que este contexto é e por que existe.}

## Linguagem

**Pedido**:
Uma intenção de compra registrada por um Cliente, ainda não faturada.
_Evitar_: ordem, compra, transação

**Fatura**:
Um pedido de pagamento enviado ao Cliente após a entrega.
_Evitar_: boleto, cobrança, invoice

**Cliente**:
Pessoa ou organização que faz Pedidos.
_Evitar_: usuário, conta, comprador
```

## Regras

- **Seja opinativo.** Existindo várias palavras para o mesmo conceito, escolha a
  melhor e liste as outras em `_Evitar_`. Um glossário que aceita tudo não
  resolve nada.
- **Definições apertadas.** Uma ou duas frases no máximo. Defina o que a coisa
  **é**, não o que ela **faz**.
- **Só termos específicos deste contexto.** Conceito geral de programação
  (timeout, retry, DTO, feature flag) não entra, mesmo que o projeto use muito.
  Antes de adicionar, pergunte: *isto é único deste domínio, ou é programação em
  geral?* Só o primeiro entra.
- **Agrupe sob subtítulos** quando surgirem clusters naturais. Se todos os termos
  pertencem a uma área coesa, lista plana está ótimo.
- **Português.** O glossário existe para casar com a fala do usuário e com os
  nomes no código. Se o código está em inglês e a conversa em português, registre
  o par: `**Pedido** (`Order` no código)`.

## Um contexto vs. múltiplos

**Um contexto (maioria dos repos):** um `CONTEXT.md` na raiz.

**Múltiplos contextos:** um `CONTEXT-MAP.md` na raiz lista os contextos, onde
vivem e como se relacionam:

```md
# Mapa de Contextos

## Contextos

- [Ordering](./src/ordering/CONTEXT.md) — recebe e acompanha pedidos
- [Billing](./src/billing/CONTEXT.md) — gera faturas e processa pagamentos
- [Fulfillment](./src/fulfillment/CONTEXT.md) — separação e expedição

## Relações

- **Ordering → Fulfillment**: Ordering emite `OrderPlaced`; Fulfillment consome
- **Fulfillment → Billing**: Fulfillment emite `ShipmentDispatched`; Billing consome
- **Ordering ↔ Billing**: tipos compartilhados `CustomerId` e `Money`
```

A skill infere qual estrutura se aplica:

- Existe `CONTEXT-MAP.md`? Leia para achar os contextos.
- Existe só um `CONTEXT.md` na raiz? Contexto único.
- Não existe nenhum? Crie o `CONTEXT.md` na raiz quando o primeiro termo for
  resolvido.

Com múltiplos contextos, infira a qual deles o tópico atual pertence. Se não
estiver claro, pergunte.

## Convivência com `.context.md`

O canuto já usa `.context.md` (minúsculo, com ponto, um por diretório) para
contexto **estrutural**: o que aquele código faz, quais módulos existem, o que
depende do quê. Os dois arquivos coexistem e não competem:

- `.context.md` muda quando **o código** muda.
- `CONTEXT.md` muda quando **o entendimento** muda.

Um termo novo em `CONTEXT.md` frequentemente deveria renomear coisas no código —
essa é a intenção. Quando isso acontecer, o `.context.md` da área afetada também
precisa de refresh (`context-maintenance`).
