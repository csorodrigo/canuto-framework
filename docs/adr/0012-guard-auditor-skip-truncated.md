# ADR-0012 — O guard vira auditor: SKIP-TRUNCATED nunca é HOLD

Data: 2026-08-01 · Status: aceito (implementação completa em 2026-08-01, 2ª rodada)

## Contexto

A auditoria 2026-08-01 mediu `CANUTO_ALLOW_COMMIT=1` como modus operandi: 92
overrides no mecesa, 246 no lucrando-ai. Causa raiz identificada: o
pre-commit guard trunca o diff de migrations/validators grandes antes de
mandar ao reviewer Codex e depois dá `HOLD` **pelo próprio truncamento** —
sempre o mesmo falso motivo, sempre a mesma resposta (ignorar via override).
O gate virou ruído em vez de sinal.

O edge-of-chaos nomeia essa espiral (ADR-0021 dele): chokepoint → bypass →
chokepoint, e formula o princípio central (ADR-0003 dele): *"the delta
enriches a beat, it does not gate one"* — uma condição que só **enriquece**
a revisão (ter o diff completo) não pode **gatear** o commit quando ausente.

## Opções consideradas

1. **Parar de truncar diffs grandes** — rejeitada: custo de contexto/token
   inviável para diffs de migration reais.
2. **Bloquear sempre que houver truncamento** (postura conservadora) — é o
   comportamento medido e é exatamente o que gerou o ruído dos 92/246
   overrides — rejeitada.
3. **Rebaixar HOLD-por-truncamento a advisory** (`SKIP-TRUNCATED`) e reservar
   bloqueio real para veredito sobre o que foi de fato revisado — aceita.

## Decisão

O que está implementado hoje em `.agents/hooks/codex-pretool-guard.sh`:

- O enum de veredito ganha um terceiro valor (`:260`): `COMMIT` \| `HOLD` \|
  `SKIP-TRUNCATED`.
- O prompt do reviewer instrui explicitamente (`:291-295`): nunca retornar
  `HOLD` por conteúdo ausente, omitido ou truncado — "omission is a
  deliberate budgeting decision, not an author error"; se um arquivo
  security-sensitive ficou fora do contexto por orçamento, o veredito certo é
  `SKIP-TRUNCATED`, tratado como **advisory pass**, nunca bloqueio.
- Em runtime (`:498-517`): `SKIP-TRUNCATED` nunca bloqueia o commit, imprime
  "diff truncado — review parcial, não vinculante" e grava evento
  `type=skip-truncated` no arquivo de métricas com os campos relevantes
  (`files_omitted`, `sensitive_omitted`, `summary`).
- O override `CANUTO_ALLOW_COMMIT=1` (`:155`) continua funcionando e
  registrado no metrics.

## Consequências

- (+) Elimina a classe de `HOLD` mais barulhenta do sistema — bloqueio pelo
  próprio truncamento do guard, e não pelo conteúdo do commit.
- (+) Diferencia estruturalmente "não vi o suficiente para opinar" (advisory)
  de "vi e reprovo" (bloqueante) — a distinção que faltava.
- (+) **Escada de enforcement** (2ª rodada, mesmo dia): `CANUTO_GUARD_MODE`
  `0=off` / `1=observe` / `2=gate` (default `2`; valor inválido cai em `2`).
  A escada cobre SÓ a perna de review do `handle_commit_gate`; os checks
  estáticos de segurança ficam sempre ativos em qualquer modo. Modo `1` roda
  o review inteiro e registra o veredicto com `enforced:false` sem nunca
  bloquear; modo `0` registra `disabled` uma vez por sessão. A des/re-escalada
  do default é decisão futura POR EVIDÊNCIA — os eventos já carregam
  `mode`/`enforced` desde já (eoc ADR-0021: a catraca decide sobre dado
  logado, nunca por vibe).
- (+) **Infra ≠ veredito**: falha de transporte/timeout/schema do reviewer
  emite `type=guard-dark` e imprime "review indisponível — commit segue SEM
  review (dark)" — nunca HOLD nem COMMIT fabricado.
- (+) **O veto ganha caneta** (eoc ADR-0024): o override registra
  `reason:"${CANUTO_ALLOW_REASON:-unstated}"` no evento `override-commit` —
  não exigida, só registrada; vira dado de calibração da próxima auditoria.
- (−) A 1ª tentativa de implementação via Codex falhou por colisão de
  sessões concorrentes no mesmo worktree (registrado em
  `.context/fase2/COORDINATION.md`); a 2ª rodada (Claude) completou o spec.
- (−) A falha do GERADOR de diff-context (`codex-diff-context.sh`) segue no
  fail-open pré-existente sem review nenhum — é anterior ao review, então não
  passa por `_guard_dark_event`; a falha do REVIEWER (fast/full/schema
  inválido) emite `type=guard-dark` com `reason` (`reviewer-unavailable` /
  `invalid-output`). Um fato, uma classe: gerador escuro ≠ reviewer escuro.
