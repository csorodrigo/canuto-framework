---
timeout: 1800
cli: claude
permission_mode: acceptEdits
expect_output: .agents/vault/digests/heartbeat-usage-audit.md
---
Você é o Maestro do framework Canuto em modo heartbeat (autônomo, single-shot).
Tarefa: auditoria mensal de USO REAL do framework — o mesmo exame forense que
gerou os achados de 2026-04/06, agora recorrente e barato.

1. Rode o pipeline forense (dados ficam em .context/audits/):
   `node .agents/tools/framework-session-audit.js --session-limit 200`
   (workspaces root vem de CANUTO_WORKSPACES_ROOT ou ~/conductor/workspaces;
   se indisponível, siga só com vault + sessions + event logs.)

2. Leia as métricas de delegação, se existirem:
   `jq -r '[.role,.model,.rc,.duration_s] | @tsv' ~/.codex/delegate-metrics.jsonl 2>/dev/null | sort | uniq -c | sort -rn | head -30`
   Destaque: taxa de rc=124, fallbacks, modelos efetivos vs models.yaml.

3. Leia o event log de cada projeto com vault
   (`~/.canuto/vault/projects/*/events/log.jsonl`):
   - GATE por veredito (pass/fail/skipped) — os gates estão mordendo?
   - DELEGATION por veredito — timeouts/empty caíram desde o post-gate?
   - CLOSEOUT por dia — o learning loop está rodando?
   - HEARTBEAT por task/veredito.

4. Escreva o digest em `.agents/vault/digests/heartbeat-usage-audit.md`
   (SOBRESCREVA — o post-gate confere que foi tocado):
   - Top 10 componentes usados de verdade (com contagem e fonte)
   - Componentes com 0 uso no período (candidatos a _archive/ na próxima revisão)
   - Skills "deveriam mas não estão sendo usados": gates com skip frequente,
     CLOSEOUT ausente, instincts com applied=0 há 30+ dias
   - Comparação com o período anterior, se o digest anterior existir no git

Regras: não arquive nada sozinho — arquivamento de skill é decisão humana
(tier curado, ADR-0005). Não faça push nem PR. Não escreva fora do vault e
de .context/audits/ (CONTRACT: docs/adr/0004-heartbeat-single-shot.md).
