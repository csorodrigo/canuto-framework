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
- After Architect calls `ExitPlanMode` on **M/L tasks** (via the legacy-compatible `plan-review.sh` hook bridge)
- Maestro automatically runs `/co-validate` mode

**Not for:**
- XS/S tasks (overhead not justified)
- When Codex MCP is not configured (degrade gracefully, continue without)
- Implementation tasks (Codex reviews plans, doesn't code)

**Runtime flag:** `CO_REVIEW=false` disables automatic trigger for M/L tasks.

## Prerequisites

Two Codex MCP servers must be configured (global `settings.json`):

```bash
# Recommended: let install.sh configure these wrapper-backed MCPs
bash install.sh --repair
```

Verify: `claude mcp list` → both should show `✓ Connected`.

### MCP Tool Mapping

| Mode | MCP Server | Tool | Model |
|------|-----------|------|-------|
| co-brainstorm | codex-coder | `spawn_agents_parallel` | gpt-5.4 (high) |
| co-plan | codex-reviewer | `spawn_agent` | `reviewer` profile (`gpt-5.4`, reasoning: high) |
| co-validate | codex-reviewer | `spawn_agent` | `reviewer` profile (`gpt-5.4`, reasoning: high) |

### Backend Preference (fallback chain)

```
1. codex-reviewer MCP (`spawn_agent`, one-shot) — REVIEWS / CO-PLAN / CO-VALIDATE
2. codex-coder MCP (gpt-5.4 (high), parallel) — CO-BRAINSTORM
3. CCB `ask codex` (only with active Codex session, visible panes, anchoring risk) — FALLBACK
4. Claude-only review — LAST RESORT
```

### Alternative: CCB Backend

If MCPs are unavailable, co-review falls back to CCB's `ask` CLI:

```bash
ask codex "<co-review prompt>"
pend <task-id>  # retrieve when ready
```

**Important**:
- CCB fallback only works when a Codex CCB session is already active for this workspace.
- CCB panes are visible — risk of anchoring bias. Do not look at the Codex pane until your own review is complete.

---

## Core Principle: Independence First, Comparison Second

**Complete your own work BEFORE seeing Codex's output.** This eliminates anchoring bias.

```
T0:   Launch both in parallel (Codex in background, Claude works independently)
T1-N: Parallel independent work (no cross-contamination)
TN+1: Both complete → retrieve Codex's output
TN+2: Compare perspectives, synthesize best of both
```

---

## Three Modes (Summary)

For detailed prompts, output formats, and examples, read `references/modes.md`.

### Mode 1: /co-brainstorm
1. `mcp__codex-coder__spawn_agents_parallel` → 3 Codex agents brainstorm independently (gpt-5.4 (high))
2. Main agent brainstorms independently (3-5 approaches)
3. After all complete → collect Codex ideas
4. Compare: convergent ideas (high confidence), unique ideas from each, recommend best

### Mode 2: /co-plan
1. `mcp__codex-reviewer__spawn_agent` → Codex reviewer creates an implementation plan independently
2. Architect creates its own plan (standard flow)
3. After both complete → compare Claude's plan with the one-shot reviewer response
4. Compare: shared steps (validated), unique steps (gaps?), different approaches (trade-offs)

### Mode 3: /co-validate (auto for M/L)
1. Read the plan file
2. `mcp__codex-reviewer__spawn_agent` → Codex reviewer reviews as staff engineer
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

If Codex MCP servers are not configured or fail:
- Log: `[Co-Review] codex-reviewer MCP not available. Checking fallbacks...`
- Try `codex exec --profile reviewer` as the first degraded reviewer path.
  - Log: `[Co-Review] Using codex exec --profile reviewer (degraded path).`
- If no reviewer path is available, try CCB only when a Codex session is active.
  - Log: `[Co-Review] Using CCB ask codex as fallback. Avoid looking at Codex pane until your review is complete.`
- If CCB also unavailable: fall back to Claude-only review.
  - Log: `[Co-Review] No external reviewer available. Continuing with single-perspective review.`
- Do NOT block the flow.

---

## Compatibility

`plan-second-opinion.md` remains the legacy planning reference. The hook `plan-review.sh` remains supported as the compatibility bridge that triggers this skill on `ExitPlanMode`.

## Mode 4: Auto-Review on Commit (Pre-Commit Gate)

**Trigger**: Automatic when committing changes from M/L tasks with Codex involvement.
**Runtime**: Implemented by `.agents/hooks/codex-pretool-guard.sh`.

### Flow
1. Before commit, collect `git diff --staged`
2. If diff touches security-sensitive files → also trigger `/security-gate`
3. Send to `mcp__codex-reviewer__spawn_agent` (reviewer profile):

```
mcp__codex-reviewer__spawn_agent({
  prompt: `
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
`
})
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

The current `codex-reviewer` MCP wrapper is one-shot. It does **not** return `threadId` and does not support `codex-reply`.

Persist instead:
- the generated markdown review in `.agents/tmp/codex/`
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
