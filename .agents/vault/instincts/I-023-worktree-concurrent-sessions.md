---
id: I-023
title: Conductor worktrees compartilham .git — sessões paralelas podem resetar working tree
confidence: high
created: 2026-04-18
tags: [git, conductor, worktree, concurrency, debugging]
---

# I-023 — Worktrees Conductor compartilham .git

## Pattern

Quando duas sessões Claude rodam simultaneamente em workspaces diferentes que são git worktrees da mesma repo, commits + branch-switches de uma sessão podem **resetar o working tree** da outra silenciosamente.

## Evidence

**Sessão 2026-04-18:** durante FASE 2a Bloco A, ~20 Edits bem-sucedidos (Grep imediato pós-Edit mostrava 0 matches da string antiga) voltavam ao estado original segundos depois. System-reminders diziam "file modified by user or linter". `git diff` nos arquivos editados retornava vazio.

Root cause via `git reflog --all`:
```
HEAD@{3}: checkout: moving to feat/gemini-integration-fase-2a  ← eu criei branch
HEAD@{2}: commit: docs(audit): ...  ← OUTRA SESSÃO commitou na MINHA branch
HEAD@{1}: checkout: moving from feat to csorodrigo/check-codex-calls  ← OUTRA sessão
HEAD@{0}: merge: Fast-forward + push  ← OUTRA sessão
```

9 processos Claude ativos, 2 sessões distintas (`746da78d-...` eu + `4fa79590-...` outra).

## Why

Conductor cria worktrees (`workspaces/X/tallahassee/`) que compartilham `.git/` com o repo canônico (`repos/X/`). Uma sessão fazendo `git checkout` afeta o working tree da outra. Edits uncommitted em arquivos que diferem entre branches são **sobrescritos**.

## How to apply

- **Antes de edits grandes em worktree Conductor**, confirme que nenhuma outra sessão está ativa: `ps -eo pid,comm | grep claude` → deve ter só 1 processo real
- Se achar múltiplas: pergunte ao user OU encerre as outras antes de continuar
- **Sinal de diagnóstico:** Edit "sucede" mas `git diff` imediato está vazio + system-reminder "modified by user/linter"
- **Não tente re-edit em loop** — confirme com user primeiro
