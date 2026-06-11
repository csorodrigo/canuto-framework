shortDescription: Personas explicitly report what they searched and did NOT find, eliminating silence ambiguity.
usedBy: [maestro, architect, coder, reviewer]
version: 1.0.0
lastUpdated: 2026-03-18
copyright: Rodrigo Canuto © 2026.
inspiration: pgs-engine (Partitioned Graph Search) — structured absence reporting across knowledge partitions.

## When to Use

**Triggers:**
- Every persona handoff that involves investigation or search (code, docs, APIs, patterns)
- Diagnóstico do fluxo /fix — report what was ruled out, not just what was found
- Architect plan — report alternatives explored and discarded
- Cobertura de testes (Coder) — report scenarios considered but deemed out of scope

**Not for:**
- Trivial handoffs (XS tasks with no investigation needed)
- Simple code edits where nothing was searched

---

## Purpose

Eliminate the ambiguity of silence. Today, when a persona doesn't mention something, Maestro can't tell if:
- (a) it was checked and not found (confirmed absence), or
- (b) it was never checked (unknown gap)

Structured absence reporting makes this distinction explicit, enabling the Maestro to track **coverage** and detect **genuine knowledge gaps** vs. **unexplored territory**.

---

## Concepts

### Confirmed Absence

Something was explicitly searched for but does not exist. High-confidence negative result.

```
[ABSENCE] Searched src/middleware/ for rate-limiting middleware — none found.
```

### Unexplored Territory

Something relevant was identified but not investigated due to scope or time constraints.

```
[NOT CHECKED] Database indexes for the users table — outside current task scope.
```

### Convergent Absence

Multiple personas independently report the same absence. Strong signal of a genuine gap.

```
[CONVERGENT ABSENCE] Both Architect and Coder report: no error handling strategy for external API failures.
```

---

## Procedure

### For Personas (Adding Absences to Handoffs)

Every persona handoff that involves investigation MUST include an `## Absences` section after the main content:

```markdown
## Absences

- [ABSENCE] Searched `src/auth/` for refresh token rotation logic — not implemented.
- [ABSENCE] Checked `package.json` for rate-limiting library — none installed.
- [NOT CHECKED] Redis session store configuration — outside scope of this task.
```

**Rules:**
1. Only report absences relevant to the current task
2. Use `[ABSENCE]` for things you searched and confirmed don't exist
3. Use `[NOT CHECKED]` for things you identified as relevant but didn't investigate
4. Include WHERE you searched (file, directory, docs) — make it verifiable
5. Keep each absence to one line

### For Maestro (Aggregating Absences)

When receiving handoffs with absences:

1. **Track absences** across persona handoffs during the session
2. **Detect convergent absences** — if 2+ personas report the same gap, flag it:
   ```
   ⚠️ Convergent absence detected: "no error handling for external API failures"
   Reported by: Architect (planning), Coder (test gaps)
   Consider addressing this gap before continuing.
   ```
3. **Surface critical absences** to the user when they affect task quality
4. **Record persistent absences** in `pending.md` if they represent genuine technical debt

---

## Examples

### ✅ Good — specific, verifiable absence report

```markdown
## Absences

- [ABSENCE] Searched `src/api/middleware/` for authentication middleware — found `auth.ts` but no rate limiting.
- [ABSENCE] Checked Stripe webhook handler in `src/webhooks/` — no idempotency key validation.
- [NOT CHECKED] Load testing configuration — outside scope of auth feature.
```

### ✅ Good — Maestro detecting convergent absence

```
⚠️ Convergent absence: "no input validation on user registration endpoint"
- Architect noted during planning: no validation schema found in src/schemas/
- Coder noted during test writing: no validation tests exist
- Coder noted during implementation: endpoint accepts any payload
Recommendation: Add validation before proceeding with next feature.
```

### ❌ Bad — vague, unverifiable

```markdown
## Absences

- Didn't find much about error handling
- Some things might be missing
```

This is bad because: no specific paths searched, no distinction between confirmed absence and unchecked territory, not actionable.

### ❌ Bad — over-reporting irrelevant absences

```markdown
## Absences

- [ABSENCE] No GraphQL schema found (project uses REST)
- [ABSENCE] No Python files found (project is TypeScript)
- [ABSENCE] No Docker Compose file (not relevant to this task)
```

This is bad because: reporting absences of things that were never expected. Only report absences relevant to the current task.

---

## Guardrails

- **Absences are optional for XS tasks.** Don't add overhead to trivial changes.
- **Quality over quantity.** 2-3 relevant absences are better than 10 irrelevant ones.
- **Never fabricate absences.** Only report what you actually searched for.
- **Absences are not complaints.** They're neutral observations, not criticisms of the codebase.
- **Convergent absences require 2+ independent sources.** Don't flag convergence from a single observation.
- **Maestro decides priority.** Not every absence needs action — some are just noted for coverage tracking.
