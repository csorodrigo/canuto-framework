shortDescription: Comprehensive final quality pass before shipping — spacing, states, alignment, and details.
usedBy: [user]
version: 1.0.0
lastUpdated: 2026-03-20

## Purpose

Polish is the last step, not the first. It catches the final 20% that separates "functional" from "finished". Run after all feature work is complete and the design direction is set. Polish fixes alignment, spacing consistency, missing interaction states, keyboard navigation, and the small details that break the impression of quality.

## When to Use

- Before opening a PR for any feature with user-facing UI
- After `/bolder` or `/colorize` — to ensure the amplification didn't introduce inconsistencies
- After the Reviewer's Design Lens — to action SHOULD FIX issues
- When the user says "it's almost there, just needs finishing"

## Procedure

### Pass 1 — Visual Alignment

Walk through every UI element systematically:

- **Spacing:** Is every gap using a Tailwind spacing scale value (`gap-4`, `p-6`, `mb-8`) or a CSS custom property? No arbitrary pixel values (`gap-[13px]`).
- **Alignment:** Elements that should align vertically or horizontally actually align. Check text baselines, icon-to-text pairs, grid column starts.
- **Margin consistency:** Same component type (e.g., all cards) uses same padding internally. Headers across sections use consistent margin-bottom.
- **Icon sizing:** Icons in the same context are the same size (`w-4 h-4` or `w-5 h-5`, not a mix).
- **Border radius:** Consistent use of a single radius scale from `design-profile.md`. Not `rounded-md` on one card and `rounded-2xl` on the next unless intentional.

### Pass 2 — Interaction States

Every interactive element must implement all states. Review each button, input, link, and toggle:

| State | Must have |
|-------|-----------|
| **Default** | Base appearance |
| **Hover** | Visual feedback (color, shadow, transform) |
| **Focus** | Visible `:focus-visible` ring (accessibility) |
| **Active** | Tactile feedback: `active:-translate-y-px active:scale-[0.98]` |
| **Disabled** | Reduced opacity + `cursor-not-allowed`, non-interactive |
| **Loading** | Skeleton or spinner matching layout shape |
| **Error** | Inline error message + red border/ring, not just console.log |
| **Success** | Positive confirmation state where applicable |

### Pass 3 — Typography Consistency

- Body text size consistent across similar content (all card descriptions same `text-sm`, all section intros same `text-base`)
- No widows (single word on last line of a paragraph) — use `text-pretty` or `text-balance` on headings
- Heading hierarchy makes sense: `h1` → `h2` → `h3` never skips levels
- No mixed `font-medium` and `font-semibold` for the same UI role — pick one

### Pass 4 — Color & Theming

- No hardcoded hex or RGB values — all colors reference CSS custom properties or Tailwind tokens
- Dark mode: every element has a `dark:` variant if the project supports dark mode
- No text on colored backgrounds without checking contrast (≥ 4.5:1)

### Pass 5 — Responsiveness

- Check every breakpoint: `sm` (640px), `md` (768px), `lg` (1024px)
- Asymmetric desktop layouts collapse to single-column (`w-full`) on mobile
- No horizontal scroll on any viewport width
- Text doesn't overflow fixed-width containers (use `overflow-hidden text-ellipsis` or `truncate` where needed)
- `min-h-[100dvh]` instead of `h-screen` everywhere

### Pass 6 — Edge Cases & Copy

- Long strings: does layout handle a user name with 40 characters? A description with 3 lines?
- Empty states: what appears when there's no data? (Not a blank white void)
- Loading states: does every async operation show a skeleton or indicator?
- No generic copy ("Loading...", "Error occurred") — messages should be helpful and contextual
- No placeholder text in production-bound components ("Lorem ipsum", "John Doe")

### Pass 7 — Keyboard Navigation

- Tab order follows visual reading order
- All interactive elements reachable via keyboard
- Modals trap focus correctly; Esc closes them
- Skip-to-content link present for long pages

## Checklist Output Format

```
## Polish Checklist

### Done
- [x] All spacing uses Tailwind scale
- [x] Focus rings on all interactive elements
...

### Needs fix
- [ ] Card description text overflows at 2x zoom — add `overflow-hidden`
- [ ] Button missing `:active` state
- [ ] Dark mode missing on tooltip
...
```

## Rules

- Polish after feature work, not during. Mixing implementation and polish leads to incomplete passes.
- Do not ship without checking all states — missing loading/error states are bugs, not polish.
- Polish issues are **SHOULD FIX** unless they break usability (then MUST FIX).
- Run `/audit` first to get a prioritized issue list, then use `/polish` to work through each category systematically.
