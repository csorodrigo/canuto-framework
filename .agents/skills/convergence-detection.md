shortDescription: Detect when multiple personas independently reach the same conclusion, marking it as high-confidence.
usedBy: [maestro]
version: 1.0.0
lastUpdated: 2026-03-18
copyright: Rodrigo Canuto © 2026.
inspiration: pgs-engine — convergent findings across independent partitions indicate high-confidence results.

## When to Use

**Triggers:**
- After 2+ persona handoffs on the same task — Maestro checks for convergent findings
- During synthesis (Reviewer pass) — compare findings with earlier personas
- Session end — note convergent patterns for instinct extraction

**Not for:**
- Single-persona tasks (XS with Coder only — nothing to converge)
- Findings that were explicitly communicated between personas (not independent)

---

## Purpose

When the Architect identifies a risk in planning, and the Tester independently discovers the same issue in testing, and the Reviewer flags it again — that's **convergence**. Three independent observations of the same thing are far more reliable than one.

Convergence detection turns coincidental overlap into **actionable confidence signals**, helping Maestro prioritize issues and extract high-quality instincts.

---

## Concepts

### Convergent Finding

Two or more personas independently identify the same issue, pattern, or concern without being informed of each other's observation.

### Convergence Score

| Personas Agreeing | Score | Meaning |
|-------------------|-------|---------|
| 2 | Medium | Likely real — worth attention |
| 3 | High | Almost certainly real — prioritize |
| 4+ | Critical | Systemic issue — address immediately |

### Independence Requirement

Convergence only counts when findings are **independent**:
- ✅ Architect notes missing validation in plan, Tester discovers it in tests → convergent
- ❌ Architect notes missing validation, Maestro tells Tester to check for it → not convergent (directed)

---

## Procedure

### Detection

After each persona handoff, Maestro compares the current findings against previous handoffs:

1. Extract key concerns from the current handoff (issues, flags, absences)
2. Compare against concerns from previous personas in this task
3. If a match is found and the findings were independent → flag as convergent

### Announcement

```
🔄 Convergence Detected:
- Finding: "No input validation on user registration endpoint"
- Independent sources:
  1. Architect (planning): noted missing validation schema in src/schemas/
  2. Coder (implementation): flagged lack of Zod schema for request body
  3. Tester (testing): found endpoint accepts malformed payloads
- Convergence score: High (3 sources)
- Recommendation: Address before merging — this is a confirmed gap.
```

### Action

Based on convergence score:

| Score | Maestro Action |
|-------|----------------|
| Medium | Note in handoff to next persona, surface at session end |
| High | Interrupt current flow, recommend addressing before continuing |
| Critical | Trigger escalation — route to Architect for re-planning |

### Instinct Extraction

Convergent findings are prime candidates for instinct extraction:

```
Session Learnings:
- [NEW] I-015 — [code-pattern] Input validation consistently missing on new endpoints
  Source: Convergent finding (3 personas, 2026-03-18)
  Confidence: medium (first occurrence, but 3-way convergence → start at medium)
```

Convergent findings start at `medium` confidence (instead of the usual `low`) because they're already validated by multiple independent sources.

---

## Examples

### ✅ Good — convergence with clear independent sources

```
🔄 Convergence Detected:
- Finding: "Error responses don't include request IDs for debugging"
- Independent sources:
  1. Architect: planned structured error responses but didn't include request IDs
  2. Reviewer: flagged missing correlation IDs in error handling review
- Convergence score: Medium (2 sources)
- Recommendation: Add request ID to error response schema before next feature.
```

### ✅ Good — convergence leading to instinct

```
Session Learnings:
- [NEW] I-022 — [architecture] Error responses lack correlation IDs
  Source: Convergent finding — Architect + Reviewer (2026-03-18)
  Confidence: medium (3-way convergence → elevated from low)
```

### ❌ Bad — false convergence (directed, not independent)

```
🔄 Convergence Detected:
- Finding: "Missing rate limiting"
- Sources:
  1. Architect: planned rate limiting
  2. Coder: implemented rate limiting per Architect's plan
  3. Tester: tested rate limiting per plan
```

This is bad because: all sources are following the plan, not independently discovering the same thing. This is plan execution, not convergence.

---

## Guardrails

- **Independence is required.** Only count findings that were reached without knowledge of each other.
- **Don't force convergence.** Not every task will have convergent findings. That's fine.
- **Convergence is about concerns, not solutions.** Two personas might identify the same problem but propose different fixes — that's still convergence on the problem.
- **Don't interrupt for Medium convergence.** Note it, but don't derail the flow.
- **Convergent instincts start at medium confidence.** They've already been validated by multiple sources.
- **Log convergence in audit trail.** Every convergence detection is an auditable event.
