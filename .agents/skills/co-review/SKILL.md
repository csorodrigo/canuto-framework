---
name: co-review
description: Coordinate independent Claude and Codex planning or review passes, then compare results without anchoring bias.
skill: co-review
trigger: "/co-brainstorm, /co-plan, /co-validate, or automatic for M/L plan review and pre-commit"
persona: maestro
version: 2.1.0
lastUpdated: 2026-08-03
invocacao: model
shortDescription: >
  Bias-free parallel collaboration with Codex via MCP. Three modes: brainstorm (ideation),
  plan (parallel planning), validate (staff-engineer review). Eliminates anchoring bias by
  completing your own work before seeing Codex's output. Reviews run on two blind axes —
  Standards (does it follow the repo?) and Spec (is it what was asked?).
usedBy: [maestro, architect]
evals:
  - prompt: "let's brainstorm approaches for the auth system with codex"
    should_trigger: true
  - prompt: "get a second opinion on this plan"
    should_trigger: true
  - prompt: "co-validate the architect's plan before we start coding"
    should_trigger: true
  - prompt: "run the tests"
    should_trigger: false
  - prompt: "review the code changes"
    should_trigger: false
  - prompt: "ask codex to write the implementation"
    should_trigger: false
---

## When to Use

**Explicit triggers:**
- `/co-brainstorm <topic>` — divergent ideation with independent perspectives
- `/co-plan <task>` — parallel planning, compare approaches after both complete
- `/co-validate <plan-file>` — staff-engineer review of a finalized plan

**Automatic trigger:**
- For **M/L tasks**, Maestro explicitly runs `/co-validate` after the plan is ready
- `plan-review.sh` is retired; do not depend on `ExitPlanMode` hooks for this flow

