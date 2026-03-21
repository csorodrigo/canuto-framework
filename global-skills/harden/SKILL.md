shortDescription: Production resilience — edge cases, text overflow, i18n, error handling, and accessibility robustness.
usedBy: [user]
version: 1.0.0
lastUpdated: 2026-03-20

## Purpose

Designs work perfectly with demo data. Production is different: users have 60-character names, translations are 40% longer than English, API calls fail, and people use phones in low-bandwidth areas. `/harden` improves the resilience of a UI against real-world conditions that happy-path demos never test.

Pairs with the Tester persona's unit/integration test coverage — while Tester validates logic, `/harden` validates UX resilience.

## When to Use

- Before shipping any feature that handles user-generated content
- Before internationalizing the product
- After `/polish` — to check that the polished state holds under stress
- When the user reports visual bugs in production that didn't appear in development

## Procedure

### Pass 1 — Text Overflow & Variable Length

Test every text element with edge case inputs:

| Test | What to look for |
|------|-----------------|
| 60-character user name | Does it overflow its container? Use `truncate` or `text-ellipsis overflow-hidden` |
| 3-line description | Does card height grow gracefully, or does it break the grid layout? |
| 1-word description | Does the layout look broken with very short content? |
| Empty string | Does the element collapse, show whitespace, or display an empty state? |
| Special characters: `<script>`, `&amp;`, emoji 🎉, RTL text | Does the UI escape/render correctly? |

**Fixes:**
```tsx
// Truncate single line
<p className="truncate">{name}</p>

// Multi-line clamp (CSS)
<p className="line-clamp-3">{description}</p>

// Flexible card height (grid approach)
<div className="grid grid-rows-[auto_1fr_auto] h-full">
  <CardHeader />
  <CardBody />  {/* stretches to fill */}
  <CardFooter />
</div>
```

### Pass 2 — Internationalization (i18n)

- **Text expansion:** German and Finnish translations are often 30–40% longer than English. Test layouts with 40% more text.
- **RTL languages (Arabic, Hebrew):** Ensure `dir="rtl"` is applied at the root. CSS logical properties (`ms-`, `me-`, `ps-`, `pe-`) handle RTL automatically; avoid `ml-`, `mr-` for layout.
- **Date/number formatting:** Never hardcode `"/"` as date separator or `","` as thousands separator. Use `Intl.DateTimeFormat` and `Intl.NumberFormat`:

```ts
// ✅ Locale-aware
new Intl.DateTimeFormat(locale, { dateStyle: 'medium' }).format(date)
new Intl.NumberFormat(locale, { style: 'currency', currency: 'USD' }).format(amount)

// ❌ Hardcoded format
`${date.getMonth() + 1}/${date.getDate()}/${date.getFullYear()}`
```

- **CJK characters (Chinese, Japanese, Korean):** These are wider per character. Test that character-count-limited fields (like username max-length) account for this.

### Pass 3 — Error Handling

Every async operation must handle failures gracefully:

| Scenario | Required UX |
|----------|------------|
| Network timeout | Show inline error + retry button. Not just a toast. |
| API 4xx (bad request) | Show specific helpful message. Not "Something went wrong". |
| API 5xx (server error) | Show "Try again" with retry action. Log to error monitoring. |
| Empty response | Show empty state component. Not a blank area. |
| Partial data | Show what loaded, indicate what's missing. |

```tsx
// Error state pattern
{isError && (
  <div className="rounded-lg border border-red-200 bg-red-50 p-4 dark:border-red-800 dark:bg-red-950">
    <p className="text-sm text-red-700 dark:text-red-300">
      {error.message || "Couldn't load data. Check your connection."}
    </p>
    <button onClick={retry} className="mt-2 text-sm font-medium text-red-700 underline">
      Try again
    </button>
  </div>
)}
```

### Pass 4 — Form & Input Validation

- Client-side validation for immediate feedback (format checks, required fields)
- **Always** server-side validation — never trust client only
- Validation messages inline (below the field), not only in a toast or alert
- Disable submit while submitting — prevent double-submit
- Clear form state after successful submission

```tsx
<Input
  aria-invalid={!!errors.email}
  aria-describedby={errors.email ? "email-error" : undefined}
/>
{errors.email && (
  <p id="email-error" className="mt-1 text-sm text-red-600" role="alert">
    {errors.email.message}
  </p>
)}
```

### Pass 5 — Concurrent & Race Condition Scenarios

- Search/filter: if two searches fire quickly, does the UI show results from the second query, not the first?
- Loading states: does clicking a button twice submit twice? (Add `disabled` while loading)
- Stale data: after a network error, does the UI still show the last-known data correctly?

### Pass 6 — Performance Under Realistic Data

- What happens with 1000 items in a list? (Use virtualization: `@tanstack/react-virtual`)
- What happens with a 10MB image upload?
- What happens on a slow 3G connection? (Test via Chrome DevTools → Network throttling)

### Pass 7 — Accessibility Resilience

- Zoom to 200%: does layout remain usable (no overflow, no overlapping elements)?
- High contrast mode: are all elements still distinguishable?
- Screen reader: do all interactive elements have labels? (`aria-label`, `aria-labelledby`, or visible text)

## Rules

- Hardened UIs work with 0 items, 1 item, and 1000 items.
- Every network operation has at least 3 states: loading, success, error.
- Error messages tell the user what happened AND what to do next.
- Never skip i18n pass for products with any international user base.
- Coordinate with Tester persona for validation edge cases — Tester writes the regression tests, `/harden` identifies the scenarios.
