# Co-Review: Detailed Mode Reference

Loaded on demand when a co-review mode activates. See `SKILL.md` for the summary.

The current `codex-reviewer` contract is one-shot via `mcp__codex-reviewer__spawn_agent`.
Do not assume reviewer-side `threadId` or `codex-reply`.

---

## Mode 1: /co-brainstorm

### Codex Prompt Template

```text
Brainstorm approaches for: {topic}
Context: {relevant project files and constraints}

Generate 3-5 distinct approaches with pros/cons for each.
Return the ideas directly in this response.
```

### Output Format

```markdown
## Co-Brainstorm: {topic}

### Claude's Approaches
1. {approach} — {pros/cons}

### Codex's Approaches
1. {approach} — {pros/cons}

### Synthesis
- Convergent: {list}
- Codex-unique: {list}
- Claude-unique: {list}
- Recommended: {which approach and why}
```

---

## Mode 2: /co-plan

### Codex Prompt Template

```text
Create an implementation plan for: {task description}
Project context: {stack, constraints, relevant files}

Include:
- steps
- files to modify
- risks
- test strategy

Return the plan directly in this response.
```

### Output Format

```markdown
## Co-Plan: {task}

### Architect's Plan
{standard Architect plan}

### Codex's Plan
{Codex's plan}

### Comparison
| Aspect | Architect | Codex | Verdict |
|--------|-----------|-------|---------|
| {aspect} | {approach} | {approach} | {which is better and why} |

### Recommendation
{synthesized plan incorporating best of both}
```

---

## Mode 3: /co-validate

### Codex Prompt Template

```text
You are a staff engineer reviewing this implementation plan.
Be critical and thorough. Look for:
1. What could make this plan fail?
2. Hidden dependencies or edge cases?
3. Simpler alternatives?
4. Unverified assumptions?
5. Missing error handling or rollback strategy?

Plan:
---
{plan content}
---

Return the review directly in this response.
```

### Output Format

```markdown
## Co-Validate: {plan name}

### Convergent Issues
- {issue}: {description}

### Codex-Only Issues
- {issue}: {description} — [Accept | Override: {reason}]

### Claude-Only Issues
- {issue}: {description} — [Accept | Override: {reason}]

### Verdict: ✓ LGTM | ⚠️ Concerns ({N} issues to address)
```

---

## MCP Tool Reference

| Tool | Purpose |
|------|---------|
| `mcp__codex-coder__spawn_agents_parallel` | Parallel brainstorm or implementation |
| `mcp__codex-reviewer__spawn_agent` | One-shot reviewer pass using the `reviewer` profile |

If reviewer MCP is unavailable, the explicit degraded path is:
`codex exec --profile reviewer` -> `/ask codex` only when a CCB Codex session is active -> Claude-only review.
