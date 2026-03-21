shortDescription: How to make frontend features visually distinctive and design-coherent.
usedBy: [coder, reviewer, architect]
version: 3.0.0
lastUpdated: 2026-03-20
copyright: Rodrigo Canuto © 2026.

## When to Use

**Triggers:**
- Architect is planning a task that produces user-facing UI (include Design Direction section in plan)
- Coder is implementing any screen, page, or component visible to the user
- Reviewer is reviewing code with user-facing changes (activates Design Lens — Pass 3)

**Not for:**
- Backend-only tasks with no visible UI
- Internal admin utilities where design quality is not a priority
- XS tasks where visual impact is negligible (e.g., fix a typo on a label)

---

## Purpose

Prevent generic-looking UI by encoding opinionated design principles within the locked stack (Tailwind CSS + shadcn/ui). This skill ensures every user-facing feature has visual personality, consistency, and intentional design choices — not default component styling.

Works alongside `frontend-implementation` (which covers _where_ to put code). This skill covers _how it should look_.

Includes a vocabulary of reference aesthetic patterns and protocols for ingesting user-provided visual inspirations and presenting design previews before implementation.

---

## Context Gathering Protocol

Before any visual work on a **new project or unfamiliar codebase**, gather the following context. This feeds `design-profile.md` creation during the Architect's interview. For S/XS tasks without an Architect, the Coder asks these 4 questions before generating design variations.

| Question | Why it matters |
|----------|----------------|
| **Target audience** — Who uses this product? | Shapes tone: clinical (medical tools), playful (consumer apps), premium (B2B SaaS) |
| **Primary use cases** — Top 3 user workflows? | Determines density, information hierarchy, and which UI patterns earn their place |
| **Brand personality** — 3–5 adjectives (e.g. "precise, calm, modern" or "bold, irreverent, fast") | Translates to font weight, color saturation, motion intensity |
| **Competitive context** — What does this need to stand out from? | Identifies clichés to actively avoid in this vertical |

If the design-profile already exists and answers these, skip directly to reading it.

---

## Design Knobs

Three tunable parameters that control the visual output globally. Default values are set below but can be overridden per-project in `design-profile.md` or dynamically by the user in conversation.

| Knob | Default | Range | Description |
|------|---------|-------|-------------|
| **DESIGN_VARIANCE** | 6 | 1–10 | 1 = symmetric, predictable layouts. 10 = asymmetric, editorial layouts. |
| **MOTION_INTENSITY** | 5 | 1–10 | 1 = no animations, CSS hover only. 10 = choreographed Framer Motion sequences. |
| **VISUAL_DENSITY** | 4 | 1–10 | 1 = art-gallery airy spacing. 10 = cockpit-mode packed data. |

> Defaults (6, 5, 4) are more conservative than the Taste Skill reference (8, 6, 4) to suit production SaaS apps. Adjust per-project in `design-profile.md`.

**How knobs affect decisions:**
- **DESIGN_VARIANCE 1–3:** Centered layouts, symmetrical grids, equal paddings. Standard hero sections allowed.
- **DESIGN_VARIANCE 4–7:** Offset margins, varied aspect ratios, left-aligned headers. Centered hero sections discouraged.
- **DESIGN_VARIANCE 8–10:** Masonry layouts, fractional CSS Grid (`2fr 1fr 1fr`), generous asymmetric whitespace.
- **MOTION_INTENSITY 1–3:** No auto-animations. CSS `:hover` and `:active` states only.
- **MOTION_INTENSITY 4–7:** CSS transitions with `cubic-bezier(0.16, 1, 0.3, 1)`. Staggered load-in delays. Only `transform` and `opacity`.
- **MOTION_INTENSITY 8–10:** Framer Motion spring physics, scroll-triggered reveals, layout transitions with `layoutId`.
- **VISUAL_DENSITY 1–3:** Large section gaps, generous whitespace, premium/editorial feel.
- **VISUAL_DENSITY 4–7:** Standard web app spacing.
- **VISUAL_DENSITY 8–10:** Compact padding, `border-t` / `divide-y` instead of cards, monospace for numbers.

