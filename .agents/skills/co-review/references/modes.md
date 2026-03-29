# Co-Review: Detailed Mode Reference

Loaded on demand when a co-review mode activates. See `SKILL.md` for the summary.

---

## Mode 1: /co-brainstorm — Full Procedure

### Codex Prompt Template

```
Brainstorm approaches for: {topic}
Context: {relevant project files and constraints}

Generate 3-5 distinct approaches with pros/cons for each.
When done, reply ONLY with: "My brainstorming is complete and I'm ready to present"
Do NOT share your ideas yet — wait until explicitly asked.
```

- If Codex asks clarifying questions via `codex-reply`, the subagent answers using codebase context.
- Wait for the "ready to present" signal before retrieving.

### Retrieval Prompt

```
Please share your brainstorming results now.
```

### Output Format

```markdown
## Co-Brainstorm: {topic}

### Claude's Approaches
1. {approach} — {pros/cons}
...

### Codex's Approaches
1. {approach} — {pros/cons}
...

### Synthesis
- **Convergent** (both suggested): {list}
- **Codex-unique**: {list}
- **Claude-unique**: {list}
- **Recommended**: {which approach and why}
```

---

## Mode 2: /co-plan — Full Procedure

### Codex Prompt Template

```
Create an implementation plan for: {task description}
Project context: {stack, constraints, relevant files}

Include: steps, files to modify, risks, test strategy.
When done, reply ONLY with: "My plan is ready to present"
Do NOT share your plan yet — wait until explicitly asked.
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

## Mode 3: /co-validate — Full Procedure

### Codex Prompt Template

```
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

When done, reply ONLY with: "My review is complete and I'm ready to present"
Do NOT share your review yet.
```

### Output Format

```markdown
## Co-Validate: {plan name}

### Convergent Issues (both found — high confidence)
- {issue}: {description}

### Codex-Only Issues (evaluate)
- {issue}: {description} — [Accept | Override: {reason}]

### Claude-Only Issues (evaluate)
- {issue}: {description} — [Accept | Override: {reason}]

### Verdict: ✓ LGTM | ⚠️ Concerns ({N} issues to address)
```

---

## MCP Tool Reference (Quick)

| Tool | Purpose |
|------|---------|
| `mcp__codex-collab__codex` | Start new Codex session (returns `response` + `threadId`) |
| `mcp__codex-collab__codex-reply` | Continue session via `threadId` (clarifying questions, retrieval) |

Full MCP docs: `.agents/mcp/codex-collab.md`
