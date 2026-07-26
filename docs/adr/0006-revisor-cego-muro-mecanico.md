# ADR-0006 — Revisor cego por muro mecânico, não por instrução

Data: 2026-07-26 · Status: aceito

## Contexto

O co-review do Canuto pede "context isolation" por prosa: o Maestro deve
listar o que o revisor não deve ver. O edge-of-chaos (ADR-0013/0014 dele)
faz a cegueira ser propriedade estrutural: os subagentes revisores carregam
`disallowedTools` no frontmatter e o harness remove a porta da memória —
"this is the wall, not a courtesy".

## Opções consideradas

1. **Continuar por prosa** — rejeitada (ADR-0001: prosa não vira
   comportamento; um revisor que lê a conversa/instincts herda os vieses de
   quem escreveu).
2. **Subagent com allowlist mínima de tools** — aceita: Claude Code permite
   restringir tools por agente; subagentes já não veem a conversa por
   construção.

## Decisão

- `.claude/agents/blind-reviewer.md`: agente com `tools: Read, Grep, Glob`
  apenas — sem Bash, sem Write/Edit, sem MCP (vault via MCP inacessível por
  omissão), sem Web. Vê SÓ o que o dispatcher entrega no prompt (diff,
  arquivos citados) mais leitura do working tree.
- Limite honesto documentado: o vault é filesystem; `Read` consegue
  alcançá-lo. O muro mecânico cobre conversa (estrutural), execução,
  escrita e MCP; a proibição de ler `.agents/vault/` durante review é
  instrução no system prompt do agente — declarada como tal, não vendida
  como muro.
- O co-review M/L usa este agente para a segunda opinião cega; o veredito
  volta como strikes/MUST-FIX, nunca como reescrita.

## Consequências

- (+) Cegueira de conversa e impossibilidade de efeito colateral são
  estruturais.
- (+) Vieses do produtor não contaminam o revisor via contexto compartilhado.
- (−) O revisor não roda testes (sem Bash) — verificação de execução
  continua no Reviewer normal com `verification-gates`; os dois papéis são
  complementares, não substitutos.
