# Decisions Log

> Append-only log of architectural and business decisions made across sessions.
> Each entry records WHAT was decided, WHY, and WHEN.
> This file saves tokens by preventing re-discussion of settled topics.

---

<!-- Append new decisions below this line. Do not delete previous entries. -->

<!-- Example format:

## 2026-02-25 — JWT over session cookies for auth

**Context:** Needed to choose an authentication strategy for the API.
**Decision:** Use JWT with short-lived access tokens (15min) and long-lived refresh tokens (7d).
**Reason:** Stateless auth simplifies horizontal scaling. Refresh tokens mitigate short expiry UX.
**Trade-offs:** Revocation requires a blocklist. Accepted for now; revisit if abuse is detected.

-->
