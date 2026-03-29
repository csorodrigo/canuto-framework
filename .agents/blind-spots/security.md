# Domain: Security & Infrastructure

Keywords: security, CORS, CSP, headers, secrets, env, encryption, HTTPS, TLS, certificate, firewall, WAF, OWASP, vulnerability, CVE, dependency

lastReviewed: 2026-03-29

## Pitfall: Secrets in Git History

**Trigger:** Any task involving API keys, tokens, passwords, or connection strings
**Common mistake:** Committing secrets, then "fixing" by removing them in a new commit (they remain in git history)
**Correct approach:** Use `.env` files (gitignored) and environment variables. If a secret was ever committed: rotate it immediately (generate new key), then use `git filter-branch` or BFG Repo-Cleaner to purge history. Prevention: pre-commit hooks that scan for secret patterns.

## Pitfall: Missing Content Security Policy

**Trigger:** Deploying a web application that serves HTML
**Common mistake:** No CSP headers, allowing any script to execute (XSS has no defense-in-depth)
**Correct approach:** Add Content-Security-Policy header. Start with `default-src 'self'` and add exceptions as needed. Use nonces for inline scripts. CSP is the last line of defense when input sanitization fails.

## Pitfall: Dependency Supply Chain

**Trigger:** Adding new npm/pip/cargo packages
**Common mistake:** Installing packages without checking: maintenance status, download count, recent security advisories
**Correct approach:** Before adding a dependency: (1) check last publish date (>1 year = risk), (2) check for known vulnerabilities (`npm audit`, `pip-audit`), (3) prefer well-maintained packages with many dependents, (4) pin exact versions in lockfile.

## Pitfall: Error Messages Leaking Internal State

**Trigger:** Implementing error handling for production
**Common mistake:** Returning stack traces, SQL errors, or file paths in API error responses
**Correct approach:** Log detailed errors server-side (Sentry, CloudWatch). Return generic error messages to the client: "An unexpected error occurred" with a correlation ID for support. Never expose: database names, table structures, file paths, stack traces, or internal IPs.

## Pitfall: SSRF via User-Controlled URLs

**Trigger:** Features that accept URLs from users (image upload from URL, webhooks, link preview)
**Common mistake:** Fetching user-supplied URLs without validation (allows access to internal services: `http://169.254.169.254` for cloud metadata)
**Correct approach:** Validate URLs against an allowlist of domains/protocols. Block private IP ranges (10.x, 172.16-31.x, 192.168.x, 169.254.x, localhost). Use a dedicated service/proxy for fetching external URLs.

## Pitfall: Insecure Direct Object Reference (IDOR)

**Trigger:** API endpoints that accept resource IDs in URL or body (e.g., `/api/users/123/settings`)
**Common mistake:** Trusting the ID parameter without verifying the authenticated user owns/can access that resource
**Correct approach:** Always verify authorization: `WHERE id = :resourceId AND owner_id = :authenticatedUserId`. Use UUIDs instead of sequential IDs to make enumeration harder (defense in depth, not replacement for auth checks).
