---
skill: parallel-impl
trigger: /parallel-impl, or when Architect breaks a feature into 3+ independent subtasks
persona: maestro
version: 1.0.0
lastUpdated: 2026-03-30
shortDescription: >
  Break features into independent subtasks and implement them in parallel via
  spawn_agents_parallel. 3-5x speedup for large features with independent modules.
usedBy: [maestro, architect]
evals:
  - prompt: "implement these 4 components in parallel"
    should_trigger: true
  - prompt: "build the auth, dashboard, and settings pages concurrently"
    should_trigger: true
  - prompt: "fix this one typo"
    should_trigger: false
---

## When to Use

- Feature has **3+ independent subtasks** (different files/modules, no shared state)
- Task size is **M/L** (overhead justified)
- Each subtask can be described self-contained (no cross-dependencies)

**Not for:**
- Tasks with sequential dependencies (A must finish before B starts)
- XS/S tasks (just code them directly)
- Tasks touching the same files (merge conflicts)

---

## Procedure

### 1. Decompose

Architect breaks the feature into independent subtasks. Each subtask needs:
- **Goal**: one-sentence description
- **Files**: which files to create/modify
- **Constraints**: no new deps, test requirements, style rules
- **Context**: relevant types, interfaces, existing patterns

```markdown
## Subtasks

1. **Auth middleware** → src/middleware/auth.ts (new)
2. **User model** → src/models/user.ts (new)
3. **Auth routes** → src/routes/auth.ts (new)
4. **Auth tests** → tests/auth.test.ts (new)
```

### 2. Validate Independence

Before spawning, check:
- [ ] No two subtasks modify the same file
- [ ] No subtask depends on another's output
- [ ] Each subtask has all context it needs inline

If any check fails → sequential execution instead.

### 3. Spawn Parallel Agents

Run multiple `codex exec --profile coder` invocations in parallel via shell `&`
or via `xargs -P`. Each subtask gets its own output file.

```bash
# Pattern: spawn N parallel coder runs, capture each output, wait, then read all.
codex exec --color never --profile coder \
  -o /tmp/codex-sub1-$$.md \
  "Subtask 1: Create auth middleware at src/middleware/auth.ts. Requirements: ..." &
codex exec --color never --profile coder \
  -o /tmp/codex-sub2-$$.md \
  "Subtask 2: Create user model at src/models/user.ts. Requirements: ..." &
codex exec --color never --profile coder \
  -o /tmp/codex-sub3-$$.md \
  "Subtask 3: Create auth routes at src/routes/auth.ts. Requirements: ..." &
codex exec --color never --profile coder \
  -o /tmp/codex-sub4-$$.md \
  "Subtask 4: Create auth tests at tests/auth.test.ts. Requirements: ..." &
wait
# Read all outputs:
for f in /tmp/codex-sub*-$$.md; do echo "=== $f ==="; cat "$f"; done
```

Caveat: 4 concurrent Codex sessions write to filesystem simultaneously. Confirm
the safety check (no two subtasks edit the same file) is solid before parallel.

### 4. Consolidate

After all agents complete:
1. Read `git diff` — verify all changes look correct
2. Check for conflicts or inconsistencies between subtasks
3. Run tests if available
4. Fix any integration issues (type mismatches, import paths)

### 5. Review

Trigger code review via `codex exec --profile reviewer`:
```
[CODE REVIEW REQUEST]
--- CHANGES START ---
<full git diff>
--- CHANGES END ---

Review these parallel-implemented changes. Check for:
- Cross-module consistency (types, naming, imports)
- Missing integration points
- Each module follows project conventions
```

---

## Prompt Template for Each Agent

```
You are implementing ONE part of a larger feature. Other agents are working on other parts in parallel.

## Your Task
{subtask_description}

## Files to Create/Modify
{file_list}

## Constraints
- Do NOT modify files outside your scope: {file_list}
- Follow existing project patterns (check nearby files for style)
- Include proper imports and type definitions
- Add JSDoc/comments for public APIs only

## Context
{relevant_types_interfaces_patterns}

## Plan
{step_by_step_implementation}
```

---

## Limits

- **Max parallel agents**: 5 (diminishing returns beyond this)
- **Max files per agent**: 3 (too many = agent loses focus)
- **Timeout**: 120s per agent (escalate to the reviewer path if timeout)

---

## Graceful Degradation

If `codex-coder` MCP unavailable:
1. Try sequential `codex exec --profile coder` calls
2. Fallback: Claude implements sequentially (no parallelism)
3. Log: `[Parallel-Impl] MCP unavailable, falling back to sequential execution`

---

## Anti-Patterns

- DO NOT spawn parallel agents for dependent tasks — will produce broken code
- DO NOT have two agents edit the same file — merge conflict guaranteed
- DO NOT skip the consolidation step — parallel != correct
- DO NOT use for XS/S tasks — overhead exceeds benefit
