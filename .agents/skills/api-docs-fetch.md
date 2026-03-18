shortDescription: How to fetch current API/SDK documentation before writing integration code.
usedBy: [coder, architect]
version: 1.0.0
lastUpdated: 2026-03-18
copyright: Rodrigo Canuto © 2026.

## When to Use

**Triggers:**
- Coder is about to implement an integration with a third-party API or SDK (Stripe, Supabase, OpenAI, etc.)
- Architect is planning a feature that depends on external service capabilities
- Any persona is unsure about the current API signature, parameters, or behavior of an external library

**Not for:**
- Internal project code — use `.context.md` and `FEATURE-MAP.md` instead
- Libraries already well-documented in the project's own codebase
- Quick utility functions that don't involve external API calls

---

## Purpose

Prevent API hallucination by fetching current, versioned documentation before writing integration code. Uses [Context Hub](https://github.com/andrewyng/context-hub) (`chub` CLI) to search, retrieve, and annotate third-party API docs — so the agent works with real, up-to-date references instead of memorized (and often outdated) API shapes.

Works alongside `stack-lock` (which controls approved dependencies) and `cli-usage` (which governs command execution).

---

## Prerequisites

Context Hub CLI must be installed globally:

```bash
npm install -g @aisuite/chub
```

Verify with `chub --version`. If not installed, ask the user to install it before proceeding.

---

## Procedure

### 1. Search for Documentation

Before writing any code that calls an external API or SDK:

```bash
chub search "<library-or-service-name>" --json
```

Examples:
```bash
chub search "stripe payments"      # find Stripe docs
chub search "supabase auth"        # find Supabase Auth docs
chub search "openai chat"          # find OpenAI Chat API docs
```

If no results are found, proceed with caution and flag uncertainty: `[UNCERTAIN] — No chub docs available for <library>. Using training knowledge — verify before shipping.`

### 2. Fetch the Documentation

Once you have the doc ID from search results:

```bash
chub get <doc-id> --lang ts        # fetch TypeScript version
chub get <doc-id> --lang py        # fetch Python version
chub get <doc-id> --file ./temp    # save to file for reference
```

- Always specify `--lang` matching the project's language.
- Read the fetched content thoroughly before implementing.
- Do **not** rely on memorized API shapes — use the fetched doc as the source of truth.

### 3. Implement Using the Fetched Docs

- Use exact function signatures, parameter names, and types from the docs.
- If the doc shows a specific import path, use that exact path.
- If the doc mentions required configuration (API keys, headers, base URLs), ensure they are set up following the `security-practices` skill.

### 4. Annotate Discoveries

When you discover something not covered in the docs (a gotcha, workaround, version quirk, or undocumented behavior):

```bash
chub annotate <doc-id> "description of the discovery"
```

Examples:
```bash
chub annotate stripe/api "Webhook verification requires raw body — do not parse before verifying"
chub annotate supabase/auth "signInWithOAuth redirect URL must be in the allowed list in dashboard"
```

Annotations persist locally and appear automatically on future `chub get` calls — enabling cross-session learning.

### 5. Provide Feedback (Optional)

If a doc was particularly helpful or had issues:

```bash
chub feedback <doc-id> up --label helpful
chub feedback <doc-id> down --label outdated
```

Ask the user before sending feedback upstream.

---

## Integration with Framework Workflow

### For Architect
When planning a feature that involves external APIs:
1. Run `chub search` to verify API capabilities before committing to a design.
2. Reference the doc ID in the plan so the Coder can fetch it directly.
3. Note any API limitations discovered in the plan's "Constraints" section.

### For Coder
When implementing an integration step from the Architect's plan:
1. Check if the plan references a chub doc ID — if so, `chub get` it first.
2. If no doc ID is referenced, run `chub search` before coding.
3. After implementation, annotate any gotchas discovered during coding.
4. In the Implementation Summary, note: `API docs source: chub:<doc-id>` or `API docs source: training knowledge [UNCERTAIN]`.

### For Reviewer
During the Quality Lens review of integration code:
- Check if the Coder's Implementation Summary includes an API docs source.
- If source is `[UNCERTAIN]`, flag as SHOULD FIX — suggest verifying via `chub get`.

---

## Examples

### ✅ Good — fetch docs before implementing Stripe integration

```
1. chub search "stripe checkout" --json
   → Found: stripe/checkout (v2024.12)

2. chub get stripe/checkout --lang ts
   → Fetched: Stripe Checkout Session API reference

3. Implemented using exact createCheckoutSession() signature from docs

4. Discovered: redirect URL must use absolute path, not relative
   → chub annotate stripe/checkout "redirect URL must be absolute (https://...), relative paths cause silent failure"

5. Implementation Summary: API docs source: chub:stripe/checkout
```

Uses chub to verify the API before coding, annotates a discovery for future sessions.

### ❌ Bad — implement from memory without verification

```
1. Wrote Stripe integration using remembered API shape
2. Used stripe.checkout.sessions.create() with wrong parameter name
3. Test failed because 'success_url' was passed as 'successUrl' (camelCase vs snake_case)
```

This is bad because: relied on training knowledge instead of fetching current docs. The snake_case parameter name is in the official docs but the LLM hallucinated camelCase.

---

## Guardrails

- Do not assume `chub` is installed. Check first, ask user to install if missing.
- Do not send feedback upstream without user approval.
- Do not use `chub` for internal project documentation — it's for third-party APIs only.
- If `chub search` returns no results, explicitly flag `[UNCERTAIN]` in the implementation summary.
- Annotations are local-only. They do not modify the upstream documentation.
- Follow `cli-usage` skill rules when executing `chub` commands (explain before running, ask confirmation for first use).
