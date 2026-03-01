shortDescription: How to make frontend features visually distinctive and design-coherent.
usedBy: [coder, reviewer, architect]
version: 1.0.0
lastUpdated: 2026-03-01
copyright: Rodrigo Canuto © 2026.

## Purpose

Prevent generic-looking UI by encoding opinionated design principles within the locked stack (Tailwind CSS + shadcn/ui). This skill ensures every user-facing feature has visual personality, consistency, and intentional design choices — not default component styling.

Works alongside `frontend-implementation` (which covers _where_ to put code). This skill covers _how it should look_.

Includes a vocabulary of reference aesthetic patterns and protocols for ingesting user-provided visual inspirations and presenting design previews before implementation.

---

## Procedure

### 1. Read the Design Profile

Before any visual work, read `.agents/memory/design-profile.md`.

- If it exists: all visual decisions must align with it.
- If it does not exist:
  - For M/L tasks: the Architect creates one during the interview step. Do not implement UI without a design profile.
  - For XS/S tasks (no Architect): proceed directly to Step 6 (Design Preview). After the user approves a variation, bootstrap a minimal `design-profile.md` from that approval before writing implementation code.

### 2. Consult the Component Inventory

Read `.agents/memory/component-inventory.md`.

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

#### Color

- Use CSS custom properties (HSL variables in `:root`), following shadcn/ui's theming convention.
- Never hardcode hex values in components. Always reference design tokens.
- The design profile defines the palette: a dominant color, at least one strong accent, and a background treatment.
- Each section or card can have its own chromatic identity — avoid uniform monochrome. Use harmonious palette variants (e.g., orange card, green card, blue card).
- No timid pastels unless the design profile explicitly calls for them.

#### Motion

- One high-impact animation per view beats ten micro-interactions.
- Use CSS transitions for simple state changes (hover, focus, active).
- Use Framer Motion only for entrance/exit animations or complex orchestrated sequences.
- Staggered reveals for lists and grids: items enter sequentially, not all at once.
- Every animation must have a purpose (draw attention, provide feedback, guide flow). No decorative-only animations.
- Always respect `prefers-reduced-motion`.

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

---

## Golden Rule

> "Make unexpected but contextually coherent choices. If the previous generation used a centered hero, try a split layout. If it used a gradient background, try a textured pattern. Always vary between generations — but stay within the design profile."

---

## Guardrails

- Do not introduce CSS-in-JS or styled-components. Tailwind + CSS modules (if needed) are the tools.
- Do not add animation libraries beyond Framer Motion without approval.
- Do not override shadcn/ui component internals. Extend via `className`, `variants`, or wrapper components.
- Do not ignore the design profile. If you disagree with it, escalate to Architect for a profile update.
- Do not copy-paste component code between files. Extract to shared components and add to the inventory.
- Glassmorphism and glow effects require contrast/accessibility testing (WCAG AA minimum for text).
- Do not use spatial decorators on performance-critical views without checking impact.
