shortDescription: Generates a complete design system from user requirements using BM25 search over a curated database of 50+ styles, 161 color palettes, 57 font pairings, and 161 product types.
usedBy: [architect, coder, contextualizer]
version: 1.0.0
lastUpdated: 2026-03-23
copyright: Rodrigo Canuto © 2026.

## When to Use

**Triggers:**
- Starting a new project with no design system defined
- `design-profile.md` does not exist or is empty
- User asks "what design should this have?", "create a visual identity", or "choose a style"
- Architect is creating the design profile for a new page/feature from scratch

**Not for:**
- Projects with an established `design-profile.md` (use `frontend-design` instead)
- Extracting brand from an existing website (padrão arquivado em `_archive/brand-bootstrap.md`)
- Quick color or typography tweaks (use `/colorize` or `/typeset` instead)

---

## Purpose

Generate a complete, opinionated design system recommendation from natural language requirements. Uses BM25 search over a curated database to match product type → style → color palette → typography → stack-specific guidelines. Output persists to `design-system/MASTER.md` for hierarchical retrieval by all personas.

Works alongside `frontend-design` (consumes the generated profile for implementation decisions). Extração automática de brand era papel do `brand-bootstrap` (arquivado).

---

## Prerequisites

Python 3 must be available. Scripts are at `.agents/tools/design-search/scripts/`. No pip dependencies — stdlib only.

```bash
python3 --version  # must be 3.x
```

---

## Procedure

### Step 1 — Extract requirements from user

Before running the search, extract from the user's request:
- **Product type**: SaaS, dashboard, landing page, e-commerce, mobile app, etc.
- **Industry/domain**: fintech, healthcare, creative, enterprise, etc.
- **Style keywords**: minimal, bold, elegant, playful, data-dense, etc.
- **Primary audience**: developers, executives, consumers, etc.

If unclear, ask before proceeding. Use AskUserQuestion for this.

### Step 2 — Generate complete design system

```bash
python3 .agents/tools/design-search/scripts/search.py "<query>" \
  --design-system \
  --project-name "<project name>" \
  --format markdown \
  --persist
```

Replace `<query>` with a descriptive phrase combining product type + industry + style keywords.

**Example queries:**
- `"saas dashboard analytics minimal enterprise"`
- `"e-commerce fashion luxury editorial"`
- `"fintech mobile app dark bold"`

This creates:
- `design-system/MASTER.md` — global design rules (pattern, style, colors, typography, effects, anti-patterns)
- `design-system/pages/<page>.md` — page-specific overrides (if `--page` flag used)

### Step 3 — Present to user for approval

Show the generated design system highlights:

```
Design System generated for <Project Name>:

Style: <style name> — <keywords>
Colors: Primary <hex>, Accent <hex>, Background <hex>
Typography: <heading font> (heading) + <body font> (body)
Key effects: <effects>
Anti-patterns to avoid: <list>

Does this direction feel right? Any adjustments before we proceed?
```

**Never auto-proceed to implementation without user validation.**

### Step 4 — Optional: query for additional domain details

If the user needs more detail on a specific domain:

```bash
# More color palette options
python3 .agents/tools/design-search/scripts/search.py "<keyword>" --domain color

# Typography alternatives
python3 .agents/tools/design-search/scripts/search.py "<keyword>" --domain typography

# UX guidelines for this product type
python3 .agents/tools/design-search/scripts/search.py "<keyword>" --domain ux

# Landing page patterns
python3 .agents/tools/design-search/scripts/search.py "<keyword>" --domain landing

# Icon style recommendations
python3 .agents/tools/design-search/scripts/search.py "<keyword>" --domain icons
```

### Step 5 — Map to design-profile.md

After user approval, translate the design system into the project's `design-profile.md` using the standard format defined in `frontend-design`. Key mappings:

| Design System Output | design-profile.md section |
|---|---|
| Colors (primary, accent, background, text) | Color Palette |
| Typography (heading + body fonts + Google Fonts URL) | Typography |
| Style name + keywords | Aesthetic Pattern |
| Key effects | Motion & Effects |
| Anti-patterns | Guardrails |

---

## Page-specific overrides

To generate a design system override for a specific page:

```bash
python3 .agents/tools/design-search/scripts/search.py "<page-specific query>" \
  --design-system \
  --format markdown \
  --persist \
  --page "<page-name>"
```

Creates `design-system/pages/<page-name>.md`. Page rules override MASTER.md rules for that page only.

---

## Examples

### ✅ Good — query → present → validate → map to profile

```
User: "Building a SaaS analytics dashboard for enterprise data teams."

1. Query: "saas dashboard analytics enterprise data"
   python3 .agents/tools/design-search/scripts/search.py "saas dashboard analytics enterprise data" \
     --design-system -p "DataApp" -f markdown --persist

2. Present to user:
   "Generated design system for DataApp:
    Style: Data-Dense Dashboard — minimal padding, grid layout, max data visibility
    Colors: Primary #2563EB, Accent #F97316, Background #F8FAFC
    Typography: Fira Code (heading) + Fira Sans (body)
    Effects: Hover tooltips, chart zoom, smooth filter animations
    Avoid: Ornate design, no-filter layouts

    Does this feel right for your data team users?"

3. User approves → map to design-profile.md
```

### ❌ Bad — skip query, auto-generate profile, proceed to code

```
1. Assumed "minimal + blue" based on "enterprise" keyword
2. Wrote design-profile.md without running search or showing user
3. Coder started implementing with unvalidated choices
```

---

## Guardrails

- Never write `design-profile.md` or start implementation without user validation.
- The design system is a recommendation — user can override any dimension.
- If query returns weak results (low confidence), ask the user for more keywords.
- When a `design-profile.md` already exists, do not overwrite it — ask if the user wants to update it.
- `design-system/MASTER.md` is auto-generated and can be regenerated safely; `design-profile.md` is human-curated.

---

## Multimodal analysis (v2.0, 2026-04-29)

Use **Claude (multimodal nativo)** como analisador visual primário — Claude
Opus 4.7 lê imagens diretamente. Para análise de logic/contraste/a11y do
componente em paralelo, spawn `codex exec --profile reviewer`.

```
# 1. Capture via /browse, /gstack ou Playwright (Codex) — nunca screencapture
#    automático sem mask (risco PII)
# 2. Compartilhe screenshot inline na conversa Claude OU referencie path
# 3. Claude analisa visual diretamente (a11y, spacing, hierarquia, overflow)
# 4. Para logic do componente (state, render, ARIA): spawn codex em paralelo
```

> Historical note (2026-04-29): previously delegated screenshot analysis to
> Gemini 3.1-pro-preview multimodal. Gemini foi removido; multimodal nativo
> do Claude cobre o use case com uma dependência a menos.
