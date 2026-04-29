---
skill: codex-test-fix
trigger: /test-fix, or after Coder finishes implementation and tests exist
persona: maestro
version: 1.0.0
lastUpdated: 2026-03-30
shortDescription: >
  Autonomous test-fix loop via Codex. Runs tests, analyzes failures, fixes code,
  re-runs — up to 3 iterations. Opus only sees the final result (green or red).
usedBy: [maestro, coder]
evals:
  - prompt: "run tests and fix any failures"
    should_trigger: true
  - prompt: "the tests are failing, have codex fix them"
    should_trigger: true
  - prompt: "just run the tests"
    should_trigger: false
  - prompt: "review the code"
    should_trigger: false
---

## When to Use

- After Coder (Codex) finishes implementation
- Tests exist and are runnable
- You want autonomous fix without manual intervention

**Not for:**
- Projects without tests (nothing to verify)
- When you want manual control over each fix (just run tests yourself)

---

## Procedure

### 1. Detect Test Command

Auto-detect from project:
```
package.json → npm test / vitest / jest
Makefile → make test
pytest.ini / pyproject.toml → pytest
go.mod → go test ./...
mix.exs → mix test
```

If unclear, ask user.

### 2. Run Test-Fix Loop

Spawn Codex with the full loop prompt:

```
codex exec --profile coder({
  prompt: `
You are a test-fixer agent. Your job is to make all tests pass.

## Instructions
1. Run the test command: {test_command}
2. If ALL tests pass → report SUCCESS and stop
3. If tests FAIL:
   a. Read the failure output carefully
   b. Identify the root cause (not just the symptom)
   c. Fix the source code (NOT the tests, unless the test itself is wrong)
   d. Run tests again
4. Repeat up to 3 times
5. After 3 failed attempts → report FAILURE with:
   - Which tests still fail
   - What you tried
   - Your best theory on the root cause

## Rules
- Fix source code, not tests (unless the test expectation is clearly wrong)
- Each fix should be minimal and targeted
- Do not refactor unrelated code
- If a test requires a missing dependency, report it — don't install

## Project Context
{relevant_context}
`
})
```

### 3. Process Result

| Codex Result | Action |
|-------------|--------|
| SUCCESS (all green) | Log `[Test-Fix] ✅ All tests passing after N iterations` → proceed to review |
| FAILURE (still red) | Log `[Test-Fix] ❌ Tests still failing after 3 attempts` → present to user with Codex's analysis |

### 4. Post-Fix Review

If Codex made fixes:
1. Read `git diff` to see what changed
2. Verify fixes are correct (not just test-silencing hacks)
3. If suspicious, trigger `codex exec --profile reviewer` for review

---

## Auto-Escalation

If `codex-coder` (gpt-5.5 (high)) fails all 3 attempts:
1. Collect the test output + Codex's analysis
2. Escalate to `codex exec --profile reviewer` (reviewer profile):

```
codex exec --profile reviewer({
  prompt: `
[TEST-FIX ESCALATION]
gpt-5.5 (high) failed to fix these tests after 3 attempts.

## Failing Tests
{test_output}

## What Was Tried
{codex_analysis}

## Source Code
{relevant_files}

Analyze the root cause and provide the exact fix needed.
`
})
```

3. Apply the reviewer guidance manually
4. Re-run tests to verify

---

## Output Format

```
[Test-Fix] Starting test-fix loop (max 3 iterations)
[Test-Fix] Iteration 1: 3/15 tests failing
[Test-Fix] Iteration 2: 1/15 tests failing
[Test-Fix] Iteration 3: ✅ All 15 tests passing
[Test-Fix] Fixed files: src/auth.ts, src/middleware.ts
```

---

## Graceful Degradation

- MCP unavailable → Claude runs tests and fixes directly
- No test command found → ask user
- Tests require external services → warn user, skip those tests
