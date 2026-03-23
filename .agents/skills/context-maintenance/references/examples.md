# Examples — context-maintenance

## .context.md

### ✅ Good — complete, useful

```markdown
<context path="src/auth" updated="2026-03-01">

Handles all authentication logic: JWT generation, validation, and session refresh.
This directory owns the auth contract — no other directory should duplicate token logic.

## Summary

- token-service.ts – generates and verifies JWTs using the configured secret.
- auth-middleware.ts – Express middleware that attaches decoded user to req.user.
- session-store.ts – manages refresh token persistence via Redis.

## Constraints

- MUST NOT store tokens in localStorage — use httpOnly cookies only.
- MUST throw InvalidTokenError (never return null) on verification failure.

## Guidance

- SHOULD use short-lived access tokens (15min) with long-lived refresh tokens (7d).

</context>
```

Orients the next agent instantly: what lives here, what the rules are, what each file does.

### ❌ Bad — vague, useless

```markdown
# Auth

This folder contains authentication files.
```

Tells the agent nothing specific, doesn't list files, has no constraints — the next agent reads raw source anyway.

---

## repo-index.json Entity

### ✅ Good — rich, searchable

```json
{
  "name": "authMiddleware",
  "type": "middleware",
  "file": "src/auth/middleware.ts",
  "line": 8,
  "tags": ["auth", "express", "guard", "jwt-validation"],
  "dependencies": ["external:express", "generateToken", "config.jwtSecret"],
  "dependents": ["createPayment", "getUserProfile", "updateSettings"]
}
```

Precise location, specific tags, clear dependency chain. Any persona can find this instantly.

### ❌ Bad — vague, untagged

```json
{
  "name": "middleware",
  "type": "function",
  "file": "src/auth/middleware.ts",
  "line": 1,
  "tags": ["middleware"],
  "dependencies": [],
  "dependents": []
}
```

Generic name, single vague tag, no dependencies mapped — provides no more value than reading the raw file.