**Mobile override:** For DESIGN_VARIANCE 4+, any asymmetric layout above `md:` **must** collapse to single-column (`w-full`, `px-4`) on viewports < 768px.

---

## LLM Bias Correction

LLMs have statistical biases toward generic UI patterns. Actively avoid these "AI tells" to produce premium, non-generic interfaces:

### Forbidden Patterns (unless explicitly requested by user or design profile)

**Visual — AI slop palette:**
- No cyan-on-dark, purple-to-blue gradients, or neon accents on dark backgrounds — this is the predictable "AI color palette"
- No default neon/outer `box-shadow` glows — use inner borders or tinted shadows instead
- No pure `#000000` black — use off-black (Zinc-950, Slate-950, or Charcoal)
- No oversaturated accents — desaturate to blend with neutrals
- No excessive gradient text on large headers
- No lazy glassmorphism without intent — `backdrop-blur` is only valid when the design profile specifies it AND the background justifies frosted glass (dark or gradient). Glassmorphism on a solid white background is meaningless.

**Typography:**
- Avoid Inter for premium/creative contexts — prefer Geist, Outfit, Cabinet Grotesk, Satoshi, or the design profile's specified fonts
- No oversized H1s that scream — control hierarchy with weight and color, not just massive scale
- Serif fonts are only for editorial/creative — never on dashboards or software UIs

**Layout:**
- No centered hero when DESIGN_VARIANCE > 4 — use split-screen, left-aligned, or asymmetric whitespace
- No "hero metric layout": large number + small label + supporting stats row as dashboard card — the single most repeated AI dashboard cliché
- No "icon + heading + body text" in a 3-column equal grid for feature sections — use zig-zag, asymmetric grid, or horizontal scroll
- No `h-screen` for full-height sections — always use `min-h-[100dvh]` (prevents mobile viewport bugs)
- No complex flexbox percentage math — use CSS Grid (`grid grid-cols-1 md:grid-cols-3 gap-6`)

**Content & Data:**
- No generic placeholder names ("John Doe", "Jane Smith") — use creative, realistic names
- No predictable numbers (99.99%, 50%, 1234567) — use organic data (47.2%, +1 (312) 847-1928)
- No filler AI copywriting ("Elevate", "Seamless", "Unleash", "Next-Gen") — use concrete verbs
- No broken Unsplash links — use `https://picsum.photos/seed/{random}/800/600` or SVG placeholders

**Components:**
- shadcn/ui must always be customized (radii, colors, shadows) — never ship vanilla defaults
- No generic circular loading spinners — use skeletal loaders matching layout sizes
- Cards must have elevation purpose — for VISUAL_DENSITY > 7, prefer `border-t` / `divide-y` / negative space

### Required UI States

LLMs naturally generate only the "happy path" successful state. Every interactive component **must** implement:

- **Loading:** Skeletal loaders matching the layout shape (not generic spinners)
- **Empty:** Composed empty states indicating how to populate data
- **Error:** Clear, inline error reporting (not just console.log)
- **Tactile feedback:** On `:active`, apply `-translate-y-[1px]` or `scale-[0.98]` for physical push feel

---

## Procedure

### 1. Read the Design Profile

Before any visual work, read `~/.canuto/vault/projects/{project-slug}/design/profile.md`.

- If it exists: all visual decisions must align with it.
- If it does not exist:
  - For M/L tasks: the Architect creates one during the interview step. Do not implement UI without a design profile.
  - For XS/S tasks (no Architect): proceed directly to Step 6 (Design Preview). After the user approves a variation, bootstrap a minimal `design-profile.md` from that approval before writing implementation code.

### 2. Consult the Component Inventory

Read `~/.canuto/vault/projects/{project-slug}/design/components/` (or query `bases/components-registry.base`).

- If a component already exists that satisfies the requirement, reuse it.
- If a variant is needed, extend the existing component with a new variant rather than creating a duplicate.
- If no existing component fits, create a new one following the design profile rules, then add it to the inventory.

### 3. Apply Design Principles

Every user-facing UI must intentionally apply at least 3 of these 5 principles. Do not ship default shadcn/ui components without customization.

