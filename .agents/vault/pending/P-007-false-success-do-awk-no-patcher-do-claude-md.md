---
type: pending
id: P-007
status: pending
priority: low
owner: maestro
provider: ""
created-session: "2026-08-03"
source: "revisão adversarial da sessão 2026-08-03 (strike MINOR, pré-existente)"
rework-count: 0
retry-count: 0
tags: [install, shell, robustez]
---

# P-007 — `install.sh:894`: falha do awk reportada como sucesso no patcher do CLAUDE.md

## Defeito

```bash
awk '...' "$CLAUDE_MD" > "${CLAUDE_MD}.tmp" && mv "${CLAUDE_MD}.tmp" "$CLAUDE_MD"
ok "  patched: planning-interview rule added to ## Project Rules"
appended=1
```

O `awk` está do lado esquerdo de um `&&`, o que o isenta do `set -e` ativo
(`install.sh:21`). Se ele falhar — ENOSPC, `.tmp` já existente como diretório,
diretório sem permissão — o `mv` não roda, o `CLAUDE_MD` fica intacto, mas o
script imprime "patched" e segue. Sobra um `CLAUDE.md.tmp` órfão na raiz, e
`*.tmp` não está no `.gitignore`, então entra num `git add -A`.

## Correção

Mesmo shape já aplicado em `merge_agents_md` na sessão de 2026-08-03:

```bash
if awk '...' "$src" > "$tmp"; then
  cat "$tmp" > "$dst"      # cat-over preserva symlink, modo e inode
  appended=1
else
  warn "..."
fi
rm -f "$tmp"
```

## Por que é low

Pré-existente, não introduzido pela mudança desta sessão, e o modo de falha
exige uma condição de disco/permissão. Mas é o mesmo defeito que o revisor cego
apontou no bloco novo — corrigir os dois deixa o arquivo consistente.

## Verificar junto

- [ ] Adicionar `*.tmp` ao `.gitignore` da raiz.
- [ ] Varrer o `install.sh` por outros `cmd > tmp && mv tmp dst` com `ok` incondicional.
