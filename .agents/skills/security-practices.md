shortDescription: Rules for handling secrets, environment variables, and security-sensitive code.
usedBy: [coder, reviewer, architect, tester]
version: 1.0.0
lastUpdated: 2026-02-25
copyright: Rodrigo Canuto © 2026.

## Purpose

Prevent accidental exposure of secrets and enforce security hygiene across all personas. This skill is referenced by Coder (when implementing), Reviewer (when checking), and Tester (when writing security tests).

---

## Procedure

### 1. Secrets Management

**Never commit secrets.** This includes:
- API keys, tokens, passwords.
- Database connection strings with credentials.
- Private keys, certificates.
- OAuth client secrets.
- Any value that would be different between environments.

**Required pattern:**
- Use `.env` files for local development (always in `.gitignore`).
- Provide a `.env.example` with placeholder values and comments.
- Reference environment variables in code via `process.env.VARIABLE_NAME` (or equivalent).

### 2. .gitignore Rules

Every project MUST have these entries in `.gitignore`:
```
.env
.env.local
.env.*.local
*.pem
*.key
credentials.json
service-account.json
```

### 3. Code Patterns

**Input validation:**
- Validate and sanitize all user inputs at the boundary (API handler, form submission).
- Never trust client-side validation alone.

**Authentication:**
- Never store passwords in plain text. Use bcrypt or argon2.
- Never log tokens, passwords, or sensitive headers.
- Use short-lived tokens with refresh mechanisms when possible.

**Error handling:**
- Never expose stack traces or internal error details to end users.
- Log detailed errors server-side; return generic messages to clients.
- Never include sensitive data in error messages.

**Dependencies:**
- Flag any new dependency that handles crypto, auth, or network.
- Prefer well-maintained libraries with active security advisories.

### 4. Review Checklist

The Reviewer MUST check:
- [ ] No hardcoded secrets in code, configs, or comments.
- [ ] `.env.example` exists and is up to date.
- [ ] Sensitive files are in `.gitignore`.
- [ ] User inputs are validated at the boundary.
- [ ] Error responses do not leak internal details.
- [ ] No sensitive data in logs.

---

## Guardrails

- If you find a secret in committed code, flag it immediately. Do not just remove it — the git history still has it.
- Never generate or suggest real API keys or passwords, even as examples. Use obvious placeholders like `your-api-key-here`.
- When in doubt about whether something is sensitive, treat it as sensitive.
