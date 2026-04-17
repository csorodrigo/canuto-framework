shortDescription: Systematic multi-dimensional UI quality scan — a11y, UX guidelines, interaction states, responsiveness — with a structured pre-delivery checklist.
usedBy: [reviewer, tester, architect]
version: 1.0.0
lastUpdated: 2026-03-23
copyright: Rodrigo Canuto © 2026.

## When to Use

**Triggers:**
- Pre-ship UI review — catching issues before the PR merges
- User asks "audit the interface", "check for accessibility issues", or "is this ready to ship?"
- Reviewer is doing a UI pass and needs structured coverage
- New page/component completed and needs quality gate before handoff
- UX feedback received but root cause is unclear

**Not for:**
- Performance profiling (use dedicated profiling tools)
- Security auditing (use `security-practices`)
- Design system generation (use `design-consultation`)
- Visual polish after audit (use `frontend-design`)

---

## Purpose

Run a structured UX audit combining:
1. BM25-powered UX guideline lookup (99 guidelines across 10 categories)
2. A fixed pre-delivery checklist covering critical a11y, interaction, and layout checks

Produces a prioritized list of issues with severity levels (CRITICAL → LOW) so the Reviewer knows what to fix first.

---

## Procedure

### Step 1 — Identify audit scope

Determine from the current task:
- **What to audit**: specific page, component, or full app
- **Focus areas**: a11y, mobile UX, forms, navigation, data display, animations
- **Target users**: general public, enterprise, mobile-first, etc.

### Step 2 — Query UX guidelines for the context

```bash
python3 .agents/tools/design-search/scripts/search.py "<context keyword>" --domain ux
```

**Example queries:**
- `python3 .agents/tools/design-search/scripts/search.py "form validation onboarding" --domain ux`
- `python3 .agents/tools/design-search/scripts/search.py "navigation mobile sidebar" --domain ux`
- `python3 .agents/tools/design-search/scripts/search.py "data table dashboard" --domain ux`
- `python3 .agents/tools/design-search/scripts/search.py "animation transition feedback" --domain ux`

Returns up to 3 relevant UX guidelines with category, key checks (must have), and anti-patterns (avoid).

### Step 3 — Run the pre-delivery checklist

Apply this checklist to the UI under review. Mark each item as ✅ pass, ❌ fail, or ⚠️ warning.

#### CRITICAL — Block ship if failing

**Accessibility:**
- [ ] Text contrast ≥ 4.5:1 (body), ≥ 3:1 (large text 24px+)
- [ ] All interactive elements reachable via keyboard (Tab order correct)
- [ ] Focus rings visible on all focusable elements (not hidden by `outline: none`)
- [ ] Images have descriptive `alt` text; decorative images have `alt=""`
- [ ] Icon-only buttons have `aria-label`
- [ ] Form inputs have associated `<label>` (not placeholder-only)

**Touch & Interaction:**
- [ ] All tap targets ≥ 44×44px (iOS) / 48×48dp (Material)
- [ ] `cursor-pointer` on all clickable elements
- [ ] Loading state shown on async actions (button disabled + spinner)
- [ ] Errors displayed near the field that caused them (not only at top)

#### HIGH — Fix before ship

**Responsiveness:**
- [ ] Layout works at 375px (mobile), 768px (tablet), 1024px (laptop), 1440px (desktop)
- [ ] No horizontal scroll on any viewport width
- [ ] No fixed-px container widths that break on small screens

**Animation:**
- [ ] Transitions between 150–300ms (not instant, not slow)
- [ ] `prefers-reduced-motion` respected — animations disabled or reduced when set

**Navigation:**
- [ ] Back button/gesture works as expected
- [ ] Deep links work (URL reflects current state)
- [ ] Bottom nav has ≤ 5 items (mobile)

#### MEDIUM — Fix if time allows

