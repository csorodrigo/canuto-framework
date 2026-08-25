---
id: I-029
title: Um sentinel por item inserido; bloco de patch espelha a seção inteira
confidence: low
created: 2026-08-03
applied-count: 1
last-seen: 2026-08-03
tags: [install, idempotencia, patcher, merge]
source-session: "2026-08-03"
---

# I-029 — Patcher idempotente: um sentinel por item, e nunca seção parcial

## Pattern A — sentinel único guardando inserção múltipla

```bash
if ! grep -q "FRASE_A" "$f"; then
  inserir A, B e C        # ← errado
fi
```

Se o consumidor apagar, traduzir ou reformatar **só** a frase A, o guard erra e
o bloco reinsere A, B e C — duplicando B e C. Quanto mais tempo o arquivo vive
no projeto do usuário, mais provável a edição parcial.

Correto: um sentinel por item. Colete os faltantes primeiro e insira numa
passada só, para preservar a ordem canônica.

## Pattern B — bloco de patch entregando pedaço da seção

Quando o instalador tem dois caminhos — heredoc de geração e bloco de patch —
o bloco de patch precisa espelhar a seção **inteira**, não só o delta que
motivou a mudança. Caso contrário:

1. o consumidor sem a seção recebe uma versão amputada;
2. o sentinel passa a casar para sempre;
3. nenhuma execução futura repara.

O resultado é dois projetos com a mesma versão do instalador e conjuntos de
regras materialmente diferentes, ambos reportando "patched".

## Pattern C — a duplicação de texto precisa de detector

Texto replicado entre heredoc de geração, bloco de patch e arquivo de exemplo
não tem como não divergir. Se não for possível ter fonte única, adicione um
teste que assere a contagem de cópias — e **verifique o teste negativamente**,
perturbando cada cópia, senão ele é um verde vazio.

## Onde apareceu

`install.sh` → `merge_agents_md`. Os blocos irmãos (`MCPPATCH`, `PROFILEPATCH`,
`VAULTPATCH`, `RUNTIMEPATCH`) já seguiam o Pattern B corretamente; o bloco novo
foi o único que entregava um pedaço.

## Gatilho

Ao adicionar qualquer bloco novo em `merge_agents_md`, `merge_claude_md` ou
qualquer patcher section-level: comparar com os blocos irmãos antes de escrever.
Divergir da convenção deles é sinal de defeito, não de melhoria.
