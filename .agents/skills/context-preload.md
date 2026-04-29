---
skill: context-preload
trigger: Before delegating M/L coding task to Codex via spawn_agent
persona: architect
version: 1.0.0
lastUpdated: 2026-03-30
shortDescription: >
  Writes a context package file that Codex reads from disk instead of receiving
  inline in the prompt. Saves 20-50K Opus tokens per M/L task delegation.
usedBy: [architect, maestro]
evals:
  - prompt: "prepare context for codex to implement the auth module"
    should_trigger: true
  - prompt: "delegate this to codex"
    should_trigger: true
  - prompt: "fix this typo"
    should_trigger: false
---

## Purpose

Instead of Opus reading 10 files and inlining them in the spawn_agent prompt
(expensive — 20-50K Opus tokens), write a single context package file to disk.
Codex reads it from the filesystem (zero Opus tokens).

**Reusable**: same package serves multiple spawn_agent calls in one session.

---

## Procedure

### 1. Assemble the Package

Architect gathers:
- **Plan**: current implementation plan (from plan file)
- **Digests**: relevant directory digests (from vault/digests/)
- **Types**: key interfaces and type definitions
- **Constraints**: no new deps, test requirements, style rules
- **File paths**: which files to create/modify

### 2. Write to Disk

```
Write to: .agents/tmp/context-package.md
```

Helper:

```bash
bash .agents/tools/codex-context-package.sh \
  --task "auth module" \
  --plan path/to/PLAN.md \
  --file src/auth/middleware.ts \
  --dir src/auth \
  --output .agents/tmp/context-package.md
```

Format:
```markdown
# Context Package — {task name}
Generated: {timestamp}

## Plan
{implementation plan from Architect}

## Relevant Digests
### src/auth/
{digest content}

### src/models/
{digest content}

## Key Types
```typescript
interface User { id: string; email: string; role: Role }
type Role = 'admin' | 'user' | 'guest'
```

## Constraints
- No new dependencies
- Tests required (vitest)
- Follow existing patterns in src/auth/

## Files to Create/Modify
- src/auth/middleware.ts (modify)
- src/auth/session.ts (create)
- tests/auth/session.test.ts (create)
```

### 3. Delegate to Codex

The spawn_agent prompt references the file instead of inlining:

```
codex exec --profile coder({
  prompt: `
Read .agents/tmp/context-package.md for full task context and implementation plan.
Implement everything described in the plan. Write code to the files listed.
After implementation, run tests if a test command is available.
`
})
```

### 4. Cleanup

After the task is complete (code written, reviewed, committed):
- Delete `.agents/tmp/context-package.md`
- Or leave for next spawn_agent in same session

### Verification Gate

The `codex-pretool-guard.sh` hook blocks medium/large `spawn_agent` calls when no
context package is present in `.agents/tmp/`.

---

## For Parallel Implementation

When using `/parallel-impl`, create scoped packages:
```
.agents/tmp/context-package-subtask-1.md
.agents/tmp/context-package-subtask-2.md
.agents/tmp/context-package-subtask-3.md
```

Each agent reads only its own package.

---

## Token Savings Example

| Approach | Opus Tokens | Codex Tokens |
|----------|-------------|-------------|
| Inline (old) | 40K (read + inline) | 40K (receive) |
| Preload (new) | 2K (write file) | 40K (read from disk) |
| **Savings** | **38K Opus tokens** | Same |

At Opus pricing (~$15/1M tokens input), saving 38K tokens = ~$0.57 per task.
Over 50 tasks/week = ~$28.50/week savings.

---

## Integration

- **cost-routing.md**: references preload as the context delivery method
- **multi-provider.md**: coding delegation uses preload for M/L tasks
- **parallel-impl.md**: each parallel agent gets a scoped package
- **.gitignore**: `.agents/tmp/` is gitignored (install.sh ensures this)
