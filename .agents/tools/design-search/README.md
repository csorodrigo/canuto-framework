shortDescription: BM25 search engine over curated design database — 161 color palettes, 57 font pairings, 50+ styles, 99 UX guidelines, 161 product types.
maintainer: nextlevelbuilder/ui-ux-pro-max-skill (ported to Canuto Framework)
version: ported 2026-03-23

# design-search

Python-based search engine for design intelligence. No pip dependencies — stdlib only.

## Quick Reference

```bash
# Full design system from natural language query
python3 .agents/tools/design-search/scripts/search.py "saas dashboard minimal enterprise" \
  --design-system --project-name "MyApp" --format markdown --persist

# Color palettes by product/mood
python3 .agents/tools/design-search/scripts/search.py "fintech dark trust" --domain color

# Font pairings by mood
python3 .agents/tools/design-search/scripts/search.py "elegant luxury" --domain typography

# UX guidelines for context
python3 .agents/tools/design-search/scripts/search.py "form onboarding" --domain ux

# Style recommendations
python3 .agents/tools/design-search/scripts/search.py "minimal saas" --domain style

# Landing page patterns
python3 .agents/tools/design-search/scripts/search.py "conversion saas" --domain landing

# Chart type recommendations
python3 .agents/tools/design-search/scripts/search.py "time series analytics" --domain chart

# Google Fonts recommendations
python3 .agents/tools/design-search/scripts/search.py "modern readable" --domain google-fonts
```

## Available domains

| Flag | Database | What it returns |
|---|---|---|
| `--domain color` | colors.csv | Semantic token sets (primary, accent, bg, fg) with WCAG notes |
| `--domain typography` | typography.csv | Heading+body pairs with Google Fonts URL + Tailwind config |
| `--domain ux` | ux-guidelines.csv | UX guidelines by category with key checks + anti-patterns |
| `--domain style` | styles.csv | Visual style name, keywords, best-for, performance |
| `--domain product` | products.csv | Product type matching with recommended patterns |
| `--domain landing` | landing.csv | Landing page section patterns + conversion strategy |
| `--domain chart` | charts.csv | Chart type recommendations |
| `--domain icons` | icons.csv | Icon style recommendations |
| `--domain google-fonts` | google-fonts.csv | Google Fonts with CSS imports |
| `--domain web` | app-interface.csv | Web interface guidelines |

## Design system generation

```bash
python3 .agents/tools/design-search/scripts/search.py "<query>" \
  --design-system \
  --project-name "<name>" \
  --format markdown \
  --persist \
  [--page "<page-name>"]
```

Outputs: pattern + style + colors + typography + effects + anti-patterns + pre-delivery checklist.

With `--persist`: writes `design-system/MASTER.md` and optionally `design-system/pages/<page>.md`.

## Consuming skills

| Skill | Uses |
|---|---|
| `design-consultation` | `--design-system --persist` |
| `colorize` | `--domain color` |
| `typeset` | `--domain typography` |
| `audit` | `--domain ux` + checklist |

## Database contents

- **colors.csv**: 161 semantic color palettes indexed by product type
- **typography.csv**: 57 font pairings with Tailwind config
- **styles.csv**: 50+ visual styles (glassmorphism, minimalism, brutalism, etc.)
- **ux-guidelines.csv**: 99 UX guidelines across 10 categories (a11y, touch, forms, nav, etc.)
- **products.csv**: 161 product types with reasoning rules
- **ui-reasoning.csv**: 100 rules for matching product type → UI category
- **landing.csv**: Landing page conversion patterns
- **charts.csv**: 25 chart type recommendations

## Source

Ported from [nextlevelbuilder/ui-ux-pro-max-skill](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill).
Scripts: `scripts/core.py` (BM25 + CSV loader), `scripts/search.py` (CLI), `scripts/design_system.py` (generator).
