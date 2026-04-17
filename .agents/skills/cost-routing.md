---
skill: cost-routing
trigger: Automatic — Maestro consults before every tier-2 delegation
persona: maestro
version: 1.0.0
lastUpdated: 2026-03-30
shortDescription: >
  Cost-aware task routing table. Routes work to the cheapest provider that can
  handle the task quality. Saves 60-80% on Anthropic costs by defaulting to Codex.
usedBy: [maestro]
evals:
  - prompt: "implement the auth module"
    should_trigger: true
  - prompt: "plan the architecture"
    should_trigger: false
---

## Purpose

Before delegating ANY tier-2 task, Maestro consults this routing table to determine
which provider should handle it. The goal: **minimize Anthropic spend without losing quality.**

**Principle: Use the cheapest provider that meets quality requirements.**

---

## Cost Routing Matrix

| Task Type | Size | Provider | Tool | Est. Savings vs Opus |
|-----------|------|----------|------|---------------------|
| **Code generation** | M/L | Codex (gpt-5.4 (high)) | `mcp__codex-coder__spawn_agent` | 60-70% |
| **Code generation** | XS/S | Claude (direct) | — | 0% (MCP overhead exceeds benefit) |
| **Code review** | M/L | Codex (reviewer profile) | `mcp__codex-reviewer__spawn_agent` | 40-50% |
| **Code review** | XS/S | Claude (direct) | — | 0% |
| **Test-fix loop** | Any | Codex (gpt-5.4 (high)) | `mcp__codex-coder__spawn_agent` | 80% |
| **Context reading** | Any | Codex (vault MCP) | Codex reads via obsidian-vault MCP | 90% |
| **Browser QA** | Any | Codex (Playwright) | `mcp__codex-coder__spawn_agent` | 70% |
| **Planning** | Any | Claude Opus | — | N/A (needs best reasoning) |
| **Architecture** | Any | Claude Opus | — | N/A |
| **User interview** | Any | Claude Opus | — | N/A (needs AskUserQuestion) |
| **Brainstorm** | Any | Codex (parallel) | `spawn_agents_parallel` | 60% |
| **Security scan** | Any | Codex (reviewer profile) | `mcp__codex-reviewer__spawn_agent` | 40% |
| **Documentation** | Any | Codex (gpt-5.4 (high)) | `mcp__codex-coder__spawn_agent` | 70% |
| **Context loading** | Any | Codex (context-loader) | `mcp__codex-coder__spawn_agent` | 90% |
| **Session notes** | Any | Codex (session-writer) | `mcp__codex-coder__spawn_agent` | 80% |
| **PR description** | Any | Codex (pr-writer) | `mcp__codex-coder__spawn_agent` | 70% |
| **GitHub ops** | Any | Codex (github MCP) | `mcp__codex-coder__spawn_agent` | 60% |
| **Refactoring prep** | M/L | Codex (refactor-prep) | `mcp__codex-coder__spawn_agent` | 60% |
| **Onboarding** | Any | Codex (onboarding) | `mcp__codex-coder__spawn_agent` | 90% |
| **Vault reading** | Any | Codex (multi-vault) | `mcp__codex-coder__spawn_agent` | 90% |

---

## Decision Procedure

Before each delegation, Maestro follows this flowchart:

```
1. Is this a tier-1 task (planning, architecture, orchestration)?
   → YES: Opus handles directly. STOP.
   → NO: continue.

2. Is this XS/S size?
   → YES: Opus handles directly (MCP overhead not justified). STOP.
   → NO: continue.

3. Does this task require AskUserQuestion or interactive tools?
   → YES: Opus handles directly. STOP.
   → NO: continue.

4. Route to Codex per the matrix above.
   → If codex-coder MCP available: use spawn_agent
   → If codex-reviewer MCP available: use spawn_agent
   → Fallback: CCB ask codex only when an active Codex session exists → Claude direct
```

---

## Context Optimization Rules

To minimize Opus token consumption:

1. **Never read raw source files just to pass them to Codex.** Use context preload instead:
   - Write context to `.agents/tmp/context-package.md`
   - Codex reads from disk (zero Opus tokens)

2. **Use vault digests** (from context-digest skill) instead of reading full files:
   - 500-line file → 50-line digest = 10x token savings

3. **Let Codex self-serve context** via its native MCPs:
   - obsidian-vault: reads vault notes directly
   - ast-grep: searches code patterns directly
   - Opus doesn't need to pre-read for Codex

---

## Cost Tracking

After each session, log provider usage to vault metrics:
```yaml
provider_tokens:
  claude: {input_tokens}
  codex: {input_tokens}
estimated_cost:
  claude: ${cost}
  codex: ${cost}
savings_pct: {percentage vs all-opus baseline}
```

See: `.agents/vault/bases/cost-dashboard.base` for trend visualization.

---

## When to Override

Sometimes Opus should handle despite the matrix saying Codex:
- Task requires deep understanding of framework internals
- Previous Codex attempt failed and escalation didn't fix it
- User explicitly requests Claude to handle it
- Task involves sensitive operations (deploy, migration, data mutation)

Always log overrides in the session summary with justification.
