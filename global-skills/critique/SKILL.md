shortDescription: Holistic UX/design evaluation — hierarchy, information architecture, emotion, and effectiveness.
usedBy: [user]
version: 1.0.0
lastUpdated: 2026-03-20

## Purpose

Evaluate a design as a design director would: does it actually work as an experience, not just as a collection of implemented components? `/critique` combines technical quality assessment with UX effectiveness. It asks: does the visual hierarchy lead the eye correctly? Does the information architecture make sense? Does it feel right for the brand and context?

Run after implementation, before presenting to the user or shipping. Also useful when something "feels off" but you can't articulate why.

## When to Use

- After implementing a new screen, page, or major feature
- Before a design review or stakeholder presentation
- After `/bolder` — to validate the amplification serves UX, not just aesthetics
- When the implementation is correct but the user says "it doesn't feel right"

## Procedure

### Check 1 — AI Slop Scan (run first)

Before any nuanced evaluation, eliminate the obvious:

- Cyan/purple gradient palette? → Replace
- Hero metric layout (big number + label)? → Redesign section
- 3-column icon + heading + text grid? → Redesign section
- Bounce/elastic easing? → Replace with smooth deceleration
- Vanilla shadcn/ui components? → Customize to design profile
- Inter font in a premium context? → Replace per design profile

If any of these are present, flag as Critical and address before continuing with deeper critique.

### Check 2 — Visual Hierarchy

Where does the eye land first when looking at this UI?

- It should land on the most important element (primary CTA, key metric, main heading)
- The second most important element should be clearly second
- Is this hierarchy achieved through size, weight, color, and space — or does everything compete equally?
- Is there a focal point per section, or does each section feel like a grid of equal-weight items?

### Check 3 — Information Architecture

- How many decisions does the user face at once? (More than 5–7 items at the top level = overload)
- Is related information grouped visually and spatially?
- Are the section labels/headings meaningful or generic ("Section 1", "Features")?
- Is the navigation hierarchy clear — does the user know where they are and how to get back?

### Check 4 — Emotional Resonance

- How does this make you feel at first glance?
- Does that feeling match the brand personality adjectives in `design-profile.md`?
- Premium products should feel expensive (restraint, space, weight). Playful products should feel approachable (color, friendly type, humanizing copy). Clinical products should feel precise (structure, density, data).
- If the emotion doesn't match the brand, which element is creating the mismatch? (Usually typography or color)

### Check 5 — Discoverability

- Can users tell what's interactive vs. decorative?
- Are calls-to-action obvious? Do they stand out from secondary actions?
- Is anything important hidden (requires scroll, hover, or extra interaction to find)?
- Are form errors, validations, and confirmations clearly communicated?

### Check 6 — Composition

- Is there visual breathing room? Or does every element crowd the edges?
- Is there a rhythm to the vertical spacing — does it feel intentional or random?
- Is there a dominant element per section, or do all sections feel like equal boxes?
- Does the layout have any asymmetry, or is it perfectly centered/symmetric throughout? (For DESIGN_VARIANCE > 4, some asymmetry is expected)

### Check 7 — Typography Effectiveness

- Can you read the most important text in < 2 seconds without effort?
- Is there a clear scale difference between headings, subheadings, and body?
- Does the font choice feel right for the brand?
- Is body text comfortable to read (16px+, 45–75 char line length)?

### Check 8 — Color Effectiveness

- Does the primary brand color appear on the most important elements?
- Are accent colors being used meaningfully (not scattered everywhere)?
- Does the palette feel intentional, or like colors were chosen by color picker?
- Is semantic color consistent: green = success, red = error, yellow = warning?

### Check 9 — Interaction States

- Do buttons communicate they're clickable without hover (shape, color, contrast)?
- Are loading states meaningful (skeleton matching layout) or generic (spinner)?
- Are error states helpful and inline (not just a toast notification)?

### Check 10 — Microcopy & Voice

- Does the writing sound like the brand, or like generic product copy ("Get started", "Explore features")?
- Are labels clear or ambiguous ("Submit" → "Send message", "Click here" → "Download report")?
- Are empty states useful (explain what's missing and how to populate it)?
- Are error messages actionable ("Something went wrong" → "Couldn't save — check your connection and retry")?

## Output Format

```
## Critique Report

**Overall impression:** [one sentence]

### Critical (blocks good UX)
- [Issue] — [location] — [recommendation]

### High (significantly undermines experience)
- [Issue] — [location] — [recommendation]

### Medium (reduces quality)
- [Issue] — [location] — [recommendation]

### What's working well
- [Positive finding] — worth preserving or amplifying

### Recommended next steps
- /polish — for spacing/state pass
- /typeset — for typography issues
- /bolder — if the design is still too generic after fixes
```

## Rules

- Be direct and specific. "The hierarchy is unclear" is not useful. "The secondary CTA is visually equal to the primary CTA — reduce its weight by switching to `variant='ghost'` and removing the filled background" is useful.
- Always start with the AI slop scan. Don't do nuanced critique on a foundation of generic defaults.
- Reference `design-profile.md` to distinguish intentional choices from mistakes.
- Critique is not a list of problems — end with what's working well to preserve it.
