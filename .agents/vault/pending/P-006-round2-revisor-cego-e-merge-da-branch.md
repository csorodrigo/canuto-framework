---
type: pending
id: P-006
status: pending
priority: high
owner: maestro
provider: ""
created-session: "2026-08-03"
source: "sessão 2026-08-03 — regras de engenharia no AGENTS.md"
rework-count: 0
retry-count: 0
tags: [review, merge, agents-md]
---

# P-006 — Fechar o ciclo de review e decidir o merge da branch

## Estado

Branch `claude/agent-feasibility-analysis-quvsma`, 3 commits, **não mergeada**,
sem PR aberto:

- `8ea8b02` — 3 regras de engenharia em `## Coding Rules`
- `ccaf5fb` — crases escapadas em heredoc quoted
- `50cad9c` — hardening do patcher + teste `12f2`

## Ações

- [x] Round 2 do revisor cego incorporado — veredito REQUEST CHANGES,
      1 BLOCKER + 3 MAJOR + 2 MINOR, **todos os 6 endereçados** em `5f1a62f`.
      O BLOCKER era regressão da correção do round 1 (ver `instincts/I-030`).
- [x] Round 3 e round 4 rodados. **Round 4 fechou em APPROVE** — loop de review
      encerrado.
- [ ] Decidir o merge (única ação restante). Ver ressalvas abaixo.

## Estado do review — ENCERRADO EM APPROVE

| Round | Veredito | Strikes | Disposição |
|-------|----------|---------|------------|
| 1 | REQUEST CHANGES | 3 MAJOR + 4 MINOR | 5 corrigidos, 1 rejeitado, 1 corrigido de outro jeito |
| 2 | REQUEST CHANGES | 1 BLOCKER + 3 MAJOR + 2 MINOR | 6/6 corrigidos |
| 3 | REQUEST CHANGES | 4 MAJOR + 3 MINOR | 5 corrigidos, 2 aceitos e documentados |
| 4 | **APPROVE** | 0 gate, 2 ressalvas | não corrigidas — decisão consciente |

Commits: `8ea8b02`, `ccaf5fb`, `50cad9c`, `b3f5c1c`, `5f1a62f`, `fcdc72e`.
Suíte no commit aprovado: 316 passed, 0 failed.

## Ressalvas aceitas no APPROVE (não são gate)

1. **Sem `trap`**: interrupção por sinal entre a escrita do temp e o `mv` deixa
   `AGENTS.md.canuto.<pid>` órfão no working tree. É o estilo do arquivo inteiro
   — zero `trap` em 3871 linhas, e `TMP_DIR` e `.prev.$$` têm o mesmo shape. O
   `git add` usa lista de paths explícita, então o órfão não entra em commit.
2. **Regex de heading estrita**: `## Coding Rules ##` (hashes de fechamento),
   heading indentado 1-3 espaços, ou Setext (`Coding Rules` + `-----`) não são
   reconhecidos, e o instalador anexa uma segunda seção. Converge em 1 run (não
   cresce), mas deixa duas seções com conteúdos diferentes num arquivo cuja
   função é ser lido por agente. Os blocos irmãos usam substring sem âncora e
   não têm essa classe.

**Não corrigidas de propósito.** Ver `instincts/I-030`: neste mesmo trabalho, uma
correção de MINOR introduziu um BLOCKER. Mexer depois do APPROVE reabre o ciclo
de risco sem mandato. Se forem corrigidas um dia, exigem novo round de review.

## Opção de projeto ainda em aberto

Substituir a cirurgia de seção markdown por bloco gerenciado com marcador
(`<!-- canuto:engineering-rules -->` ... `<!-- /canuto:engineering-rules -->`)
colapsaria a classe inteira de defeito que os 4 rounds encontraram: deteção vira
exata, idempotência vira estrutural, ressalva 2 desaparece. A janela barata é
**antes do merge** — depois existem instalações para migrar.

## Contexto para não reabrir a discussão

As 4 regras rejeitadas do print original **não devem voltar** sem revisitar o
motivo. Estão registradas em `sessions/2026-08-03.md` com arquivo:linha dos
conflitos. Em especial "não preservar retrocompatibilidade" e "preferir libs
estabelecidas" colidem com gates ativos.
