---
name: ask-canuto
description: Roteador do canuto — diz qual skill ou fluxo encaixa na sua situação.
type: global-skill
version: 1.0.0
lastUpdated: 2026-08-03
invocacao: user
copyright: Rodrigo Canuto © 2026. Padrão de router adaptado de mattpocock/skills (MIT).
---

# /ask-canuto — Qual skill usar

Router sobre as skills do canuto. Descreva a situação; este arquivo diz por onde
entrar.

> **Por que isto existe.** O framework tem ~55 skills e a **Regra do 1%** ("se há
> 1% de chance de uma skill se aplicar, ela DEVE ser checada"). Isso é carga
> cognitiva empurrada para quem opera. Um router é a cura: uma coisa para lembrar
> em vez de cinquenta. Ver `skill-creator/GLOSSARY.md` → *Router Skill*.

---

## Comece pela pergunta que você está fazendo

| Se você está dizendo… | Entre por |
|---|---|
| "quero construir X, mas não sei direito o quê" | **`/office-hours`** → `/grilling` |
| "tenho um plano, quero estressar ele" | **`/grilling`** (+ `/domain-modeling`) |
| "planejei, quero segunda opinião antes de codar" | **`/co-plan`** ou `/co-validate` |
| "a gente chama a mesma coisa de três nomes" | **`/domain-modeling`** |
| "essa decisão vale registrar?" | **`/domain-modeling`** (filtro de 3 condições) |
| "vamos implementar isso" | **`/tdd`** (via Coder) |
| "esse código tá difícil de testar / de navegar" | **`/codebase-design`** |
| "esse módulo tem 14 métodos, tá certo?" | **`/codebase-design`** (teste da deleção) |
| "tá quebrado e eu não sei por quê" | **`/investigate`** (Lei de Ferro: sem raiz, sem fix) |
| "quero revisar o que mudou" | **`/review`** (roteia por perfil do diff) |
| "pesquisa isso pra mim" | **`/research`** (tem Fase 0 de inteligência de comunidade) |
| "a UI tá feia / genérica / quebrando" | **`/critique`**, `/polish`, `/bolder`, `/audit` |
| "o framework tá estranho" | **`/canuto-project-doctor`** |
| "o que rolou semana passada?" | **`/retro`** |
| "acabamos de subir, e a doc?" | **`/document-release`** |
| "quero uma skill nova" ou "temos skills demais" | **`/skill-creator`** |

---

## Os fluxos completos

### Fluxo de feature (o caminho padrão)

```
/office-hours          ← só se a ideia ainda é vaga
      ↓
/grilling + /domain-modeling     ← OBRIGATÓRIO antes de fechar plano
      ↓
Architect (usa /codebase-design para nomear modules e seams)
      ↓
/co-validate           ← automático para M/L
      ↓
Coder + /tdd           ← seams pré-acordados, fatias verticais
      ↓
/review                ← eixos Standards e Spec
```

### Fluxo de bug

```
/investigate           ← read-only, raiz confirmada por mutação/contra-teste/bisect
      ↓
Coder + /tdd           ← teste de regressão que morde a linha provada
      ↓
/review
```

### Fluxo de saúde do próprio framework

```
/canuto-project-doctor  → /health-check → /skill-creator (modo poda)
/vault-maintenance      → /vault-sync
/retro                  → instincts
```

---

## As skills que o agente alcança sozinho

Estas são **model-invoked**: você não precisa lembrar delas, o agente puxa quando
a situação encaixa. Estão aqui só para você saber que existem.

`grilling` · `domain-modeling` · `codebase-design` · `tdd` · `co-review` ·
`research` · `verification-gates` · `skill-check-protocol` · `continuous-learning` ·
`security-practices` · `context-maintenance` · `canuto-ptbr-editor` ·
`canuto-orchestrate`

Se uma delas **não** disparou quando deveria, isso é bug de `description` — leve
para `/skill-creator`, não repita o pedido com outras palavras.

---

## Manutenção

Este router **mente** assim que fica desatualizado. Toda vez que uma skill
user-invoked for adicionada, renomeada, removida, ou mudar de lugar no fluxo,
re-leia este arquivo e atualize. É passo obrigatório do `/skill-creator`
(Passo 8, item 3).
