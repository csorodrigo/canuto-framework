---
skill: context-health
trigger: Automatic — Maestro checks when session quality may degrade, or when the user asks for context health
persona: maestro
version: 1.0.0
lastUpdated: 2026-04-18
shortDescription: >
  Scores current session context quality across seven operational signals.
  Warns before context decay becomes visible to the user.
usedBy: [maestro]
evals:
  - prompt: "check context health before we continue"
    should_trigger: true
  - prompt: "why is this session starting to repeat itself?"
    should_trigger: true
  - prompt: "implement the auth module"
    should_trigger: false
---

## Purpose

`/context-health` adds a quality dimension to Canuto session telemetry. Cost and token skills show how much the session spent; this skill shows whether the active context is still useful, fresh, and worth carrying forward.

The goal is early warning: surface cache misses, dead-weight skills, stale memory, inactive MCPs, compaction risk, excessive delegation, and repeated user prompts before the user notices degraded answers.

---

## When to Use

**Triggers:**
- User asks for `"context health"`, `"quality score"`, `"context degradation"`, `"loop detector"`, or `"why are we repeating?"`
- Before a large handoff when Maestro suspects the session is close to compaction
- After a long multi-agent run with several subagents or repeated retries
- At session end when writing metrics to `.agents/vault/metrics/`
- When budget controls warn but the question is quality, not only spend

**Not for:**
- Fresh sessions with fewer than three user turns and no handoffs
- Pure cost questions such as `"how much did this cost?"` without a quality concern
- Provider routing decisions where `cost-routing` already has enough information
- Code health, test health, install health, or repository diagnostics unrelated to active context quality

---

## The 7 Signals

| Signal | What it measures | Healthy range | Degraded range | Source of truth |
|--------|------------------|---------------|----------------|-----------------|
| **Cache hit rate** | Percent of input tokens served from prompt cache instead of re-sent from scratch | `>= 80%` | `< 50%` | Latest token/cost entries in `.agents/vault/metrics/` and session usage notes in `.agents/vault/audit/` |
| **Skill activation density** | Skills actually invoked this session divided by skills loaded into the active prompt | `>= 0.35` | `< 0.15` | Session skill mentions in `.agents/vault/audit/`; loaded skill inventory from the active prompt skill list, using session log/audit evidence. If unavailable, mark this signal `unknown`. |
| **MEMORY.md drift** | Orphaned topic references in `MEMORY.md` plus entries after line 200 | `0-2 drift points` | `> 8 drift points` | `MEMORY.md` and referenced local topic files |
| **MCP server health** | Configured MCP servers that fired at least once during the session | `>= 70%` | `< 30%` | Claude-side configured servers in `~/.claude/settings.json` and project-level `.mcp.json` when present; tool activity in `.agents/vault/audit/`. Codex MCPs from `~/.codex/config.toml` are out of scope. |
| **Compaction proximity** | Remaining turns or tokens before the next compaction trigger | `>= 25% remaining` | `< 10% remaining` | Token estimates in `.agents/vault/metrics/` and pre-compact/session notes in `.agents/vault/audit/` |
| **Subagent cost share** | Share of session spend consumed by subagents instead of the coordinating persona | `<= 20%` | `> 30%` | Provider/persona cost summaries in `.agents/vault/metrics/` and handoff traces in `.agents/vault/audit/` |
| **Repetition index** | User turns semantically similar to earlier user turns in the same session | `0-1 repeated turns` | `>= 4 repeated turns` | User-turn history and retry notes in `.agents/vault/audit/` |

If a source is missing, mark the signal `unknown`, assign a neutral score of `5`, and list the missing source in the report. Do not invent telemetry.

---

## Composite Score

Score each signal from `0` to `10`, then compute:

```text
context_health =
  cache_hit_rate_score * 0.14 +
  skill_activation_density_score * 0.12 +
  memory_drift_score * 0.15 +
  mcp_server_health_score * 0.10 +
  compaction_proximity_score * 0.20 +
  subagent_cost_share_score * 0.11 +
  repetition_index_score * 0.18
```

