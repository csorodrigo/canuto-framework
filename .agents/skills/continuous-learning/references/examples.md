# Examples — continuous-learning

## ✅ Good — well-formed instinct extraction

After a session where the /fix flow found that API errors were being swallowed by a try/catch:

```markdown
### I-012 — [debugging] Silent error swallowing in API layer
- **Pattern:** try/catch blocks in src/api/ catch errors but log them without re-throwing
- **Learning:** Always re-throw after logging in API middleware. Check error propagation in any new endpoint.
- **Confidence:** low
- **Source:** Session 2026-03-08 — /fix traced auth failure to swallowed 401 in src/api/middleware/error-handler.ts
- **Applied:** 0
```

## ✅ Good — reinforcement of existing instinct

```
Session Learnings:
- [REINFORCED] I-005 — [testing] Missing edge case: empty array inputs (low → medium)
  Previously seen in: Session 2026-03-01
  Now seen in: Session 2026-03-08 (Reviewer caught missing test for empty cart)
```

## ❌ Bad — too generic

```markdown
### I-099 — [code-pattern] Write good code
- **Pattern:** Code sometimes has bugs
- **Learning:** Write better code
```

Not actionable, not specific to this project, not something a persona can apply.

## ❌ Bad — should be a decision, not an instinct

```markdown
### I-100 — [architecture] Use Zustand for state
- **Pattern:** Need state management
- **Learning:** Use Zustand
```

This belongs in `decisions.md` or `stack.md`. Instincts are about HOW to work, not WHAT to use.
