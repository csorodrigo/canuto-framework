shortDescription: Branching strategy, commit conventions, and PR practices.
usedBy: [coder, reviewer, maestro]
version: 1.0.0
lastUpdated: 2026-02-25
copyright: Rodrigo Canuto © 2026.

## Purpose

Standardize how Git is used across projects so that:
- History is readable and meaningful.
- Branches are predictable and short-lived.
- PRs are reviewable and well-documented.

This skill is opt-in. Each project can enable it via CLAUDE.md.

---

## Procedure

### 1. Commit Messages

Follow **Conventional Commits** format:

```
<type>(<scope>): <description>

[optional body]

[optional footer]
```

**Types:**
- `feat` — new feature.
- `fix` — bug fix.
- `refactor` — code change that neither fixes a bug nor adds a feature.
- `docs` — documentation only.
- `test` — adding or fixing tests.
- `chore` — maintenance (deps, configs, CI).
- `style` — formatting, whitespace (no logic change).
- `perf` — performance improvement.

**Rules:**
- Subject line: imperative mood, lowercase, no period, max 72 characters.
- Body: explain WHY, not WHAT (the diff shows what).
- Footer: reference issues (`Closes #42`, `Fixes #13`).

**Examples:**

Good:
```
feat(auth): add JWT refresh token rotation

Refresh tokens are now rotated on each use to prevent replay attacks.
Old tokens are invalidated immediately after rotation.

Closes #42
```

Bad:
```
updated auth stuff
```

### 2. Branching

**Branch naming:**
```
<type>/<short-description>
```

Examples:
- `feat/user-auth`
- `fix/token-expiry-bug`
- `refactor/api-error-handling`
- `docs/update-readme`

**Rules:**
- Branch from `main` (or the project's default branch).
- Keep branches short-lived (ideally < 3 days).
- Delete branches after merge.

### 3. Pull Requests

**PR title:** Same format as commit message subject line.

**PR body template:**
```markdown
## Summary
Brief description of what this PR does and why.

## Changes
- List of notable changes.

## Testing
- How this was tested.
- [ ] Unit tests pass.
- [ ] Manual testing done for <scenario>.

## Related
- Closes #<issue>
- Relates to #<issue>
```

**Rules:**
- One logical change per PR.
- Keep PRs reviewable (< 400 lines when possible).
- Request review from a persona different from the one that coded.

---

## Guardrails

- Never force-push to `main` or shared branches.
- Never commit directly to `main` — always use branches + PRs.
- Never merge your own PR without review (even in solo projects, the Reviewer persona reviews).
- Never amend published commits on shared branches.
