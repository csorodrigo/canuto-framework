# Frontend Design — Aesthetic Patterns Reference

> Extended reference for `../SKILL.md`. Read when selecting visual patterns or running inspiration ingestion.

---

## Aesthetic Pattern Recipes

A vocabulary of advanced visual techniques. Apply based on the design profile's `Preferred Aesthetic Patterns` section.

### Glassmorphism

Frosted glass effect for premium surfaces. Best over dark or gradient backgrounds.

```
backdrop-blur-md bg-white/10 border border-white/20 shadow-lg rounded-2xl
```

Dark mode: `bg-black/20 border-white/10`. Add `rounded-2xl` for softer feel.

### Glow Accents

Neon/glow effect for interactive elements and CTAs in dark mode.

```
shadow-[0_0_15px_rgba(var(--accent-color),0.5)]
ring-2 ring-accent/50
```

Combine with transitions: `transition-shadow hover:shadow-[0_0_25px_rgba(...)]`.

### Depth Layering

Elements that feel like they float in space.

```
translate-y-[-2px] hover:translate-y-[-4px] transition-transform
shadow-md hover:shadow-xl
```

Multi-layer shadows: combine `shadow-md` (close, soft) with `shadow-xl` (distant, spread) via custom CSS.

### Color-per-Card Identity

Each card or section has a distinct background color from a harmonious palette.

```
bg-orange-50 border-orange-200   /* card 1 */
bg-emerald-50 border-emerald-200 /* card 2 */
bg-blue-50 border-blue-200       /* card 3 */
```

Dark mode: muted tones (`bg-orange-950/50 border-orange-800/30`).

### Tactile Surfaces

Soft neumorphism for a physical, touchable feel.

```
shadow-[inset_0_2px_4px_rgba(0,0,0,0.06)] shadow-lg
rounded-2xl
```

Combine with muted colors and generous padding.

### Spatial Decorators

Non-functional floating geometric shapes for ambient decoration.

```html
<!-- Blurred circle, absolutely positioned -->
<div class="absolute -top-20 -right-20 w-40 h-40 bg-accent/20 rounded-full blur-3xl" />

<!-- Radial gradient overlay -->
<div class="absolute inset-0 bg-[radial-gradient(circle_at_30%_20%,rgba(var(--accent),0.1),transparent_50%)]" />
```

Use sparingly — 1–2 per section maximum. They create atmosphere, not content.

### Liquid Glass Refraction

Enhanced glassmorphism with physical edge simulation.

```
backdrop-blur-md bg-white/10
border border-white/10
shadow-[inset_0_1px_0_rgba(255,255,255,0.1)]
rounded-2xl
```

Inner border + inner shadow simulates light refracting through glass. Use on dark/gradient backgrounds.

### Spring Physics Motion (MOTION_INTENSITY > 5)

Premium interactive feel via Framer Motion spring physics.

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
- Wrap perpetual animations in `React.memo` to prevent parent re-renders
- For `staggerChildren`, parent and children variants must be in the same Client Component tree

---

## Inspiration Ingestion Protocol

When the user provides visual references (images, Pinterest/Dribbble links, screenshots):

1. **Read/view** each reference
2. **Extract patterns**: color palette, typographic style, surface treatment, layout type, effects (glow, glass, shadow, gradients), overall mood
3. **Map** extracted patterns to the Aesthetic Pattern Recipes above — e.g., "image X uses glassmorphism + glow accents on dark background"
4. **Document** the extraction in the plan's "Design Direction" section (Architect) or update `design-profile.md` directly (if evolving an existing profile)
5. **Save** reference images to `.context/attachments/` and link in the design profile's References section

---

## Design Preview Protocol

Before implementing user-facing UI, present 3 visually distinct variations. Each variation must use different aesthetic patterns. User chooses. Only continue with the chosen variation.

**For Architect (tasks M/L)** — in the plan's Design Direction section:

```
**Variation A — [name]**: [mood]. Patterns: [list from recipes above].
[2-3 sentence visual description of how this would look.]

**Variation B — [name]**: [mood]. Patterns: [list — must differ from A].
[2-3 sentence visual description — must differ from A.]

**Variation C — [name]**: [mood]. Patterns: [list — must differ from A and B].
[2-3 sentence visual description — must differ from A and B.]
```

Each variation must combine different patterns (e.g., A = glassmorphism + dark, B = color-per-card + flat-depth, C = tactile + neumorphism). The chosen variation becomes the final Design Direction.

**For Coder (tasks S/XS, or when Architect did not participate):**

Generate the main component or section in 3 style variations as functional code. Present to user via Maestro. User chooses. Only continue with the chosen variation.
