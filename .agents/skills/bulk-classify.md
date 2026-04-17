---
skill: bulk-classify
trigger: Automatic — Maestro consults when a task requires classifying >10 items with short labels
persona: maestro
version: 1.0.0
lastUpdated: 2026-04-17
shortDescription: >
  High-volume classification slot backed by Gemini flash-lite (separate quota bucket).
  Labels PRs by size, triages issues, detects intent, categorizes diffs — at a fraction
  of the cost of Opus or Codex.
usedBy: [maestro]
evals:
  - prompt: "classify these 30 PRs by size"
    should_trigger: true
  - prompt: "write the auth middleware"
    should_trigger: false
---

## Purpose

Some tasks need a cheap, fast "yes/no" or "bucket X" answer over many items. Opus is
overkill (cost), Codex is overkill (latency + MCP overhead), and Claude direct is
fine but wastes Anthropic spend.

The `bulk-classify` slot routes these to **Gemini `gemini-3.1-flash-lite-preview`**,
which has:

- Separate quota bucket on OAuth (`Flash-Lite` bar — independent from Pro / Flash)
- Low latency (~1s per call)
- Zero marginal cost up to ~1000 req/day via OAuth

## When to use

- PR size labeling (XS / S / M / L) across many PRs at once
- Issue triagem by type (bug / feature / question / spam)
- Intent detection (deciding which skill to route a user prompt to)
- Diff categorization (UI / backend / docs / config / migration)
- Deduplicating similar items by semantic category
- Any "one-word-or-short-label" classification at >10 items/invocation

## When NOT to use

- Under 5 items — overhead > benefit, Claude direct is fine
- Decisions that require reasoning or judgment — use Opus or Codex reviewer
- Anything needing citations or long context — flash-lite is small-context
- Very high volume (>500 items/call or >1000/day sustained) — consider Vertex ADC
  (`GOOGLE_GENAI_USE_VERTEXAI=true` + `gcloud auth application-default login`) to
  escape the OAuth daily quota

## How to invoke

Single classification:

```
mcp__gemini__ask-gemini({
  prompt: "Classifique em 1 palavra (XS/S/M/L): 'adicionar coluna created_at em users'",
  model: "gemini-3.1-flash-lite-preview"
})
```

Batch (serialize — stdio MCP is single-connection, see `gemini-routing.md`):

```
for item in items:
  label = await mcp__gemini__ask-gemini({
    prompt: f"Classifique em 1 palavra (XS/S/M/L): '{item}'",
    model: "gemini-3.1-flash-lite-preview"
  })
  results.append((item, label))
```

Structured output (better for parsing):

```
mcp__gemini__ask-gemini({
  prompt: """
    Classify each line in the input. For each line, output exactly one label from:
    XS, S, M, L. Format: one label per line, in the same order.

    Input:
    - add created_at column to users
    - rewrite the billing module
    - fix typo in README
    - split the worker into 3 services

    Output (4 lines, labels only):
  """,
  model: "gemini-3.1-flash-lite-preview"
})
```

## Output quality tips

- **Pin the label set explicitly in the prompt.** Flash-lite hallucinates less when
  the valid options are enumerated.
- **Ask for one-word or one-line outputs.** Flash-lite is great at terse output,
  verbose prompts degrade it.
- **Batch up to ~20 items per call** — past that, flash-lite starts losing order.
- **Validate output against the label set.** Discard or retry anything not in the
  enumerated set.

## Cost tracking

Treat `gemini-3.1-flash-lite-preview` calls as **free** up to 1000/day cumulative
on the Flash-Lite bar. Above that threshold:

1. Rate-limit client-side (sleep between calls)
2. Batch more aggressively (20 items/call instead of 1)
3. Switch to Vertex ADC — adds GCP billing but unlimited

Log per-session counts in the metrics note under `provider_tokens.gemini_flash_lite`.

## See also

- `.agents/skills/gemini-routing.md` — gotchas, versioning, banned models
- `.agents/skills/cost-routing.md` — full routing matrix
- `.context/gemini-mcp-poc.md` — POC evidence for the bucket-separation claim
