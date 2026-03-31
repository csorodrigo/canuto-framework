---
name: co-plan
description: Official plan-review gate through the Codex reviewer path (reviewer profile; defaults to o1-pro when supported).
---

# Co-Plan

Use this when the user asks for the official plan gate. This is not generic Codex CLI
consultation. The preferred reviewer path is `mcp__codex-reviewer__spawn_agent`.

## Execution

1. Locate the active plan file in this order:
   - the current tool response's `plan_file_path`
   - `PLAN.md`, `plan.md`, or `PLAN.txt` in the repo
   - the latest matching file in `~/.claude/plans/`
2. Read the full plan content and embed it in the reviewer prompt.
3. Try the official reviewer first:

```text
mcp__codex-reviewer__spawn_agent(prompt="
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
6. Never claim `o1-pro` ran unless the official reviewer MCP or `--profile reviewer`
   path actually ran with that model.

## Required Output

Every `/co-plan` result must state:
- `reviewerPath`
- `model`
- `fallbackOccurred`
- `verdict`
- `issues` or `clean`
