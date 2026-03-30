---
skill: stuck-detection
trigger: Passive — Maestro monitors automatically during Debugger-Coder-Tester cycles
persona: maestro
version: 1.0.0
lastUpdated: 2026-03-29
shortDescription: >
  Detects when the Debugger→Coder→Tester cycle is looping without progress and escalates before wasting tokens.
usedBy: [maestro]
evals:
  - prompt: "the tests keep failing even after the third fix attempt"
    should_trigger: true
  - prompt: "we're going in circles on this auth bug"
    should_trigger: true
  - prompt: "run the tests again after the fix"
    should_trigger: false
  - prompt: "the first fix didn't work, let's try a different approach"
    should_trigger: false
---

## When to Use

This skill is **passive** — Maestro applies it automatically during any Debugger→Coder→Tester cycle. It is NOT triggered by the user.

**Activates when:** the same task enters its 3rd iteration of the fix-test cycle, or the same escalation pattern repeats twice.

**Does NOT apply to:** first or second fix attempts (normal iteration), different tasks within the same session, or user-directed retries ("try again with X approach").

## Purpose

Prevent token waste from runaway fix-test loops. When agents are stuck, more iterations of the same approach rarely help. The correct action is to pause, re-evaluate, and either re-plan or simplify.

Adapted from Claude Octopus's loop self-regulation pattern (WTF-likelihood scoring).

## Procedure

### Signals Maestro Tracks

Maestro maintains a **cycle counter** per task (alongside the existing file modification map):

| Signal | Threshold | Action |
|--------|-----------|--------|
| Debugger→Coder→Tester cycle count | >= 3 | Emit stuck warning |
| Same error message repeating | 2 consecutive cycles with identical root cause | Emit stuck warning |
| Same escalation pattern | 2x (e.g., Tester→Debugger→Coder→Tester→Debugger→Coder) | Emit stuck warning |
| File rework + cycle count | File modified 3x AND cycle count >= 2 | Emit stuck warning (compound signal) |

### Stuck Warning

When any signal crosses its threshold, Maestro MUST pause and present:

```
⚠️ Stuck detected: <task> has entered cycle <N> with <signal description>.

Options:
1. Re-plan — send back to Architect with the failure context
2. Simplify — reduce scope to the smallest working increment
3. Ask user — present the situation and get direction
4. Override — continue anyway (user must explicitly approve)
```

### Rules

- **Never silently continue** past the threshold. The whole point is to break the loop.
- **Log the stuck event** in the audit trail as type `STUCK` with cycle count and signal.
- **If the user chooses "Re-plan"**: Architect receives the failure history as context (what was tried, why it failed).
- **If the user chooses "Override"**: reset the cycle counter but increase the threshold to 5 for this task (avoid nagging).
- **Compound signals** (rework + cycles) trigger at LOWER thresholds because they indicate both the approach AND the implementation are wrong.

## Examples

### Good — Stuck Detection Fires

```
[Maestro] ⚠️ Stuck detected: "Add payment webhook handler" has entered cycle 3.
Signal: Debugger diagnosed the same TypeError in src/webhooks/stripe.ts:42
in cycles 2 and 3. The Coder's fix attempts changed the symptom but not the root cause.

Options:
1. Re-plan — Architect reviews the webhook architecture
2. Simplify — implement a minimal webhook that just logs events
3. Ask user — you may know something about Stripe's webhook format
4. Override — continue with cycle 4
```

### Bad — DO NOT do this

```
Tests failed again. Sending back to Coder for another attempt.
```

This is bad because: no cycle awareness, no stuck detection, will loop indefinitely.

## Anti-Patterns

- DO NOT reset the cycle counter when a different file fails (same task = same counter).
- DO NOT count user-initiated retries ("try X instead") as stuck cycles — those are directed attempts.
- DO NOT skip the stuck warning because "we're almost there" — that's the sunk cost fallacy.
