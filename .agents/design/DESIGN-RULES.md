---
name: design-rules
version: 1.0.0
lastUpdated: 2026-08-21
shortDescription: >
  Design system normativo do front — densidade, tipografia, espaçamento,
  overflow e copy. NÃO é skill: é contrato, consultado por QUALQUER runtime
  (Claude, Codex ou humano) antes de qualquer trabalho de UI.
---

# DESIGN-RULES — regras de front para todos os projetos

> **Contrato de consulta obrigatória.** Antes de planejar, gerar ou revisar
> QUALQUER tela, página ou componente visível ao usuário, o agente (Claude,
> Codex, qualquer role) DEVE ler este arquivo e obedecê-lo. Task-files de
> front montados pelo Maestro para o `codex-delegate.sh` DEVEM referenciar
> este arquivo. A skill `frontend-design` complementa (direção estética);
> em conflito, **este arquivo vence**.

Isto NÃO é "o mesmo design para todos os projetos". Cores, marca e
personalidade variam por projeto. O que este arquivo fixa é o **regime**:
denso, compacto, funcional, sem estouro de frame e sem copy de propaganda.

---

## 0. Os dois modos

Toda tela é classificada antes de qualquer decisão:

| Modo | O que é | Exemplos |
|---|---|---|
| **APP** | UI operacional: o usuário veio TRABALHAR | dashboard, tabelas, formulários, configurações, admin, CRUD |
| **LANDING** | Página de aquisição: o usuário veio AVALIAR | home pública, página de vendas, pricing, onboarding de marketing |

Na dúvida, é **APP**. As regras abaixo valem para os dois modos, exceto onde
uma coluna LANDING liberar explicitamente mais respiro.

---

## 1. Tipografia (valores fechados)

Escala única — nenhum tamanho fora dela:

| Papel | APP | LANDING |
|---|---|---|
| Corpo padrão | `text-sm` (14px) | `text-base` (16px) |
| Secundário/meta | `text-xs` (12px) | `text-sm` (14px) |
| Título de seção/card | `text-base font-medium` | `text-xl`–`text-2xl` |
| Título de página | `text-lg`–`text-xl` | — |
| H1/hero | proibido acima de `text-2xl` | máx `text-5xl` desktop / `text-3xl` mobile |

- `leading-tight` em títulos, `leading-normal` no corpo. Nunca `leading-loose`.
- Nada de `font-black` decorativo em APP; peso máximo `font-semibold`.
- `tracking-tight` só em títulos LANDING ≥ `text-3xl`.

## 2. Espaçamento e densidade (valores fechados)

Grid de 4px. Escala permitida por contexto — usar o MENOR valor que resolve:

| Contexto | APP | LANDING |
|---|---|---|
| Gap entre itens de lista/grid | `gap-2`–`gap-3` | `gap-4`–`gap-6` |
| Padding de card | `p-3`–`p-4` | `p-6` |
| Padding vertical de seção | `py-4`–`py-6` (teto duro) | `py-12`–`py-16` (teto duro; hero máx `py-20`) |
| Espaço entre seções | `space-y-6` | `space-y-16` máx |
| Altura de linha de tabela | `h-9` (36px) | — |
| Altura de input/botão padrão | `h-8`–`h-9` (`size="sm"` do shadcn) | `h-10`–`h-11` em CTA |

- **Proibido em qualquer modo**: `py-24`, `py-32`, `my-20+`, `gap-10+`,
  `p-8+` em cards de APP. Se parecer que precisa, o problema é a estrutura.
- Densidade é o default: tabelas com `text-sm`, células `px-3 py-2`;
  formulários com labels `text-xs`/`text-sm` e campos `h-9`; sidebar com
  itens `h-8`.
- Um card só existe se agrupa 2+ informações relacionadas. Card gigante com
  uma linha de conteúdo é proibido — vira linha de lista.

## 3. Largura e contenção

| Contexto | Regra |
|---|---|
| Container de APP | `max-w-screen-2xl mx-auto px-4` (dashboards podem ser full-width com `px-4`) |
| Container de seção LANDING | `max-w-6xl mx-auto px-4` |
| Texto corrido (parágrafos) | `max-w-prose` — nunca linha de texto de borda a borda |
| Formulários | `max-w-lg`–`max-w-2xl`; nunca campos esticados na tela inteira |

## 4. Overflow — tolerância zero

Conteúdo estourando o frame é **bug, não estética**. Regras mecânicas:

