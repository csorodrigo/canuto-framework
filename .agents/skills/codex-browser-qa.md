---
skill: codex-browser-qa
trigger: /codex-qa, or when browser testing is needed and Codex has Playwright MCP
persona: maestro
version: 1.0.0
lastUpdated: 2026-03-30
shortDescription: >
  Delegates browser QA entirely to Codex via spawn_agent + Playwright MCP. Opus
  only receives the final report. 70% cost savings vs Opus-driven browser testing.
usedBy: [maestro, tester]
evals:
  - prompt: "test the login flow on localhost:3000"
    should_trigger: true
  - prompt: "run browser qa with codex"
    should_trigger: true
  - prompt: "review the code"
    should_trigger: false
---

## Purpose

Browser QA via Opus = every navigate/click/screenshot is an Opus API call (expensive).
Delegating the entire QA flow to Codex = 1 spawn_agent call → Codex does everything autonomously.

**70% cost savings** on browser testing sessions.

---

## Prerequisites

- Codex has Playwright MCP registered (`codex mcp list` shows `playwright`)
- If not: fall back to Opus-driven browser-qa skill (existing)

---

## Procedure

### 1. Prepare QA Brief

Maestro prepares the test specification:
```markdown
## QA Brief
- **URL**: http://localhost:3000
- **Scenarios**:
  1. Login with valid credentials → expect dashboard
  2. Login with invalid credentials → expect error message
  3. Navigate to settings → expect form fields populated
  4. Submit empty form → expect validation errors
- **Expected behaviors**: responsive layout, no console errors, forms validate
```

### 2. Spawn Codex QA Agent

```
mcp__codex-coder__spawn_agent({
  prompt: `
You are a QA tester with access to Playwright browser automation.

## Target
URL: {url}

## Test Scenarios
{scenarios}

## Instructions
For each scenario:
1. Navigate to the target URL
2. Perform the actions described
3. Take a screenshot after each major step
4. Check the browser console for errors
5. Verify expected behaviors

## Report Format
For each scenario, report:
- Status: PASS / FAIL
- Screenshots: list of screenshot paths
- Console errors: any errors found
- Notes: anything unexpected

## Summary
At the end, provide:
- Total: X/Y scenarios passed
- Critical issues: list
- Warnings: list
- Overall verdict: SHIP / FIX FIRST
`
})
```

### 3. Process Results

Codex returns:
- Test report with pass/fail per scenario
- Screenshot paths
- Console error list
- Overall verdict

Opus presents the report to the user without touching the browser.

### 4. Fix Loop (optional)

If issues found:
1. Codex reports the issues with repro steps
2. Maestro delegates fix to Codex Coder
3. After fix, re-run QA via spawn_agent
4. Repeat until green or max 3 rounds

---

## Fallback

If Codex Playwright MCP not available:
1. Log: `[Codex-QA] Playwright MCP not available for Codex`
2. Fall back to Opus-driven `/browse` or `/qa` skill
3. Warn: cost will be higher

---

## Integration

- **browser-qa.md**: add Codex delegation as default route
- **cost-routing.md**: Browser QA → Codex (70% savings)
- **codex-collab.md**: documents Playwright MCP setup for Codex
