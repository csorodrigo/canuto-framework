---
name: domain-modeling
description: Construir e afiar a linguagem compartilhada do projeto no CONTEXT.md. Use quando um termo do domínio estiver ambíguo ou disputado, quando uma decisão difícil de reverter merecer ADR, ou quando outra skill precisar manter o modelo de domínio.
skill: domain-modeling
trigger: /domain-modeling
persona: architect
version: 1.0.0
lastUpdated: 2026-08-03
invocacao: model
shortDescription: >
  Linguagem ubíqua do projeto — desafia termos contra o glossário, testa com cenários
  de borda e escreve CONTEXT.md e ADRs na hora em que a decisão cristaliza.
usedBy: [architect, contextualizer, maestro, coder]
requires:
  bins: []
  env: []
  config: []
evals:
  - prompt: "a gente fala 'pedido' e 'ordem' pra mesma coisa, tá confuso"
    should_trigger: true
  - prompt: "escolhemos postgres em vez de mongo, vale registrar isso em algum lugar?"
    should_trigger: true
  - prompt: "atualiza o .context.md de src/api porque mudei os handlers"
    should_trigger: false
  - prompt: "explica o que faz o módulo de billing"
    should_trigger: false
---

## Quando Usar

**Gatilhos:**
- Termo do domínio ambíguo, disputado, ou usado com dois sentidos
- O usuário descreve algo em 20 palavras que um nome resolveria
- Decisão difícil de reverter acabou de ser tomada
- Outra skill (`/grilling`, `/codebase-design`, `/tdd`) precisa do modelo

**Não é para:**
- Atualizar `.context.md` estrutural → `context-maintenance`
- Explicar o que um módulo faz → leitura normal do código
- Registrar toda decisão de sessão → o filtro de três condições existe pra isso

---

## Propósito

O agente entra num projeto e precisa descobrir o jargão sozinho. Sem linguagem
compartilhada ele usa 20 palavras onde 1 basta:

- **ANTES:** "tem um problema quando uma lesson dentro de uma section de um course
  é tornada 'real', ou seja, ganha um lugar no filesystem"
- **DEPOIS:** "tem um problema com a **materialization cascade**"

O ganho se paga sessão após sessão, em três frentes: variáveis, funções e
arquivos nomeados de forma consistente; codebase mais navegável pelo agente; e
**menos tokens gastos pensando**, porque o agente tem uma linguagem mais concisa
para pensar com.

Esta é a disciplina **ativa** — desafiar termos, inventar cenários de borda,
escrever o glossário no instante em que ele cristaliza. Apenas *ler* o
`CONTEXT.md` para pegar vocabulário não é esta skill; é um hábito de uma linha
que qualquer skill deve ter.

---

## CONTEXT.md ≠ .context.md

O canuto já tem uma camada de contexto. Esta é outra, e elas não se sobrepõem:

| | `.context.md` (existente) | `CONTEXT.md` (esta skill) |
|---|---|---|
| Onde | um por diretório | um na raiz |
| Responde | **o que este código faz** | **o que estas palavras significam** |
| Conteúdo | módulos, entradas, dependências | glossário, e só |
| Mantido por | `context-maintenance` / Contextualizer | `domain-modeling` / Architect |
| Muda quando | o código muda | o *entendimento* muda |

`CONTEXT.md` é **totalmente livre de detalhe de implementação**. Não é spec, não é
rascunho, não é depósito de decisão técnica. É glossário e nada mais.

---

## Estrutura de arquivos

A maior parte dos repos tem um contexto só:

```
/
├── CONTEXT.md
├── docs/adr/
│   ├── 0001-slug.md
│   └── 0002-slug.md
└── src/
```

Se existir um `CONTEXT-MAP.md` na raiz, o repo tem múltiplos contextos e o mapa
aponta onde cada um vive, mais como se relacionam. Formato completo em
[CONTEXT-FORMAT.md](CONTEXT-FORMAT.md).

**Crie os arquivos preguiçosamente** — só quando houver algo para escrever. Sem
`CONTEXT.md`? Crie quando o primeiro termo for resolvido.

