---
id: I-026
title: Branch de origin/main quando o trabalho é tópico separado da branch atual
confidence: high
created: 2026-04-18
tags: [git, workflow, pr, branching]
---

# I-026 — Tópico separado → branch de `origin/main`, não da atual

## Pattern

Quando uma nova tarefa é **tópico independente** da branch onde a sessão começou, criar a feature branch a partir de `origin/main` (com stash da WIP local se preciso) — **nunca** `git checkout -b` direto da branch atual quando ela já tem commits ahead de main não-relacionados ao novo trabalho.

## Evidence

**Sessão 2026-04-18 (PR #35 → #36):** Sessão começou em `feat/gemini-integration-fase-2a` (31 commits ahead de main, todos sobre integração Gemini). Trabalho da sessão foi tópico separado: rtk + Repomix MCP + skill /context-health. Criei branch via `git checkout -b feat/rtk-repomix-context-health` da atual.

Resultado: PR #35 abriu com **32 commits / 66 files / 7455 additions** e ficou `mergeStateStatus: DIRTY` (CONFLICTING) porque herdou todo o histórico gemini não-mergeado.

Custo: tive que abortar, stash, re-branchar de `origin/main`, cherry-pick (que também conflitou em install.sh por causa de refactor não-meu na branch original), abortar de novo, re-aplicar Edits manualmente, commit limpo, push, fechar PR sujo, abrir PR #36 (598 additions / 9 files / 0 deletions, MERGEABLE em segundos).

## How to apply

- **Antes de `git checkout -b`**: perguntar "este trabalho é continuação da branch atual ou tópico separado?"
- Se separado: `git stash push -u -m "WIP <branch atual>"` → `git checkout -b <nova> origin/main` → trabalho → commit → push → `git checkout <branch atual> && git stash pop`
- Em workspace Conductor com `main` em outro worktree: usar `git checkout -b <nova> origin/main` direto (não tentar `git checkout main` antes — falha com "already used by worktree")
- Se já errou e o PR está poluído: fechar com `gh pr close --delete-branch`, recriar limpo, **não tentar rebase --onto** se há conflitos em arquivos não-meus (cherry-pick + Edits manuais é mais seguro que merge automático aceitando refatores alheios)
- `gh pr merge --auto --squash` falha com "main already used by worktree" pra fazer post-merge cleanup local, mas o merge via API funciona — verificar com `gh pr view` antes de retry
