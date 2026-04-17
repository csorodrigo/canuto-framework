shortDescription: Run frontend visual QA with real browser smoke checks, console errors, responsive layouts, and text overflow checks.
usedBy: [coder, tester, reviewer]
version: 1.0.0
lastUpdated: 2026-04-17
copyright: Rodrigo Canuto © 2026.

## Purpose

Catch UI regressions that unit tests miss. Use this skill for web apps, admin panels, landing pages, games, and interactive tools when the rendered interface matters.

---

## Checklist

- Start the app using the project's normal dev command.
- Open the main affected route in a real browser.
- Check desktop and mobile viewport.
- Capture screenshots when the change is visual.
- Check browser console for errors.
- Check loading, empty, error, and success states when applicable.
- Verify text does not overflow buttons, cards, nav, tables, or dialogs.
- Verify interactive controls still respond.

---

## Output Format

```markdown
## Frontend Visual QA

### Routes Checked
- <route> - desktop/mobile

### Browser Findings
- Console errors: <none/list>
- Layout issues: <none/list>
- Interaction issues: <none/list>

### Evidence
- Screenshot paths or test output, if produced.

### Remaining Risks
- <risk or none>
```

---

## Guardrails

- Do not claim visual QA passed without opening the rendered UI.
- Do not ignore console errors as "probably unrelated" unless evidence supports it.
- Do not use screenshot-only checks for workflows that require interaction.
