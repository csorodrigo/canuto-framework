---
name: co-review
description: Coordinate independent Claude and Codex planning or review passes, then compare results without anchoring bias.
skill: co-review
trigger: "/co-brainstorm, /co-plan, /co-validate, or automatic for M/L plan review and pre-commit"
persona: maestro
version: 2.0.0
lastUpdated: 2026-03-30
shortDescription: >
  Bias-free parallel collaboration with Codex via MCP. Three modes: brainstorm (ideation),
  plan (parallel planning), validate (staff-engineer review). Eliminates anchoring bias by
  completing your own work before seeing Codex's output.
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

## Staff Engineer Framing

- **Never assume Codex's suggestions are correct** — validate each one yourself.
- **You are the lead engineer** with final say on all decisions.
- **Treat Codex's output as a junior developer's review** — useful but not authoritative.
- **Override with justification** — if you disagree, explain why.

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
