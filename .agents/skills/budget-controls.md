shortDescription: Define and enforce token/cost budgets per persona and per session to prevent runaway consumption.
usedBy: [maestro]
version: 1.0.0
lastUpdated: 2026-03-18
copyright: Rodrigo Canuto © 2026.
inspiration: Paperclip — monthly budgets per agent with hard enforcement and real-time tracking.

## When to Use

**Triggers:**
- Session start — Maestro loads budget config and sets session limits
- Before each persona handoff — Maestro checks remaining budget
- Session end — Maestro logs token consumption in metrics
- User asks: `"how much have we spent?"`, `"token budget"`, `"cost report"`

**Not for:**
- Projects where cost is not a concern (disable via `budget: disabled` in CLAUDE.md)
- Single-provider setups with flat-rate pricing

---

## Purpose

Prevent surprise costs from long sessions, stuck loops, or multi-provider delegation. Budget controls give visibility into token consumption and allow Maestro to make informed decisions about when to abbreviate, skip optional steps, or warn the user.

---

## Concepts

### Budget Levels

| Level | Scope | Example |
|-------|-------|---------|
| **Session budget** | Total tokens for the entire session | 200K tokens |
| **Persona budget** | Max tokens a single persona can consume per invocation | Architect: 30K, Coder: 80K |
| **Task budget** | Estimated tokens for a specific task (based on size) | M task: ~120K tokens |

### Budget Config

Defined in `.agents/stack.md` or `CLAUDE.md` under `## Budget`:

```markdown
## Budget

- session-limit: 200000 tokens
- persona-limits:
  - architect: 30000
  - coder: 80000
  - tester: 40000
  - debugger: 30000
  - reviewer: 20000
  - contextualizer: 50000
- warn-at: 80%
- hard-stop: false
```

**Fields:**
- `session-limit` — total token budget for the session
- `persona-limits` — per-persona caps (optional, defaults to proportional split)
- `warn-at` — percentage at which Maestro warns the user (default: 80%)
- `hard-stop` — if true, Maestro stops work when budget is exceeded; if false (default), warns but continues

### Task Size Estimates

| Size | Estimated Tokens | Typical Flow |
|------|-----------------|--------------|
| XS | 10-20K | Coder + Reviewer |
| S | 20-50K | Architect (abbrev) + Coder + Reviewer |
| M | 50-150K | Full flow |
| L | 100-250K+ | Full flow + extended Tester |

These are estimates. Actual consumption varies.

---

## Procedure

### On Session Start

1. Read budget config from `CLAUDE.md` or `.agents/stack.md`
2. If no config exists, use defaults (session: 200K, warn-at: 80%, hard-stop: false)
3. Initialize counters: `{ session: 0, personas: {} }`

### Before Each Handoff

Maestro estimates remaining budget:

```
[Budget] Session: ~65K / 200K used (32%). Next: Tester (~40K estimated). Sufficient.
```

If estimated consumption would exceed the session limit:

```
⚠️ Budget warning: Session at ~170K / 200K (85%).
Tester pass estimated at ~40K, which would exceed the session limit.
Options:
(a) Run Tester with abbreviated scope (edge cases only, skip comprehensive coverage)
(b) Skip Tester and go directly to Reviewer
(c) Continue anyway (budget is advisory)
```

### On Session End

Log consumption in metrics:

```markdown
### Token Budget
- Session limit: 200K
- Estimated consumption: ~145K (72%)
- Breakdown: Architect ~25K, Coder ~70K, Tester ~35K, Reviewer ~15K
- Budget status: ✅ Within limits
```

### Multi-Provider Cost Tracking

When using multi-provider delegation, track estimated costs:

```markdown
### Cost Estimate
- Claude (Architect + Reviewer): ~40K tokens × $0.015/1K = ~$0.60
- Codex (Coder): ~70K tokens × $0.01/1K = ~$0.70
- Total estimated: ~$1.30
```

---

## Examples

### ✅ Good — proactive budget management

```
[Budget] Session at ~160K / 200K (80%) — warn threshold reached.
Remaining personas: Tester, Reviewer.
Estimated remaining cost: ~55K tokens.

Recommendation: Run Tester with focused scope (critical paths only) to stay within budget.
Proceed? [Y/abbreviated/skip]
```

### ✅ Good — session end budget summary

```
Session Budget Summary:
- Limit: 200K | Used: ~185K (92%)
- Heaviest persona: Coder (~90K — complex implementation with 5 files)
- Budget status: ⚠️ Near limit but completed all goals
```

### ❌ Bad — no budget awareness

```
[Maestro → Tester] Run comprehensive tests on all endpoints.
```

No check on remaining budget before routing to an expensive pass. Could exceed session limits silently.

### ❌ Bad — hard-stopping without options

```
Budget exceeded. Stopping work.
```

This is bad because: doesn't give the user options. Budget should be advisory by default — present choices, not ultimatums.

---

## Cost Routing Matrix

Before delegating any tier-2 task, consult the `cost-routing` skill for the optimal provider.
See `.agents/skills/cost-routing.md` for the full decision matrix.

**Quick reference:**

| Route | Savings |
|-------|---------|
| M/L coding → Codex gpt-5-codex | 60-70% |
| Reviews → Codex o1-pro | 40-50% |
| Test-fix → Codex loop | 80% |
| Context → Codex vault MCP | 90% |
| Browser QA → Codex Playwright | 70% |
| Planning → Opus (always) | N/A |

## Provider Cost Tracking Schema

At session end, append to metrics note:

```yaml
provider_tokens:
  claude: {total_input_tokens}
  codex: {total_input_tokens}
estimated_cost:
  claude: ${input_tokens * 0.015 / 1000}
  codex: ${input_tokens * 0.003 / 1000}
savings_pct: {1 - (actual_cost / all_opus_baseline_cost) * 100}
tasks_delegated: {count of tasks sent to codex}
escalations: {count of gpt-5-codex → o1-pro escalations}
```

**Dashboard**: `.agents/vault/bases/cost-dashboard.base` visualizes trends.

## Guardrails

- **Budget is advisory by default.** Always present options, never hard-stop without user consent (unless `hard-stop: true` in config).
- **Estimates are approximations.** Token counting is imprecise — use them for trend awareness, not precise accounting.
- **Don't micro-optimize.** Budget tracking should add awareness, not anxiety. Check at handoff boundaries, not every message.
- **Multi-provider costs are estimates.** Actual API pricing may differ — use budget tracking for relative comparisons.
- **No budget config = use defaults.** The feature works out of the box with sensible defaults.
- **Log in metrics, not in memory.** Budget data goes into `metrics.md` at session end, not into persistent memory.
- **Cost routing is a guideline, not a law.** Override when quality demands it — but log the override.
