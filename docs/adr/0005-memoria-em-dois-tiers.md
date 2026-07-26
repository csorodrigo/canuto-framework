# ADR-0005 — Memória em dois tiers: hipótese grava direto, curado exige humano

Data: 2026-07-26 · Status: aceito

## Contexto

O learning loop do Canuto exigia aprovação para TODA escrita ("never
auto-save instincts", "never silently write"). Resultado medido: nada era
escrito — o vault do próprio framework ficou 7 semanas sem nota de sessão,
`handoffs/` vazio, `repo-index.json` nunca gerado. Gate total = loop morto.

O edge-of-chaos resolve com a disciplina de dois tiers (ADR-0008 dele, a
guarda da "falha Zep"): extração automática escreve livremente no tier
hipótese; só a curadoria humana promove ao tier com autoridade.

## Opções consideradas

1. **Manter aprovação total** — rejeitada: medida e morta.
2. **Auto-write total** — rejeitada: decisão/regra/global com autoridade
   escritas por LLM sem humano é exatamente a falha que o tier curado evita.
3. **Fronteira de tiers** — aceita.

## Decisão

| Tier | Conteúdo | Escrita |
|---|---|---|
| Hipótese | instinct candidates (low), sessions, pending, metrics | automática; anuncia-se o que foi salvo |
| Curado | promoções medium/high, decisions, stack.md, global-instincts | só com aprovação explícita |

- Aging é mecânico e só toca hipótese: `instinct-aging.sh` arquiva
  (`status: archived`, nunca deleta) low sem uso >30 dias; evento
  INSTINCT_ARCHIVED no log. Curado é exento — prune de curado é humano.
- `obsidian-writeback-queue` mantém preview+aprovação apenas para o tier
  curado.

## Consequências

- (+) O loop volta a escrever; o custo de um candidato ruim é ~zero
  (arquivável, nunca promovido sozinho).
- (+) Aprovação humana vira sinal raro e significativo, não ruído.
- (−) O vault acumula mais hipótese — mitigado pelo aging e pelo teto de
  30 instincts ativos.
