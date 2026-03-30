---
skill: codex-refactor-prep
trigger: Before implementing large features, when codebase needs preparation
persona: architect
version: 1.0.0
lastUpdated: 2026-03-30
shortDescription: >
  Codex prepares the codebase before feature implementation — extracts interfaces,
  creates stubs, organizes imports, splits large files. Opus plans, Codex prepares,
  Codex implements.
usedBy: [architect, maestro]
evals:
  - prompt: "prepare the codebase for the new auth system"
    should_trigger: true
  - prompt: "refactor before implementing"
    should_trigger: true
  - prompt: "implement the auth system"
    should_trigger: false
---

## Purpose

Before implementing a large feature, the codebase often needs preparation:
- Extract interfaces from concrete classes
- Create stub files for new modules
- Organize imports across affected files
- Split oversized files (>500 LOC)

Doing this in Opus wastes tokens on mechanical work. Codex does it faster and cheaper.

---

## Procedure

### 1. Architect Identifies Prep Work

From the plan, identify what needs preparation:
```markdown
## Prep Needed
- Extract `AuthProvider` interface from `src/auth/provider.ts`
- Create stub: `src/auth/session.ts` with exported types
- Split `src/routes/index.ts` (800 LOC) into per-domain route files
- Add barrel exports to `src/auth/index.ts`
```

### 2. Spawn Codex Refactorer

```
mcp__codex-coder__spawn_agent({
  prompt: `
You are preparing the codebase for a new feature. Do NOT implement the feature —
only prepare the structure.

## Preparation Tasks
{prep_task_list}

## Rules
- Extract interfaces but keep existing implementations working
- Stub files should have correct types but empty function bodies (throw 'not implemented')
- Maintain all existing imports — update paths where you split files
- Run any available linter after changes
- Do NOT change any business logic
- Do NOT add new dependencies

## Context
Read .agents/tmp/context-package.md for project context.
`
})
```

### 3. Verify Preparation

After Codex finishes:
1. `git diff` — verify only structural changes, no logic changes
2. Run tests — everything should still pass
3. If tests fail → revert and have Codex retry with more context

### 4. Proceed to Implementation

With the codebase prepared, the main implementation is cleaner:
- New code fits into extracted interfaces
- Stubs get filled in with real implementations
- No need to split files mid-implementation

---

## Integration

- **parallel-impl.md**: prep runs before parallel agents are spawned
- **multi-provider.md**: prep is a Codex task (tier-2)
- **cost-routing.md**: refactoring → Codex (60% savings)
