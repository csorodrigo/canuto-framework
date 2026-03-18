shortDescription: How to extract brand identity from an existing website to bootstrap the design profile.
usedBy: [architect, coder, contextualizer]
version: 1.0.0
lastUpdated: 2026-03-18
copyright: Rodrigo Canuto © 2026.

## When to Use

**Triggers:**
- Starting a new project that must match an existing brand identity (client website, competitor reference, redesign)
- Architect is creating `design-profile.md` and the user provides a URL as visual reference
- Bootstrapping a project where brand assets (logos, colors) already exist on a live website

**Not for:**
- Projects with no existing brand (create `design-profile.md` from scratch via the design interview)
- Extracting assets from local files (use file system tools directly)
- Ongoing design work where the profile is already established

---

## Purpose

Automate the initial population of `design-profile.md` by extracting brand assets (logos, colors, brand name) from a live URL using [OpenBrand](https://github.com/ethanjyx/openbrand). This eliminates manual color-picking and logo-hunting when bootstrapping projects that need to match an existing brand.

Works alongside `frontend-design` (which uses the design profile for visual decisions).

---

## Prerequisites

OpenBrand can be used in three ways (in order of preference):

### Option A: MCP Server (Recommended for Claude Code)
```bash
claude mcp add --transport stdio openbrand -- npx -y openbrand-mcp
```
Requires `OPENBRAND_API_KEY` from [openbrand.sh/dashboard](https://openbrand.sh/dashboard) (free).

### Option B: NPM Library
```bash
npm add openbrand
```
No API key required for programmatic use.

### Option C: Hosted API
```bash
curl "https://openbrand.sh/api/extract?url=https://example.com" \
  -H "Authorization: Bearer <api-key>"
```

Ask the user which method is available. If none, guide them through Option A setup.

---

## Procedure

### 1. Extract Brand Assets

Given a URL from the user:

```bash
# Via MCP (if configured): the tool is available as extract_brand_assets
# Via CLI/API:
curl -s "https://openbrand.sh/api/extract?url=<target-url>" \
  -H "Authorization: Bearer $OPENBRAND_API_KEY" | jq .
```

The extraction returns:
- **brand_name**: Detected brand name
- **logos**: Array of logo URLs (favicons, apple-touch-icon, nav logos, inline SVGs)
- **colors**: Array of detected colors (theme-color, manifest values, dominant colors from logos)
- **backdrop_images**: OG images, hero backgrounds, CSS background images

### 2. Map to Design Profile

Take the extracted data and populate `design-profile.md`:

| Extracted Data | Maps To |
|---|---|
| `brand_name` | Used as project context reference |
| `colors[0]` (primary) | Color Palette → Dominant |
| `colors[1]` (secondary) | Color Palette → Accent 1 |
| `colors[2]` (accent) | Color Palette → Accent 2 |
| `logos` | References section (save URLs) |
| `backdrop_images` | References section |

### 3. Present to User for Validation

**Never auto-commit the extracted profile.** Always present the mapped values and ask:

```
I extracted the following brand identity from <url>:

Brand: <brand_name>
Colors:
  - Dominant: <color1> (used as primary)
  - Accent 1: <color2>
  - Accent 2: <color3>
Logos found: <count> (saved to references)

Does this look correct? Should I adjust any colors or add additional brand references?
```

The user may:
- Approve as-is → write to `design-profile.md`
- Adjust colors → update before writing
- Add more URLs → extract and merge
- Reject → proceed with manual design interview

### 4. Complete the Profile

OpenBrand extracts colors, logos, and brand name — but NOT:
- Typography (heading/body fonts)
- Motion strategy
- Surface treatment preferences
- Visual signature elements
- Aesthetic pattern preferences

After populating the color and reference sections, the Architect must still interview the user for the remaining sections using the standard `frontend-design` skill procedure (Steps 1–6).

### 5. Save Brand Assets Locally (Optional)

If the user wants local copies of extracted assets:

```
.context/attachments/
  brand-logo.svg        # primary logo
  brand-og-image.png    # OG image
```

Reference these in `design-profile.md` under the References section.

---

## Integration with Framework Workflow

### For Architect
During the design interview for M/L tasks:
1. Ask: "Is there an existing website or brand to match?"
2. If yes → run this skill to extract assets before the interview.
3. Pre-fill `design-profile.md` with extracted colors.
4. Continue the design interview for remaining sections (typography, motion, etc.).

### For Contextualizer
When bootstrapping a new project:
1. If the user provides a reference URL during setup → run brand extraction.
2. Include extracted brand data in the initial `.context.md` for the project root.

---

## Examples

### ✅ Good — extract brand, validate, then complete profile

```
User: "I'm rebuilding the dashboard for acme.com. Match their brand."

1. Extract: openbrand extract_brand_assets("https://acme.com")
   → brand_name: "ACME Corp"
   → colors: ["#1a56db" (primary), "#f97316" (accent), "#f8fafc" (background)]
   → logos: [favicon.ico, logo.svg, og-image.png]

2. Present to user:
   "Extracted ACME Corp brand: dominant blue (#1a56db), orange accent (#f97316),
    light background (#f8fafc). 3 logos found. Correct?"

3. User approves → populate design-profile.md Color Palette section

4. Continue interview:
   "Now let's define typography. What mood are you going for?
    The current brand uses clean, corporate blues — professional? Bold? Playful?"

5. Complete remaining sections via standard design interview
```

Extraction accelerates the process; human validates; interview completes the gaps.

### ❌ Bad — auto-populate entire profile without validation

```
1. Extracted colors from URL
2. Guessed typography from "looks corporate" → assigned Inter
3. Wrote full design-profile.md without asking user
4. Coder started implementing with unvalidated profile
```

This is bad because: auto-committed without user validation, guessed typography (OpenBrand doesn't extract fonts), and skipped the design interview for non-extractable sections.

---

## Guardrails

- Never auto-write `design-profile.md` without user validation of extracted data.
- OpenBrand does NOT extract typography or motion preferences — those require the design interview.
- If OpenBrand is not available (no MCP, no API key), fall back to manual design interview entirely.
- Extracted colors may need adjustment — website colors don't always translate directly to app themes.
- Save external asset URLs in references but don't hotlink them in production code.
- Follow `security-practices` for API key handling (`OPENBRAND_API_KEY` goes in `.env`, never committed).
