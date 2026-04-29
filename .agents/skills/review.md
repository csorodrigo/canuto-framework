---
skill: review
trigger: "/review [--auto|--small|--large|--ui|--security|--refactor], or any direct ask to review the current diff"
persona: maestro
version: 1.0.0
lastUpdated: 2026-04-18
shortDescription: >
  Manual entry-point for the diff-router (lazy-opus-review's Gemini layer).
  /review with no flag = auto-detect from diff. With flag = force the path.
  Counterpart for cases where you want explicit control instead of waiting
  for Maestro to auto-route.
usedBy: [maestro]
evals:
  - prompt: "/review"
    should_trigger: true
  - prompt: "/review --security"
    should_trigger: true
  - prompt: "review this diff with gemini"
    should_trigger: true
  - prompt: "review this PR for security"
    should_trigger: true
  - prompt: "implement the auth module"
    should_trigger: false
---

## Purpose

`lazy-opus-review.md` já tem um diff-router automático que escolhe Codex / Gemini /
triple baseado em perfil de diff. Este skill é o **entry point manual** para
disparar o mesmo router quando você quer controle explícito (ex: já sabe que é
security, não quer esperar o auto-detect).

**Distinção:**
- `lazy-opus-review` = hook automático sobre output do Codex (você não chama)
- `/review` = comando manual para reviewar diff arbitrário (working tree, branch, PR)

---

## When to Use

**Triggers:**
- `/review` ou `/review --<flag>`
- "review este diff", "review this PR", "preciso de code review do que mudei"
- Antes de `/commit` ou `/ship` em mudança não-trivial
- Após Codex implementar M/L task e você quer review extra além do automático

**Not for:**
- Plan review (use `/co-plan` ou `/co-plan --triple`)
- Skill / docs review (overhead desnecessário)
- Output do Codex ainda fresco — `lazy-opus-review` já fez isso. Use `/review` se quer **outra rodada** com path diferente.

---

## Flags / variants

| Flag | Quando usar | Reviewer primary | Secundário |
|---|---|---|---|
| `--auto` (default) | Não sei o perfil — deixa router decidir | calculado por heurística | calculado |
| `--small` | < 100 linhas, 1-3 arquivos | Codex reviewer | — |
| `--large` | > 500 linhas, multi-módulo | **Gemini 3.1-pro** (long-context) | Codex (bugs exec) |
| `--ui` | Frontend / componentes visuais (precisa screenshot antes/depois) | **Gemini multimodal** | Opus (taste) |
| `--refactor` | Rename / extração / movimentação cross-file | **Gemini** (vê call sites) | — |
| `--security` | auth / crypto / payment / RLS / permissions | **Triple obrigatório** (Codex + Gemini + Opus) | — |
| `--config` | infra / CI / .env / dockerfile | Codex reviewer | Opus (blast radius) |

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
```
codex exec --profile reviewer({
  prompt: "Review este diff. Foco em bugs, edge cases, contratos.\n\n--- DIFF ---\n<git diff inline>\n--- END ---"
})
```

### Path: Gemini long-context (large / refactor)
```
mcp__gemini__ask-gemini({
  prompt: "@./ Review este diff: cross-module impacts, contratos quebrados, migration safety, backwards compat.\n\n--- DIFF ---\n<git diff>\n--- END ---",
  model: "gemini-3.1-pro-preview"
})
```

### Path: Gemini multimodal (ui)
```
# Pré-requisito: você tira screenshots antes/depois e copia pra .context/
mcp__gemini__ask-gemini({
  prompt: "@.context/before.png @.context/after.png Compare visual: hierarquia, alinhamento, espaçamento, regressões.\n\n--- DIFF ---\n<git diff>\n--- END ---",
  model: "gemini-3.1-pro-preview"
})
# Pós-call: rm .context/before.png .context/after.png
```

### Path: Triple (security)
Reusa o fluxo do `/co-plan --triple` aplicado a diff em vez de plan:
- Stream A: Opus self-review do diff
- Stream B: `codex exec --profile reviewer` (engineering adversarial)
- Stream C: `mcp__gemini__ask-gemini({ prompt: "@./ ... + diff inline", model: "gemini-3.1-pro-preview" })`

Convergência: 3/3 → mandatory fix; 2/3 → medium; 1/3 → evaluate.

---

## Examples

### ✅ Good — auto-detect

```
Usuário: /review

Maestro:
1. git diff --shortstat → 47 linhas, 2 arquivos
2. Heurística: small
3. Dispara codex exec --profile reviewer
4. Output: "[Review] Small diff via Codex. Verdict: 1 minor issue (line 23, var name)."
```

### ✅ Good — flag explícita

```
Usuário: /review --security

Maestro:
1. git diff (mudou middleware/auth.ts)
2. Triple obrigatório (Opus + Codex + Gemini)
3. Output: "[Review] Triple security. 3/3 flagged: token expiry usa < em vez de <=. Mandatory fix."
```

### ✅ Good — UI com screenshots

```
Usuário: /review --ui

Maestro: "Preciso dos screenshots antes/depois em .context/. Você tem?"
Usuário: "tirei agora, .context/before.png e .context/after.png"
Maestro: chama Gemini multimodal + Opus pra taste, deleta arquivos depois.
```

### ❌ Bad — usar `/review` em output do Codex que acabou de chegar

```
Codex retornou implementação com CONFIDENCE: 9.
Usuário: /review

Maestro: "[Review] lazy-opus-review já aceitou (confidence 9). /review aqui é redundante.
         Use /review --large só se quiser segunda opinião com Gemini long-context."
```

### ❌ Bad — `/review --ui` sem screenshots

```
Usuário: /review --ui

Maestro: NÃO chamar Gemini multimodal sem imagens — gera output hipotético.
         Resposta correta: "Sem screenshots. Tire e coloca em .context/ antes."
```

---

## Integration

- **lazy-opus-review.md** — fonte da lógica de roteamento. `/review` é o entry-point manual da mesma matriz.
- **co-plan/SKILL.md** (`global-skills/`) — o triple usado em `--security` reusa o fluxo `/co-plan --triple`.
- **gemini-routing.md** — gotchas obrigatórias antes de chamar Gemini (sandbox, multimodal cleanup, modelos banidos).
- **cost-routing.md** — matriz que mostra quando review cai pra Gemini vs Codex vs Opus.
- **codex-test-fix.md** — quando review detecta bug, encadear com fix loop.
- **ask-gemini.md** — wrapper irmão para chamadas Gemini ad-hoc fora do contexto de review.
- **health.md** — checa se Codex/Gemini MCPs estão acessíveis antes de invocar.
