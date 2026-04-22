# Frontend Design — Design Patterns Reference

> Extended reference for `../SKILL.md`. Read this when implementing or reviewing UI.

---

## LLM Bias Correction

LLMs statistically generate generic UI. Actively avoid these "AI tells":

### Forbidden Patterns

**Visual — AI slop palette:**
- No cyan-on-dark, purple-to-blue gradients, or neon accents on dark backgrounds
- No default neon/outer `box-shadow` glows — use inner borders or tinted shadows
- No pure `#000000` black — use off-black (Zinc-950, Slate-950)
- No oversaturated accents — desaturate to blend with neutrals
- No excessive gradient text on large headers
- No lazy glassmorphism on solid white backgrounds — `backdrop-blur` is only valid when background justifies frosted glass
- Do not reduce "premium" to beige serif typography, generic dark glow, or a single luxury-coded color trick

**Typography:**
- Avoid Inter for premium/creative contexts — prefer Geist, Outfit, Cabinet Grotesk, Satoshi
- No oversized H1s that scream — control hierarchy with weight and color, not scale
- Serif fonts only for editorial/creative — never dashboards or software UIs
- No long, paragraph-like hero headlines. Marketing H1s should read as a sharp statement, not a pitch deck summary

**Layout:**
- No centered hero when DESIGN_VARIANCE > 4 — use split-screen, left-aligned, or asymmetric
- No "hero metric layout": large number + small label + stats row as dashboard card — single most repeated AI dashboard cliché
- No polluted heroes packed with badges, fake stats, logo strips, pills, and multiple competing CTAs
- No "icon + heading + body text" in 3-column equal grid for features — use zig-zag or asymmetric grid
- No repeated left-text/right-image sections down the whole page
- No identical card rows repeated section after section
- No section rhythm that stays the same from top to bottom. Vary density, image ratio, alignment, and whitespace with control
- No `h-screen` for full-height sections — always `min-h-[100dvh]`
- No complex flexbox percentage math — use CSS Grid

**Content & Data:**
- No generic placeholder names ("John Doe") — use creative realistic names
- No predictable numbers (99.99%, 50%) — use organic data (47.2%)
- No filler AI copywriting ("Elevate", "Seamless", "Unleash") — use concrete verbs
- No fake startup wordmarks or meaningless brand names unless supplied by the user
- No broken Unsplash links — use `https://picsum.photos/seed/{random}/800/600`

**Components:**
- shadcn/ui must always be customized — never ship vanilla defaults
- No generic circular loading spinners — use skeletal loaders matching layout sizes
- Cards must have elevation purpose — for VISUAL_DENSITY > 7, prefer `border-t`/`divide-y`

---

## Design Principles — Full Detail

### Typography

- Never default to Inter, Roboto, or Arial — consult design profile for approved font pair
- Use extreme weight contrasts: light for body (300–400), heavy for headings (700–900)
- Clear size hierarchies: noticeable jumps between levels (14px / 20px / 36px — not 16px / 18px / 20px)
- Combine serif + sans-serif for contrast when profile allows
- Define custom fonts in `tailwind.config.ts` if profile specifies them
- Body text minimum 16px. Line length 45–75 characters (`max-w-prose` or `ch` units)
- Run `/typeset` for a focused typography audit

### Color

- Use CSS custom properties (HSL variables in `:root`), following shadcn/ui theming convention
- For new palettes: prefer OKLCH (`oklch(65% 0.15 230)`) — perceptually uniform, no lightness distortion
- Use `color-mix(in oklch, ...)` for tint/shade variants
- Never hardcode hex values in components — always reference design tokens
- Design profile defines: dominant color, at least one strong accent, background treatment
- Each section/card can have its own chromatic identity — avoid monochrome uniformity
- No timid pastels unless profile explicitly calls for them
- Run `/colorize` for strategic color introduction on monochromatic designs

### Motion

- One high-impact animation per view beats ten micro-interactions
- CSS transitions for simple state changes (hover, focus, active)
- Framer Motion only for entrance/exit or complex orchestrated sequences
- Staggered reveals for lists: items enter sequentially
- Every animation must have a purpose — no decorative-only animations
- Always respect `prefers-reduced-motion`
- No bounce or elastic easing — use `ease-out-quart/quint/expo` for CSS, `{ stiffness: 100, damping: 20 }` for Framer spring
- Run `/animate` for strategic motion analysis