**Rationale:**
- Compaction proximity gets the highest weight because imminent context loss can invalidate otherwise healthy signals.
- Repetition index is next because repeated user prompts are the clearest external symptom of degraded understanding.
- MEMORY.md drift and cache hit rate carry strong weight because they affect long-term recall and prompt efficiency.
- Skill density, MCP health, and subagent share are lower-weight operational signals; they matter, but they should not dominate a session that is otherwise coherent.

**Scoring rules:**
- Cache hit rate: `10` at `>= 80%`, `5` at `50-79%`, `2` at `30-49%`, `0` below `30%`.
- Skill activation density: `10` at `>= 0.35`, `6` at `0.20-0.34`, `3` at `0.15-0.19`, `0` below `0.15`.
- MEMORY.md drift: `10` for `0-2`, `7` for `3-5`, `4` for `6-8`, `0` above `8`.
- MCP server health: `10` at `>= 70%`, `6` at `50-69%`, `3` at `30-49%`, `0` below `30%`.
- Compaction proximity: `10` at `>= 25% remaining`, `6` at `10-24%`, `0` below `10%`.
- Subagent cost share: `10` at `<= 20%`, `6` at `21-30%`, `3` at `31-45%`, `0` above `45%`.
- Repetition index: `10` for `0`, `8` for `1`, `5` for `2-3`, `0` for `>= 4`.

Composite below `5/10` must include a warning section and concrete recovery options.

---

## Output Format

Save the report to `.agents/vault/metrics/context-health-YYYY-MM-DD.md`.

### Inline Badge

Emit this badge in the active session before writing the markdown file:

```text
[Context Health] Score: N.N/10 (healthy|watch|degraded). Top risk: <signal-name>.
```

### Markdown Template

```markdown
---
type: metric
metric: context-health
date: YYYY-MM-DD
score: N.N
status: healthy|watch|degraded
tags: [metrics, context-health]
---

# Context Health — YYYY-MM-DD

**Score:** N.N/10
**Status:** healthy|watch|degraded
**Recommendation:** one concise sentence.

| Signal | Value | Score | Status | Note |
|--------|-------|-------|--------|------|
| Cache hit rate | 84% | 10 | Healthy | Prompt cache is carrying the stable prefix. |

## Unknowns

Required when any signal is scored neutral `5` due to missing telemetry; omit when every signal has source data.

- Signal name: missing source or unavailable telemetry.

## Warning

Only include when score is below 5/10.

## Next Actions

1. Action tied to the weakest signal.
2. Action tied to the next weakest signal.
3. Optional handoff or compaction recommendation.
```

### Sample Healthy Report

```markdown
# Context Health — 2026-04-18

**Score:** 8.4/10
**Status:** healthy
**Recommendation:** Continue the session; no compaction or routing change needed.

| Signal | Value | Score | Status | Note |
|--------|-------|-------|--------|------|
| Cache hit rate | 86% | 10 | Healthy | Stable system and skill prefix is caching well. |
| Skill activation density | 0.28 | 6 | Watch | Most loaded skills are relevant, with some unused prompt weight. |
| MEMORY.md drift | 1 | 10 | Healthy | No meaningful stale memory detected. |
| MCP server health | 75% | 10 | Healthy | Most configured servers fired. |
| Compaction proximity | 18% remaining | 6 | Watch | Context loss is not close, but the next handoff should re-check it. |
| Subagent cost share | 18% | 10 | Healthy | Delegation is proportionate. |
| Repetition index | 1 | 8 | Watch | One repeated clarification, not a loop. |

## Next Actions

1. Keep current routing.
2. Re-check after the next major handoff or before compaction.
```

### Sample Degraded Report

