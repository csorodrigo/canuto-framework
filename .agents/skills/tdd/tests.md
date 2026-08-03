# Testes bons e ruins

Referência divulgada de [`tdd`](SKILL.md). Adaptado de `mattpocock/skills` (MIT).

## Testes bons

**Estilo integração**: testam através de interfaces reais, não de mocks das
partes internas.

```typescript
// BOM: testa comportamento observável
test("usuário consegue finalizar compra com carrinho válido", async () => {
  const cart = createCart();
  cart.add(product);
  const result = await checkout(cart, paymentMethod);
  expect(result.status).toBe("confirmed");
});
```

Características:

- Testa comportamento com que usuários/callers se importam
- Usa apenas a API pública
- Sobrevive a refactor interno
- Descreve **O QUÊ**, não **COMO**
- Uma asserção lógica por teste

---

## Testes ruins

### Detalhe de implementação

Acoplados à estrutura interna.

```typescript
// RUIM: testa detalhe de implementação
test("checkout chama paymentService.process", async () => {
  const mockPayment = vi.mock(paymentService);
  await checkout(cart, payment);
  expect(mockPayment.process).toHaveBeenCalledWith(cart.total);
});
```

Bandeiras vermelhas:

- Mockar colaborador interno
- Testar método privado
- Asserir contagem ou ordem de chamadas
- Teste quebra ao refatorar sem mudança de comportamento
- Nome do teste descreve COMO, não O QUÊ
- Verificar por meio externo em vez de pela interface

### Verificação por canal lateral

```typescript
// RUIM: contorna a interface para verificar
test("createUser salva no banco", async () => {
  await createUser({ name: "Alice" });
  const row = await db.query("SELECT * FROM users WHERE name = ?", ["Alice"]);
  expect(row).toBeDefined();
});

// BOM: verifica pela interface
test("createUser torna o usuário recuperável", async () => {
  const user = await createUser({ name: "Alice" });
  const retrieved = await getUser(user.id);
  expect(retrieved.name).toBe("Alice");
});
```

O segundo é melhor por dois motivos: sobrevive à troca do adapter de persistência
(o seam continua o mesmo), e falha por um motivo que importa — o usuário não é
recuperável — em vez de por um detalhe de schema.

### Tautológico

O valor esperado reafirma a implementação, então o teste passa por construção.

```typescript
// RUIM: o esperado é recalculado do jeito que o código calcula
test("calculateTotal soma os itens", () => {
  const items = [{ price: 10 }, { price: 5 }];
  const expected = items.reduce((sum, i) => sum + i.price, 0);
  expect(calculateTotal(items)).toBe(expected);
});

// BOM: o esperado é um literal independente e conhecido
test("calculateTotal soma os itens", () => {
  expect(calculateTotal([{ price: 10 }, { price: 5 }])).toBe(15);
});
```

O teste ruim continua passando se `calculateTotal` for trocado por qualquer
`reduce` — inclusive um errado, desde que erre igual. Ele não consegue discordar
do código.

---

## Mocking

A regra curta: **mocke no seam externo, nunca dentro**.

- **Mocke** o que atravessa a fronteira do processo e você não controla: HTTP de
  terceiro, relógio, aleatoriedade, sistema de arquivos quando o teste não pode
  tocá-lo.
- **Não mocke** colaborador interno do módulo sob teste. Se você precisa mockar
  algo interno para o teste rodar, o módulo tem forma errada — leve a questão
  para `/codebase-design`.
- **Prefira fake a mock.** Um repositório em memória que satisfaz a mesma
  interface é um **adapter**: dá o mesmo isolamento sem acoplar o teste à ordem
  de chamadas.
- **Dois adapters, um seam real.** Se o fake é o único adapter que existirá além
  do de produção, o seam se justifica pelo teste. Se nem isso, você criou seam
  hipotético.

---

## Nomeando

O nome do teste é onde a linguagem do `CONTEXT.md` aparece primeiro. Use os
termos canônicos do glossário — não sinônimos.

```typescript
// Glossário define "Pedido" e evita "ordem"
test("Pedido cancelado não gera Fatura", ...)   // BOM
test("ordem cancelada não gera cobrança", ...)  // RUIM: dois termos evitados
```

Nome de teste é a superfície mais lida do projeto depois dos nomes de função. Um
glossário que não chega até aqui não chegou a lugar nenhum.
