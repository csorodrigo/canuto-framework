---
name: co-plan
description: Official plan-review gate through the Codex reviewer path (reviewer profile — `gpt-5.5` with reasoning: high).
---

# Co-Plan

Use this when the user asks for the official plan gate. This is not generic Codex CLI
consultation. The preferred reviewer path is `codex exec --profile reviewer`.

## Execution

1. Locate the active plan file in this order:
   - the current tool response's `plan_file_path`
   - `PLAN.md`, `plan.md`, or `PLAN.txt` in the repo
   - the latest matching file in `~/.claude/plans/`
2. Read the full plan content and embed it in the reviewer prompt.
3. Invoke the reviewer via CLI:

```bash
codex exec --color never --profile reviewer \
  -s read-only --skip-git-repo-check \
  -o /tmp/co-plan-review-$$.md \
  "$(cat <<'PROMPT'
You are reviewing an implementation plan before coding starts.
Review only the embedded plan below.
Find logical gaps, hidden dependencies, missing validation/test strategy,
rollback gaps, bad sequencing, and simpler alternatives.
Be direct. Be terse. No compliments.

THE PLAN:
<embedded plan>
PROMPT
)"
# Read result via: cat /tmp/co-plan-review-$$.md
```

4. Treat this path as:
   - `reviewer: codex --profile reviewer`
   - `profile: reviewer`
   - `model: gpt-5.5 (high)` (per `.agents/config/models.yaml`)
   - `fallbackOccurred: false`
5. If `codex` CLI is unavailable, degrade explicitly in this order:
   - `/ask codex` only when an active CCB Codex session exists for this workspace
   - Claude-only review last (mark `fallbackOccurred: true` and explain)
6. Never claim the reviewer profile ran unless `codex exec --profile reviewer` actually returned a result.

## Required Output

Every `/co-plan` result must state:
- `reviewerPath`
- `model`
- `fallbackOccurred`
- `verdict`
- `issues` or `clean`

---

## `/co-plan --dual` (dual review variant)

Para planos estratégicos onde o custo de uma decisão errada > custo do dual review,
use a variante dual: Opus self-review + Codex reviewer com escalação para architect (xhigh) em paralelo.

### Quando usar
- Planos que afetam arquitetura (novos módulos, microserviços, schema changes)
- Planos com dependências externas (APIs pagas, integrações críticas)
- Planos de segurança ou compliance
- Quando o usuário explicitamente pede `--dual` ou plan crítico

### Fluxo (2 streams paralelos)
```
Stream A — Opus (self-review):
  Claude consolida o plano próprio com análise de premissas.

Stream B — Codex reviewer (engineering adversarial, profile=reviewer):
  codex exec --color never -q --profile reviewer \
    --output-last-message /tmp/codex-review-$$.md \
    "Review this plan for engineering gaps, edge cases, test strategy,
     rollback paths. [PLAN INLINE]"

(opcional) Stream C — Codex architect (premise check com xhigh reasoning):
  codex exec --color never -q --profile architect \
    --output-last-message /tmp/codex-arch-$$.md \
    "Review this plan against the repo. Que premissas desse plano o código
     existente contradiz? [PLAN INLINE]"
  Use Stream C apenas se a complexidade justificar (>50 arquivos afetados,
  ou refactor cross-module).
```

### Síntese
Claude consolida os streams:
- **Convergência** (Opus + Codex concordam) → high-confidence issue, fix mandatório
- **Divergência** → evaluate — Claude apresenta os dois lados
- **Issue Codex-only** ou **Opus-only** → discuss before deciding

### Output
Mesmo formato do `/co-plan` normal, mas com seção "## Dual review matrix"
mostrando quem levantou cada issue.

### Não usar `/co-plan --dual` se:
- XS/S task (dual overhead > benefit)
- Plan muda só 1 arquivo
- User está em modo de iteração rápida (trade-off de latência)

> **Nota histórica (2026-04-29)**: anteriormente esta skill suportava `/co-plan --triple`
> com Gemini como Stream C. Gemini foi removido do framework; Stream C agora é
> opcional via Codex architect profile (xhigh reasoning) para casos genuinamente
> grandes. Detalhes em `docs/FEATURE-MAP.md`.
