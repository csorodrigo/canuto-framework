---
skill: codex-context-loader
trigger: On session start, or when Architect needs codebase context for planning
persona: contextualizer
version: 1.0.0
lastUpdated: 2026-03-30
shortDescription: >
  Delegates codebase reading to Codex instead of Opus. Codex reads source files
  and generates digests via `codex exec`. Opus receives only the summary. 90% savings.
usedBy: [contextualizer, maestro]
evals:
  - prompt: "load context for planning the auth feature"
    should_trigger: true
  - prompt: "read the entire src directory for me"
    should_trigger: true
  - prompt: "fix this typo"
    should_trigger: false
---

## Purpose

On session start or before planning, Opus typically reads 10-30 source files
(~30K-80K tokens). This skill delegates the reading to Codex, which generates
compact digests. Opus receives ~2K tokens of summary.

**90% token savings on context loading.**

---

## Procedure

### 1. Identify Relevant Directories

Maestro identifies which directories are relevant to the current task:
```
src/auth/, src/models/, src/routes/
```

### 2. Spawn Codex Context Loader

```
codex exec --color never --profile coder \
  -s workspace-write --skip-git-repo-check \
  -o /tmp/codex-context-loader-$$.md \
  "$(cat <<'PROMPT'
You are a context loader. Read the following directories and generate
compact digests for each. Write the output to .agents/tmp/context-digests.md.

## Directories to Digest
{directory_list}

## Digest Format (per directory)
# Digest: {dir_path}/
**Files**: N files, N LOC total
## Public API
- function signatures (exported only)
## Key Types
- interfaces, types, enums
## Dependencies
- external packages + internal imports
## Architecture
- patterns used (middleware, repository, hooks, etc.)
## Summary
- 2-3 sentence plain language description

## Rules
- Do NOT include function bodies or implementation details
- Do NOT include comments from source files
- Do NOT include test files unless specifically requested
- Keep each digest under 60 lines
PROMPT
)"
```

### 3. Opus Reads Digests

After Codex writes `.agents/tmp/context-digests.md`:
```
[Context loaded via Codex — 2K tokens vs ~50K raw reading]
```

Opus reads the digests file (small) and plans from it.

### 4. Stale Check

Before spawning, check `.agents/vault/digests/` for existing digests:
- If fresh (git hash matches HEAD) → skip, use cached digest
- If stale → spawn Codex to regenerate

---

## Token Savings

| Approach | Opus Tokens | Cost |
|----------|-------------|------|
| Opus reads raw files | 50K | ~$0.75 |
| Codex generates digests | 2K (read summary) | ~$0.03 |
| **Savings** | **48K tokens** | **~$0.72 per session** |

Over 5 sessions/day × 20 days/month = ~$72/month savings.

---

## Integration

- **context-digest.md**: this skill uses the same digest format
- **context-preload.md**: digests feed into context packages for Codex
- **cost-routing.md**: context loading → Codex (90% savings)
- **Session start**: Maestro triggers this before any planning

---

## Graceful Degradation

- Codex CLI unavailable → Opus reads files directly (standard behavior)
- Log: `[Context-Loader] Codex unavailable, falling back to direct reads`
