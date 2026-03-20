shortDescription: Systematic multi-dimensional design quality scan — a11y, performance, responsiveness, and anti-patterns.
usedBy: [user]
version: 1.0.0
lastUpdated: 2026-03-20

## Purpose

Run a systematic quality audit before shipping. Unlike the Reviewer's Design Lens (which checks design-profile adherence), `/audit` evaluates objective quality dimensions: accessibility, performance, responsiveness, theming, and AI slop anti-patterns. It documents issues with severity prioritization but does **not** fix them — audit first, fix second.

## When to Use

- Before shipping any feature with user-facing UI (especially M/L tasks)
- When a design "feels off" but you can't pinpoint why
- After implementing a new page or major component
- As a pre-handoff checklist before a design review

## Procedure

### Phase 1 — Anti-Patterns Check (run first)

Scan the current UI for the most common AI-generated design clichés. If found, these are automatic **Critical** or **High** issues:

| Anti-Pattern | Severity |
|---|---|
| Cyan-on-dark, purple-to-blue gradient, or neon accent palette | Critical |
| Hero metric layout (large number + label + supporting stats row) | High |
| 3-column equal grid with icon + heading + body (feature section) | High |
| Lazy glassmorphism on solid background (no frosted layer underneath) | High |
| Bounce/elastic easing on any animation | High |
| Inter font in premium or creative context | Medium |
| Centered hero with DESIGN_VARIANCE > 4 | Medium |
| Gradient text on main headings | Medium |
| Pure `#000000` black in any surface | Medium |
| Vanilla (uncustomized) shadcn/ui component | Medium |

### Phase 2 — Accessibility Scan

Check these accessibility dimensions:

- **Contrast:** Text on background ≥ 4.5:1 (AA), ≥ 7:1 preferred for body text (AAA)
- **Focus indicators:** All interactive elements must have visible `:focus-visible` rings
- **Touch targets:** Interactive elements ≥ 44×44px on mobile
- **Keyboard navigation:** Can every interactive element be reached and activated via keyboard?
- **Alt text:** All `<img>` elements have meaningful `alt` attributes (empty `alt=""` for decorative images)
- **Color as sole indicator:** Never use color alone to convey state (add icons, patterns, or text)
- **`prefers-reduced-motion`:** All animations must degrade gracefully

### Phase 3 — Responsiveness Scan

- Does layout collapse cleanly at `sm` (640px), `md` (768px), and `lg` (1024px) breakpoints?
- Asymmetric layouts: do they collapse to single-column on mobile (DESIGN_VARIANCE > 4 rule)?
- `h-screen` usage: replaced with `min-h-[100dvh]`?
- Fixed widths: any elements that overflow at narrow viewports?
- Touch targets: ≥ 44×44px on all interactive elements at mobile breakpoints?

### Phase 4 — Theming & Token Consistency

- No hardcoded hex values in components (all colors via CSS custom properties or Tailwind tokens)
- Dark mode: does the feature work correctly with `dark:` variants?
- Missing dark mode variants: which tokens lack `dark:` coverage?
- `design-profile.md` tokens: are all colors/fonts referencing the profile's approved values?

### Phase 5 — Performance Check

- Animating layout properties (`width`, `height`, `top`, `left`, `margin`, `padding`)? Replace with `transform`/`opacity`.
- `will-change: transform` applied to non-animating elements? Remove.
- Noise/grain filters on scrolling containers? Move to fixed `pointer-events-none` pseudo-elements.
- Framer Motion used for simple hover states? Replace with CSS transitions.
- Images without explicit dimensions (causes layout shift)? Add `width`/`height` or `aspect-ratio`.

### Phase 6 — Report

Structure findings as a prioritized issue list:

```
## Audit Report

### Critical (blocks ship)
- [ ] [description] — [location: file:line or component name]

### High (fix before review)
- [ ] [description] — [location]

### Medium (fix in follow-up)
- [ ] [description] — [location]

### Low (nice to fix)
- [ ] [description] — [location]

### Commands to run next
- /critique — for holistic UX evaluation
- /polish — for final spacing/state pass
- /typeset — if typography issues were found
- /animate — if motion issues were found
- /colorize — if palette issues were found
```

## Rules

- Audit = document, not fix. Create the prioritized list, then ask the user how to proceed.
- Always run Phase 1 (anti-patterns) first — it's the fastest filter and catches the most impactful issues.
- Map each issue to its owning skill (`/typeset`, `/animate`, `/colorize`, `/harden`) for targeted follow-up.
- Reference `design-profile.md` to distinguish "intentional deviation" from "mistake" when evaluating anti-patterns.
