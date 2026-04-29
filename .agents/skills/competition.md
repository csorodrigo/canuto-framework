---
skill: competition
trigger: /compete, or when facing architectural decisions with 2+ viable approaches
persona: maestro
version: 1.0.1
lastUpdated: 2026-03-30
maturity: experimental
shortDescription: >
  Dual implementation mode — Claude and Codex implement the same feature independently,
  then compare: performance, readability, LOC, correctness. Pick the best. Eliminates
  single-perspective bias on architectural decisions.
usedBy: [maestro, architect]
evals:
  - prompt: "implement this two ways and compare"
    should_trigger: true
  - prompt: "compete: Claude vs Codex on the auth module"
    should_trigger: true
  - prompt: "just implement it"
    should_trigger: false
---

## When to Use

**Experimental mode:** opt-in only. Do not treat this as part of the default Canuto coding path.

- Architectural decision with **2+ viable approaches** and no clear winner
- High-stakes code where the **best approach matters** (performance, maintainability)
- Learning: want to see how two AI models approach the same problem differently

**Not for:**
- Clear-cut implementations (one obvious approach)
- XS/S tasks (overhead far exceeds benefit)
- Time-sensitive tasks (competition takes 2x time)

**Cost warning:** This runs two full implementations. Use sparingly.

---

## Procedure

### 1. Define the Challenge

```markdown
## Competition Brief
- **Task**: {feature description}
- **Files**: {target files/modules}
- **Constraints**: {shared constraints both must follow}
- **Evaluation criteria**: performance | readability | LOC | test coverage | maintainability
```

### 2. Run in Parallel

**Codex implementation** (via MCP):
```
codex exec --profile coder({
  prompt: `
Implement the following feature. This is a competition — give your BEST implementation.

## Task
{feature_description}

## Constraints
{shared_constraints}

## Output
Write all files. Aim for: clean code, good naming, minimal complexity, correct behavior.
`
})
```

**Claude implementation** (in worktree or stash):
- Use Agent tool with `isolation: "worktree"` so implementations don't conflict
- Or: Claude implements in `.competition/claude/` temp directory

### 3. Collect Results

After both complete:
1. **Codex's changes**: read from main working tree (`git diff`)
2. **Claude's changes**: read from worktree or temp dir

### 4. Compare

Run comparison on both implementations:

| Dimension | Codex | Claude | Winner |
|-----------|-------|--------|--------|
| **Correctness** | passes tests? | passes tests? | — |
| **LOC** | line count | line count | fewer = better |
| **Readability** | subjective 1-10 | subjective 1-10 | — |
| **Performance** | O(?) complexity | O(?) complexity | — |
| **Maintainability** | coupling, abstractions | coupling, abstractions | — |
| **Test coverage** | % covered | % covered | — |

### 5. Deep Review (optional)

Send BOTH implementations to the reviewer path for an independent comparison:

```
codex exec --profile reviewer({
  prompt: `
[COMPETITION REVIEW]
Two implementations of the same feature. Compare objectively.

--- IMPLEMENTATION A (Codex) ---
{codex_diff}
--- END A ---

--- IMPLEMENTATION B (Claude) ---
{claude_diff}
--- END B ---

Score each on: correctness, readability, performance, maintainability (1-10).
Declare a winner with justification.
`
})
```

### 6. Present to User

```markdown
## Competition Results: {feature_name}

### Codex Implementation
- LOC: 45
- Approach: {summary}
- Strengths: {list}
- Weaknesses: {list}

### Claude Implementation
- LOC: 52
- Approach: {summary}
- Strengths: {list}
- Weaknesses: {list}

### Verdict
**Winner: {Codex/Claude}** — {justification}

### Recommendation
{which to use, or hybrid taking best of both}
```

### 7. Apply Winner

- Apply the winning implementation to the working tree
- Discard the losing implementation
- If hybrid: merge best parts from both

---

## Hybrid Mode

Sometimes the best result is a **hybrid** — taking the architecture from one and the details from another:

1. Identify strongest aspects of each
2. Use winner's architecture as base
3. Cherry-pick specific patterns from loser
4. Run tests to verify the hybrid works

---

## Graceful Degradation

- MCP unavailable → run both implementations sequentially in Claude (different approaches, not different models)
- Worktree unavailable → use temp directories
- Only one implementation succeeds → use that one, note the failure

---

## Anti-Patterns

- DO NOT use for trivial tasks — massive waste of resources
- DO NOT bias the comparison — present facts, let user decide
- DO NOT always pick Claude or always pick Codex — judge each case
- DO NOT skip the test step — a beautiful implementation that doesn't work loses
