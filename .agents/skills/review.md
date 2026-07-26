---
skill: review
trigger: "/review [--auto|--small|--large|--ui|--security|--refactor], or any direct ask to review the current diff"
persona: maestro
version: 2.0.0
lastUpdated: 2026-04-29
shortDescription: >
  Manual entry-point for the diff-router. /review with no flag = auto-detect
  from diff. With flag = force the path. Counterpart for cases where you want
  explicit control instead of waiting for Maestro to auto-route.
usedBy: [maestro]
evals:
  - prompt: "/review"
    should_trigger: true
  - prompt: "/review --security"
    should_trigger: true
  - prompt: "review this diff"
    should_trigger: true
  - prompt: "review this PR for security"
    should_trigger: true
  - prompt: "implement the auth module"
    should_trigger: false
---

## Purpose

Este skill é o **entry point manual e canônico** do diff-router: escolhe o
profile (coder/reviewer/architect) baseado no perfil do diff, conforme a
matriz de flags abaixo.

> Nota histórica: a lógica nasceu no hook `lazy-opus-review` (arquivado em
> 2026-06-11 — 0 firings em 200 sessões; ver
> `.agents/skills/_archive/lazy-opus-review.md`). Desde então **este arquivo é
> a fonte da matriz de roteamento** — não existe mais review automático sobre
> output do Codex; toda rodada de review é disparada manualmente por `/review`.

---

## When to Use

**Triggers:**
- `/review` ou `/review --<flag>`
- "review este diff", "review this PR", "preciso de code review do que mudei"
- Antes de `/commit` ou `/ship` em mudança não-trivial
- Após Codex implementar M/L task e você quer review extra além do automático

**Not for:**
- Plan review (use `/co-plan` ou `/co-plan --dual`)
- Skill / docs review (overhead desnecessário)
- Rodada redundante — se um `/review` já passou neste mesmo diff, só repita com profile diferente (ex: `--large` para architect xhigh) se quiser deeper reasoning.

---

## Flags / variants

| Flag | Quando usar | Reviewer primary | Secundário |
|---|---|---|---|
| `--auto` (default) | Não sei o perfil — deixa router decidir | calculado por heurística | calculado |
| `--small` | < 100 linhas, 1-3 arquivos | `codex exec --profile reviewer` | — |
| `--large` | > 500 linhas, multi-módulo | `codex exec --profile architect` (xhigh, deeper reasoning) | Claude Opus (taste) |
| `--ui` | Frontend / componentes visuais (precisa screenshot antes/depois) | Claude (multimodal native) | `codex exec --profile reviewer` (logic) |
| `--refactor` | Rename / extração / movimentação cross-file | `codex exec --profile architect` (xhigh, sees call sites with deeper reasoning) | — |
| `--security` | auth / crypto / payment / RLS / permissions | **Dual obrigatório**: Opus self-review + `codex exec --profile reviewer` | optional `codex exec --profile architect` (xhigh) for huge surface |
| `--config` | infra / CI / .env / dockerfile | `codex exec --profile reviewer` | Opus (blast radius) |

---

## Procedure

1. **Coletar o diff:**
   - Sem args extras: `git diff` (working tree não-staged) + `git diff --staged`
   - `--branch <name>`: `git diff main...<name>`
   - `--pr <num>`: `gh pr diff <num>`
   - `--file <path>`: `git diff -- <path>`
2. **Se `--auto` (ou sem flag), heurística para escolher path:**
   - Linhas mudadas via `git diff --shortstat`
   - Diretórios afetados (`auth/`, `payments/`, `crypto/` → security; `components/`, `pages/`, `*.tsx` → ui; etc)
   - Tipo de mudança (renames detectados via `git diff --find-renames` → refactor)
3. **Disparar reviewer(s)** conforme tabela acima.
4. **Consolidar output:** se houver primary + secundário, Opus apresenta os 2 outputs lado-a-lado e marca convergências/divergências.
5. **Salvar relatório** em `.agents/vault/audit/review-YYYY-MM-DD-HHMM.md` (formato livre: bullets de issues + verdict).

---

## Reviewer call patterns

### Path: Codex reviewer (small / config)
```bash
git diff > /tmp/canuto-review-diff.patch
codex exec --color never --profile reviewer -s read-only --skip-git-repo-check \
  -o /tmp/canuto-review-out.md \
  "Review the diff at /tmp/canuto-review-diff.patch. Focus: bugs, edge cases, contratos. Output: verdict + list of issues with file:line."
```

### Path: Codex architect (large / refactor)
```bash
git diff > /tmp/canuto-review-diff.patch
codex exec --color never --profile architect -s read-only --skip-git-repo-check \
  -o /tmp/canuto-review-out.md \
  "Review the diff at /tmp/canuto-review-diff.patch with deep reasoning. Focus: cross-module impacts, contracts broken, migration safety, backwards compat. Walk the repo to verify call sites if needed."
```

### Path: UI (multimodal via Claude)
```
# Pré-requisito: você tira screenshots antes/depois e copia pra .context/
# Then ask Claude to compare directly — Claude has native multimodal.
# Pair with a Codex --profile reviewer call for the underlying logic of the diff.
```

### Path: Dual (security)
Reusa o fluxo do `/co-plan --dual` aplicado a diff em vez de plan:
- Stream A: Opus self-review do diff (Claude direct, no spawn)
- Stream B: `codex exec --profile reviewer` (engineering adversarial)
- Optional Stream C: `codex exec --profile architect` (xhigh) for very large security surface

Convergência: 2/2 → mandatory fix; 1/2 → medium worth discussing.

---

## Examples

### ✅ Good — auto-detect

```
Usuário: /review

Maestro:
1. git diff --shortstat → 47 linhas, 2 arquivos
2. Heurística: small
3. Dispara codex exec --profile reviewer
4. Output: "[Review] Small diff via Codex reviewer. Verdict: 1 minor issue (line 23, var name)."
```

### ✅ Good — flag explícita

```
Usuário: /review --security

Maestro:
1. git diff (mudou middleware/auth.ts)
2. Dual obrigatório (Opus self-review + Codex reviewer)
3. Output: "[Review] Dual security. 2/2 flagged: token expiry usa < em vez de <=. Mandatory fix."
```

### ✅ Good — UI

```
Usuário: /review --ui

Maestro: "Preciso de screenshots antes/depois ou descrição do componente. Compartilha?"
Usuário: cola screenshots inline ou aponta path em .context/
Maestro: Claude analisa imagens diretamente; opcional spawn `codex exec --profile reviewer` pra logic do diff em paralelo.
```

### ❌ Bad — usar `/review` em output do Codex que acabou de chegar

```
Codex retornou implementação com CONFIDENCE: 9 e um /review já aprovou o diff.
Usuário: /review

Maestro: "[Review] Este diff já passou por review (confidence 9). /review aqui é redundante.
         Use /review --large com profile architect só se quiser deeper reasoning de uma segunda passada."
```

---

## Integration

- **co-plan/SKILL.md** (`global-skills/`) — o `--dual` usado em `--security` reusa o fluxo `/co-plan --dual`.
- **cost-routing.md** — matriz que mostra quando review cai para reviewer vs architect vs Opus direto.
- **/fix** (gstack) — quando review detecta bug, encadear com fix loop.
- **codex-health-check.sh** (`.agents/tools/`) — checa se Codex CLI está acessível antes de invocar.
