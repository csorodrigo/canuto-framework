# Desenhando para testabilidade

Referência divulgada de [`codebase-design`](SKILL.md).

## Deep vs shallow, visualmente

**Deep** — interface pequena, muita implementação escondida:

```
┌─────────────────────┐
│  Interface pequena  │  ← poucos métodos, parâmetros simples
├─────────────────────┤
│                     │
│  Implementação      │  ← lógica complexa escondida
│  profunda           │
└─────────────────────┘
```

**Shallow** — interface grande, implementação fina que só repassa:

```
┌─────────────────────────────────┐
│      Interface grande           │  ← muitos métodos, params complexos
├─────────────────────────────────┤
│  Implementação fina             │  ← só repassa
└─────────────────────────────────┘
```

## As três regras

### 1. Receba dependências, não as crie

```typescript
// Testável
function processOrder(order, paymentGateway) {}

// Difícil de testar
function processOrder(order) {
  const gateway = new StripeGateway();
}
```

O segundo obriga o teste a interceptar a construção — e é daí que nasce o mock de
colaborador interno, que acopla o teste à implementação.

### 2. Devolva resultados, não produza efeitos colaterais

```typescript
// Testável
function calculateDiscount(cart): Discount {}

// Difícil de testar
function applyDiscount(cart): void {
  cart.total -= discount;
}
```

O primeiro é verificável pela própria chamada. O segundo obriga o teste a
inspecionar estado externo — verificação por canal lateral, o anti-padrão que a
skill `tdd` nomeia.

### 3. Superfície pequena

Menos métodos = menos testes necessários. Menos parâmetros = setup de teste mais
simples.

---

## Diagnóstico de módulo raso

Sintomas ordenados por facilidade de medir:

| Sintoma | Como medir | O que sugere |
|---|---|---|
| Muitos exports num arquivo só | `grep -c '^export ' arquivo` | interface grande — todo caller aprende tudo |
| Arquivo enorme escrito à mão | `wc -l`, checando que não é gerado | ou é god object, ou são N módulos sem seam entre eles |
| Muitos `toHaveBeenCalled` na suíte | `grep -rc toHaveBeenCalled` | testes atravessando a interface para espiar dentro |
| Muitos `vi.mock` de caminho relativo | `grep -roE "vi\.mock\(['\"]\.\.?/"` | mock de colaborador **interno** — o teste está preso à implementação |
| Teste maior que o código testado | `wc -l` dos dois | fatiamento horizontal: a suíte testa forma, não comportamento |

Nenhum desses números **prova** módulo raso — eles apontam onde aplicar o **teste
da deleção**. Um arquivo grande com uma interface de três funções é deep, não
raso; um arquivo pequeno com quinze exports é raso, não deep.

A ordem correta é: medir → escolher um candidato → aplicar o teste da deleção →
só então propor o seam.
