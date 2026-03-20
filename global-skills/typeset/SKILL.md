shortDescription: Focused typography audit and improvement — fonts, hierarchy, scale, readability, and pairing.
usedBy: [user]
version: 1.0.0
lastUpdated: 2026-03-20

## Purpose

Typography carries the majority of a UI's information. Good typography is invisible — it just works. Bad typography is immediately distracting. `/typeset` provides a systematic typography assessment and improvement plan: font choices, size hierarchy, weight contrast, line length, and pairing strategy.

Typography is the **highest-leverage** design improvement for most UIs — a well-set page feels premium regardless of other design elements.

## When to Use

- After implementing any page or feature with significant text content
- When `/audit` flags typography issues
- When the design profile specifies a font pair but the output still looks generic
- When the user says "it looks flat" or "it doesn't feel premium" — typography is often the culprit

## Procedure

### Step 1 — Font Audit

Review what fonts are currently in use:

**Red flags:**
- Inter, Roboto, Arial, Open Sans, system-ui as the primary font in a premium or creative context → Replace
- Monospace font used as "technical" aesthetic without genuine code content → Replace
- More than 2–3 distinct font families → Simplify
- Font not loading (falling back to system font) → Fix the import in `tailwind.config.ts`

**Check against `design-profile.md`:**
- Does the current font match the approved heading font and body font?
- If the profile doesn't specify fonts, make a recommendation based on the brand personality adjectives

**Font pairing principles:**
- High contrast pairings work best: a distinctive display/heading font + a neutral body font
- Same-family pairings (e.g., Fraunces + Literata) work for editorial; avoid for SaaS
- Avoid pairing two similar-weight sans-serifs (e.g., Inter + DM Sans) — barely noticeable difference

### Step 2 — Size Scale Audit

Check the heading hierarchy:

```
Ideal scale (noticeable jumps):
text-xs (12px) — labels, captions
text-sm (14px) — secondary body, metadata
text-base (16px) — primary body copy
text-lg (18px) — lead text, featured body
text-2xl (24px) — section headings, card titles
text-4xl (36px) — page sub-headings
text-6xl (60px) — hero headings

Bad scale (muddy hierarchy):
text-sm / text-base / text-lg for heading levels — differences too subtle
```

Issues to fix:
- Heading levels too close in size (< 4px difference between adjacent levels) → Increase jump
- H1 is not significantly larger than H2 → Amplify
- All body text same size regardless of role (primary vs. secondary) → Differentiate

### Step 3 — Weight Contrast Audit

```
Target contrast:
Body: font-light (300) or font-normal (400)
Subheadings: font-semibold (600)
Headings: font-bold (700) or font-extrabold (800) or font-black (900)

Problem patterns:
font-medium (500) for everything — almost no contrast, flat appearance
font-semibold body text — too heavy for reading comfort
font-normal headings + font-normal body — no differentiation
```

### Step 4 — Line Length

- Body copy: 45–75 characters per line. Use `max-w-prose` (65ch) or explicit `max-w-[75ch]`
- Too wide (> 85ch) → Add `max-width` constraint
- Too narrow (< 40ch, especially on desktop) → Check if container is too constrained

### Step 5 — Responsive Typography

For marketing/content pages: use fluid type with `clamp()`:
```css
font-size: clamp(2rem, 5vw, 4rem); /* heading */
font-size: clamp(1rem, 2vw, 1.25rem); /* body */
```

For app UIs: use fixed `rem` scales (fluid type creates inconsistency in dense UI).

Tailwind fluid type (via `tailwindcss-fluid-type` plugin or manual config):
```js
// tailwind.config.ts
fontSize: {
  'fluid-sm': 'clamp(0.875rem, 2vw, 1rem)',
  'fluid-base': 'clamp(1rem, 2.5vw, 1.125rem)',
  'fluid-lg': 'clamp(1.25rem, 3vw, 1.5rem)',
}
```

### Step 6 — Line Height & Letter Spacing

- Body text: `leading-relaxed` (1.625) for comfortable reading, `leading-normal` (1.5) minimum
- Headings: `leading-tight` (1.25) or `leading-none` (1) for large display type
- Large headings (> `text-4xl`): `tracking-tight` or `tracking-tighter` — large type needs tighter tracking
- All-caps labels: `tracking-widest` — uppercase text always needs letter spacing

### Step 7 — Recommendations Output

```
## Typography Report

### Font changes
- [ ] Replace Inter with [recommended font] — reason: [brand mismatch / premium context]
- [ ] Add [display font] for headings per design-profile

### Scale changes
- [ ] Increase H1 from text-4xl to text-6xl — H1 and H2 currently too close in size
- [ ] Differentiate secondary body (text-sm font-light) from primary body (text-base font-normal)

### Weight changes
- [ ] Replace font-medium body with font-normal — reduces visual weight appropriately

### Readability
- [ ] Add max-w-prose to article content — lines currently 95ch (too wide)
- [ ] Switch body from leading-normal to leading-relaxed

### Implementation
Updated tailwind.config.ts:
[code snippet with font family definitions]
```

## Rules

- Body text must be ≥ 16px (`text-base`). No exceptions.
- Line length must be constrained for any paragraph of > 2 lines.
- Update `tailwind.config.ts` with font definitions — never use `@import url(...)` inline in components.
- After making font changes, verify they appear in production (check network tab for font loading).
- Reference `design-profile.md` for the approved font pair before recommending new fonts.
