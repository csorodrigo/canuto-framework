---
skill: lazy-opus-review
trigger: Automatic — after Codex returns any output
persona: maestro
version: 1.0.0
lastUpdated: 2026-03-30
shortDescription: >
  Confidence-gated review. Codex self-rates confidence (1-10). If >= 8, Opus
  accepts without deep review. If < 8, Opus does full review. 50% review savings.
usedBy: [maestro]
evals:
  - prompt: "should I review this codex output?"
    should_trigger: true
  - prompt: "accept codex output without review"
    should_trigger: true
  - prompt: "always review everything"
    should_trigger: false
---

## Purpose

Not every Codex output needs full Opus review. Simple, high-confidence outputs
(formatting, docs, straightforward implementations) can be accepted with
minimal verification. Complex, uncertain outputs need full review.

**50% savings on review tokens** by skipping unnecessary deep reviews.

---

## Confidence Protocol

### In Every Codex Prompt, Append:

```
## Self-Assessment (REQUIRED)
At the end of your response, include:
CONFIDENCE: N/10
UNCERTAIN_AREAS: [list any areas you're unsure about, or "none"]
```

### Confidence Thresholds

| Confidence | Action | Opus Tokens |
|-----------|--------|-------------|
| **9-10** | Accept immediately, no review | ~500 (skim diff) |
| **7-8** | Quick review — skim diff, check uncertain areas only | ~2000 |
| **4-6** | Full review — read all changes carefully | ~5000-10000 |
| **1-3** | Reject — likely wrong, re-prompt or escalate | ~1000 + retry |

### Maestro Decision Flow

```
Codex returns output with CONFIDENCE: N
  ↓
N >= 9? → Accept. Skim git diff (30 seconds). Log "[Lazy-Review] Auto-accepted (confidence N)"
  ↓
N >= 7? → Quick review. Read diff + check UNCERTAIN_AREAS only.
  ↓
N >= 4? → Full review. Read all changes. Optionally trigger codex-reviewer (o1-pro).
  ↓
N < 4? → Reject. Re-prompt with more context or escalate.
```

---

## Override Conditions

Always do full review regardless of confidence when:
- Changes touch auth, crypto, payment, or security files
- Changes modify database schema or migrations
- Changes affect CI/CD pipeline
- Task is user-facing (UI components, API endpoints)
- First time Codex works on this module (no prior history)

---

## Tracking

Log confidence scores in session metrics:
```yaml
codex_confidence:
  avg: 7.8
  auto_accepted: 12
  quick_reviewed: 5
  full_reviewed: 3
  rejected: 1
```

Trends: if average confidence drops below 6, review the prompt templates.

---

## Integration

- **multi-provider.md**: all Codex prompts include confidence protocol
- **budget-controls.md**: lazy review reduces review token budget
- **review-scores-template.md**: track confidence vs actual quality correlation
