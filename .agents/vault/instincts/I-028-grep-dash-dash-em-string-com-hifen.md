---
id: I-028
title: grep/sed com string que começa em "-" precisa de `--` antes do padrão
confidence: low
created: 2026-08-03
applied-count: 1
last-seen: 2026-08-03
tags: [shell, install, false-negative, idempotencia]
source-session: "2026-08-03"
---

# I-028 — `grep -qF -- "$x"` quando `$x` pode começar com hífen

## Pattern

Guardas de idempotência que procuram uma **linha de markdown** dentro de um
arquivo quase sempre procuram uma string que começa com `- ` (bullet). Sem `--`,
o `grep` interpreta o padrão como bundle de opções:

```
$ grep -qF "- Grow in layers: ..." arquivo
grep: invalid option -- ' '
```

O exit code não-zero é indistinguível de "não encontrado". Num guard do tipo

```bash
grep -qF "$rule" "$file" || inserir_regra
```

isso significa que a regra é **sempre** inserida — a cada execução. O sintoma só
aparece na segunda run, então passa por teste de uma passada só.

## Correto

```bash
grep -qF -- "$rule" "$file" || inserir_regra
```

Vale igual para `sed`, `awk -v`, `printf` com string de origem externa, e
qualquer `[ "$x" = ... ]` onde `$x` vem de heredoc de conteúdo.

## Onde apareceu

`install.sh` → `merge_agents_md`, guard por regra do bloco `## Coding Rules`.
O mesmo erro foi cometido no teste `12f2` escrito para cobrir o caso — ou seja,
teste e código compartilharam o defeito.

## Gatilho

Sempre que escrever um guard `grep -q` cujo padrão vem de uma variável, e não de
um literal digitado na hora. Se o conteúdo é markdown, assuma que começa com `-`.

## Regra de teste que teria pego

Rodar o instalador/patcher **duas vezes** e assertar contagem 1, nunca só uma vez.
