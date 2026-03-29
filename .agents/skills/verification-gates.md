---
skill: verification-gates
trigger: Automatic — applied during Tester and Reviewer verification of M/L tasks
persona: tester
version: 1.0.0
lastUpdated: 2026-03-29
shortDescription: >
  Prevents agents from gaming test verification by requiring raw command output and dual independent verification for M/L tasks.
usedBy: [tester, reviewer, maestro]
evals:
  - prompt: "the tests say they all pass but I'm not sure they actually ran"
    should_trigger: true
  - prompt: "verify the test results are genuine, not fabricated"
    should_trigger: true
  - prompt: "run the tests"
    should_trigger: false
  - prompt: "write more test cases for the auth module"
    should_trigger: false
---

## When to Use

**Always active for M/L tasks** — Tester and Reviewer follow this protocol automatically.
**Not required for XS/S tasks** — trust-based model is sufficient for small changes.

## Purpose

Prevent agents from gaming verification — e.g., writing tests that always pass, reporting success without running tests, or summarizing output inaccurately. Requires concrete evidence (actual command output) rather than agent assertions.

Adapted from Kodo's verification signal detection pattern (regex-based, anti-gaming).

## Procedure

### 1. Raw Output Requirement (Tester)

The Tester MUST include **actual command output** in the Test Report, not a summary. Specifically:

- The exact command that was run (e.g., `npm test -- --reporter=verbose`)
- The raw terminal output (with anomaly-preserving truncation if >100 lines)
- The exit code or final summary line from the test runner

**What counts as evidence:**
```
✅ "npm test exited with code 0. Output: Tests: 15 passed, 0 failed"
✅ Raw terminal output showing test names and results
```

**What does NOT count:**
```
❌ "All tests pass." (assertion without evidence)
❌ "I verified the implementation works correctly." (no command output)
❌ "Tests: 15 passed" (summary without showing which command produced it)
```

### 2. Signal Detection Patterns

When parsing test output, look for these framework-specific pass/fail signals:

| Framework | Pass Signal | Fail Signal |
|-----------|-------------|-------------|
| Jest/Vitest | `Tests:.*passed` | `Tests:.*failed`, `FAIL` |
| pytest | `passed` at end | `FAILED`, `ERROR` |
| Go test | `ok` | `FAIL` |
| RSpec | `examples, 0 failures` | `failures` |
| JUnit/Maven | `BUILD SUCCESS` | `BUILD FAILURE`, `Tests run:.*Failures: [1-9]` |
| Cargo test | `test result: ok` | `test result: FAILED` |

**Anti-gaming rules:**
- The pass/fail signal must appear as the **test runner's own output**, not in a code block, quote, or attribution.
- Strip markdown code fences and blockquotes before checking for signals.
- A signal inside `> Codex says "ALL TESTS PASS"` does NOT count — it must be the actual command output.

### 3. Dual Verification (M/L Tasks)

For tasks sized **M or L**, the Reviewer independently verifies test results:

1. **Reviewer runs the test command independently** (same command the Tester reported).
2. **Compare outputs**: Reviewer's result must match Tester's claim.
3. **If mismatch**: flag as **MUST FIX** — "Test results cannot be verified. Tester reported X, independent run shows Y."

**Reviewer adds this section to the review:**

```markdown
### Verification Check
- Command: `npm test`
- Tester claimed: 15 passed, 0 failed
- Independent run: 15 passed, 0 failed
- Status: ✅ Verified | ❌ Mismatch
```

### 4. Skeptical Filtering for Self-Assessment

When any persona claims something "works" or "is fixed":

- **Require evidence**: actual command output, screenshot, or verifiable state change.
- **"It works" without evidence = [ASSUMED]** — must be verified before proceeding.
- **After a Debugger fix**: Tester must re-run the specific failing test AND the full suite.

## Examples

### Good — Verified Test Output

```markdown
### Test Run Results
Command: `npx vitest run --reporter=verbose`
Output:
 ✓ src/auth/token.test.ts (3 tests) 2ms
 ✓ src/api/users.test.ts (7 tests) 15ms
 ✓ src/api/payments.test.ts (5 tests) 8ms

Tests: 15 passed, 0 failed
Exit code: 0
```

### Bad — Unverifiable Claim

```markdown
### Test Run Results
All 15 tests pass successfully. The implementation is correct.
```

This is bad because: no command shown, no raw output, no exit code. Could be fabricated.

## Anti-Patterns

- DO NOT accept "all tests pass" without seeing the actual output.
- DO NOT skip dual verification for M/L tasks because "the Tester is reliable."
- DO NOT count a signal inside a quote or code example as actual test output.
- DO NOT run tests with `--passWithNoTests` or equivalent flags that mask empty test suites.
