# Callouts Reference

## Syntax

```markdown
> [!type] Optional Title
> Content goes here.
```

## Foldable Callouts

```markdown
> [!faq]- Collapsed by default
> Hidden content.

> [!faq]+ Expanded by default
> Visible content.
```

## Nesting

```markdown
> [!question] Can callouts be nested?
> > [!todo] Yes!, they can.
> > > [!example] You can even use multiple layers of nesting.
```

## Available Types

| Type | Aliases | Color | Icon |
|------|---------|-------|------|
| `note` | — | Blue | Pencil |
| `abstract` | `summary`, `tldr` | Cyan | Clipboard list |
| `info` | — | Blue | Info circle |
| `todo` | — | Blue | Checkbox |
| `tip` | `hint`, `important` | Cyan | Flame |
| `success` | `check`, `done` | Green | Checkmark |
| `question` | `help`, `faq` | Yellow | Help circle |
| `warning` | `caution`, `attention` | Orange | Warning triangle |
| `failure` | `fail`, `missing` | Red | X mark |
| `danger` | `error` | Red | Zap |
| `bug` | — | Red | Bug |
| `example` | — | Purple | List |
| `quote` | `cite` | Gray | Quote marks |

## Custom Callouts (CSS)

```css
.callout[data-callout="custom-type"] {
    --callout-color: 0, 0, 0;
    --callout-icon: lucide-icon-name;
}
```
