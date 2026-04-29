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
3. Try the official reviewer first:

```text
codex exec --profile reviewer(prompt="
You are reviewing an implementation plan before coding starts.
Review only the embedded plan below.
Find logical gaps, hidden dependencies, missing validation/test strategy,
rollback gaps, bad sequencing, and simpler alternatives.
Be direct. Be terse. No compliments.

THE PLAN:
<embedded plan>
")
```

4. Treat this path as:
   - `reviewer: codex-reviewer`
   - `profile: reviewer`
   - `model: reviewer-profile`
   - `fallbackOccurred: false`
5. If the MCP reviewer is unavailable, degrade explicitly in this order:
   - `codex exec --profile reviewer`
   - `/ask codex` only when an active CCB Codex session exists for this workspace
   - Claude-only review last
6. Never claim the reviewer profile ran unless the official reviewer MCP or `--profile reviewer`
   path actually ran.

## Required Output

Every `/co-plan` result must state:
- `reviewerPath`
- `model`
- `fallbackOccurred`
- `verdict`
- `issues` or `clean`

---

## `/co-plan --triple` (tri-plan variant, FASE 2a+)

Para planos estratégicos onde o custo de uma decisão errada > custo do triple review,
use a variante triple: Opus + Codex reviewer + Gemini 3.1-pro-preview em paralelo.

### Quando usar
- Planos que afetam arquitetura (novos módulos, microserviços, schema changes)
- Planos com dependências externas (APIs pagas, integrações críticas)
- Planos de segurança ou compliance
- Quando o usuário explicitamente pede `--triple` ou "tri-plan"

### Fluxo (3 streams paralelos)
```
Stream A — Opus (self-review):
  Claude consolida o plano próprio com análise de premissas.

Stream B — Codex reviewer (engineering adversarial):
  codex exec --profile reviewer({
    prompt: "Review this plan for engineering gaps, edge cases, test strategy,
             rollback paths. [PLAN INLINE]"
  })

Stream C — Gemini 3.1-pro-preview (cross-model + long-context premise check):
  mcp__gemini__ask-gemini({
    prompt: "@./ Review this plan against the actual repo. Que premissas desse
             plano o código existente contradiz? Que padrões já estabelecidos
             o plano viola silenciosamente? [PLAN INLINE]",
    model: "gemini-3.1-pro-preview"
  })
```

### Síntese
Claude consolida os 3 streams:
- **Convergência** (os 3 concordam) → high-confidence issue, fix mandatório
- **2/3 concordam** → medium, worth fixing
- **1/3 flagou algo único** → evaluate — pode ser insight genuíno ou ruído

### Output
Mesmo formato do `/co-plan` normal, mas com seção "## Triple review matrix"
mostrando quem levantou cada issue.

### Não usar `/co-plan --triple` se:
- XS/S task (triple overhead > benefit)
- Plan muda só 1 arquivo
- User está em modo de iteração rápida (trade-off de latência)
