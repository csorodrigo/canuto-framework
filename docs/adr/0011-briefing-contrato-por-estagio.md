# ADR-0011 — O briefing tem contrato por estágio: required, expected-empty, duas pernas

Data: 2026-08-01 · Status: aceito

## Contexto

`README.md:225` anunciava "Maestro briefing" como comportamento passivo
automático, mas `session-start.sh` não injetava briefing nenhum (gap
confirmado na auditoria 2026-08-01). O edge-of-chaos já tinha nomeado essa
classe de bug em `docs/briefing-lifecycle-audit.md`: um compositor de brief
que falha em silêncio e um compositor que não tinha nada para mostrar
produzem a mesma saída — string vazia. Sem diferenciar as duas, um brief
quebrado ("lobotomia silenciosa") é indistinguível de um projeto
genuinamente novo.

O Track A desta árvore já tinha um `build_vault_brief()` funcional dentro do
hook (last session + pending + instincts, injetado via `additionalContext`).
Preso dentro do hook, porém, o compositor não podia ser provado
isoladamente — não dava para simular sabotagem e checar se o vazio-honesto
sobrevivia.

## Opções consideradas

1. **Manter o compositor dentro do hook** — rejeitada: sem extração não há
   como escrever um controle positivo (compor contra um vault fresco
   descartável) sem reimplementar o hook inteiro num teste.
2. **Leitura recusar quando a identidade for frágil**, espelhando a postura
   estrita da escrita (`canuto_require_project_slug`, ADR-0010) — rejeitada:
   apagaria um brief que já funciona hoje (leitura degrada e rotula, nunca
   recusa; ver ADR-0010, postura de leitura).
3. **Extrair o compositor para `brief-compose.sh` sourceable, com contrato de
   3 estados no expected-empty e controle positivo de duas pernas** —
   aceita.

## Decisão

- `.agents/tools/brief-compose.sh` (novo): `canuto_compose_brief <root>`
  (`:147`) — Identity é a única seção **required**: se o slug não resolve,
  imprime o marcador `CANUTO_BRIEF_MARK_IDENTITY_FAIL` (`:47`, "⚠ identidade
  não resolvida — vault não consultado"), nunca string vazia.
- Expected-empty com **3 estados, nunca 2** (`:48-53`): vault existe e seção
  vazia → marcador honesto por seção (`CANUTO_BRIEF_MARK_NO_PENDING`,
  `CANUTO_BRIEF_MARK_NO_INSTINCT`, etc.); vault **declarado** no `CLAUDE.md`
  mas ausente em disco → `CANUTO_BRIEF_MARK_VAULT_ABSENT` (feeder
  declarado-e-ausente é QUEBRADO, não silêncio); nada declarado e nenhum
  vault → `CANUTO_BRIEF_MARK_FRESH` ("projeto sem vault — 1ª sessão?").
- `canuto_check_identity <root>` (`:383`) — duas pernas. Perna 1: compõe
  contra o vault **vivo**, falha se a Identity está em estado de falha ou se
  um vault declarado está ausente. Perna 2: compõe contra um vault **fresco**
  em `mktemp -d` (slug fake, dirs vazios) e exige os marcadores honestos de
  vazio — prova que o compositor sabe renderizar o vazio sem crashar nem
  devolver `""` (um compositor quebrado que sempre devolve `""` passaria na
  perna 1 de um projeto populado sem essa segunda checagem). Qualquer erro
  interno é FAIL — fail-closed, nunca "não consegui determinar".
- `.agents/tools/memory-usage.sh` (novo): `canuto_usage_record <slug>
  <ref...>` (`:94`, best-effort, nunca no caminho crítico, store separado em
  `<vault>/projects/<slug>/_usage/usage.jsonl`, nunca em `events/`) e
  `canuto_usage_rerank <slug>` (`:137`, score recência+frequência com
  meia-vida 7 dias, sort estável — ref sem uso mantém a ordem de entrada).
  Invariante do eoc documentado no header (`:19`): **ranqueia-antes-de-
  gravar** — o caller reordena com o uso já registrado até a chamada
  anterior; a leitura de agora nunca reforça a própria ordem (senão o
  briefing vira profecia auto-realizável).
- `session-start.sh` faz `source` de `brief-compose.sh` pela cascata padrão
  (repo → `CLAUDE_PROJECT_DIR` → `~/.canuto/lib`; sem lib = sem brief, nota
  em `_health/missing-lib.jsonl`) e chama `canuto_compose_brief`; grava as
  refs incluídas via `canuto_usage_record` e emite `BRIEF_COMPOSED` com
  `{slug, sections_populated, sections_empty, sections_broken}`.

## Consequências

- (+) `README.md:225` deixa de ser uma afirmação falsa: todo repo git passa
  a ver ao menos 2 linhas de brief (estado fresco incluído);
  `CANUTO_NO_BRIEF=1` continua desligando tudo.
- (+) Custo medido caiu de 0.65–0.79s para 0.14–0.19s ao tirar a resolução
  estrita de slug e o `mktemp`/`date` do rerank frio do caminho comum
  (`.context/fase2/receipts/A4-briefing.md`).
- (+) As três classes de sabotagem que a spec pedia (compositor mudo, seção
  vazia sem marcador, marcador honesto zerado) foram pegas nos testes ad-hoc
  do A4 e portadas para o `test-framework.sh` como Test 16 (30 asserções:
  4 estados de vault, gate `check-identity` OK/FAIL, rerank com decay/sort
  estável/ts-futuro/linha malformada).
- (−) `sections_broken` pode conter `identity_fragile`/`vault_orphan` mesmo
  quando `canuto_check_identity` retorna OK — é deliberado (fragilidade e
  órfão são avisos com dono na ADR-0010, não motivo de FAIL do gate de
  briefing), mas quem quiser gatear neles hoje precisa adicionar essa
  condição a mão.
