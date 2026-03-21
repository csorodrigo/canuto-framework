---
name: defuddle
description: Extract clean readable markdown from web pages using defuddle CLI. Removes navigation, ads, and clutter. Preferred over WebFetch for standard web pages to reduce token consumption.
origin: kepano/obsidian-skills (adapted for Canuto Framework)
---

# Defuddle Skill

Extract clean, readable content from web pages. Removes navigation, ads, and unnecessary clutter. Preferred over WebFetch for standard web pages — produces cleaner markdown with fewer tokens.

## When to Use

- When ingesting web content into the Canuto vault
- When the user asks to clip or save web content as markdown
- When standard WebFetch returns too much noise (nav, ads, footers)
- When researching external sources for decisions or context

## Installation

```bash
npm install -g defuddle
```

## Usage

Always use the `--md` flag for markdown output:

```bash
defuddle parse <url> --md
```

### Save to File

```bash
defuddle parse <url> --md -o content.md
```

### Extract Metadata

```bash
defuddle parse <url> -p title
defuddle parse <url> -p description
defuddle parse <url> -p domain
```

## Examples

### ✅ Good — Clean web content extraction

```bash
# Extract article content as markdown
defuddle parse https://example.com/blog/article --md

# Save to vault
defuddle parse https://example.com/blog/article --md -o .agents/vault/research/article.md

# Get title for frontmatter
defuddle parse https://example.com/blog/article -p title
```

### ❌ Bad — Using WebFetch for standard web pages

```bash
# WebFetch returns full page with nav, ads, footers
# Use defuddle instead for cleaner output
```

## Integration with Canuto Vault

When saving web content to the vault, add proper frontmatter:

```markdown
---
type: research
source: https://example.com/article
extracted: 2026-03-21
tags:
  - research
  - web-clip
---

[defuddle output here]
```

## References

- [defuddle GitHub](https://github.com/nicholasgasior/defuddle)