### Backgrounds and Surfaces

- No solid white backgrounds unless profile specifies minimalist style
- Layer gradients, subtle noise textures, or geometric patterns for depth
- Card surfaces must have visible depth: shadow, border, or background contrast
- Glassmorphism: `backdrop-blur` + semi-transparency + luminous border (dark/gradient backgrounds only)

### Composition and Layout

- Allow controlled asymmetry — not everything needs centering
- Use negative space intentionally — generous padding in one section makes a dense section more impactful
- Consider overlap: cards over sections, text over images
- Break grid monotony: not every row needs equal columns
- Decorative 3D elements (spheres, organic shapes) for ambience when profile allows
- For public/marketing pages, choose a composition pattern from `aesthetic-patterns.md` before laying out the hero and section sequence
- For image-led work, use media as layout structure: full-bleed crops, framed product shots, editorial panels, gallery cadence, or object-focused hero treatment

---

## Per-Persona Actions

### For Architect (tasks M/L)

- **Interview**: ask about mood, visual references, whether to match or evolve existing design profile
  - If user provides images or links: execute Inspiration Ingestion Protocol (see `aesthetic-patterns.md`)
- **Passive image-first bias**: when planning a landing page, homepage, hero, marketing site, redesign, or visually important first impression, choose a composition pattern and image strategy internally before presenting Design Direction. Do not ask the user to enable this behavior.
- **Plan**: include `### Design Direction` section with 3 variations (see Design Preview in `aesthetic-patterns.md`)
  - Wait for user choice before finalizing plan
- **Steps**: reference `frontend-design` skill in any step that produces visible UI

### For Coder

- **Before coding**: read `design-profile.md` and `component-inventory.md`
  - If plan contains visual references: read and extract patterns first
- **Passive image-first bias**: for landing/homepage/hero/redesign work, apply the chosen composition pattern, hero restraint, image role, and section rhythm as part of normal `frontend-design` work
- **Preview** (S/XS, no Architect): generate 3 style variations before full implementation
- **During implementation**: apply at least 3 of the 5 design principles. Do not ship vanilla shadcn/ui without customization matching the design profile
- **After creating a shared component**: add to `component-inventory.md`
- **Handoff**: include `### Design Applied` section in Implementation Summary

### For Reviewer

**Design Lens** (Pass 3 — only when `design-profile.md` exists AND task involves user-facing UI; skip for XS/internal/backend):
- Does the implementation follow the design profile? (colors, fonts, mood, visual signature)
- Did the Coder check the component inventory? Are there duplicated components?
- Are shadcn/ui components customized or left at vanilla defaults? (vanilla = SHOULD FIX)
- Were at least 3 of the 5 design principles applied?
- Does this new UI feel consistent with existing pages?
- Was a design preview approved before full implementation?
- For landing/homepage/hero/redesign work: did the UI avoid polluted heroes, repeated section templates, decorative-only imagery, generic glow/gradient defaults, and weak section rhythm?

Design issues are **SHOULD FIX**, never MUST FIX. Design is important but does not block shipping.
- For holistic UX/design evaluation: run `/critique`
- For comprehensive multi-dimensional quality scan: run `/audit`
- For final pixel-perfect pass: run `/polish`

---

## Examples

### ✅ Good — customized component with 3+ design principles applied

```tsx
// Glassmorphism surface + color identity + motion entrance + typography contrast
<motion.div
  initial={{ opacity: 0, y: 16 }}
  animate={{ opacity: 1, y: 0 }}
  className="backdrop-blur-md bg-white/10 border border-white/20
             shadow-lg rounded-2xl p-6 bg-emerald-950/50"
>
  <h2 className="font-serif text-3xl font-bold tracking-tight">Revenue</h2>
  <p className="text-sm font-light text-white/70 mt-1">Last 30 days</p>
</motion.div>
```

Applies: glassmorphism surface, color-per-card identity (emerald), motion entrance, typography contrast (serif bold + light body).

### ❌ Bad — vanilla shadcn/ui, zero customization

```tsx
<Card>
  <CardHeader>
    <CardTitle>Revenue</CardTitle>
    <CardDescription>Last 30 days</CardDescription>
  </CardHeader>
</Card>
```

Zero design application — no color, no typography contrast, no surface treatment, no motion. Ships the design system's placeholder look.
