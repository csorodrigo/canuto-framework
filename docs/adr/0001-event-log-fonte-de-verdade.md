# ADR-0001 — O event log append-only é a fonte de verdade dos eventos de sessão

Data: 2026-07-26 · Status: aceito

## Contexto

A auditoria de 200 sessões (2026-06-10/11) mediu que registro por prosa não
acontece: só 3 dos ~85 skills raiz foram lidos alguma vez em runtime, o skill
`audit-trail` (que pede ao agente escrever uma nota por evento) teve adesão
quase nula, e o vault do próprio framework ficou 7 semanas sem nota de sessão
enquanto os commits continuavam. Instrução não vira comportamento.

O edge-of-chaos resolveu o mesmo problema com o ADR-0006 dele: "a mutable,
LLM-lossy store cannot be a versioning root" — o log de eventos é a verdade,
tudo o mais é projeção, e a escrita é mecânica.

## Opções consideradas

1. **Mais prosa** (reforçar playbooks, lembretes) — rejeitada: foi exatamente
   o que a auditoria provou não funcionar.
2. **MCP obrigatório para o vault** — rejeitada: o MCP obsidian teve 0
   chamadas em 200 sessões; adicionar dependência a um caminho morto.
3. **Log JSONL escrito pelos hooks** — aceita: os hooks já disparam em todo
   o lifecycle (SessionStart/Stop/PostToolUse/Notification) e não dependem
   de o modelo escolher cumprir.

## Decisão

- `events/log.jsonl` por projeto (vault global > vault local > fallback
  `.agents/.cache/events/`), append-only, uma linha JSON por evento.
- Escrito por `.agents/tools/event-log.sh`, chamado pelos hooks:
  SESSION_START, SESSION_END, PRE_COMPACT, TOOL_CALL, GATE, DELEGATION,
  HEARTBEAT, INSTINCT_ARCHIVED. O agente só escreve eventos semânticos
  (CLOSEOUT, HANDOFF, REWORK) via CLI — e o gate de saída verifica.
- Notas do vault (audit/, sessions/) tornam-se **projeções**: podem ser
  derivadas do log; o inverso nunca.

## Consequências

- (+) Todo gate passa a ter algo mecânico para verificar (ADR-0002).
- (+) O pipeline forense (`framework-session-audit`) ganha dataset direto,
  sem heurística de transcript.
- (−) Crescimento do log (mitigado: TOOL_CALL só para tools de estado,
  `CANUTO_EVENT_LOG_TOOLS=core|all|off`).
- (−) Correção nunca é edição: um evento errado se corrige com outro evento.