#### Typography

- Never default to Inter, Roboto, or Arial. Consult the design profile for the approved font pair.
- Use extreme weight contrasts: light for body (300–400), heavy for headings (700–900). No medium-weight-everything.
- Create clear size hierarchies with noticeable jumps between heading levels (e.g., 14px / 20px / 36px — not 16px / 18px / 20px).
- Combine serif + sans-serif for contrast when the profile allows (e.g., Playfair Display italic for emphasis + sans-serif for body).
- Define custom fonts in `tailwind.config.ts` if the design profile specifies them.
- Body text minimum 16px. Line length 45–75 characters (use `max-w-prose` or explicit `ch` units).

> For a focused typography audit (scale, pairing, hierarchy, line-length), run `/typeset`.

#### Color

- Use CSS custom properties (HSL variables in `:root`), following shadcn/ui's theming convention.
- For new palettes: prefer OKLCH (`oklch(65% 0.15 230)`) over HSL — perceptually uniform, doesn't distort lightness when rotating hue, supported in all modern browsers. Use `color-mix(in oklch, ...)` for tint/shade variants.
- Never hardcode hex values in components. Always reference design tokens.
- The design profile defines the palette: a dominant color, at least one strong accent, and a background treatment.
- Each section or card can have its own chromatic identity — avoid uniform monochrome. Use harmonious palette variants (e.g., orange card, green card, blue card).
- No timid pastels unless the design profile explicitly calls for them.

> For strategic color introduction on a monochromatic design, run `/colorize`.

#### Motion

- One high-impact animation per view beats ten micro-interactions.
- Use CSS transitions for simple state changes (hover, focus, active).
- Use Framer Motion only for entrance/exit animations or complex orchestrated sequences.
- Staggered reveals for lists and grids: items enter sequentially, not all at once.
- Every animation must have a purpose (draw attention, provide feedback, guide flow). No decorative-only animations.
- Always respect `prefers-reduced-motion`.
- No bounce or elastic easing (`spring` with high stiffness and low damping) — looks dated and amateur. Use `ease-out-quart/quint/expo` for CSS, or `{ stiffness: 100, damping: 20 }` for Framer spring.

> For strategic motion analysis and improvement, run `/animate`.

#### Backgrounds and Surfaces

- No solid white backgrounds unless the design profile specifies a minimalist style.
- Layer gradients, subtle noise textures, or geometric patterns for depth.
- Use Tailwind's gradient utilities (`bg-gradient-to-*`) and backdrop effects.
- Card surfaces must have visible depth: shadow, border, or background contrast.
- Glassmorphism is a premium surface option: `backdrop-blur` + semi-transparency + luminous border.

#### Composition and Layout

- Allow controlled asymmetry. Not everything needs to be centered.
- Use negative space intentionally — generous padding in one section makes a dense section feel more impactful.
- Consider overlap: cards overlapping sections, text over images, for visual interest.
- Break grid monotony: not every row needs equal columns.
- Decorative 3D elements (spheres, organic shapes) for ambience when the profile allows.

### 4. Reference Aesthetic Patterns

A vocabulary of advanced visual techniques. The Coder applies these based on what the design profile's `Preferred Aesthetic Patterns` section specifies.

#### Glassmorphism

Frosted glass effect for premium surfaces. Ideal for cards over dark or gradient backgrounds.

```
backdrop-blur-md bg-white/10 border border-white/20 shadow-lg
```

For dark mode: `bg-black/20 border-white/10`. Add `rounded-2xl` for softer feel.

#### Glow Accents

Neon/glow effect for interactive elements and CTAs in dark mode.

```
shadow-[0_0_15px_rgba(var(--accent-color),0.5)]
ring-2 ring-accent/50
```

Combine with transitions: `transition-shadow hover:shadow-[0_0_25px_rgba(...)]`.

#### Depth Layering

Cards and elements that feel like they float in space.

```
translate-y-[-2px] hover:translate-y-[-4px] transition-transform
shadow-md hover:shadow-xl
```