---

## Durante a sessão

Estas cinco ações rodam **inline**, no instante em que o gatilho aparece. Não
acumule para o fim da sessão — termo resolvido e não escrito é termo perdido.

### Desafie contra o glossário

Quando o usuário usa um termo que conflita com a linguagem já registrada, fale na
hora:

> "Seu glossário define **cancelamento** como X, mas você parece estar dizendo Y.
> Qual dos dois?"

### Afie linguagem difusa

Termo vago ou sobrecarregado ganha uma proposta de termo canônico:

> "Você está dizendo **conta** — é o Cliente ou o Usuário? São coisas diferentes."

### Discuta cenários concretos

Quando relações do domínio estão em jogo, teste com cenário específico. Invente
casos que sondam a borda e forçam o usuário a ser preciso sobre onde um conceito
termina e o outro começa.

### Cruze com o código

Quando o usuário afirma como algo funciona, confira se o código concorda.
Contradição vira pergunta, não suposição:

> "Seu código cancela Pedidos inteiros, mas você acabou de dizer que
> cancelamento parcial existe. Qual dos dois está certo?"

### Escreva na hora

Termo resolvido → `CONTEXT.md` atualizado ali mesmo, no formato de
[CONTEXT-FORMAT.md](CONTEXT-FORMAT.md).

**Critério de conclusão:** todo termo resolvido nesta sessão está no
`CONTEXT.md`, e nenhum detalhe de implementação entrou junto.

---

## ADRs — ofereça com parcimônia

O canuto já tem prática forte de ADR (`docs/adr/`, numeração sequencial). O que
faltava era o filtro de **quando**.

Ofereça ADR só quando as **três** condições forem verdadeiras:

1. **Difícil de reverter** — mudar de ideia depois custa de verdade
2. **Surpreendente sem contexto** — um leitor futuro vai olhar o código e pensar
   "por que diabos fizeram assim?"
3. **Resultado de trade-off real** — havia alternativas genuínas e você escolheu
   uma por razões específicas

Faltando uma, pule. Fácil de reverter? Você vai reverter. Não é surpreendente?
Ninguém vai perguntar. Não havia alternativa? Não há nada a registrar além de
"fizemos o óbvio".

### O que qualifica

- **Forma arquitetural** — "é um monorepo"; "o write model é event-sourced, o
  read model é projetado no Postgres"
- **Padrão de integração entre contextos** — "Ordering e Billing conversam por
  eventos de domínio, não HTTP síncrono"
- **Escolha de tecnologia com lock-in** — banco, message bus, auth, alvo de
  deploy. Não toda biblioteca: só as que levariam um trimestre para trocar
- **Fronteira e escopo** — "dados de Cliente pertencem ao contexto Customer;
  outros contextos referenciam por ID". Os **nãos** explícitos valem tanto quanto
  os sins
- **Desvio deliberado do caminho óbvio** — "SQL manual em vez de ORM porque X".
  Isso impede o próximo engenheiro de "consertar" o que era intencional
- **Restrição invisível no código** — "não podemos usar AWS por compliance";
  "resposta abaixo de 200ms por contrato com a API do parceiro"
- **Alternativa rejeitada quando a rejeição não é óbvia** — considerou GraphQL e
  ficou com REST por razões sutis? Registre, ou alguém sugere GraphQL de novo em
  seis meses

### Formato

Siga o formato já em uso em `docs/adr/` (Contexto → Opções consideradas →
Decisão → Consequências), numerando a partir do maior número existente. Um ADR
pode ser curto: o valor está em registrar **que** a decisão foi tomada e **por
quê**, não em preencher seções.

---

## Guardrails

- `CONTEXT.md` guarda glossário; detalhe de implementação vai para `.context.md`,
  ADR ou código
- Termo geral de programação (timeout, retry, DTO) fica de fora, mesmo que o
  projeto use muito — só entra o que é específico deste domínio
- Seja opinativo: existindo várias palavras para o mesmo conceito, escolha uma e
  liste as outras em `_Evitar_`
- Escreva inline, não em lote no fim da sessão
- ADR só passando pelas três condições
