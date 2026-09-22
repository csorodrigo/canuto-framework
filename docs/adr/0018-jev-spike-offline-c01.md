# ADR-0018 — JEV: spike offline de C-01 antes de qualquer fundação genérica

Data: 2026-09-22 · Status: aceito (escopo: spike-offline apenas)

## Contexto

Um plano de implantação para uma capacidade consultiva (JEV — julgamento fechado
consultivo) propunha construir um núcleo genérico multi-pergunta (registry,
envelope versionado, adapter, receipts, harness) antes de qualquer piloto medir
valor real. Uma revisão adversarial do plano (grilling interativo + revisão
cega via subagente Claude + revisão cega via `codex exec` gpt-5.6-sol)
identificou dois problemas: (1) construir a fundação antes de qualquer
evidência de valor arrisca sunk cost em arquitetura que ninguém usa; (2) um
spike "100% bespoke" que pula os controles de segurança do invariante 3
("selecionar folhas read-only dentro de política previamente aprovada")
reimplementaria esses controles de forma inconsistente ou os ignoraria.

Este ADR cobre só a primeira fatia executável dessa revisão: o spike-offline
de C-01 (classificar intenção da tarefa: LOCALIZAR, EXPLICAR, INVESTIGAR,
PLANEJAR, IMPLEMENTAR, REVISAR, INSUFFICIENT), sem nenhuma chamada externa,
sem consumidor real, sem vendor. O objetivo é validar a mecânica do pipeline
(schema, canonicalização, idempotência) e medir o baseline determinístico —
não decidir se um vendor real vale a pena, o que exige corpus com rótulo
humano real e confirmação de DPA (fora do escopo deste ADR).

## Decisão

- `.agents/tools/closed-judgment/` contém um schema mínimo (`schema.js`),
  hashing canônico versionado (`canonicalize.js`), um classificador
  determinístico (`baseline-classifier.js`) e um mock adapter local
  (`mock-adapter.js`, explicitamente rotulado como não-sinal-de-vendor) — sem
  registry multi-pergunta, sem policy engine configurável. Isso fica para
  depois de um gate de decisão real, só se um segundo caso justificar
  generalizar.
- A chave de idempotência (`contextHash`) hasheia a serialização canônica
  **completa** do contexto — nunca trunca a entrada — e inclui versão do
  canonicalizador, da policy, do manifest de folhas, do provedor/modelo/adapter
  e do código. Truncar antes de hashear colidiria contextos reais diferentes
  na mesma chave, suprimindo silenciosamente uma reavaliação necessária.
- `INSUFFICIENT` é um `choice` válido (o classificador respondeu "não sei"),
  não um status `ABSTAINED` — `ABSTAINED` fica reservado para falha de
  infraestrutura, não para incerteza de conteúdo. Isso fecha o buraco de
  "abstention gaming" apontado na revisão: abster-se de conteúdo não escapa da
  métrica de cobertura.
- `.agents/tests/closed-judgment/fixtures/` traz um corpus **sintético**,
  explicitamente marcado como não-suficiente para o gate de decisão real (ver
  `fixtures/README.md`). Os testes não assumem que o baseline acerta tudo —
  o corpus sintético já expõe ambiguidade real de palavra-chave, e isso é
  reportado, não escondido.
- Nenhum código aqui faz chamada de rede, escreve em consumidor real, ou toca
  em folha/tool fora deste harness. O gate de DPA e a auditoria de folha
  read-only (invariante 3) só entram quando/se houver um kernel mínimo de
  segurança e um consumidor real — não fazem parte deste ADR.

## Provas exigidas

- `bash test-framework.sh` inclui `.agents/tests/closed-judgment/replay.test.js`
  (schema, canonicalização sem truncamento, idempotência, harness ponta a
  ponta) e passa.
- `node .agents/tools/closed-judgment/replay.js --fixtures <corpus>` roda sem
  chamada de rede e sem erro de schema; `summary.json` reporta cobertura e
  precisão do baseline, incluindo misses (não os esconde).
- Nenhum literal de identidade (`rodrigooliveira`, `/Users/rodrigo`) nos
  arquivos novos — grep-gate do Teste 11 do `test-framework.sh` continua
  passando.

## Consequências

- (+) mede o baseline determinístico e valida a mecânica do pipeline antes de
  qualquer custo de fundação genérica ou de vendor.
- (+) não reabre o buraco do invariante 3 (nenhuma folha real, nenhum
  consumidor real, nenhum efeito colateral possível nesta fase).
- (-) os números deste spike (baseline: ~89% precisão / 95% cobertura no
  corpus sintético de 20 casos) não representam valor real de C-01 — o corpus
  precisa ser substituído por dados reais com rótulo humano antes do gate de
  decisão valer algo.
- (-) o gate de decisão real (generalizar arquitetura, confirmar DPA, wire em
  consumidor real) continua bloqueado por três coisas que este ADR não
  resolve: corpus real, adjudicação humana, e confirmação de DPA/contrato do
  vendor — nenhuma das três pode ser fabricada por um agente.