Multi-layer shadows: combine `shadow-md` (close, soft) with `shadow-xl` (distant, spread) using custom CSS for dual-shadow effect.

#### Color-per-Card Identity

Each card or section has a distinct background color from a harmonious palette. Not gray uniformity.

```
bg-orange-50 border-orange-200   /* card 1 */
bg-emerald-50 border-emerald-200 /* card 2 */
bg-blue-50 border-blue-200       /* card 3 */
```

In dark mode: use muted tones (`bg-orange-950/50 border-orange-800/30`).

#### Tactile Surfaces

Soft neumorphism for a physical, touchable feel.

```
shadow-[inset_0_2px_4px_rgba(0,0,0,0.06)] shadow-lg
rounded-2xl or rounded-3xl
```

Combine with muted colors and generous padding for premium tactile feel.

#### Spatial Decorators

Non-functional floating geometric or organic shapes for ambient decoration.

```html
<!-- Blurred circle positioned absolutely -->
<div class="absolute -top-20 -right-20 w-40 h-40 bg-accent/20 rounded-full blur-3xl" />

<!-- Radial gradient overlay -->
<div class="absolute inset-0 bg-[radial-gradient(circle_at_30%_20%,rgba(var(--accent),0.1),transparent_50%)]" />
```

Use sparingly. 1–2 decorators per section maximum. They create atmosphere, not content.

#### Liquid Glass Refraction

Enhanced glassmorphism with physical edge simulation. Goes beyond basic `backdrop-blur`.

```
backdrop-blur-md bg-white/10
border border-white/10
shadow-[inset_0_1px_0_rgba(255,255,255,0.1)]
rounded-2xl
```

The inner border + inner shadow simulates light refracting through a glass edge. Use on dark or gradient backgrounds.

#### Spring Physics Motion (MOTION_INTENSITY > 5)

Premium interactive feel using Framer Motion spring physics instead of linear easing.

```tsx
// Spring config for weighty, premium feel
{ type: "spring", stiffness: 100, damping: 20 }

// Layout transitions for smooth re-ordering
<motion.div layout layoutId="card-1" />

// Staggered orchestration for lists
{ staggerChildren: 0.08 }
```

**Key rules:**
- Never use `useState` for continuous hover animations — use `useMotionValue` + `useTransform`
- Wrap dynamic lists in `<AnimatePresence>`
- See **Performance Guardrails** section for full animation performance rules.

### 5. Inspiration Ingestion Protocol

When the user provides visual references (images, Pinterest/Dribbble links, screenshots):

1. **Read/view** each reference.
2. **Extract patterns**: color palette, typographic style, surface treatment, layout type, effects (glow, glass, shadow, gradients), overall mood.
3. **Map** extracted patterns to the Reference Aesthetic Patterns (Step 4) — e.g., "image X uses glassmorphism + glow accents on a dark background."
4. **Document** the extraction in the plan's "Design Direction" section (Architect) or update `design-profile.md` directly (if evolving an existing profile).
5. **Save** reference images to `.context/attachments/` and link them in the design profile's References section.

### 6. Design Preview Protocol

Before implementing user-facing UI, present 3 visually distinct variations for approval. Never implement a full page or section without approval of at least one visual direction.

**For Architect (tasks M/L):**

In the plan's Design Direction section, describe 3 variations:

```
**Variation A — [name]**: [mood]. Patterns: [list from Step 4].
[2-3 sentence visual description of how this would look.]

**Variation B — [name]**: [mood]. Patterns: [list from Step 4].
[2-3 sentence visual description — must differ from A.]

**Variation C — [name]**: [mood]. Patterns: [list from Step 4].
[2-3 sentence visual description — must differ from A and B.]
```

Each variation must combine different patterns (e.g., A = glassmorphism + dark, B = color-per-card + flat-with-depth, C = tactile + neumorphism). User chooses one. The chosen variation becomes the final Design Direction.

**For Coder (tasks S/XS, or when Architect did not participate):**

Generate the main component or section in 3 style variations as functional code. Present to the user via Maestro. User chooses. Only continue with the chosen variation.

### 7. For Architect

When planning a task that involves user-facing UI:

