# ADR-0002 — Gates fail-closed nas costuras, não instruções no playbook

Data: 2026-07-26 · Status: aceito

## Contexto

O Canuto tinha ~6 invariantes reais impostos por hooks e dezenas de "gates"
que eram texto. Dois furos medidos: (1) o gate de testes pré-PR só
interceptava o tool MCP do GitHub — `gh pr create` via Bash passava reto;
(2) 17% das delegações Codex falhavam com rc=124 (timeout) sem que o Maestro
percebesse, consumindo resultado vazio como se fosse entrega.

O edge-of-chaos formulou o princípio (ADR-0016 dele, "no wake, no publish"):
contratos sobrevivem onde são código, e a verificação pertence à **costura**
que todo caminho é obrigado a cruzar — não a uma seção de playbook.

## Opções consideradas

1. **Reforçar o playbook do Maestro** — rejeitada (ver ADR-0001: prosa não
   vira comportamento).
2. **Bloquear tudo por default** — rejeitada: o edge documenta o fracasso
   dessa via (o gate vira "o monstro", otimiza compliance e gera bypass).
   Gate bloqueante só onde o dano é objetivo; o resto observa e registra.
3. **Gate na costura + evento no log** — aceita.

## Decisão

- `pre-pr-bash-gate.sh`: criação de PR via Bash (`gh pr create`) passa pelo
  MESMO gate de testes do caminho MCP. Exit 2 bloqueia. Override consciente
  `CANUTO_SKIP_PR_GATE=1` — permitido, mas registrado no log.
- `postdelegate-verify.sh`: após toda delegação Codex, verificação mecânica
  do artefato (out-file existe, não-vazio, rc≠124). "Exit 0 não prova nada —
  o artefato prova." Falha → aviso alto ao Maestro + evento DELEGATION.
- Gate de closeout no Stop: `session-save.sh` verifica CLOSEOUT no event log
  e avisa com evidência concreta quando falta (informativo, não bloqueante —
  Stop hook não deve prender a sessão).

## Consequências

- (+) Os dois furos medidos fecham com verificação, não com pedido.
- (+) Todo veredito de gate vira evento — o pipeline de auditoria enxerga.
- (−) Overrides existem e são auditáveis; um usuário que os abuse aparece
  no log (é o desenho: rastro, não cadeado).