**Not for:**
- XS/S tasks (overhead not justified)
- When `codex` CLI is not in PATH (degrade gracefully, continue without)
- Implementation tasks (Codex reviews plans, doesn't code)

**Runtime flag:** `CO_REVIEW=false` disables automatic trigger for M/L tasks.

## Prerequisites (v2.0, 2026-04-29)

Codex CLI must be installed and authenticated:

```bash
# Recommended: let install.sh handle setup
bash install.sh --doctor
```

Verify: `codex --version` returns OK; `~/.codex/config.toml` has 5 profiles.

### Profile-to-Mode Mapping

| Mode | Profile | Model | Invocation |
|------|---------|-------|------------|
| co-brainstorm | coder | gpt-5.5 (high) | parallel `codex exec --profile coder` × N |
| co-plan | reviewer | gpt-5.5 (high) | `codex exec --profile reviewer` |
| co-validate | reviewer | gpt-5.5 (high) | `codex exec --profile reviewer` |
| escalation (long-context, deeper reasoning) | architect | gpt-5.5 (xhigh) | `codex exec --profile architect` |

### Backend Preference (fallback chain)

```
1. codex exec --profile <reviewer|coder|architect> (CLI, default for all modes)
2. CCB `ask codex` (only with active Codex CCB session, visible panes, anchoring risk) — FALLBACK
3. Claude-only review — LAST RESORT
```

### Alternative: CCB Backend

If `codex` CLI is unavailable but CCB plugin is installed, co-review falls back
to CCB's `ask` CLI:

```bash
ask codex "<co-review prompt>"
pend <task-id>  # retrieve when ready
```

**Important**:
- CCB fallback only works when a Codex CCB session is already active for this workspace.
- CCB panes are visible — risk of anchoring bias. Do not look at the Codex pane until your own review is complete.

> Historical note (2026-04-29): previously this skill required `codex-coder`
> and `codex-reviewer` MCP servers. Those wrappers were retired; CLI direct
> invocation has 10-35% lower token overhead. Outputs flow through
> `--output-last-message <file>` to keep stdout clean.

---

## Core Principle: Independence First, Comparison Second

**Complete your own work BEFORE seeing Codex's output.** This eliminates anchoring bias.

```
T0:   Launch both in parallel (Codex in background, Claude works independently)
T1-N: Parallel independent work (no cross-contamination)
TN+1: Both complete → retrieve Codex's output
TN+2: Compare perspectives, synthesize best of both
```

### Blind Reviewer (muro mecânico — ADR-0006)

Para a segunda opinião **estruturalmente** isolada, use o subagent
`blind-reviewer` (`.claude/agents/blind-reviewer.md`) em vez de instrução de
"context isolation" no prompt:

- Tools restritos a `Read, Grep, Glob` — sem Bash, sem Write, sem MCP, sem
  Web: cegueira de conversa e impossibilidade de efeito colateral são do
  harness, não cortesia do modelo.
- Entregue no prompt SÓ o artefato (plano/diff + paths citados). O output
  volta como strikes + veredito APPROVE/REQUEST CHANGES; strikes gate.
- Complementar (não substituto) do Reviewer normal: o cego não executa
  testes — verificação de execução continua com `verification-gates`.

#### Rodadas: quando a revisão para

"Strikes gate" sem teto vira laço. Num consumidor do framework (papiro), um PR passou
por 47 rodadas de revisão cega, com seis revisores por rodada a partir da 37ª, e a
própria sessão teve de inventar na 40ª um critério de parada. Em outro PR, o merge
aconteceu antes de a revisão terminar. As regras abaixo valem para revisão cega,
adversarial e co-review de um PR ou de um plano (Mode 3). O Mode 4 (pre-commit) fica de
fora: o hook `codex-pretool-guard.sh` tem política própria, que degrada para advisory no
3º HOLD seguido, e não guarda delta nem estado por achado.

1. **No máximo 3 rodadas por contagem.** Mudança é o PR, inclusive o diff da branch
   revisado antes de o PR existir, ou o plano no Mode 3; as rodadas do plano não contam para
   o PR que vem depois. Uma mudança começa com uma contagem, e só o usuário abre outra
   (regra 5). A contagem soma todos os pushes, e fechar e reabrir a mesma mudança continua a
   contagem. Depois que a revisão fechou, qualquer push reabre a revisão, exceto rebase ou
   merge da base sem conflito. Antes do push que reabre, tire a marcação de pronto. Quem
   decide se a revisão reaberta cabe na contagem atual ou numa nova é o usuário. Se a
   contagem atual já fez 3 rodadas, cabe nela só como aceite de risco registrado (regra 5);
   para revisar o push, é contagem nova.
2. **Quem orquestra numera os achados bloqueantes** (A1, A2…), sem nunca reaproveitar um
   número; o revisor não numera, e ressalva não ganha número. A partir da 2ª rodada, e já na
   1ª rodada de uma contagem nova, o revisor recebe o delta desde a rodada anterior **e o
   texto completo** de cada achado aberto. Na contagem nova, os abertos passam com o mesmo
   número; ao dividir, cada um vai para a peça que leva o código dele. Para cada um ele devolve `FECHADO` (com a evidência no delta, ou com o motivo de o
   cenário não se sustentar) ou `ABERTO` (com a linha onde o problema continua, que pode estar
   fora do delta). Quem decide se é o mesmo achado é o revisor, não o produtor.
   - No Mode 3, nas mesmas rodadas, acrescente ao prompt do Codex o bloco "Achados
     abertos" com o texto de cada um e peça `FECHADO`/`ABERTO` por achado antes do veredito.
   - Se o revisor da rodada não está disponível (fallback Claude-only em "Graceful
     Degradation"), a rodada inteira, abertos e novos, vai para um `blind-reviewer`, nunca
     para o agente principal.
3. **Bloqueia o que o revisor classifica como STRIKE**, desde que traga cenário concreto de
   falha (arquivo:linha e o que quebra, inclusive teste ausente para caminho crítico).
   RESSALVA nunca bloqueia, mesmo com cenário. No Mode 3, o prompt do Codex pede essa
   classificação (`references/modes.md`); achado do Codex sem rótulo que traga o ponto do
   plano ou arquivo:linha e o que quebra conta como STRIKE. Quem orquestra não reclassifica:
   quem julga se o cenário se sustenta é o revisor da rodada seguinte, não o produtor.
4. **O ciclo para** depois da 3ª rodada concluída, ou antes, quando um achado bloqueante
   aberto numa rodada continua `ABERTO` na rodada seguinte da mesma contagem.
5. **Ciclo parado com achado bloqueante aberto não segue para merge.** A sessão para e
   pergunta ao usuário: aceitar o risco (registrando quem aceitou), replanejar ou dividir.
   Não há 4ª rodada na mesma contagem, e o achado não vira "não verificado". Replanejar ou
   dividir abre contagem nova por decisão do usuário, registrada. Sem achado bloqueante
   aberto, a revisão fecha.
6. **Marcação de pronto para merge só depois que a revisão fecha**, e ela sai antes de um
   push que reabra a revisão (regra 1).

O "final say" do agente principal (Staff Engineer Framing) vale para sugestões. Um achado
bloqueante só sai como `FECHADO` pelo revisor ou por decisão do usuário (regra 5).

---

## Three Modes (Summary)

For detailed prompts, output formats, and examples, read `references/modes.md`.

### Mode 1: /co-brainstorm
1. `(parallel codex exec --profile coder)` → 3 Codex agents brainstorm independently (gpt-5.5 (high))
2. Main agent brainstorms independently (3-5 approaches)
3. After all complete → collect Codex ideas
4. Compare: convergent ideas (high confidence), unique ideas from each, recommend best

### Mode 2: /co-plan
1. `codex exec --profile reviewer` → Codex reviewer creates an implementation plan independently
2. Architect creates its own plan (standard flow)
3. After both complete → compare Claude's plan with the one-shot reviewer response
4. Compare: shared steps (validated), unique steps (gaps?), different approaches (trade-offs)

### Mode 3: /co-validate (auto for M/L)
1. Read the plan file
2. `codex exec --profile reviewer` → Codex reviewer reviews as staff engineer
3. Main agent conducts independent review
4. After both complete → compare the independent review with the one-shot reviewer response
5. Compare: convergent issues (fix these), unique issues from each (evaluate)
6. Present verdict: `✓ LGTM` or `⚠️ Concerns (N issues)`

---

## Os dois eixos da revisão (Standards e Spec)

Toda revisão de plano (Mode 3) e de diff (Mode 4) corre em **dois eixos
independentes**. Rodá-los juntos deixa um contaminar o outro: um reviewer que
acabou de aprovar a qualidade do código tende a assumir que ele faz a coisa
certa.

| Eixo | A pergunta | Fonte de verdade |
|---|---|---|
| **Standards** | Isto segue o padrão deste repo? Tem code smell? | `.context.md`, `stack.md`, `security-practices`, `codebase-design`, ADRs |
| **Spec** | Isto é **o que foi pedido**? | a mensagem original do usuário, o plano aprovado, a issue/PRD de origem |

**Regras:**

- Os dois eixos rodam **em paralelo e cegos um ao outro** — mesma mecânica de
  independência da §"Independence First". Na prática: o reviewer Codex leva um
  eixo, o agente principal leva o outro, e a comparação vem depois.
- O eixo **Spec** precisa da fonte original **verbatim**. Resumo do plano não
  serve — é justamente a paráfrase que esconde o desvio.
- **Se não existe fonte de spec, diga isso** em vez de inventar uma. "Eixo Spec:
  não avaliado — nenhum plano aprovado ou issue de origem foi fornecido" é um
  resultado válido; um Spec fabricado a partir do próprio diff sempre aprova.
- Um achado do eixo Spec **nunca** é estilo. "Faltou tratar o caso X que o plano
  pedia" é Spec; "esse nome podia ser melhor" é Standards.

**Formato do veredito:**

```
[Co-Review — 2 eixos]
  Standards: ✓ LGTM  |  ⚠️ N issues
  Spec:      ✓ fiel   |  ⚠️ N desvios  |  ⊘ não avaliado (sem fonte)
  Convergentes (alta confiança): ...
  Exclusivas Codex / exclusivas Claude: ...
```

> **Por que isto foi adicionado.** O `co-review` já era cego entre *modelos* — o
> que faltava era o eixo que pergunta se o resultado é o que o usuário pediu.
> Desalinhamento é o modo de falha nº 1 em desenvolvimento assistido por agente,
> e nenhuma quantidade de revisão de qualidade o pega.

---

## Staff Engineer Framing

- **Never assume Codex's suggestions are correct** — validate each one yourself.
- **You are the lead engineer** with final say on all decisions.
- **Treat Codex's output as a junior developer's review** — useful but not authoritative.
- **Override with justification** — if you disagree, explain why. Isso não fecha achado bloqueante de rodada: veja "Rodadas: quando a revisão para".

---

## Graceful Degradation

If `codex` CLI is missing or fails:
- Log: `[Co-Review] codex CLI failed (<reason>). Checking fallbacks...`
- Try CCB `ask codex` only when a Codex session is active for this workspace.
  - Log: `[Co-Review] Using CCB ask codex as fallback. Avoid looking at Codex pane until your review is complete.`
- If CCB also unavailable: fall back to Claude-only review.
  - Log: `[Co-Review] No external reviewer available. Continuing with single-perspective review.`
- Do NOT block the flow.

---

## Compatibility

`_archive/plan-second-opinion.md` remains the legacy planning reference (arquivado 2026-06-11). The hook `plan-review.sh` was retired on 2026-06-11; Maestro triggers this skill explicitly for M/L plan review.

## Mode 4: Auto-Review on Commit (Pre-Commit Gate)

**Trigger**: Automatic when committing changes from M/L tasks with Codex involvement.
**Runtime**: Implemented by `.agents/hooks/codex-pretool-guard.sh`.

### Flow
1. Before commit, collect `git diff --staged`
2. If diff touches security-sensitive files → also trigger `/security-gate`
3. Send to `codex exec --profile reviewer` (reviewer profile):

```
codex exec --color never --profile reviewer \
  -s read-only --skip-git-repo-check \
  -o .agents/tmp/codex/co-review-validate.md \
  "$(cat <<'PROMPT'
[PRE-COMMIT REVIEW]
Review this staged diff before commit. Focus on:
- Bugs, logic errors, edge cases
- Security issues (injection, auth bypass)
- Performance regressions
- Convention violations

--- CHANGES START ---
{staged_diff}
--- CHANGES END ---

Verdict: COMMIT (clean) | HOLD (issues found). If HOLD, list issues with file:line.
PROMPT
)"
```

4. **COMMIT** verdict → proceed with commit
5. **HOLD** verdict → present issues, fix before committing

### When NOT to auto-review
- XS/S tasks (overhead not justified)
- Documentation-only changes
- `CO_REVIEW=false` env var set

---

## Diff-Aware Context Compression

Before sending any diff to the reviewer, compress context to reduce tokens and cost:

### Compression Rules
1. **Keep**: changed lines + 20 lines of surrounding context
2. **Keep**: type definitions and interfaces referenced by changed code
3. **Keep**: function signatures of called functions
4. **Drop**: unchanged files entirely
5. **Drop**: import statements (unless imports changed)
6. **Drop**: comments in unchanged code

### Format
```
## File: src/auth/middleware.ts (lines 45-85 of 200)
[20 lines before change]
+ added line
- removed line
  context line
[20 lines after change]

## Referenced Types
interface User { id: string; role: Role; }
type Role = 'admin' | 'user' | 'guest';
```

### Implementation

Before calling the reviewer path, Maestro MUST compress the diff:

```bash
# Implemented helper:
bash .agents/tools/codex-diff-context.sh --staged

# Or against a branch diff:
bash .agents/tools/codex-diff-context.sh --base main
```

If the compressed diff exceeds 5000 lines, split into per-file reviews.

### Why
- reviewer-grade models charge per token — less context = cheaper reviews
- Focused context = more relevant review comments
- 20 lines is enough for a reviewer to understand the change

---

## Session Continuity

`codex exec --profile reviewer` is one-shot per invocation. For multi-turn,
re-invoke with extended context inline.

Persist instead:
- the generated markdown review via `--output-last-message <path>` in `.agents/tmp/codex/`
- the JSONL audit trail in `codex-review-events.jsonl`
- any higher-level handoff metadata you want in the vault

---

## Anti-Patterns — DO NOT

- DO NOT read Codex's output before completing your own work — defeats bias prevention.
- DO NOT skip the comparison step — the value is in the delta.
- DO NOT treat Codex's output as authoritative — you are the lead.
- DO NOT run co-review on XS/S tasks — overhead not justified.
- DO NOT block the workflow if Codex is unavailable — degrade gracefully.
- DO NOT send full files to reviewer — use diff compression to reduce tokens.
- DO NOT claim the reviewer profile ran unless the reviewer path actually used it.
