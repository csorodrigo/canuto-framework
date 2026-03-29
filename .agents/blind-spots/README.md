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
