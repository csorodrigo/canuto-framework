# ADR-0015 — Invocação é custo declarado, e linguagem compartilhada é infraestrutura

Data: 2026-08-03 · Status: aceito

## Contexto

Duas auditorias (2026-06-11 e 2026-07-26) mataram 42 skills por medição direta:
zero leituras em runtime em 200 sessões, zero caminho real de invocação — nenhuma
persona, hook, `CLAUDE.md` ou skill de entrada as citava. O diagnóstico registrado
foi correto (elas estavam mortas) e a ação foi correta (arquivar). O que faltou
foi a **causa**: nada no framework dizia o que uma skill custa, nem checava se um
caminho de invocação existia antes de distribuí-la.

O conjunto atual tem 54 skills ativas em 8.410 linhas, governadas pela **Regra do
1%** ("se há 1% de chance de uma skill se aplicar, ela DEVE ser checada"). Isso é
uma varredura linear sobre o diretório inteiro, executada pelo Maestro a cada
roteamento. Escala mal e não tem saída de emergência.

Em paralelo, uma varredura por termos no `.agents/` inteiro devolveu **zero
ocorrências** de quatro disciplinas:

| Ausente | Situação no framework |
|---|---|
| `tdd` / `red-green` / `test-first` | `tests: required` no `CLAUDE.md`, hook `require-tests-for-pr.sh` e `verification-gates` — **fiscalização sem método** |
| `glossary` / `ubiquitous` / `domain model` | `.context.md` (estrutural) e 14 ADRs, mas nenhuma camada de linguagem compartilhada |
| `deep module` / `seam` | Architect planeja sem vocabulário de design; planos usam "componente"/"camada" |
| entrevista como playbook | `CLAUDE.md` manda "nunca assuma — sempre pergunte", e nenhum arquivo diz **como** |

O `mattpocock/skills` (MIT) resolve as quatro, e traz o modelo de custo que
explica o cemitério de 42.

## Opções consideradas

1. **Instalar o plugin `mattpocock-skills`** — rejeitada: soma 22 `description`
   model-invoked a um framework que já carrega 54 skills, produzindo colisão de
   carga de contexto e trigger duplicado em `research`, `code-review`, `handoff`
   e `triage`, justamente onde o canuto já é igual ou melhor.
2. **`npx skills add` seletivo** — rejeitada como caminho primário: entrega os
   arquivos em inglês, com frontmatter e convenções de outro sistema, e sem as
   pontes para vault, personas, hooks e gates.
3. **Adotar o modelo tracker-first (`wayfinder`, `to-tickets`, `triage`) por
   atacado** — adiada: o vault (event log, instincts, métricas, decisões) é ativo
   real e a migração seria uma troca, não uma soma. Fica para avaliação separada,
   provavelmente como híbrido (vault para memória, tracker para trabalho em voo).
4. **Adaptar as disciplinas como skills canuto** — escolhida.

## Decisão

**Toda skill declara o que custa, e o eixo de invocação é campo de frontmatter.**

Novo campo obrigatório `invocacao: model | user`:

- `model` — mantém `description:`. O agente alcança sozinho e outras skills
  alcançam. Paga **carga de contexto** todo turno.
- `user` — sem `description:`. Só o humano alcança, digitando. Carga de contexto
  zero, paga **carga cognitiva**.

A Regra do 1% deixa de ser a porta de entrada. `/ask-canuto` (router
user-invoked) mapeia situação → skill, e a varredura do diretório vira o caminho
de exceção. Router que não menciona skill nova, ou que aponta para skill
removida, é **router que mente** — re-sincronizá-lo é passo obrigatório do
`/skill-creator`.

**Skills adotadas** (adaptadas ao português e às convenções do canuto, creditando
`mattpocock/skills`, MIT):

| Skill | Eixo | Preenche |
|---|---|---|
| `skill-creator` v2 + `GLOSSARY.md` | model | o modelo de custo que faltava; modo poda |
| `domain-modeling` + `CONTEXT-FORMAT.md` | model | `CONTEXT.md` (glossário) e o filtro de 3 condições para ADR |
| `codebase-design` | model | vocabulário de módulos profundos para o Architect |
| `grilling` | model | o método da regra "nunca assuma" |
| `tdd` + `tests.md` | model | o método por trás de `tests: required` |
| `/ask-canuto` | user | router |

**`CONTEXT.md` (raiz) não substitui `.context.md`.** São camadas distintas:
`.context.md` responde *o que este código faz* e muda quando o código muda;
`CONTEXT.md` responde *o que estas palavras significam* e muda quando o
entendimento muda. `CONTEXT.md` é glossário e nada mais — detalhe de
implementação nele é violação.

**`co-review` ganha o eixo Spec.** A revisão passa a correr em dois eixos cegos
entre si: **Standards** (segue o padrão do repo?) e **Spec** (é o que foi
pedido?). Sem fonte de spec, o eixo reporta `⊘ não avaliado` — um Spec fabricado
a partir do próprio diff sempre aprova, e por isso a ausência é dita, não
inferida.

**`grilling` é obrigatório para S, M e L; XS é a exceção.** E ele é HITL por
definição: em modo autônomo (heartbeat, cron, delegação AFK) o grilling **não
roda** — registra a pendência e para. Um agente que responde as próprias
perguntas produz um plano que parece validado e não foi.

## Consequências

- Skill nova sem caminho de invocação exercitado não é promovida. O ciclo é
  `_incubando/` → `.agents/skills/` + `registry.md` → `_archive/`. Foi assim que
  as 42 morreram, e é o que a esteira impede.
- Seções `Anti-Patterns — DO NOT` passam a ser dívida conhecida: negação arrasta
  o comportamento proibido para o contexto e o torna mais disponível. Só o
  `maestro.md` carrega 11. Cada uma é candidata a reescrita positiva; as que
  sobrarem devem vir emparelhadas com o alvo. Esta ADR **não** faz essa
  reescrita — ela nomeia a dívida.
- O Architect passa a produzir planos que nomeiam **modules** e **seams**, e os
  seams sob teste viram contrato do plano em vez de decisão que o Coder toma
  dentro do loop red-green.
- Aumenta o custo de escrever skill (declarar eixo, escrever evals de
  quase-acerto, passar pelo teste do no-op frase a frase). É deliberado: o custo
  de escrever é pago uma vez; o de manter sedimento é pago toda sessão.
- Ficam fora, conscientemente: `wayfinder`/`to-tickets`/`triage` (opção 3),
  `improve-codebase-architecture` (depende de `codebase-design` estar em uso
  primeiro), `prototype`, `resolving-merge-conflicts` e o empacotamento como
  plugin Claude Code (`.claude-plugin/plugin.json`), que o `registry.md` já
  registra como mecanismo nunca implementado.

## Referências

- `mattpocock/skills` v1.2.0 — https://github.com/mattpocock/skills (MIT)
- John Ousterhout, *A Philosophy of Software Design* — módulos profundos
- Michael Feathers, *Working Effectively with Legacy Code* — seam
- Eric Evans, *Domain-Driven Design* — linguagem ubíqua
- ADR-0012 — precedente do mesmo padrão: gate que vira ruído é ignorado
