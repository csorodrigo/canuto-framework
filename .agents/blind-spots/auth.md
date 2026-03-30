# Domain: Authentication & Authorization

Keywords: auth, login, signup, JWT, token, session, password, OAuth, SSO, RBAC, permission, role

lastReviewed: 2026-03-29

## Pitfall: Token Storage in localStorage

**Trigger:** Implementing JWT or session token storage in a browser app
**Common mistake:** Storing tokens in localStorage (accessible to XSS attacks)
**Correct approach:** Use httpOnly cookies for token storage. If localStorage is necessary (SPA with separate API), implement token rotation and short expiry (<15 min for access tokens).

## Pitfall: Password Comparison Timing Attacks

**Trigger:** Implementing login or password verification
**Common mistake:** Using `===` or `==` for password/hash comparison
**Correct approach:** Use constant-time comparison (e.g., `crypto.timingSafeEqual` in Node.js, `hmac.compare_digest` in Python) to prevent timing attacks.

## Pitfall: User Enumeration via Error Messages

**Trigger:** Implementing login or password reset endpoints
**Common mistake:** Returning different messages for "user not found" vs "wrong password"
**Correct approach:** Return the same generic message for both cases: "Invalid credentials." Same for password reset: "If an account exists, a reset email was sent."

## Pitfall: Missing Rate Limiting on Auth Endpoints

**Trigger:** Creating login, signup, or password reset endpoints
**Common mistake:** No rate limiting, allowing brute force attacks
**Correct approach:** Add rate limiting per IP and per account. Suggested: 5 attempts per minute per IP, 20 per hour per account. Use exponential backoff or account lockout after threshold.

## Pitfall: Refresh Token Reuse

**Trigger:** Implementing token refresh flow
**Common mistake:** Allowing refresh tokens to be used multiple times
**Correct approach:** Implement refresh token rotation — each refresh issues a new refresh token and invalidates the old one. Detect reuse (same refresh token used twice) as a potential compromise and invalidate all tokens for that user.

## Pitfall: OAuth State Parameter

**Trigger:** Implementing OAuth/SSO login flow
**Common mistake:** Omitting the `state` parameter in OAuth redirect
**Correct approach:** Always include a cryptographically random `state` parameter and verify it on callback. This prevents CSRF attacks on the OAuth flow.

## Pitfall: Authorization != Authentication

**Trigger:** Adding access control to resources
**Common mistake:** Checking only if user is logged in, not if they have permission for the specific resource
**Correct approach:** Always verify both authentication (who are you?) AND authorization (can you access this specific resource?). Check resource ownership or role permissions on every request, not just the presence of a valid token.
