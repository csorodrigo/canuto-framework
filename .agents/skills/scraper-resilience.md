shortDescription: Build and debug scrapers with fixtures, selector drift detection, bounded retries, and failure classification.
usedBy: [architect, coder, tester, debugger]
version: 1.0.0
lastUpdated: 2026-04-17
copyright: Rodrigo Canuto © 2026.

## Purpose

Make scraper work reproducible. Scrapers fail when selectors drift, auth changes, rate limits hit, or pages load differently. This skill requires fixtures and failure classification before more retries are added.

---

## Failure Classes

- `selector-drift`: expected element missing or renamed
- `auth-block`: login, token, cookie, captcha, or permission issue
- `rate-limit`: throttling, 429, temporary block
- `network-timeout`: request or browser timeout
- `schema-drift`: parsed data shape changed
- `source-empty`: source page/API returned no data
- `unknown`: not enough evidence yet

---

## Procedure

1. Capture or locate a fixture: HTML, JSON, screenshot, or HAR.
2. Reproduce parsing against the fixture before touching live source.
3. Classify the failure.
4. Add the smallest test that proves the parser behavior.
5. Use bounded retries with explicit stop conditions.
6. Log structured evidence: URL/source, failure class, selector, timestamp, sample item count.
7. Promote reusable lessons into session learning.

---

## Guardrails

- Do not fix scraper bugs only against the live page.
- Do not add infinite or broad retries.
- Do not store secrets, cookies, or tokens in fixtures.
- Do not bypass access controls or anti-abuse systems.
