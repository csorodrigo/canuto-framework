---
skill: co-review
trigger: /co-brainstorm, /co-plan, /co-validate, or automatic for M/L plan review
persona: maestro
version: 1.0.0
lastUpdated: 2026-03-29
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
- After Architect calls `ExitPlanMode` on **M/L tasks** (replaces legacy `plan-second-opinion` hook)
- Maestro automatically runs `/co-validate` mode

**Not for:**
- XS/S tasks (overhead not justified)
- When Codex MCP is not configured (degrade gracefully, continue without)
- Implementation tasks (Codex reviews plans, doesn't code)

**Runtime flag:** `CO_REVIEW=false` disables automatic trigger for M/L tasks.

## Prerequisites

Codex MCP server must be configured:

```bash
claude mcp add codex-collab -- npx -y @openai/codex mcp-server
```

See `.agents/mcp/codex-collab.md` for full setup documentation.

### Alternative: CCB Backend

If the CCB plugin is installed and codex-collab MCP is not available, co-review can use CCB's `ask` CLI as a fallback:

```bash
ask codex "<co-review prompt>"
pend <task-id>  # retrieve when ready
```

This provides the same parallel review but with visible terminal panes. **Important**: because CCB panes are visible, there is a risk of anchoring bias (seeing Codex's output before completing your own work). When using CCB backend for co-review, **do not look at the Codex pane** until your own review is complete.

Backend preference: codex-collab MCP (background, no bias risk) > CCB `ask` (visible panes, anchoring risk).

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
1. Spawn background subagent → Codex brainstorms independently (told to say "ready" when done)
2. Main agent brainstorms independently (3-5 approaches)
3. After both complete → retrieve Codex's ideas
4. Compare: convergent ideas (high confidence), unique ideas from each, recommend best

### Mode 2: /co-plan
1. Spawn background subagent → Codex creates implementation plan independently
2. Architect creates its own plan (standard flow)
3. After both complete → retrieve Codex's plan
4. Compare: shared steps (validated), unique steps (gaps?), different approaches (trade-offs)

### Mode 3: /co-validate (auto for M/L)
1. Read the plan file
2. Spawn background subagent → Codex reviews as staff engineer (told to say "ready" when done)
3. Main agent conducts independent review
4. After both complete → retrieve Codex's review
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

If the Codex MCP is not configured or fails:
- Log: `[Co-Review] Codex MCP not available. Checking CCB fallback...`
- If CCB plugin installed and `ask` command available: use `ask codex` as fallback.
  - Log: `[Co-Review] Using CCB ask codex as fallback. Avoid looking at Codex pane until your review is complete.`
- If CCB also unavailable: fall back to Claude-only review.
  - Log: `[Co-Review] No external reviewer available. Continuing with single-perspective review.`
- Do NOT block the flow.

---

## Supersedes

This skill supersedes `plan-second-opinion.md` (legacy). The legacy hook `plan-review.sh` is deprecated.

## Anti-Patterns — DO NOT

- DO NOT read Codex's output before completing your own work — defeats bias prevention.
- DO NOT skip the comparison step — the value is in the delta.
- DO NOT treat Codex's output as authoritative — you are the lead.
- DO NOT run co-review on XS/S tasks — overhead not justified.
- DO NOT block the workflow if Codex is unavailable — degrade gracefully.
