---
name: frontend-design
description: Apply opinionated visual direction and design guardrails so frontend work avoids generic default UI.
shortDescription: How to make frontend features visually distinctive and design-coherent.
usedBy: [coder, reviewer, architect]
version: 4.0.0
lastUpdated: 2026-03-23
copyright: Rodrigo Canuto © 2026.
evals:
  - prompt: "implementing the dashboard page now, what design patterns should i apply?"
    should_trigger: true
  - prompt: "reviewer pass on a feature that adds a new modal for editing user settings"
    should_trigger: true
  - prompt: "add a new API endpoint for fetching user preferences"
    should_trigger: false
  - prompt: "write unit tests for the dashboard component"
    should_trigger: false
---

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

> **References** (read on demand):
> - `references/design-patterns.md` — LLM bias correction, 5 design principles detail, examples
> - `references/aesthetic-patterns.md` — 8 aesthetic pattern recipes + inspiration/preview protocols

---

## Context Gathering Protocol

Before any visual work on a **new project or unfamiliar codebase**, gather these 4 inputs (feeds `design-profile.md`):

| Question | Why it matters |
|----------|----------------|
| **Target audience** | Shapes tone: clinical, playful, premium |
| **Primary use cases** — Top 3 workflows | Determines density and information hierarchy |
| **Brand personality** — 3–5 adjectives | Translates to weight, saturation, motion intensity |
| **Competitive context** — What to stand out from | Identifies clichés to actively avoid |

If `design-profile.md` already exists and answers these, skip directly to reading it.

---

## Design Knobs

| Knob | Default | Range | Description |
|------|---------|-------|-------------|
| **DESIGN_VARIANCE** | 6 | 1–10 | 1 = symmetric. 10 = asymmetric, editorial. |
| **MOTION_INTENSITY** | 5 | 1–10 | 1 = hover only. 10 = choreographed Framer Motion. |
| **VISUAL_DENSITY** | 4 | 1–10 | 1 = airy editorial. 10 = cockpit-mode packed. |

> Defaults (6, 5, 4) are more conservative than Taste Skill reference (8, 6, 4) for production SaaS. Adjust in `design-profile.md`.

**How knobs affect decisions (summary):**
- DESIGN_VARIANCE 1–3: centered, symmetrical. 4–7: offset, left-aligned. 8–10: masonry, fractional CSS Grid.
- MOTION_INTENSITY 1–3: CSS hover/active only. 4–7: cubic-bezier transitions + staggered delays. 8–10: Framer Motion spring physics.
- VISUAL_DENSITY 1–3: large section gaps, editorial. 4–7: standard app spacing. 8–10: compact padding, `border-t`/`divide-y`.
- Mobile override: for DESIGN_VARIANCE 4+, asymmetric layouts above `md:` must collapse to single-column on viewports <768px.

For LLM bias correction patterns and full design principle details, read `references/design-patterns.md`.

---

## Required UI States

Every interactive component **must** implement all 4 states (LLMs naturally generate happy-path only):

- **Loading:** Skeletal loaders matching the layout shape — not generic spinners
- **Empty:** Composed empty states with guidance on how to populate data
- **Error:** Inline, clear error reporting — not just `console.log`
- **Tactile feedback:** On `:active`, apply `-translate-y-[1px]` or `scale-[0.98]`

---

## Procedure

### 1. Read the Design Profile
Read `~/.canuto/vault/projects/{project-slug}/design/profile.md`.
- If missing for M/L tasks: Architect creates it during interview. Do not implement UI without a profile.
- For S/XS without Architect: proceed to Step 5 (Design Preview), then bootstrap a minimal profile from the approved variation.

### 2. Consult the Component Inventory
Read `~/.canuto/vault/projects/{project-slug}/design/components/`.
- Reuse if exists. Extend with a new variant if close. Create + add to inventory if nothing fits.

### 3. Apply Design Principles
Apply at least 3 of the 5 principles: **Typography, Color, Motion, Backgrounds, Composition**.
Do not ship vanilla shadcn/ui components without customization.
→ Full principle detail: `references/design-patterns.md` (section: Design Principles)

### 4. Reference Aesthetic Patterns
Apply patterns from the design profile's `Preferred Aesthetic Patterns` section.
Available patterns: Glassmorphism, Glow Accents, Depth Layering, Color-per-Card, Tactile Surfaces, Spatial Decorators, Liquid Glass, Spring Physics Motion.
→ CSS recipes: `references/aesthetic-patterns.md`

### 5. Inspiration Ingestion (when user provides references)
1. View each reference. 2. Extract: palette, typography, surfaces, layout, effects, mood.
3. Map to aesthetic patterns. 4. Document in plan's Design Direction section.
→ Full protocol: `references/aesthetic-patterns.md` (section: Inspiration Ingestion)

### 6. Design Preview Protocol
Before implementing UI, present 3 visually distinct variations. Each must use different aesthetic patterns.
- For M/L (Architect): describe 3 variations in plan's Design Direction section.
- For S/XS (Coder): generate 3 code variations. User chooses. Only continue with chosen.
→ Format: `references/aesthetic-patterns.md` (section: Design Preview)

### 7–9. Per-Persona Actions (Architect, Coder, Reviewer)
→ Full per-persona checklists: `references/design-patterns.md` (section: Per-Persona Actions)

---

## Golden Rule

> "Make unexpected but contextually coherent choices. If the previous generation used a centered hero, try a split layout. If it used a gradient, try a textured pattern. Always vary — but stay within the design profile."

---

## Performance Guardrails

- Never animate `top`, `left`, `width`, or `height` — animate only `transform` and `opacity`
- Apply noise/grain filters only to fixed, `pointer-events-none` pseudo-elements
- Use `will-change: transform` sparingly, only on actively animating elements
- Wrap perpetual animations in memoized Client Components (`React.memo`)
- Ensure all `useEffect` animations contain strict cleanup functions

---

## Guardrails

- Do not introduce CSS-in-JS or styled-components — Tailwind only
- Do not add animation libraries beyond Framer Motion without approval
- Do not override shadcn/ui internals — extend via `className`, `variants`, or wrappers
- Do not ignore the design profile — escalate to Architect for updates
- Do not copy-paste component code — extract to shared components + add to inventory
- Glassmorphism and glow effects require WCAG AA contrast testing

---

## Specialized Design Skills

Use these skills when the task requires deeper domain expertise beyond this skill's scope:

| Skill | When to reach for it |
|---|---|
| `design-consultation` | No `design-profile.md` exists; need to generate a full design system from requirements using BM25 search over 161 color palettes, 57 font pairings, 50+ styles |
| `colorize` | Color scheme is monochromatic, uses raw hex, or needs a semantic token set (primary/accent/background) for a specific product type or mood |
| `typeset` | Typography hierarchy is inconsistent, uses default fonts, or needs a validated heading+body pairing with Google Fonts URL and Tailwind config |
| `audit` | Pre-ship UI review — structured a11y checklist, UX guideline lookup (99 guidelines), and pre-delivery checklist with CRITICAL/HIGH/MEDIUM/LOW severity |
| `brand-bootstrap` | Existing brand website provided as reference; extract colors + logos automatically |

These skills use `.agents/tools/design-search/` (BM25 search engine over curated design CSVs). Python 3 required.
