shortDescription: Amplify safe or generic designs into visually distinctive, memorable experiences.
usedBy: [user]
version: 1.0.0
lastUpdated: 2026-03-20

## Purpose

Transform designs that are functional but forgettable. "Bolder" doesn't mean chaotic or garish — it means **intentional, confident, and distinctive**. The goal is to escape the safe median (the average of all AI-generated UIs) without falling into a different cliché. Bold must still be usable.

## When to Use

- A UI that looks "fine" but could belong to any product
- After implementing a feature and before shipping — design review pass
- When the design profile's DESIGN_VARIANCE is 6+ but the output still looks generic
- When the user says "make it more interesting / more premium / more memorable"

## The AI Slop Trap

Before amplifying, check which direction you're heading. These patterns feel "bolder" but are just a different kind of generic:

| Trap | Why it's still AI slop |
|------|----------------------|
| Cyan-on-dark + purple gradients | The most common "dark mode premium" cliché |
| Glassmorphism on everything | Overused since 2021; now signals laziness |
| Neon glow accents | Every "modern SaaS" template uses these |
| Gradient text on every heading | Lost its impact from overuse |
| Particle backgrounds | Screams "I ran out of design ideas" |

Instead, amplify through **contrast, intention, and personality**.

## Procedure

### Step 1 — Choose a personality lane

Pick the one that fits the design profile's brand adjectives:

| Lane | Visual signatures |
|------|------------------|
| **Elegant drama** | High contrast, editorial typography, restrained palette, generous whitespace |
| **Maximalist energy** | Dense, layered, chromatic, expressive typography, pattern + texture |
| **Playful confidence** | Unexpected colors, weight contrast, irregular grid, motion-forward |
| **Clinical precision** | Monochromatic, structured, data-dense, geometric |
| **Warm editorial** | Serif + sans mix, earthy palette, soft gradients, approachable |

### Step 2 — Apply amplification axes

Address each axis in order of visual impact:

#### Typography contrast (highest leverage)
- Make the contrast between heading and body more extreme: increase heading weight (700→900), decrease body weight (400→300)
- Increase heading size further: if it was `text-4xl`, try `text-6xl` or `text-7xl`
- Add letter-spacing to heavy headings: `tracking-tight` or `tracking-tighter`
- Consider mixing a serif/display typeface into headings if brand allows

#### Color depth
- Replace the weakest neutrals with tinted versions: never pure gray, always bias toward brand hue
- Increase the accent's presence — one strong chromatic element per section
- Give cards distinct colors from the palette (color-per-card identity): not all the same background

#### Spatial drama
- Increase whitespace in the most important section, decrease in a secondary one — create rhythm through contrast
- Use asymmetric padding: `pt-24 pb-12` instead of uniform `py-16`
- Let one element escape its container (negative margin, absolute positioning, overlap)

#### Visual texture
- Add one subtle texture, gradient, or pattern as a background layer — avoid pure flat color
- Spatial decorators (absolutely positioned blurred shapes) to create depth: `absolute blur-3xl bg-accent/20 rounded-full`

#### Motion
- If MOTION_INTENSITY ≥ 5: add one entrance animation to the primary focal point of the view

### Step 3 — Validate the amplification

After changes:
- Is it still immediately readable at a glance?
- Does the primary action/CTA still draw the eye first?
- Does it feel consistent with the design profile's personality adjectives?
- Is there a clear visual hierarchy (one element is most important, others recede)?

## Anti-Patterns

- **Making everything bold** — if everything shouts, nothing stands out. Pick one focal element to amplify.
- **Copying a trendy aesthetic blindly** — bolder ≠ fashionable; it means true to the brand personality.
- **Sacrificing readability** — contrast and typographic extremes must still pass WCAG AA.
- **Undoing structure** — visual boldness works within a grid, not instead of it.

## Rules

- Amplify through typography first (highest leverage, least risk).
- One focal element dominates; all others support it.
- Bold must still be usable. Run `/audit` after `/bolder` to check nothing broke.
- If unsure, present the user with 2 variations (conservative amplification vs. bold amplification) and let them choose.
