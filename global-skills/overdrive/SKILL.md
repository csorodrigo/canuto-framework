shortDescription: Technically ambitious interfaces — View Transitions, scroll-driven animations, WebGL, and advanced browser APIs.
usedBy: [user]
version: 1.0.0
lastUpdated: 2026-03-20

## Purpose

Push an interface past conventional limits using browser capabilities that most developers don't reach for. `/overdrive` is for projects where the experience itself is part of the value proposition: portfolio sites, product launches, creative tools, or any UI where "extraordinary" is a design requirement.

**When not to use:** Settings pages, admin dashboards, data-dense UIs. Overdrive techniques require context appropriateness — they amplify signal, not noise.

## When to Use

- Portfolio, marketing, or launch pages where visual impact drives conversions
- Creative tools where the interface mirrors the product's ambition
- When the design profile's brand personality includes: "bold", "cutting-edge", "immersive", "unforgettable"
- When a technically impressive interaction would meaningfully differentiate the product
- **Not for:** Internal tools, dashboards, settings, or any UI where the data is more important than the experience

## Pre-flight

Before building anything ambitious:
1. Propose 2–3 directions with varying ambition levels — get user buy-in before building
2. Confirm the browser support requirements (View Transitions: Chrome 111+, Safari 18+, no Firefox)
3. Plan the `prefers-reduced-motion` fallback — the reduced version must still be beautiful
4. Identify the 60fps target: will this run on a mid-range laptop (not just a MacBook Pro M3)?

## Technique Catalog

### View Transitions API — Cinematic page navigation

```tsx
// Next.js 14+ with @next/view-transitions or vanilla
document.startViewTransition(() => {
  navigate(newRoute)
})

// CSS — customize the transition
::view-transition-old(root) {
  animation: 300ms ease-out both slide-out-left;
}
::view-transition-new(root) {
  animation: 300ms ease-out both slide-in-right;
}

// Named elements — morph between pages
.hero-image { view-transition-name: hero; }
```

**Best for:** Navigating between list → detail views, card → modal expansions, page-to-page transitions with shared elements.

### Scroll-Driven Animations — Parallax and timeline effects

```css
/* CSS Scroll-Driven Animations (Chrome 115+) */
@keyframes fade-in {
  from { opacity: 0; transform: translateY(24px); }
  to   { opacity: 1; transform: translateY(0); }
}

.reveal-on-scroll {
  animation: fade-in linear both;
  animation-timeline: view();
  animation-range: entry 0% entry 30%;
}

/* Parallax header */
.parallax-header {
  animation: parallax linear;
  animation-timeline: scroll();
}
@keyframes parallax {
  from { transform: translateY(0); }
  to   { transform: translateY(-30%); }
}
```

**Progressive enhancement fallback:**
```tsx
const supportsScrollTimeline = CSS.supports("animation-timeline", "scroll()")
// If false, apply Framer Motion InView as fallback
```

### WebGL / Canvas — Shaders and particle systems

Use Drei + React Three Fiber for declarative Three.js:

```tsx
import { Canvas } from "@react-three/fiber"
import { MeshDistortMaterial, Float } from "@react-three/drei"

<Canvas>
  <Float speed={2} rotationIntensity={0.5} floatIntensity={1}>
    <mesh>
      <sphereGeometry args={[1, 64, 64]} />
      <MeshDistortMaterial
        color="#6d28d9"
        distort={0.4}
        speed={2}
        roughness={0}
        metalness={0.8}
      />
    </mesh>
  </Float>
</Canvas>
```

**Performance rules for WebGL:**
- Use `<Canvas dpr={[1, 2]}>` — limits pixel ratio on high-DPI screens
- `useFrame` delta-based animations, not time-based
- Dispose geometries and materials on unmount
- Lazy-load the Canvas component — don't block initial render

### Virtual Scrolling — Massive lists at 60fps

```tsx
import { useVirtualizer } from "@tanstack/react-virtual"

const virtualizer = useVirtualizer({
  count: items.length,
  getScrollElement: () => parentRef.current,
  estimateSize: () => 72, // estimated row height
  overscan: 5,
})

return (
  <div ref={parentRef} style={{ height: "600px", overflow: "auto" }}>
    <div style={{ height: virtualizer.getTotalSize() }}>
      {virtualizer.getVirtualItems().map((item) => (
        <div key={item.key} style={{ transform: `translateY(${item.start}px)` }}>
          {items[item.index]}
        </div>
      ))}
    </div>
  </div>
)
```

**Use when:** > 500 items in a list or table.

### Web Audio API — Sonic feedback

```ts
const ctx = new AudioContext()

const playClick = () => {
  const osc = ctx.createOscillator()
  const gain = ctx.createGain()
  osc.connect(gain)
  gain.connect(ctx.destination)
  osc.frequency.value = 800
  gain.gain.setValueAtTime(0.1, ctx.currentTime)
  gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.1)
  osc.start()
  osc.stop(ctx.currentTime + 0.1)
}
```

**Rule:** Audio must be opt-in. Never play sound without explicit user action or preference setting.

## The Removal Test

Before shipping any ambitious feature, apply the removal test:

> "If I remove this effect, does the user experience become meaningfully worse?"

If yes — it earned its place. If no — cut it. Overdrive techniques must improve the experience, not just demonstrate technical capability.

## Performance Checklist

- [ ] Runs at 60fps on Chrome with CPU 4x slowdown (DevTools → Performance)
- [ ] `prefers-reduced-motion` fallback implemented and visually coherent
- [ ] WebGL Canvas lazy-loaded (not in initial bundle)
- [ ] No layout shift on animation start (no width/height/margin changes)
- [ ] Mobile tested — touch interactions work, no jank
- [ ] Graceful degradation if browser API unsupported

## Rules

- Propose directions before building — don't spend 3 hours on a WebGL effect the user didn't want.
- Progressive enhancement: the feature must work without the ambitious layer.
- One focal "wow moment" per view — competing overdrive effects cancel each other.
- 60fps on mid-range devices, not just high-end machines.
- Audio requires explicit opt-in.
