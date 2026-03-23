shortDescription: Strategic color introduction — searches 161 color palettes by product type and mood, returns semantic token sets ready for Tailwind/shadcn.
usedBy: [coder, reviewer, architect]
version: 1.0.0
lastUpdated: 2026-03-23
copyright: Rodrigo Canuto © 2026.

## When to Use

**Triggers:**
- UI is monochromatic or uses raw hex values without a semantic system
- User asks "add color", "improve the color scheme", or "this looks boring"
- Reviewer flags inconsistent use of color tokens
- `design-profile.md` has a color palette that needs expansion or adjustment
- Coder needs a semantic color set for a new product type

**Not for:**
- Generating a full design system from scratch (use `design-consultation` instead)
- Extracting brand colors from an existing website (use `brand-bootstrap` instead)
- Typography or layout issues (use `typeset` or `frontend-design` instead)

---

## Purpose

Search 161 curated color palettes indexed by product type and mood. Returns a complete semantic token set (primary, secondary, accent, background, foreground, card, muted, border, destructive, ring) with WCAG-compliant contrast notes and Tailwind-ready values. Eliminates guesswork when choosing colors.

---

## Procedure

### Step 1 — Identify the color context

Determine from the current task:
- **Product type**: fintech, healthcare, SaaS, e-commerce, creative, etc.
- **Mood/intent**: dark mode, trust, energy, luxury, minimal, bold, etc.
- **Existing constraint**: must match brand, dark/light preference, specific color to keep

### Step 2 — Search palettes

```bash
python3 .agents/tools/design-search/scripts/search.py "<keyword>" --domain color
```

**Example queries:**
- `python3 .agents/tools/design-search/scripts/search.py "fintech dark trust" --domain color`
- `python3 .agents/tools/design-search/scripts/search.py "healthcare minimal light" --domain color`
- `python3 .agents/tools/design-search/scripts/search.py "saas enterprise blue" --domain color`
- `python3 .agents/tools/design-search/scripts/search.py "e-commerce luxury warm" --domain color`

Returns up to 3 ranked palettes with: Primary, Secondary, Accent, Background, Foreground, Card, Muted, Border, Destructive, Ring, and WCAG contrast notes.

### Step 3 — Apply to Tailwind/shadcn config

Map the returned palette to `tailwind.config.ts` CSS variables (shadcn convention):

```css
:root {
  --primary: <primary-hsl>;
  --primary-foreground: <on-primary-hsl>;
  --secondary: <secondary-hsl>;
  --accent: <accent-hsl>;
  --background: <background-hsl>;
  --foreground: <foreground-hsl>;
  --card: <card-hsl>;
  --muted: <muted-hsl>;
  --border: <border-hsl>;
  --destructive: <destructive-hsl>;
  --ring: <ring-hsl>;
}
```

**Convert hex → HSL** before writing to CSS variables. Never use raw hex in component code — always use semantic tokens.

### Step 4 — Validate contrast

Check the palette notes for WCAG annotations. If contrast adjustments were made (marked as `[Accent adjusted from X for WCAG 3:1]`), honor those adjustments in the implementation.

Minimum requirements:
- Body text on background: **4.5:1**
- Large text (24px+) and UI components: **3:1**
- Decorative elements: no requirement

---

## Examples

### ✅ Good — search → semantic tokens → verify contrast

```
Task: "The dashboard uses raw #3B82F6 everywhere. Fix the color system."

1. Search:
   python3 .agents/tools/design-search/scripts/search.py "saas dashboard analytics" --domain color
   → Primary: #2563EB, Accent: #F97316, Background: #F8FAFC, WCAG: compliant

2. Apply semantic tokens in tailwind.config.ts globals.css
3. Replace all raw #3B82F6 references with var(--primary)
4. Verify contrast: #2563EB on #F8FAFC = 5.1:1 ✓
```

### ❌ Bad — pick hex by eye, skip semantic tokens

```
1. Googled "blue hex codes" → picked #4A90D9 because it looked nice
2. Used raw hex directly in className="bg-[#4A90D9]"
3. Never checked contrast ratio
4. Dark mode broken because background was hardcoded
```

---

## Guardrails

- Never use raw hex values in component code — always map to semantic tokens first.
- Always check WCAG notes in the search output before implementing.
- If the search returns a dark palette for a light-mode project, explicitly ask if the user wants to switch modes or invert the palette.
- Palette tokens are a starting point — user can adjust individual values after approval.
