# Blind Spot Library

Curated domain-specific knowledge that LLMs commonly get wrong or overlook. Unlike instincts (which are learned from project sessions), blind spots are pre-written, universal pitfalls.

## How It Works

1. Maestro extracts 2-3 keywords from the task during Instinct Lookup (Step 0.5).
2. Maestro checks `blind-spots/` files for matching trigger keywords.
3. Matching blind spots are injected into the handoff constraints for the target persona.

## Format

Each file covers one domain with 5-10 known pitfalls:

```markdown
# Domain: <name>
Keywords: keyword1, keyword2, keyword3

## Pitfall: <title>
**Trigger:** When the task involves <specific scenario>
**Common mistake:** <what LLMs typically do wrong>
**Correct approach:** <what to do instead>
```

## Maintenance

Each file has a `lastReviewed` date. The health-check skill flags files not reviewed in 6 months.

Adapted from Claude Octopus's blind spot injection pattern.

## Candidate Workflow (`_candidates/`)

- **Filename convention:** `_candidates/{target-domain}--{slug}.md` (use `NEW-{domain}--{slug}.md` only if the domain is undefined). Archive dismissed/promoted candidates under `_candidates/.archive/`.
- **Frontmatter schema:**
  ```markdown
  ---
  type: blind-spot-candidate
  target: <domain or file>
  source: trace-analysis
  signal: BS-001
  created: 2026-04-04
  status: pending
  keywords: [keyword1, keyword2]
  lastReviewed: 2026-04-04
  ---
  ```
- **Body format:** must match live blind spots exactly (Domain header, `Keywords:` line, `## Pitfall`, **Trigger/Common mistake/Correct approach**). Include an `Overfitting check` note at the end.
- **Lifecycle:** create → present during session start briefing (promote/dismiss/review) → once resolved, move to `_candidates/.archive/` or merge into a permanent blind spot file.
- **Stale guard:** candidates older than 30 days stay `pending` until reviewed; Maestro flags them as stale during the briefing.
- **Dedupe rules:** before creating a candidate, scan existing blind spots and `_candidates/` for title/keyword similarity (use `rg`); reference existing pitfalls instead of duplicating.
