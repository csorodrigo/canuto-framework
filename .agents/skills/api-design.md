shortDescription: How to design and evolve HTTP/JSON APIs in this project.
usedBy: [architect, coder, reviewer]
version: 1.0.0
lastUpdated: 2026-02-25
copyright: Rodrigo Canuto © 2026.

## When to Use

**Triggers:**
- Architect is designing or reviewing an API endpoint
- A new route, mutation, or action is being added to the project
- A breaking or compatible change to an existing contract is under discussion
- Reviewer is checking that implementation matches the declared contract

**Not for:**
- Tasks that are exclusively frontend with no API contract involved
- Internal refactors that preserve the same public interface and behavior

---

## Purpose

Provide a repeatable way to design, extend, and review APIs (REST/HTTP, JSON, RPC-like endpoints) so that:
- Contracts are explicit.
- Changes are safe and versioned when necessary.
- Different services and clients can interact without surprises.

This skill works both in Canuto projects (context + feature map) and in projects with their own documentation.

---

## Procedure

### 1. Discover the API Context

1. Identify:
   - The domain or feature the API serves.
   - Who consumes it (frontend, external partner, another service).
2. Canuto project:
   - Read the relevant section in `docs/FEATURE-MAP.md`.
   - Read `.context.md` in the controller/handler/service directories involved.
3. Foreign-schema project:
   - Read README, architecture docs, OpenAPI/Swagger, or any equivalent documentation.

### 2. Design or Update the Contract

**For a new API:**

1. Define:
   - Feature name and use case.
   - Endpoint(s):
     - Method (GET/POST/PUT/PATCH/DELETE).
     - Path (e.g., `/v1/orders/{id}`).
2. Define the contract:
   - Request:
     - Path parameters, query parameters, headers, body.
     - Types and validations (required, optional, format).
   - Response:
     - Primary status codes.
     - Payload structure (fields, types).
3. Define errors:
   - Predictable errors with clear codes and formats.
   - Error format (e.g., `error.code`, `error.message`).

**For modifying an existing API:**

1. Classify the change:
   - **Compatible** (backwards compatible): add optional field, new endpoint, new status code.
   - **Potentially breaking**: change field type, remove field, alter semantics.
2. If breaking:
   - Consider:
     - New endpoint version (`/v2/…`) or
     - Feature flag/toggle until client migration.
   - Document clearly in the Architect's plan.

### 3. Align with Implementation

1. Locate the API code based on context:
   - Handlers/controllers.
   - Services/use-cases.
   - Repositories/adapters.
2. Ensure that:
   - Code validates inputs as defined in the contract.
   - Responses follow the contract exactly (field names, types, structure).
3. Verify that:
   - Important logs and metrics are in place.
   - Error responses use the defined format consistently.

---

## Examples

### ✅ Good — well-defined endpoint

```
POST /api/v1/subscriptions
Body: { planId: string, userId: string }
Response 201: { subscriptionId: string, status: "active", createdAt: string }
Response 409: { error: { code: "ALREADY_SUBSCRIBED", message: "User already has an active subscription." } }
Response 422: { error: { code: "INVALID_PLAN", message: "Plan not found or inactive." } }
```

Contract is versioned, fully typed, errors have explicit codes, no ambiguity for the consumer.

### ❌ Bad — vague endpoint

```
POST /api/subscription
Body: { data: any }
Response: { result: any }
```

This is bad because: no versioning, no types, no error codes, no contract — every consumer must guess what to send and what to expect.

---

## Guardrails

- Never change a public API contract without classifying the change (compatible vs breaking).
- Never introduce a new endpoint without defining its full contract (request + response + errors).
- Never return different error formats from different endpoints — enforce a single project-wide error shape.
- Prefer additive changes over modifications to existing fields.
