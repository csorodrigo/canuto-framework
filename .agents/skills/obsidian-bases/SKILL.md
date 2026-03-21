---
name: obsidian-bases
description: Create and edit Obsidian Bases (.base files) with views, filters, formulas, and summaries. Use when working with .base files, creating database-like views of notes, or when the user mentions Bases, table views, card views, filters, or formulas in Obsidian.
origin: kepano/obsidian-skills (adapted for Canuto Framework)
---

# Obsidian Bases Skill

## When to Use

- When creating database views over Canuto vault notes (instincts, decisions, metrics, etc.)
- When the user asks for filtered/sorted/grouped views of memory data
- When creating `.base` files in `.agents/vault/bases/`

## Workflow

1. **Create the file**: Create a `.base` file in the vault with valid YAML content
2. **Define scope**: Add `filters` to select which notes appear (by tag, folder, property, or date)
3. **Add formulas** (optional): Define computed properties in the `formulas` section
4. **Configure views**: Add one or more views (`table`, `cards`, `list`, or `map`) with `order` specifying which properties to display
5. **Validate**: Verify the file is valid YAML with no syntax errors. Check that all referenced properties and formulas exist
6. **Test in Obsidian**: Open the `.base` file in Obsidian to confirm the view renders correctly

## Schema

Base files use the `.base` extension and contain valid YAML.

```yaml
# Global filters apply to ALL views in the base
filters:
  and: []
  or: []
  not: []

# Define formula properties
formulas:
  formula_name: 'expression'

# Configure display names
properties:
  property_name:
    displayName: "Display Name"

# Custom summary formulas
summaries:
  custom_summary_name: 'values.mean().round(3)'

# Define one or more views
views:
  - type: table | cards | list | map
    name: "View Name"
    limit: 10
    groupBy:
      property: property_name
      direction: ASC | DESC
    filters:
      and: []
    order:
      - file.name
      - property_name
      - formula.formula_name
    summaries:
      property_name: Average
```

## Filter Syntax

```yaml
# Single filter
filters: 'status == "done"'

# AND - all conditions must be true
filters:
  and:
    - 'status == "done"'
    - 'priority > 3'

# OR - any condition can be true
filters:
  or:
    - 'file.hasTag("book")'
    - 'file.hasTag("article")'

# NOT - exclude matching items
filters:
  not:
    - 'file.hasTag("archived")'

# Nested filters
filters:
  or:
    - file.hasTag("tag")
    - and:
        - file.hasTag("book")
        - file.hasLink("Textbook")
```

### Filter Operators

| Operator | Description |
|----------|-------------|
| `==` | equals |
| `!=` | not equal |
| `>` | greater than |
| `<` | less than |
| `>=` | greater than or equal |
| `<=` | less than or equal |

## Properties

### Three Types

1. **Note properties** — From frontmatter: `author` or `note.author`
2. **File properties** — File metadata: `file.name`, `file.mtime`, etc.
3. **Formula properties** — Computed values: `formula.my_formula`

### File Properties Reference

| Property | Type | Description |
|----------|------|-------------|
| `file.name` | String | File name |
| `file.basename` | String | File name without extension |
| `file.path` | String | Full path to file |
| `file.folder` | String | Parent folder path |
| `file.ext` | String | File extension |
| `file.size` | Number | File size in bytes |
| `file.ctime` | Date | Created time |
| `file.mtime` | Date | Modified time |
| `file.tags` | List | All tags in file |
| `file.links` | List | Internal links in file |
| `file.backlinks` | List | Files linking to this file |

## Formula Syntax

```yaml
formulas:
  total: "price * quantity"
  status_icon: 'if(done, "✅", "⏳")'
  created: 'file.ctime.format("YYYY-MM-DD")'
  days_old: '(now() - file.ctime).days'
  days_until_due: 'if(due_date, (date(due_date) - today()).days, "")'
```

### Key Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `date()` | `date(string): date` | Parse string to date |
| `now()` | `now(): date` | Current date and time |
| `today()` | `today(): date` | Current date (time = 00:00:00) |
| `if()` | `if(condition, trueResult, falseResult?)` | Conditional |
| `duration()` | `duration(string): duration` | Parse duration string |

### Duration Type — IMPORTANT

When subtracting two dates, the result is a **Duration** type (not a number). Access `.days`, `.hours`, `.minutes`, `.seconds` before applying number functions.

```yaml
# CORRECT
"(date(due_date) - today()).days"
"(now() - file.ctime).days.round(0)"

# WRONG - Duration doesn't support .round() directly
# "(now() - file.ctime).round(0)"
```

See [FUNCTIONS_REFERENCE.md](references/FUNCTIONS_REFERENCE.md) for the complete function reference.

## View Types

### Table View

```yaml
views:
  - type: table
    name: "My Table"
    order:
      - file.name
      - status
      - due_date
    summaries:
      price: Sum
```

### Cards View

```yaml
views:
  - type: cards
    name: "Gallery"
    order:
      - file.name
      - cover_image
      - description
```

### List View

```yaml
views:
  - type: list
    name: "Simple List"
    order:
      - file.name
      - status
```

## Default Summary Formulas

| Name | Input Type | Description |
|------|------------|-------------|
| `Average` | Number | Mathematical mean |
| `Min` / `Max` | Number | Smallest / largest |
| `Sum` | Number | Sum of all |
| `Median` | Number | Mathematical median |
| `Earliest` / `Latest` | Date | First / last date |
| `Checked` / `Unchecked` | Boolean | Count of true/false |
| `Empty` / `Filled` | Any | Count of empty/non-empty |
| `Unique` | Any | Count of unique values |

## Embedding Bases

```markdown
![[MyBase.base]]
![[MyBase.base#View Name]]
```

## YAML Quoting Rules

- Use single quotes for formulas containing double quotes: `'if(done, "Yes", "No")'`
- Use double quotes for simple strings: `"My View Name"`
- Strings with `:`, `#`, `[`, `]`, etc. must be quoted

## Examples

### ✅ Good — Canuto instincts query base

```yaml
filters:
  and:
    - file.inFolder("instincts")
    - 'file.ext == "md"'

formulas:
  days_since_seen: 'if(last_seen, (today() - date(last_seen)).days, "")'

properties:
  formula.days_since_seen:
    displayName: "Days Since Seen"

views:
  - type: table
    name: "Active Instincts"
    filters:
      and:
        - 'status != "pruned"'
    order:
      - file.name
      - confidence
      - category
      - applied
      - formula.days_since_seen
    groupBy:
      property: confidence
      direction: DESC
```

### ❌ Bad — Missing null checks, wrong duration handling

```yaml
formulas:
  # WRONG: no null check, Duration.round() doesn't work
  days_old: '(now() - date(last_seen)).round(0)'
```

## References

- [Bases Syntax](https://help.obsidian.md/bases/syntax)
- [Functions](https://help.obsidian.md/bases/functions)
- [Complete Functions Reference](references/FUNCTIONS_REFERENCE.md)
