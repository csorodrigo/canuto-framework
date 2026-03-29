# Domain: Payments & Financial Logic

Keywords: payment, stripe, billing, subscription, invoice, refund, checkout, price, currency, tax, charge, plan, pricing

lastReviewed: 2026-03-29

## Pitfall: Floating Point Currency

**Trigger:** Storing or calculating monetary amounts
**Common mistake:** Using float/double for currency (`price: 19.99` as a float)
**Correct approach:** Store currency as integers in the smallest unit (cents). `$19.99` = `1999` cents. Use Decimal/BigDecimal types if fractions are needed. Never use float for money — `0.1 + 0.2 !== 0.3` causes real billing discrepancies.

## Pitfall: Stripe Webhook Event Ordering

**Trigger:** Processing Stripe webhook events (payment_intent, subscription, invoice)
**Common mistake:** Assuming events arrive in chronological order
**Correct approach:** Events can arrive out of order or duplicated. Use the `created` timestamp and event ID for ordering. Always fetch the latest object state from Stripe API rather than relying solely on webhook payload. Implement idempotency using event ID.

## Pitfall: Missing Idempotency Key

**Trigger:** Creating charges, subscriptions, or any payment mutation
**Common mistake:** Not using idempotency keys, risking double charges on retries
**Correct approach:** Always pass an idempotency key to Stripe (or equivalent) for create operations. Generate from deterministic data (e.g., `user_id:action:timestamp_bucket` or `order_id`). This prevents double charges from network retries, user double-clicks, or webhook reprocessing.

## Pitfall: Price Display Without Locale

**Trigger:** Showing prices to users in the UI
**Common mistake:** Hardcoding `$` symbol or formatting (e.g., `$1,000.00`)
**Correct approach:** Use `Intl.NumberFormat` with the user's locale and the correct currency code. Different locales format differently: `$1,000.00` (US) vs `1.000,00 $` (Brazil) vs `1 000,00 $` (France).

## Pitfall: Subscription State Machine

**Trigger:** Implementing subscription lifecycle (trial → active → past_due → canceled)
**Common mistake:** Treating subscription status as binary (active/inactive), missing intermediate states
**Correct approach:** Model the full state machine: `trialing → active → past_due → unpaid → canceled → expired`. Handle each state in the UI (grace period warnings, reactivation flows). Past-due users should see degraded access, not a hard wall.

## Pitfall: Tax Calculation Responsibility

**Trigger:** Displaying prices or processing payments for users in different jurisdictions
**Common mistake:** Ignoring tax or hardcoding a single tax rate
**Correct approach:** Use Stripe Tax, TaxJar, or equivalent for automatic tax calculation. Tax rules vary by jurisdiction, product type, and customer location. Never hardcode tax rates. For MVP: at minimum, collect and store the customer's billing address for future compliance.
