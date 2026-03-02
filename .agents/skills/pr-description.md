shortDescription: Auto-generate pull request descriptions based on session handoffs and review results.
usedBy: [reviewer]
version: 1.0.0
lastUpdated: 2026-02-25
copyright: Rodrigo Canuto © 2026.

## Purpose

Eliminate the manual step of writing PR descriptions. After a review cycle, the Reviewer generates a ready-to-paste PR body based on the Architect's plan, Coder's changes, Tester's results, and the review verdict.

---

## When to Use

**Triggers:**
- Review verdict is **APPROVE** — Reviewer generates the PR description automatically
- Maestro explicitly requests it: `"Generate PR description"`

**Not for:**
- Mid-review (wait for APPROVE verdict or explicit request)
- Tasks that are not going through a PR workflow

---

## Template

```markdown
## Summary

<1-3 sentences describing what this PR does and why.>

## Changes

- `path/to/file.ts` — <what changed and why>
- `path/to/other.ts` — <what changed and why>

## Type of Change

- [ ] Bug fix
- [ ] New feature
- [ ] Refactoring (no behavior change)
- [ ] Breaking change
- [ ] Documentation update

## Testing

<Describe how the changes were tested. Reference specific test files if available.>

## Breaking Changes

<List any breaking changes and migration steps. Write "None" if not applicable.>

## Notes for Reviewer

<Any context that would help a human reviewer understand the decisions made.>
```

---

## Procedure

1. **Collect from the session:**
   - Architect's plan: goal, steps, constraints.
   - Coder's changed files and deviations.
   - Tester's results.
   - Reviewer's MUST FIX items resolved, final verdict.

2. **Fill the template:**
   - Summary: distill from the Architect's goal (1-3 sentences max).
   - Changes: one bullet per file from the Coder's summary.
   - Type of change: infer from the plan (new feature? fix? refactor?).
   - Testing: summarize Tester's results.
   - Breaking changes: extract from Architect's plan Constraints/Risks.
   - Notes: include relevant deviations or escalation context.

3. **Output** the filled template as a fenced markdown block labeled **`PR Description`**.

---

## Examples

### ✅ Good — specific, traceable PR description

```markdown
## Summary
Adds JWT refresh token rotation to prevent replay attacks. Tokens are now
invalidated immediately after use and replaced with a new token on each refresh.

## Changes
- `src/auth/token-service.ts` — added rotateRefreshToken() method with invalidation
- `src/api/routes/auth.ts` — updated /refresh endpoint to return new token pair

## Testing
Unit tests added in `src/auth/__tests__/token-service.test.ts`.
Integration test covers full rotation cycle (happy path + replay attempt).
```

### ❌ Bad — vague, framework-leaking PR description

```markdown
## Summary
Maestro delegated to Architect who planned 4 steps. Coder implemented them.
Reviewer approved after 1 rework cycle.

## Changes
- Made some auth changes
```

This is bad because: exposes internal framework details (Maestro, Architect), no file references, no test information — useless for a human reviewer or future git blame.

---

## Guardrails

- The PR description is a suggestion — the user reviews and pastes it. Never push or submit automatically.
- Keep Summary to 3 sentences max. If it needs more, it's too complex for one PR.
- Never include internal framework details (persona names, handoff logs) in the PR description.
- If the session included multiple tasks, generate one description per task or ask Maestro which task to describe.
- If Tester was not invoked, write "Manual testing" in the Testing section and flag it.
