# Domain: API Design & Integration

Keywords: API, REST, endpoint, GraphQL, webhook, rate limit, pagination, versioning, CORS, fetch, axios, HTTP

lastReviewed: 2026-03-29

## Pitfall: Pagination Without Total Count

**Trigger:** Implementing list/search endpoints that return multiple items
**Common mistake:** Returning all items at once, or paginating without communicating total count or next page
**Correct approach:** Always include pagination metadata: `{ data: [...], total: N, page: P, pageSize: S, hasMore: bool }`. Use cursor-based pagination for large datasets (offset pagination degrades on deep pages).

## Pitfall: Breaking Changes Without Versioning

**Trigger:** Modifying an existing API endpoint's request or response shape
**Common mistake:** Changing field names, removing fields, or changing types without versioning
**Correct approach:** Additive changes are safe (new fields). For breaking changes: version the endpoint (URL prefix `/v2/` or header), maintain the old version during transition, or use field deprecation with a sunset header.

## Pitfall: CORS Wildcard in Production

**Trigger:** Configuring CORS for a web API
**Common mistake:** Setting `Access-Control-Allow-Origin: *` for APIs that use cookies or auth headers
**Correct approach:** Whitelist specific origins. Wildcard CORS cannot be used with `credentials: include`. For development, use a permissive config that switches to strict whitelist in production.

## Pitfall: Webhook Reliability

**Trigger:** Implementing webhook receivers or senders
**Common mistake:** Not handling retries, not verifying signatures, not being idempotent
**Correct approach:** (1) Verify webhook signatures (HMAC). (2) Return 200 immediately, process async. (3) Make processing idempotent (use event ID to deduplicate). (4) If sending webhooks: implement retry with exponential backoff, log delivery status.

## Pitfall: Error Response Inconsistency

**Trigger:** Handling errors across multiple API endpoints
**Common mistake:** Each endpoint returns errors in different formats (some string, some object, some HTTP-only)
**Correct approach:** Define a standard error envelope: `{ error: { code: "VALIDATION_ERROR", message: "...", details: [...] } }`. Use consistent HTTP status codes: 400 (validation), 401 (auth), 403 (authz), 404 (not found), 409 (conflict), 422 (unprocessable), 500 (server error).

## Pitfall: Overfetching in API Responses

**Trigger:** Designing response payloads for entities with relationships
**Common mistake:** Returning the full entity graph (user → posts → comments → users → ...) causing response bloat
**Correct approach:** Return only the fields needed for the consumer. Use field selection (`?fields=id,name`), sparse fieldsets (JSON:API), or GraphQL for flexible queries. For REST: design endpoint-specific DTOs rather than dumping the ORM model.
