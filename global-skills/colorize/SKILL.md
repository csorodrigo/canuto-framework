shortDescription: Strategic color introduction — 60/30/10 balance, OKLCH palettes, semantic meaning.
usedBy: [user]
version: 1.0.0
lastUpdated: 2026-03-20

## Purpose

Add color intentionally to a monochromatic or under-colored design. Strategic color beats rainbow chaos: every color must earn its place by conveying meaning, creating hierarchy, or building brand recognition. `/colorize` teaches color balance, semantic roles, and modern CSS color techniques.

## When to Use

- A UI that uses only grays and one accent color
- When the design profile specifies a palette but it's not being applied consistently
- After `/bolder` to add chromatic depth to amplified typography/layout
- When the user says "it looks too gray" or "it feels lifeless"

## The 60/30/10 Rule

Allocate color across three roles:

| Role | % of visual space | What it is |
|------|------------------|-----------|
| **Dominant (60%)** | Backgrounds, large surfaces | Neutrals: white, near-white, dark gray, near-black — tinted slightly toward brand |
| **Secondary (30%)** | Sections, cards, panels | Brand color at low saturation / tint, or secondary accent |
| **Accent (10%)** | CTAs, highlights, active states | Primary brand color at full saturation |

**Common mistake:** Applying the brand color at 40–50% of the visual space. It stops feeling like an accent and starts feeling overwhelming or garish.

## Procedure

### Step 1 — Audit current color usage

- How many distinct colors are in use? > 6–7 (excluding shades of the same hue) = too many
- Which color has the most visual presence? Is it the right one?
- Are neutrals pure gray or tinted? Pure gray = generic. Always tint neutrals toward the brand hue.

### Step 2 — Define the palette

If `design-profile.md` doesn't specify a palette, create one now:

**Using OKLCH (recommended for new palettes):**
```css
:root {
  /* Primary brand color */
  --color-brand: oklch(55% 0.18 260);        /* mid-dark blue */
  --color-brand-light: oklch(85% 0.10 260);  /* tint for backgrounds */
  --color-brand-dim: oklch(40% 0.14 260);    /* shade for hover states */

  /* Accent */
  --color-accent: oklch(70% 0.22 45);        /* warm amber */

  /* Neutrals — tinted toward brand hue */
  --color-surface: oklch(98% 0.01 260);      /* near-white with blue tint */
  --color-surface-muted: oklch(94% 0.02 260);
  --color-foreground: oklch(20% 0.04 260);   /* near-black with blue tint */
  --color-muted: oklch(55% 0.03 260);        /* gray with blue tint */
}
```

**Key OKLCH insight:** Rotating the hue angle while keeping lightness/chroma constant produces perceptually equal colors. HSL does not — a yellow at 50% HSL lightness looks much brighter than a blue at 50%.

### Step 3 — Apply semantic color roles

| Semantic role | Color |
|--------------|-------|
| **Primary action** (main CTA) | Brand color at full saturation |
| **Destructive action** | Red: `oklch(55% 0.20 25)` |
| **Success / positive** | Green: `oklch(60% 0.17 145)` |
| **Warning / caution** | Amber: `oklch(75% 0.18 70)` |
| **Information / neutral** | Blue: `oklch(60% 0.15 230)` |
| **Disabled** | Muted at 40% opacity |

Never use color as the **only** indicator of state — always pair with an icon, text, or pattern (accessibility).

### Step 4 — Apply color-per-card identity (where appropriate)

For feature sections, pricing tiers, or category cards: assign each card a distinct chromatic identity from a harmonious set.

```tsx
// Tailwind — harmonious set of card backgrounds
const cardColors = [
  "bg-orange-50 border-orange-200 dark:bg-orange-950/50 dark:border-orange-800/30",
  "bg-emerald-50 border-emerald-200 dark:bg-emerald-950/50 dark:border-emerald-800/30",
  "bg-violet-50 border-violet-200 dark:bg-violet-950/50 dark:border-violet-800/30",
  "bg-sky-50 border-sky-200 dark:bg-sky-950/50 dark:border-sky-800/30",
]
```

This applies color-per-card identity from `frontend-design.md`'s aesthetic pattern vocabulary.

### Step 5 — Validate contrast

After applying color:
- Text on colored background: ≥ 4.5:1 contrast ratio (WCAG AA)
- Large text (≥ 18pt bold): ≥ 3:1
- Check with browser DevTools → Accessibility → Color Contrast, or use `oklch` contrast calculators

**Common failure:** Gray text on a tinted/colored background looks washed out. Use the foreground color defined against that specific background.

### Step 6 — Dark mode palette

```css
.dark {
  --color-surface: oklch(18% 0.02 260);       /* near-black with tint */
  --color-surface-muted: oklch(22% 0.02 260);
  --color-foreground: oklch(95% 0.01 260);    /* near-white */
  --color-brand: oklch(65% 0.18 260);         /* slightly lighter for dark */
  --color-brand-light: oklch(30% 0.10 260);   /* dark surface for brand elements */
}
```

## Anti-Patterns

- **Using every color in the rainbow** — choose 2–4 hues max (beyond neutrals)
- **Random color application** — every color must have a semantic or structural reason
- **Gray text on colored backgrounds** — almost always fails contrast
- **Pure gray neutrals (`#6b7280`)** — tint toward brand hue for coherence
- **Pure black (`#000`) or pure white (`#fff`) for large surfaces** — use off-black/off-white
- **The AI color palette**: cyan accents + dark purple/navy + gradient from `#7c3aed` to `#2563eb` — immediately signals AI-generated

## Rules

- 60% dominant (neutral) / 30% secondary (brand at low saturation) / 10% accent (brand full) — don't exceed accent presence.
- Semantic colors (red, green, amber) must be consistent across the entire app.
- Every color must have a dark mode variant.
- OKLCH for new palettes; if using Tailwind defaults, always tint neutrals toward the brand hue.
- Update `design-profile.md` with the final palette decisions.
