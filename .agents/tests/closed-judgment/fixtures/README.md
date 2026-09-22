# Fixtures do spike-offline de C-01

`c01-replay-corpus.synthetic.jsonl` é **sintético** — escrito para exercitar o
harness (`replay.js`), não para decidir se C-01 compensa. Os `humanLabel`
deste arquivo foram atribuídos por mim (Claude) durante a implementação do
spike, não por um humano adjudicando exemplos reais de uso. Isso NÃO satisfaz
o requisito do plano de "corpus de replay congelado e redigido, com rótulos
adjudicados por humano" — serve só para provar que o pipeline (schema,
canonicalização, idempotência, métricas) funciona ponta a ponta.

## O que falta antes do gate de decisão valer alguma coisa

1. Substituir este arquivo por um corpus real: prompts/tarefas reais que
   passaram por este projeto (ou por um consumidor do framework), redigidos
   (sem segredo, sem dado pessoal, sem identificador de cliente).
2. Um humano adjudica o `humanLabel` de cada caso — não o autor do código do
   classificador.
3. Tamanho da amostra e critério de aceite pré-declarados **antes** de rodar
   o replay real (ver ADR-0018 e o addendum de revisão adversarial) — decidir
   N depois de ver a taxa de acerto invalida a garantia estatística do gate.
4. Congelar esse corpus (versionar, não editar depois de rodar o replay real).

Até isso acontecer, qualquer número que `replay.js` imprimir sobre este
arquivo synthetic é só um teste de fumaça do código, não uma medição de valor
de C-01.
