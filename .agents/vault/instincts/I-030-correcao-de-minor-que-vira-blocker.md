---
id: I-030
title: Trocar mecanismo de escrita para atender um MINOR pode criar um BLOCKER
confidence: low
created: 2026-08-03
applied-count: 1
last-seen: 2026-08-03
tags: [review, shell, escrita-atomica, regressao]
source-session: "2026-08-03"
---

# I-030 — Avaliar troca de mecanismo de escrita pelo pior caso, não pela propriedade desejada

## O que aconteceu

Round 1 do revisor cego apontou um **MINOR**: publicar com `mv` substitui um
symlink por cópia local num layout de monorepo. Troquei por `cat tmp > arquivo`
para preservar o symlink.

Round 2 apontou que essa troca era um **BLOCKER**: o `>` trunca o arquivo do
usuário **antes** do `cat` escrever. Falha no meio (ENOSPC/EIO) deixa o arquivo
parcial ou zerado — e a linha seguinte apagava o único temp íntegro.

Troquei "symlink vira cópia em caso raro" por "arquivo do usuário destruído,
reportado como sucesso".

## Regra

Ao mudar **como** um arquivo do usuário é publicado, comparar os mecanismos pelo
**pior estado alcançável**, não pela propriedade que motivou a mudança:

| Mecanismo | Pior caso |
|---|---|
| `cat tmp > dst` / `cmd > dst` | dst truncado ou parcial; irrecuperável |
| `mv tmp dst` | rename é atômico: dst é o conteúdo velho ou o novo, nunca meio |
| `cat >> dst` | append-only; incapaz de destruir conteúdo prévio |

Se o objetivo é preservar symlink/inode, resolver o alvo (`readlink -f`) e
`mv` **em cima do alvo** entrega as duas coisas. Herdar o modo do original com
`chmod` explícito, senão o publicado nasce com o umask.

## Sinal de alerta

`set -e` não protege: em `if ! funcao; then`, o bash desliga errexit em toda a
subárvore da condição. Não presumir que uma falha aborta.

## Gatilho

Toda vez que um review pedir "preserve X" numa etapa de escrita. Antes de mudar
o mecanismo, escrever a linha do pior caso dos dois lados e comparar.