- **Interview**: ask about mood, visual references, and whether to match or evolve the existing design profile. If the user provides images or links, execute the Inspiration Ingestion Protocol (Step 5).
- **Plan**: include a `### Design Direction` section with 3 variations (Step 6). Wait for user choice before finalizing.
- **Steps**: reference `frontend-design` skill in any step that produces visible UI.

### 8. For Coder

When implementing a task that involves user-facing UI:

- **Before coding**: read `design-profile.md` and `component-inventory.md`. If the plan contains visual references from the user, read and extract patterns before implementing.
- **Preview**: if no Architect previews were generated (S/XS tasks), generate 3 style variations before full implementation (Step 6).
- **During implementation**: apply at least 3 of the 5 design principles (Step 3). Do not ship vanilla shadcn/ui components without customization matching the design profile.
- **After creating a new shared component**: add it to `component-inventory.md`.
- **Handoff**: include a `### Design Applied` section in the Implementation Summary.

### 9. For Reviewer

When reviewing code that includes user-facing UI changes:

- **Design Lens** (Pass 3 — only when `design-profile.md` exists AND the task involves user-facing UI; skip for XS/internal/backend tasks):
  - Does the implementation follow the design profile? (colors, fonts, mood, visual signature)
  - Did the Coder check the component inventory? Are there duplicated components?
  - Are shadcn/ui components customized or left at vanilla defaults? (vanilla = SHOULD FIX)
  - Were at least 3 of the 5 design principles applied?
  - Does this new UI feel consistent with existing pages in the app?
  - Was a design preview approved before full implementation?
- Design issues are **SHOULD FIX**, never MUST FIX. Design is important but does not block shipping.
- For holistic UX/design evaluation before shipping (hierarchy, IA, emotion, discoverability), run `/critique`.
- For a comprehensive multi-dimensional quality scan (a11y, performance, responsiveness, anti-patterns), run `/audit`.
- For the final pixel-perfect pass (spacing consistency, all states, keyboard nav), run `/polish`.

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

Applies: glassmorphism surface, color-per-card identity (emerald), motion entrance, typography contrast (serif bold heading + light body).

### ❌ Bad — vanilla shadcn/ui, zero customization

```tsx
<Card>
  <CardHeader>
    <CardTitle>Revenue</CardTitle>
    <CardDescription>Last 30 days</CardDescription>
  </CardHeader>
</Card>
```

This is bad because: default shadcn/ui `Card` with zero design application — no color, no typography contrast, no surface treatment, no motion. Ships the design system's placeholder look instead of the project's visual identity.

---

## Golden Rule

> "Make unexpected but contextually coherent choices. If the previous generation used a centered hero, try a split layout. If it used a gradient background, try a textured pattern. Always vary between generations — but stay within the design profile."

---

## Performance Guardrails

- Never animate `top`, `left`, `width`, or `height`. Animate exclusively via `transform` and `opacity`.
- Apply noise/grain filters only to fixed, `pointer-events-none` pseudo-elements — never to scrolling containers (prevents continuous GPU repaints).
- Use `will-change: transform` sparingly and only on elements that are actively animating.
- Do not use `z-50` or `z-10` arbitrarily — reserve z-index for systemic layers (sticky nav, modals, overlays).
- Wrap perpetual/infinite animations in their own memoized Client Components (`React.memo`) to prevent parent re-renders.
- For `staggerChildren`, parent variants and children must reside in the same Client Component tree.
- Ensure all `useEffect` animations contain strict cleanup functions.

---

## Guardrails

- Do not introduce CSS-in-JS or styled-components. Tailwind + CSS modules (if needed) are the tools.
- Do not add animation libraries beyond Framer Motion without approval.
- Do not override shadcn/ui component internals. Extend via `className`, `variants`, or wrapper components.
- Do not ignore the design profile. If you disagree with it, escalate to Architect for a profile update.
- Do not copy-paste component code between files. Extract to shared components and add to the inventory.
- Glassmorphism and glow effects require contrast/accessibility testing (WCAG AA minimum for text).
- Do not use spatial decorators on performance-critical views without checking impact.
