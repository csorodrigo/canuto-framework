---
shortDescription: Run systematic experiment loops — change a variable, test, measure, keep or discard, repeat. Automated optimization for any process with a measurable metric.
usedBy: [maestro, architect]
version: 1.2.0
lastUpdated: 2026-03-23
copyright: Rodrigo Canuto © 2026.
evals:
  - prompt: "we need to find the best prompt wording for the maestro handoff, lets run some experiments"
    should_trigger: true
  - prompt: "want to systematically test which deploy strategy gives better build times — a/b it"
    should_trigger: true
  - prompt: "run the test suite and show me the results"
    should_trigger: false
  - prompt: "compare the old version of this skill against the new one i just wrote"
    should_trigger: false
---

## When to Use

**Triggers:**
- User wants to optimize something measurable: `"optimize"`, `"find the best"`, `"test variations"`, `"A/B test"`, `"experiment"`
- A process has a clear metric (time, count, rate, score) and a variable that can be changed
- Maestro identifies a repeatable process that could benefit from systematic variation testing

**Not for:**
- One-off comparisons (just compare manually)
- Decisions that require human judgment (use `research` skill instead)
- Processes without a measurable outcome (no metric = no experiment)

---

## Purpose

Implement the auto-research pattern (inspired by Karpathy's autonomous experiment loop) for systematic optimization of any process with a measurable metric. The agent makes a small change, tests it, measures the result, keeps the winner, and tries again — automatically.

While `continuous-learning` learns from what happens naturally, `experiment-loop` deliberately creates variations to find what works best.

---

## Concepts

### Experiment

A single test of one variation against the current baseline.

| Field | Description |
|-------|-------------|
| **ID** | Auto-incrementing (`EXP-001`, `EXP-002`, ...) |
| **Hypothesis** | What we expect to happen if we make this change |
| **Variable** | What we're changing (the independent variable) |
| **Variation** | The specific change made in this experiment |
| **Metric** | What we're measuring (the dependent variable) |
| **Direction** | `higher-is-better` or `lower-is-better` |
| **Baseline** | The metric value before the change |
| **Result** | The metric value after the change |
| **Verdict** | `KEEP` (result improved) or `DISCARD` (result worsened or unchanged) |

### Experiment Series

A group of experiments optimizing the same metric by varying the same thing.

| Field | Description |
|-------|-------------|
| **Series ID** | `SER-001`, `SER-002`, ... |
| **Goal** | What we're trying to optimize |
| **Metric** | The number we're tracking |
| **Variable** | What we're changing between experiments |
| **Status** | `active`, `concluded`, `paused` |

### The Loop

```
Define metric + variable
        ↓
   Set baseline
        ↓
  ┌─→ Generate variation
  │       ↓
  │   Run test
  │       ↓
  │   Measure result
  │       ↓
  │   Compare to baseline
  │       ↓
  │   KEEP (new baseline) or DISCARD
  │       ↓
  └── Repeat (N times or until threshold met)
        ↓
   Present report
```

---

## Procedure

### Phase 1: Define the Experiment

1. **Identify the metric.** Ask the user: "What number are you trying to improve?"
   - Must be objective and measurable with a clear direction (higher or lower is better)
   - Examples: response time (lower), test pass rate (higher), token usage (lower)

2. **Identify the variable.** Ask the user: "What can we change to move that number?"
   - Must be something the agent can modify programmatically
   - Examples: prompt wording, config values, template structure, thresholds

3. **Define the test method.** How do we measure the metric after each change?
   - Run a script, execute a command, count occurrences, measure time
   - The test must be repeatable and produce consistent results

4. **Set constraints:**
   - Max experiments per series (default: 10)
   - Time limit per experiment (default: 5 minutes)
   - Minimum improvement threshold to KEEP (default: 5%)
   - Stop condition: target metric value or max experiments reached

5. **Confirm with user before starting:**
   ```
   Experiment Series: SER-001
   Goal: <what we're optimizing>
   Metric: <what we measure> (direction: <higher/lower> is better)
   Variable: <what we change>
   Test method: <how we measure>
   Constraints: max N experiments, M min each, threshold X%

   Start experiments? [Y/n]
   ```

### Phase 2: Run the Loop

For each experiment:

1. **Generate variation.** Strategies:
   - **Incremental:** Small step from current best (e.g., threshold 50 → 55)
   - **Exploratory:** Try a significantly different approach
   - **Informed:** Use results from previous experiments to guide the next variation

2. **Apply the change.** Modify the variable in the target file/config/script.

3. **Run the test.** Execute the test method and capture the metric.

4. **Record the result:**
   ```
   EXP-003: Changed <variable> from <old> to <new>
   Baseline: <baseline value>
   Result: <new value>
   Change: +/-N% (direction: <better/worse>)
   Verdict: KEEP / DISCARD
   ```

5. **Update baseline** if KEEP. Revert if DISCARD.

6. **Repeat** until stop condition is met.

### Phase 3: Report

```
Experiment Series: SER-001 — CONCLUDED
Goal: <goal>
Experiments run: N
Best result: <best metric value> (variation: <description>)
Improvement from original: +/-N%

Top 3 variations:
1. EXP-005: <variation> → <result> (KEEP)
2. EXP-003: <variation> → <result> (KEEP)
3. EXP-007: <variation> → <result> (DISCARD, close to best)

Recommendation: Apply <best variation> as the new default.
Apply? [Y/n]
```

### Phase 4: Store in Vault

Save experiment series to vault after user approval.

→ **Full vault schema** (frontmatter + experiment table template): read `references/vault-schema.md`

---

## Guardrails

- **Always get user approval before starting.** Never run experiments autonomously.
- **Always get user approval before applying the winner.** The report is a recommendation.
- **Revert on DISCARD.** Every discarded variation must be fully reverted before the next experiment.
- **Log everything.** Every experiment, every result — stored in the vault.
- **Don't experiment on production.** Experiments run on local/dev environments only.
- **Respect time limits.** If a single experiment exceeds its time limit, abort and record as `TIMEOUT`.
- **Max experiments per series: 20.** User can extend if needed.
- **No destructive experiments.** The variable being changed must be reversible.
- **Separate from instincts.** Experiment results are NOT instincts. Promote manually via `continuous-learning` if universally useful.

→ **Use cases + examples**: read `references/use-cases-and-examples.md`
