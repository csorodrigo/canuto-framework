---
id: I-027
title: Checar git log + ls-tree em main antes de afirmar que algo é gap
confidence: high
created: 2026-04-18
tags: [git, verification, anti-hallucination, framework-audit]
---

# I-027 — Antes de afirmar "não existe", checar `git log --grep` e `git ls-tree origin/main`

## Pattern

Quando o usuário pergunta sobre uma feature/skill ou quando vou afirmar que algo é "gap" / "não existe" / "não foi feito", **antes de responder**, executar:

```bash
git log --all --oneline --grep="<feature>" --since="..."
git ls-tree -r origin/main --name-only | grep -i '<feature>'
```

E olhar PRs mergeados via `gh pr list --state all`.

## Evidence

**Sessão 2026-04-18:** Usuário perguntou "não tem skill chamando Gemini ativamente? co-plan com 3 em paralelo?". Respondi com confiança que `/co-plan` era só dual (Claude + Codex), Gemini fora. Listei como gap real e propus criar `/tri-plan` do zero.

Usuário corrigiu: "ja tinha sido feito, em outra branch q vc n fez o merge". Verificação imediata mostrou:
- `git log --all --grep="tri-plan"` → commit `a735e04` "feat(gemini): Padrões 1, 2, 6 — tri-plan, diff-router review, research trio"
- `git ls-tree -r origin/main` → `global-skills/co-plan/SKILL.md` existe
- Lendo o arquivo: seção `## /co-plan --triple (tri-plan variant, FASE 2a+)` com fluxo completo de Opus + Codex reviewer + Gemini 3.1-pro-preview em paralelo

Eu olhei só em `.agents/skills/co-review/SKILL.md` e não vi que existe outra skill em `global-skills/co-plan/SKILL.md`. Skills moram em DOIS lugares no Canuto: `.agents/skills/` (project-level) e `global-skills/` (cross-project). Buscar só em um cega para metade do framework.

## How to apply

- **Antes de afirmar "não existe":** rodar Glob em ambos `.agents/skills/**` E `global-skills/**`
- **Antes de propor criar skill nova:** `git log --all --grep="<keyword>"` + `gh pr list --state all --search "<keyword>"`
- **Quando user diz "já foi feito":** assumir que está certo, fazer a verificação completa antes de discordar
- **Em workspace Conductor:** `origin/main` é a fonte de verdade do que está deployado, não a branch atual (que pode ser feature WIP)
- **Skills moram em 2 dirs:** `.agents/skills/` (project) e `global-skills/` (user-scope, deployado em `~/.claude/skills/`)
