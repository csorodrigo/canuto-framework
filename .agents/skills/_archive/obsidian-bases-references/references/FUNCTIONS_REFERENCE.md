# Functions Reference

## Global Functions

| Function | Signature | Description |
|----------|-----------|-------------|
| `date()` | `date(string): date` | Parse string to date (`YYYY-MM-DD HH:mm:ss`) |
| `now()` | `now(): date` | Current date and time |
| `today()` | `today(): date` | Current date (time = 00:00:00) |
| `if()` | `if(condition, trueResult, falseResult?)` | Conditional |
| `duration()` | `duration(string): duration` | Parse duration string |
| `file()` | `file(path): file` | Get file object |
| `link()` | `link(path, display?): Link` | Create a link |
| `image()` | `image(url, width?, height?): string` | Create image |
| `html()` | `html(string): string` | Render raw HTML |
| `min()` | `min(a, b, ...): number` | Smallest value |
| `max()` | `max(a, b, ...): number` | Largest value |

## Date Functions

| Function | Description |
|----------|-------------|
| `.year` | Year number |
| `.month` | Month (1-12) |
| `.day` | Day of month (1-31) |
| `.hour` | Hour (0-23) |
| `.minute` | Minute (0-59) |
| `.second` | Second (0-59) |
| `.format(pattern)` | Format date (e.g., `"YYYY-MM-DD"`, `"dddd"`) |
| `.relative()` | Human-readable relative time (e.g., "2 days ago") |

### Date Arithmetic

```yaml
"now() + \"1 day\""        # Tomorrow
"today() + \"7d\""         # A week from today
"now() - file.ctime"       # Returns Duration
```

Duration units: `y/year/years`, `M/month/months`, `d/day/days`, `w/week/weeks`, `h/hour/hours`, `m/minute/minutes`, `s/second/seconds`

## Duration Type

Created by subtracting dates. **Duration does NOT support `.round()`, `.floor()`, `.ceil()` directly.** Access a numeric field first.

| Field | Description |
|-------|-------------|
| `.days` | Total days |
| `.hours` | Total hours |
| `.minutes` | Total minutes |
| `.seconds` | Total seconds |
| `.milliseconds` | Total milliseconds |

```yaml
# CORRECT
"(now() - file.ctime).days"
"(now() - file.ctime).days.round(0)"

# WRONG
# "(now() - file.ctime).round(0)"
```

## String Functions

| Function | Description |
|----------|-------------|
| `.contains(str)` | Check if contains substring |
| `.startsWith(str)` | Check start |
| `.endsWith(str)` | Check end |
| `.replace(search, replace)` | Replace first match |
| `.replaceAll(search, replace)` | Replace all matches |
| `.split(separator)` | Split into list |
| `.slice(start, end?)` | Extract substring |
| `.trim()` | Remove whitespace |
| `.toLowerCase()` | To lowercase |
| `.toUpperCase()` | To uppercase |
| `.length` | String length |
| `.toString()` | Convert to string |

## Number Functions

| Function | Description |
|----------|-------------|
| `.abs()` | Absolute value |
| `.round(decimals?)` | Round |
| `.ceil()` | Round up |
| `.floor()` | Round down |
| `.toFixed(decimals)` | Format with fixed decimal places |
| `.toString()` | Convert to string |

## List Functions

| Function | Description |
|----------|-------------|
| `.filter(fn)` | Filter elements |
| `.map(fn)` | Transform elements |
| `.reduce(fn, initial)` | Reduce to single value |
| `.sort()` | Sort ascending |
| `.reverse()` | Reverse order |
| `.unique()` | Remove duplicates |
| `.flat()` | Flatten nested lists |
| `.includes(value)` | Check membership |
| `.join(separator)` | Join into string |
| `.length` | List length |
| `.first` | First element |
| `.last` | Last element |
| `.mean()` | Average |
| `.sum()` | Sum |
| `.min()` | Minimum |
| `.max()` | Maximum |

## File Functions

| Function | Description |
|----------|-------------|
| `.hasTag(tag)` | Check if file has tag |
| `.inFolder(folder)` | Check if file is in folder |
| `.hasLink(target)` | Check if file links to target |

## Link Functions

| Property | Description |
|----------|-------------|
| `.path` | Link target path |
| `.display` | Display text |

## Object Functions

| Function | Description |
|----------|-------------|
| `.keys()` | Get all keys |
| `.values()` | Get all values |
| `.entries()` | Get key-value pairs |
| `.has(key)` | Check if key exists |

## RegExp

```yaml
'/pattern/.matches(string)'
'/pattern/.test(string)'
```
