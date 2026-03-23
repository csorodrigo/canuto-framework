shortDescription: Typography audit and improvement — searches 57 font pairings by mood and product type, returns heading+body pairs with Google Fonts URLs and Tailwind config.
usedBy: [coder, reviewer, architect]
version: 1.0.0
lastUpdated: 2026-03-23
copyright: Rodrigo Canuto © 2026.

## When to Use

**Triggers:**
- Typography hierarchy is inconsistent or uses default browser fonts
- User asks "improve the fonts", "this looks generic", or "choose typography"
- Reviewer flags missing font scale, wrong line-height, or poor readability
- `design-profile.md` Typography section is empty or uses placeholder fonts
- Building a new page/component where type choices haven't been established

**Not for:**
- Full design system generation (use `design-consultation` instead)
- Color issues (use `colorize` instead)
- Fixing spacing or layout (use `frontend-design` instead)

---

## Purpose

Search 57 curated font pairings indexed by mood, style, and product type. Returns heading + body font combinations with Google Fonts import URLs, Tailwind `fontFamily` config, and usage notes. Eliminates font indecision and ensures pairings are aesthetically validated.

---

## Procedure

### Step 1 — Identify the typographic context

Determine from the current project:
- **Mood/style**: elegant, modern, playful, technical, editorial, friendly, authoritative
- **Product type**: dashboard, landing page, marketing, documentation, app, magazine
- **Existing constraint**: brand font to keep, serif vs sans-serif preference, Google Fonts only

### Step 2 — Search font pairings

```bash
python3 .agents/tools/design-search/scripts/search.py "<keyword>" --domain typography
```

**Example queries:**
- `python3 .agents/tools/design-search/scripts/search.py "elegant luxury serif" --domain typography`
- `python3 .agents/tools/design-search/scripts/search.py "technical dashboard data" --domain typography`
- `python3 .agents/tools/design-search/scripts/search.py "modern saas minimal" --domain typography`
- `python3 .agents/tools/design-search/scripts/search.py "friendly startup playful" --domain typography`

Returns up to 3 ranked pairings with:
- **Heading Font** + **Body Font**
- **Mood/Style Keywords**
- **Best For** (product types)
- **Google Fonts URL** (direct link for preview)
- **CSS Import** (ready to paste)
- **Tailwind Config** (fontFamily override)
- **Notes** (contrast rationale and usage guidance)

### Step 3 — Apply to project

**In `globals.css` or layout:**
```css
@import url('<CSS Import from search output>');
```

**In `tailwind.config.ts`:**
```ts
theme: {
  extend: {
    fontFamily: {
      sans: ['<Body Font>', 'sans-serif'],
      serif: ['<Heading Font>', 'serif'],   // if serif heading
      // or:
      heading: ['<Heading Font>', 'sans-serif'],  // if both sans-serif
    }
  }
}
```

**In shadcn/ui base styles:**
```css
body {
  font-family: theme('fontFamily.sans');
}
h1, h2, h3, h4 {
  font-family: theme('fontFamily.heading');
}
```

### Step 4 — Define the type scale

After choosing the pairing, establish the scale in `design-profile.md`:

| Level | Size | Weight | Line-height |
|---|---|---|---|
| Display | 48-72px | 700 | 1.1 |
| H1 | 36-48px | 700 | 1.2 |
| H2 | 28-36px | 600 | 1.25 |
| H3 | 22-28px | 600 | 1.3 |
| Body | 16px | 400 | 1.5 |
| Small | 14px | 400 | 1.4 |
| Caption | 12px | 400 | 1.3 |

Minimum body size is **16px**. Never go below 12px for any visible text.

---

## Examples

### ✅ Good — search → apply → document scale

```
Task: "The landing page for the luxury wellness app uses Arial everywhere."

1. Search:
   python3 .agents/tools/design-search/scripts/search.py "luxury wellness premium elegant" --domain typography
   → Heading: Playfair Display, Body: Inter
   → Google Fonts URL: (link)
   → Tailwind: { serif: ['Playfair Display', 'serif'], sans: ['Inter', 'sans-serif'] }

2. Add @import to globals.css
3. Update tailwind.config.ts fontFamily
4. Apply h1-h4 → fontFamily.serif in base styles
5. Document in design-profile.md Typography section
```

### ❌ Bad — keep defaults, add font weight inline

```
1. Kept font-sans (Tailwind default = Inter everywhere)
2. Added font-bold to headings to "make them stand out"
3. Used font-size: 13px on body text for "compact" look
4. No type scale documented
```

---

## Guardrails

- Never set body text below 16px.
- Never use more than 2 font families in a single project (heading + body).
- Always include the Google Fonts `@import` — missing import means font fallback silently.
- If the project has a `design-profile.md` with existing fonts, update it rather than replacing silently.
- Tailwind's `fontFamily.sans` overrides the default Inter — document this change for future personas.
