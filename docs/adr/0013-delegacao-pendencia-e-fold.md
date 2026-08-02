# ADR-0013 — Pendência de delegação é fold do log; recibo não fecha nada

Data: 2026-08-01 · Status: aceito

## Contexto

A auditoria 2026-08-01 mediu 42 falhas de delegação Codex contra só 3
declarações de fallback nos transcripts. `postdelegate-verify.sh` já
registrava a falha (aviso bloqueante via `additionalContext`), mas não
mantinha nenhuma pendência endereçável: o Maestro via o aviso, podia segui-lo
ou não, e nada no sistema lembrava que aquela delegação continuava sem
resolução. "Fallback nunca é silencioso" não se sustentava como regra de
prosa.

O edge-of-chaos resolve exatamente isso em `tools/voz.py` (~130 linhas): uma
pendência é um **fold** derivado do log a cada consulta, nunca uma flag
persistida — e um recibo (`receipt_sent`) **não fecha** um item; só uma
resposta com referência ou um dead-letter com razão fecham. A ADR-0017 do
eoc nomeia o antídoto ao fallback silencioso: um executor autônomo sem
resposta só pode **parquear** visível, nunca fabricar `acknowledged`.

## Opções consideradas

1. **Guardar a pendência num arquivo de estado/cursor próprio** — rejeitada:
   vira opinião que pode dessincronizar do log real; o eoc trata isso como o
   erro de design que `voz.py` corrige.
2. **Confiar só no aviso do `postdelegate-verify.sh`**, sem ledger — é o
   status quo medido (42 falhas, 3 declarações) — rejeitada.
3. **Ledger como fold puro** sobre `delegate-metrics.jsonl` + event log do
   projeto, com dois únicos atos que fecham um item — aceita.

## Decisão

- `.agents/tools/delegation-ledger.sh` (novo):
  - `delegation_ledger_pending [--since <iso>]` (`:163`) — para cada linha
    de `delegate-metrics.jsonl` com `result != "OK"` sem evento posterior de
    fechamento, imprime uma linha. **Nunca mantém cursor**: é recalculado a
    cada chamada.
  - `delegation_dead_letter <id> <razão>` (`:217`) — razão vazia ou só
    espaço → `exit 1` nomeando o `id`; senão emite
    `DELEGATION_DEAD_LETTER`.
  - `delegation_declare_fallback <id> <executor-real>` (`:239`) — emite
    `FALLBACK_DECLARED`, o ato mecânico que a regra "fallback nunca é
    silencioso" exigia.
  - `id` = o campo `ts` da linha de métrica (`delegate-metrics.jsonl` não
    tem id próprio) — trade-off de colisão em delegações no mesmo segundo,
    documentado e aceito no header do arquivo.
- `postdelegate-verify.sh` (posse da sessão AUDIT-FIX, já em produção): dois
  gates em sequência — **gate de métrica** (`:96-139`, dobra
  `delegate-metrics.jsonl`: "exit 0 do wrapper não prova nada... result !=
  OK" vira `additionalContext` bloqueante) e **gate de artefato**
  (`:141-163`, out-file existe/não-vazio/`rc != 124`). A frase que resume o
  princípio (eoc `_beat.py::assert_beat_produced`) está no cabeçalho do
  arquivo: exit 0 só prova que o subprocesso rodou — dobrar o log é a única
  prova.
- `pre-finalize.sh` (Stop hook): chama `delegation_ledger_pending` e, se
  houver pendências, imprime cada `id` com as duas opções legais
  (`delegation_dead_letter <id> "<razão>"` \| `delegation_declare_fallback
  <id> claude-direct>`) — nunca um "há pendências" genérico. Não bloqueia o
  Stop (advisory, mesma filosofia da ADR-0002).

## Consequências

- (+) Uma pendência só sai do fold por um ato registrado — nunca por
  reinício de sessão, esquecimento, ou por alguém simplesmente ter lido o
  aviso.
- (+) O Stop hook nomeia cada `id` pendente explicitamente, fechando o
  espaço onde a lacuna medida (42 vs 3) se escondia.
- (−) **Inconsistência de nomenclatura encontrada, não corrigida.**
  `.context/fase2/00-convencoes.md:42` declara o tipo de evento
  `DELEGATION_PENDING` como contrato da Fase 2, mas `postdelegate-verify.sh`
  emite o tipo genérico `DELEGATION` (com campo `verdict=...`) nas duas
  ocasiões em que grava evento (`:120`, `:165`). O item 2 do
  `spec-A2-delegation.md`, que pediria essa emissão, foi explicitamente
  pulado por colisão com a sessão AUDIT-FIX
  (`.context/fase2/receipts/A2b-delegation.md`, §3.5). O ledger não depende
  do nome do evento — lê `delegate-metrics.jsonl` diretamente — mas o
  contrato de nomenclatura documentado na Fase 2 diverge do que está em
  produção.
- (−) `DELEGATION_RESOLVED` é reconhecido pelo fold como fechamento (por
  simetria com o texto da spec), mas nenhuma função hoje o emite — só
  `DELEGATION_DEAD_LETTER` e `FALLBACK_DECLARED` são produzidos. Fica como
  extensão futura se uma re-delegação bem-sucedida precisar fechar o `id`
  original sem ser dead-letter nem fallback.