1. Todo filho de flex que carrega texto leva `min-w-0`; todo filho de grid
   que carrega texto leva `min-w-0` na célula. (Sem isso, `flex` + texto
   longo = estouro.)
2. Texto de uma linha que pode crescer (nomes, e-mails, URLs, ids): `truncate`
   + `title`/tooltip com o valor completo.
3. Texto multi-linha de dado externo: `break-words` (`overflow-wrap`).
4. Tabela, bloco de código, diagrama, qualquer conteúdo intrinsecamente largo:
   SEMPRE dentro de wrapper próprio `overflow-x-auto` — a página nunca ganha
   scroll horizontal.
5. Nenhuma largura fixa em px maior que o menor container que a contém.
   Imagens: `max-w-full h-auto`.
6. Valores dinâmicos (número grande, moeda, badge count): reservar espaço com
   `tabular-nums` e testar com o pior caso (ex.: `R$ 1.234.567,89`).
7. **Gate de verificação**: toda entrega de front é conferida em 320px,
   768px e 1440px de viewport (browser-qa/screenshot). Scroll horizontal na
   página em qualquer um = reprovado.

## 5. Copy — regime por modo

### APP: 100% funcional, zero propaganda
- Nenhum adjetivo de marketing. Proibidos (e equivalentes): "poderoso",
  "incrível", "revolucionário", "seamless", "blazing fast", "supercharge",
  "unlock", "elevate", "effortless".
- Headline de página/seção: ≤ 6 palavras, nomeia a coisa ("Faturas",
  "Membros da equipe") — não vende a coisa.
- Label resolve? Não escreva parágrafo. Descrições sob títulos só quando
  carregam informação de decisão; máx 1 linha.
- Empty states: 1 frase do que está vazio + 1 ação. Sem ilustração gigante,
  sem discurso motivacional.
- Toasts/erros: o que aconteceu + o que fazer. Sem "Ops!", sem emoji.

### LANDING: persuasão com limite
- Hero: headline ≤ 8 palavras + 1 frase de apoio (≤ 20 palavras) + 1–2 CTAs.
  Nada mais.
- Seção de benefício: título ≤ 6 palavras + 1 frase. Parede de texto é
  proibida; se precisa explicar muito, vira página de docs, não landing.
- Máx 1 superlativo por página inteira. Prova concreta (número, caso, print)
  vale mais que adjetivo — na dúvida, corte o adjetivo.
- Sem seção "fake social proof" (logos genéricos, depoimentos inventados).

## 6. Anti-padrões de LLM (o que este arquivo existe para matar)

Vieses conhecidos de UI gerada por modelo — tratar como erro de review:

- Hero `py-24`/`py-32` com headline de 3 linhas e gradiente — em app interno.
- Emoji como ícone ou decoração de título.
- Gradiente em todo botão/fundo; `shadow-xl` empilhado em tudo.
- Cards enormes em grid `gap-8` para listar 4 itens de texto.
- Três parágrafos explicando o que um label de 2 palavras diz.
- `space-y-8` entre campos de um formulário.
- Ícone decorativo de 48px ao lado de cada item de lista.
- Página de configurações que parece landing page.

## 7. Checklist de auditoria (design-audit)

Uso: sob demanda, por projeto — reviewer ou browser-qa percorre as telas
principais e reporta violações (arquivo:linha ou rota + screenshot). O
relatório vai para o vault do projeto (`audit/`); a correção é backlog
priorizado pelo usuário, nunca correção automática em massa.

- [ ] Nenhum scroll horizontal de página em 320/768/1440px
- [ ] Nenhum `py-16+` em APP; nenhum `py-24+` em LANDING (hero: `py-20` máx)
- [ ] Corpo de APP em 14px; nenhum texto fora da escala da seção 1
- [ ] Tabelas/código/conteúdo largo em wrapper `overflow-x-auto`
- [ ] `min-w-0` + `truncate`/`break-words` onde texto dinâmico encontra flex/grid
- [ ] Zero adjetivos de marketing em telas de APP
- [ ] Headlines dentro dos limites de palavras (APP ≤ 6; LANDING hero ≤ 8)
- [ ] Cards justificam existir (2+ infos); sem card-de-uma-linha
- [ ] Formulários contidos (`max-w-lg`–`2xl`), campos `h-9`, `space-y-4` máx

## 8. Exceções

Exceção só existe **declarada no plano** (Architect) com justificativa de uma
linha, antes da implementação — nunca decidida silenciosamente pelo coder.
Exemplo legítimo: página de login isolada com mais respiro vertical. Exemplo
ilegítimo: "achei que ficava bonito mais espaçado".
