# ADR-0018 — Escrita distribuída entra por envelopes; somente o integrador publica o vault

Data: 2026-08-23 · Status: aceito, rollout opt-in

## Contexto

O ADR-0007 moveu o vault oficial do Mac para a VPS e permitiu que o working
vault da VPS e o espelho do Mac empurrassem para o mesmo hub bare. Isso resolveu
a dependência do Mac, mas criou uma topologia multiwriter: Obsidian Git, cron,
hooks, Claude, Codex e sessões SSH podiam produzir históricos divergentes ou
falhas de push invisíveis.

Além disso, "um host escritor" não garante serialização. Vários processos no
mesmo Papiro ainda podem editar, commitar ou publicar simultaneamente. Locks
locais do event log protegem apenas um arquivo e são deliberadamente fail-open;
não constituem um contrato de mutação do vault inteiro.

## Decisão

- O Papiro mantém o papel de integrador ativo, mas a autoridade de mutação fica
  num processo `vault-integrator`, com working tree limpo, branch canônica e lock
  exclusivos. `--commit` falha antes da mutação se detectar WIP ou branch errada.
- Mac, Dobra e outros hosts mantêm clones locais para leitura. Eles não precisam
  do Papiro no caminho crítico de busca.
- Escritas atravessam envelopes JSON idempotentes. Cada envelope contém:
  `id`, operação, target, tier, hash do payload, precondição CAS, origem e,
  quando curado, aprovação.
- O v1 aceita somente `create` e `replace` de Markdown sob
  `projects/<slug>/<area>/`. Delete, move e merge permanecem fora do contrato.
- `replace` exige `expected_sha256`; target alterado desde a proposta é rejeitado.
- Tier hipótese pode entrar em áreas operacionais permitidas. Tier curado exige
  `approval.by` e `approval.at`.
- Cada aplicação gera receipt fora do vault, com hashes, origem, target, commit
  e estado de publicação. Um journal é persistido antes da mutação; interrupção
  antes do receipt vira `recovery-required`, nunca reaplicação silenciosa.
  Repetir o mesmo envelope não reaplica a mutação;
  reutilizar o mesmo id com conteúdo diferente é colisão e falha alto.
- O lock do integrador é fail-closed. Um segundo processo recebe `EX_TEMPFAIL`
  em vez de escrever sem coordenação.
- O outbox é persistente. Falha de SSH mantém o envelope no host de origem.
- Commit e push são flags explícitas. A instalação não ativa cron nem publicação
  automaticamente.

## Relação com decisões anteriores

Este ADR **substitui somente a parte multiwriter do ADR-0007**. Continuam válidas
as decisões de que o framework roda onde a sessão roda, a VPS não é periferia e
o Mac não é a única fonte de memória.

O ADR-0001 permanece válido: eventos de lifecycle continuam tendo log append-only
como fonte de verdade; notas de sessão e auditoria são projeções. O integrador
controla mutações de Markdown, não redefine a origem dos eventos.

## Rollout

A implementação inicial vive em `.agents/vps/` e é opt-in. A migração completa
exige, em fases posteriores, redirecionar os writers legados do Papiro para
`vault-submit` e desativar auto-push dos espelhos. Até esse corte, receipts do
integrador provam apenas operações que passaram por ele — não provam ausência de
writers legados.

## Consequências

- (+) Escritas cross-host deixam de disputar `main` diretamente.
- (+) Dobra e Mac continuam lendo localmente durante indisponibilidade do Papiro.
- (+) CAS impede sobrescrever uma nota que mudou após a proposta.
- (+) Receipts distinguem conteúdo aplicado, commit criado e push publicado.
- (+) O escopo estreito impede que a primeira versão vire um motor destrutivo de
  merge/delete antes da auditoria do vault.
- (−) O Papiro vira líder ativo de publicação; failover ainda é manual.
- (−) Writers legados precisam ser migrados antes de declarar single-writer pleno.
- (−) Envelopes carregam payload em base64 e não são adequados a anexos grandes;
  binários e mídia ficam fora do v1.
