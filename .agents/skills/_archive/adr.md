shortDescription: Record architectural decisions with structured ADR format stored in .agents/decisions/.
usedBy: [architect, maestro]
version: 1.0.0
lastUpdated: 2026-02-25
copyright: Rodrigo Canuto © 2026.

## When to Use

**Triggers:**
- A decision affects how multiple parts of the system interact
- The project is committing to a specific technology, pattern, or library
- A decision has trade-offs future developers must understand
- An earlier decision is being reversed or superseded

**Not for:**
- Low-risk, reversible decisions (rename a variable, add a utility function)
- Decisions already captured in `stack.md` (use that for library choices)

---

## Purpose

Capture significant architectural and technical decisions with their rationale, alternatives, and consequences. ADRs prevent the same debates from happening repeatedly and create a traceable history of why the codebase is the way it is.

---

## When to Create an ADR

The Architect MUST create an ADR when the decision:
- Affects how multiple parts of the system interact.
- Commits the project to a specific technology or pattern.
- Has trade-offs that future developers would need to understand.
- Replaces or reverses a previous decision.

Skip ADRs for low-risk, reversible, or purely tactical decisions (e.g., "rename this variable", "add a utility function").

---

## Storage

ADRs are stored in `.agents/decisions/`:

```
.agents/
  decisions/
    ADR-001-use-jwt-for-auth.md
    ADR-002-postgresql-over-mongodb.md
    ADR-003-deprecate-v1-api.md
```

File naming: `ADR-NNN-short-title-kebab-case.md`  
Number: sequential, zero-padded to 3 digits.

---

## Template

```markdown
# ADR-NNN: <Title>

**Date:** YYYY-MM-DD
**Status:** Proposed | Accepted | Deprecated | Superseded by ADR-NNN
**Author:** Architect (session YYYY-MM-DD)

---

## Context

<Describe the problem, forces at play, and why a decision is needed now. 2-5 sentences.>

## Decision

<State the decision clearly and directly. Start with "We will..." or "The system will...". 1-3 sentences.>

## Alternatives Considered

| Option | Pros | Cons |
|--------|------|------|
| Option A (chosen) | + fast, + simple | - limited scale |
| Option B | + more flexible | - high complexity |
| Option C | + standard | - not supported by X |

## Consequences

**Positive:**
- <Benefit 1>
- <Benefit 2>

**Negative / Trade-offs:**
- <Trade-off 1>
- <Trade-off 2>

**Neutral:**
- <Side effect with no clear valence>

## Related Decisions

- Supersedes: ADR-NNN (if applicable)
- Related to: ADR-NNN (if applicable)
```

---

## Procedure

### Creating an ADR

1. Architect determines an ADR is needed (see "When to Create an ADR").
2. Find the next sequential number by checking `.agents/decisions/` (or start at ADR-001).
3. Fill the template.
4. Save to `.agents/decisions/ADR-NNN-title.md`.
5. Reference the ADR in the Architect's plan under Constraints or Risks.
6. Maestro includes the ADR file in the git commit.

### Updating an ADR Status

- When a decision is reversed: mark old ADR as `Superseded by ADR-NNN`, create new ADR.
- When a decision is deprecated: mark as `Deprecated`, note reason.
- **Never edit** an accepted ADR's Decision or Context retroactively. Append a new ADR instead.

---

## Examples

### ✅ Good — complete ADR with context, decision, and alternatives

```markdown
# ADR-002: PostgreSQL over MongoDB for user and subscription data

**Date:** 2026-02-15
**Status:** Accepted

## Context
We need a database for user accounts and subscription records. The data is relational
(users → subscriptions → plans) and consistency is critical for billing.

## Decision
We will use PostgreSQL via Prisma. All relational data lives in a single Postgres instance.

## Alternatives Considered
| Option | Pros | Cons |
|--------|------|------|
| PostgreSQL (chosen) | ACID, Prisma support, relational | Harder to scale horizontally |
| MongoDB | Flexible schema | No joins, inconsistency risk for billing |

## Consequences
Positive: Strong consistency for billing, type-safe queries with Prisma.
Negative: Schema migrations required for structural changes.
```

### ❌ Bad — incomplete ADR, decision without rationale

```markdown
# ADR-002: Use PostgreSQL

We decided to use PostgreSQL.
```

This is bad because: no context, no alternatives, no trade-offs — in 6 months, no one (including AI agents) knows why this decision was made or what was rejected.

---

## Guardrails

- ADRs are append-only. Never delete an ADR, even if the decision was wrong.
- Keep the Decision section to 3 sentences max. If it needs more, split into multiple ADRs.
- Alternatives Considered is required. An ADR with only the chosen option is incomplete.
- The Architect writes ADRs. The Reviewer may flag missing ADRs in the review checklist.
- Link from code comments when practical: `// See ADR-002 for why we chose PostgreSQL`.