```markdown
# Context Health — 2026-04-18

**Score:** 3.9/10
**Status:** degraded
**Recommendation:** Stop expanding context; compact, summarize, and restart from a fresh handoff.

| Signal | Value | Score | Status | Note |
|--------|-------|-------|--------|------|
| Cache hit rate | 58% | 5 | Watch | Prompt cache is only partially carrying the stable prefix. |
| Skill activation density | 0.12 | 0 | Degraded | Many loaded skills are dead weight. |
| MEMORY.md drift | 7 | 4 | Watch | Stale or invisible memory entries are present. |
| MCP server health | 38% | 3 | Watch | Configured servers are mostly inactive. |
| Compaction proximity | 12% remaining | 6 | Watch | Context loss is close enough to require cleanup planning. |
| Subagent cost share | 18% | 10 | Healthy | Delegation is still proportionate. |
| Repetition index | 4 | 0 | Degraded | User prompts show a loop. |

## Warning

Context quality is below 5/10. Continuing without cleanup risks repeated work, missed instructions, and poor handoffs.

## Next Actions

1. Write a compact handoff from `.agents/vault/audit/` into `.agents/vault/metrics/`.
2. Drop unused skills and inactive MCP assumptions from the next prompt.
3. Restart from the summary before assigning more subagents.
```

---

## Procedure

1. Read the latest relevant session notes from `.agents/vault/audit/`.
2. Read current token, provider, and cost metrics from `.agents/vault/metrics/`.
3. Read Claude-side MCP configuration from `~/.claude/settings.json` and project-level `.mcp.json` when present, then compare configured servers with actual tool activity in audit notes.
4. Inspect `MEMORY.md` when present: count missing topic files referenced by the file and count any entries after line 200.
5. Count loaded skills from active prompt skill-list evidence in the session log or audit notes, then count skills actually invoked in `.agents/vault/audit/`; if loaded-skill evidence is absent, mark skill activation density `unknown`.
6. Estimate compaction proximity from token budget, turn count, and any pre-compact notes already written in `.agents/vault/audit/`.
7. Compute each signal score using the scoring rules above.
8. Compute the weighted composite score and classify status:
   - `healthy`: `>= 7.0`
   - `watch`: `5.0-6.9`
   - `degraded`: `< 5.0`
9. Emit the inline badge in the active session.
10. Write the report to `.agents/vault/metrics/context-health-YYYY-MM-DD.md`.
11. If the score is below `5/10`, show the warning section and recommend compaction, prompt slimming, or a fresh handoff before more work.

---

## Integration

- **smart-token-metering**: provides budget/token estimates and mode-switching thresholds. Cache hit data comes from session audit/metrics entries (`.agents/vault/audit/`, `.agents/vault/metrics/`), not from this skill.
- **cost-routing**: keeps work on the cheapest capable provider; `/context-health` warns when cheap routing creates repeated loops or excessive delegation.
- **budget-controls**: enforces per-session and per-persona spend limits; `/context-health` adds a separate quality score so low cost is not mistaken for healthy context.
- **audit-trail**: supplies session events, handoffs, repeated prompts, and tool activity used by several signals.
- **context-digest**: recommended recovery path when compaction proximity or MEMORY.md drift is poor.

---

## Examples

### ✅ Good — quality warning before the user notices

```
[Context Health] Score: 4.6/10 (degraded). Top risk: compaction proximity.
Main risks: compaction proximity 6% remaining, repetition index 4, skill density 0.11.
Recommendation: compact now and restart from a focused handoff before assigning more agents.
```

### ❌ Bad — cost-only signal treated as quality

```
Session cost is low, so context is fine.
```

This is bad because cheap sessions can still be stale, repetitive, over-loaded with unused skills, or close to compaction.

### ✅ Good — unknown telemetry handled honestly

```
[Context Health] Score: 6.8/10 (watch). Top risk: cache hit rate.
Unknown: cache hit rate was not present in `.agents/vault/metrics/`, so it was scored neutral at 5.
Recommendation: continue, but write provider token metrics at session end.
```

### ❌ Bad — inventing precision from missing files

```
Cache hit rate is 92% and MCP health is 80%.
```

This is bad when the values are not present in `.agents/vault/metrics/`, `.agents/vault/audit/`, `~/.claude/settings.json`, or project-level `.mcp.json` when applicable. Missing data must be marked unknown.