**Typography:**
- [ ] Body text ≥ 16px
- [ ] Line-height ≥ 1.5 for body text
- [ ] No gray-on-gray text combinations
- [ ] Semantic color tokens used (no raw hex in components)

**Forms:**
- [ ] Helper text explains constraints (password requirements, format, etc.)
- [ ] Required fields marked clearly
- [ ] Progressive disclosure — don't show all fields upfront if unnecessary

**Charts & Data:**
- [ ] Legends and tooltips present on all charts
- [ ] Color is not the only way to convey meaning (add icons/labels for colorblind users)

#### LOW — Polish pass

- [ ] No emoji used as icons (use SVG: Lucide/Heroicons)
- [ ] Hover states smooth (150ms transition)
- [ ] Empty states designed (not blank white space)
- [ ] Skeleton loaders for content that takes >300ms to load

### Step 4 — Report findings

Structure the report as:

```
## Audit Report: <Component/Page>

### CRITICAL (block ship)
- [ ] <Issue description> — <specific element/location> — fix: <suggested fix>

### HIGH (fix before ship)
- [ ] <Issue description> — <location> — fix: <suggestion>

### MEDIUM (fix if time allows)
- [ ] <Issue description> — <location>

### PASS
- ✅ <What was checked and passed>

### Verdict: SHIP-READY / BLOCKED / NEEDS REVIEW
```

---

## Examples

### ✅ Good — structured audit with prioritized output

```
Task: "Review the onboarding form before we ship."

1. Query UX guidelines:
   python3 .agents/tools/design-search/scripts/search.py "form onboarding registration" --domain ux
   → Returns: form labels, error placement, progressive disclosure guidelines

2. Run pre-delivery checklist against the form
   → CRITICAL fail: email input has no <label>, only placeholder
   → HIGH fail: submit button has no loading state
   → MEDIUM fail: password requirements shown as error only, not as helper text
   → PASS: contrast, keyboard nav, touch targets

3. Report:
   CRITICAL: Add <label for="email"> — "Email" placeholder disappears on focus
   HIGH: Disable submit button + show spinner on async submit
   MEDIUM: Add helper text under password field listing requirements

   Verdict: BLOCKED — fix CRITICAL items before ship
```

### ❌ Bad — visual-only review, skip checklist

```
1. Looked at screenshot
2. "Looks good to me — colors are nice, layout is clean"
3. Shipped without checking keyboard nav, contrast, or touch targets
4. JIRA tickets filed post-ship for a11y issues
```

---

## Guardrails

- CRITICAL items always block ship — do not negotiate these with the user.
- HIGH items should block ship unless there is an explicit, documented exception.
- If a CRITICAL item cannot be fixed now, create a tracking note in `.agents/vault/pending/`.
- Report must always include a Verdict: SHIP-READY, BLOCKED, or NEEDS REVIEW.
- When auditing a component in isolation, note which checks require full-page context to verify.

---

## Gemini multimodal integration

Este skill analisa screenshots ou consome mídia visual. Use **Gemini 3.1-pro-preview**
como analisador visual primário — OCR + layout understanding são superiores ao que
Claude isolado faz com imagens (POC 2026-04-17 validou coerência).

```
# 1. Capture via /browse, /gstack ou Playwright (Codex) — nunca screencapture
#    automático sem mask (risco PII — ver gemini-routing.md)
# 2. Copie a imagem pra dentro do workspace (gemini-cli bloqueia /tmp)
cp /path/to/shot.png .context/shot.png

# 3. Analise via Gemini multimodal
mcp__gemini__ask-gemini({
  prompt: "@.context/shot.png [análise específica — a11y, spacing, hierarquia,
           overflow, etc.]. Output em markdown estruturado.",
  model: "gemini-3.1-pro-preview"
})

# 4. Delete imediatamente
rm .context/shot.png
```

Gemini faz **ver** (OCR objetivo). Claude Opus faz **julgar** (taste).
Ver `.agents/skills/gemini-routing.md` pros gotchas.
