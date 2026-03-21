shortDescription: Add strategic animations and micro-interactions — purpose-driven motion, not decoration.
usedBy: [user]
version: 1.0.0
lastUpdated: 2026-03-20

## Purpose

Improve existing animations or add motion to a UI that lacks it. Every animation must serve one of these goals: improve understanding (show state change), provide feedback (confirm action), guide flow (reveal content), or create delight (reward engagement). Motion for its own sake is noise.

## When to Use

- After implementing a feature — add motion pass before shipping
- When a UI feels static and lifeless
- When animations exist but feel wrong (too fast, too slow, too bouncy)
- After `/audit` flags motion issues

## Motion Taxonomy

Understand which type of motion you're adding before choosing technique:

| Type | Purpose | Timing | Technique |
|------|---------|--------|-----------|
| **Entrance** | Reveal content on load/mount | 200–400ms | Framer `initial`/`animate` |
| **Micro-interaction** | Confirm small actions (button press, toggle) | 80–150ms | CSS `:active` + `transform` |
| **State transition** | Convey status change (loading, success, error) | 150–300ms | CSS transition on class swap |
| **Navigation flow** | Indicate hierarchy between screens | 300–500ms | Framer layout + `layoutId` |
| **Feedback** | Validate user input (form, drag, resize) | 100–200ms | CSS transition |
| **Delight** | Reward engagement (confetti, completion) | 400–800ms | Framer `AnimatePresence` |

## Procedure

### Step 1 — Audit existing motion

Before adding anything:
- What animations already exist? Are they purposeful or decorative?
- Are any animations using layout properties (`width`, `height`, `top`, `left`, `margin`)? Flag for replacement.
- Any bounce/elastic easing? Flag for replacement.
- Is `prefers-reduced-motion` respected? If not, it's a bug to fix first.

### Step 2 — Choose one high-impact moment

One well-orchestrated animation beats ten scattered micro-interactions. Identify the single highest-leverage motion for this view:
- The primary CTA button (tactile `:active` feedback)?
- The main content reveal (entrance)?
- A state transition (loading → loaded)?

Implement that first before adding secondary animations.

### Step 3 — Apply easing rules

```css
/* CSS — use these, not ease-in-out or linear for UI motion */
transition: transform 200ms cubic-bezier(0.16, 1, 0.3, 1); /* ease-out-expo */
transition: transform 300ms cubic-bezier(0.25, 1, 0.5, 1); /* ease-out-quart */
```

```tsx
// Framer Motion — spring for weighty, premium feel
{ type: "spring", stiffness: 100, damping: 20 }   // smooth, professional
{ type: "spring", stiffness: 200, damping: 25 }   // snappier

// AVOID: high stiffness + low damping = bouncy/amateur
// { stiffness: 400, damping: 10 } — NO
```

### Step 4 — Implement with performance guardrails

```tsx
// Entrance animation (Framer)
<motion.div
  initial={{ opacity: 0, y: 16 }}
  animate={{ opacity: 1, y: 0 }}
  transition={{ duration: 0.3, ease: [0.16, 1, 0.3, 1] }}
/>

// Staggered list (Framer)
const container = { animate: { transition: { staggerChildren: 0.06 } } }
const item = { initial: { opacity: 0, y: 8 }, animate: { opacity: 1, y: 0 } }

// Tactile button (CSS only — no library needed)
/* Tailwind: active:-translate-y-px active:scale-[0.98] transition-transform duration-75 */

// prefers-reduced-motion — always include
@media (prefers-reduced-motion: reduce) {
  * { animation-duration: 0.01ms !important; transition-duration: 0.01ms !important; }
}
```

### Step 5 — Validate

- Does the animation play at 60fps? Check Chrome DevTools → Performance.
- Test on a mid-range device (not just high-end machine).
- Test with `prefers-reduced-motion: reduce` enabled.
- Remove the animation and check: does the UI feel worse? If not, the animation wasn't earning its place.

## Anti-Patterns

- **Animating layout properties** — `width`, `height`, `top`, `left`, `margin`, `padding`. Always use `transform` + `opacity` instead.
- **Duration > 500ms for feedback** — feels laggy. Reserve longer durations for entrance/navigation only.
- **Bounce or elastic easing** — looks dated. Use smooth deceleration curves.
- **Animating everything** — animation fatigue. Pick the one moment that matters most.
- **Framer for simple hover** — CSS transitions are faster to write and render. Framer for orchestrated sequences only.
- **Perpetual/infinite animations without `React.memo`** — causes parent re-renders on every frame.
- **`useEffect` animations without cleanup** — memory leaks.

## Rules

- Only animate `transform` and `opacity`. Never layout properties.
- One hero animation > many micro-interactions.
- Every animation must pass the "removal test": if removing it makes the UI feel worse, it earned its place. If not, cut it.
- Always implement `prefers-reduced-motion` — it's an accessibility requirement, not optional.
