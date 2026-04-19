shortDescription: Validate spreadsheet deliverables for formulas, expected sheets, totals, formatting, and openability.
usedBy: [coder, tester, reviewer]
version: 1.0.0
lastUpdated: 2026-04-17
copyright: Rodrigo Canuto © 2026.

## Purpose

Catch spreadsheet delivery failures before the user opens the file. Use this skill for `.xlsx`, `.xls`, `.csv`, and reporting exports.

---

## Checklist

- File opens with a spreadsheet library or Excel-compatible validator.
- Expected sheets are present.
- Header rows and filters are present when expected.
- Key totals match source data or fixture totals.
- No formula errors: `#REF!`, `#VALUE!`, `#DIV/0!`, `#NAME?`, `#N/A`.
- Freeze panes, widths, and wrap settings keep the file readable.
- Empty input and small sample input are handled.
- Generated file path is reported clearly.

---

## Output Format

```markdown
## Spreadsheet Delivery Check

### File
- <path>

### Structure
- Sheets: <list>
- Rows/columns: <summary>

### Validation
- Formula errors: N
- Totals checked: <summary>
- Openability: pass/fail

### Remaining Risks
- <risk or none>
```

---

## Guardrails

- Do not ship a spreadsheet that has not been reopened after generation.
- Do not rely on visual inspection only.
- Do not silently truncate rows or long cell text.
