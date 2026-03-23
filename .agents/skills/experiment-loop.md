---
shortDescription: Run systematic experiment loops — change a variable, test, measure, keep or discard, repeat. Automated optimization for any process with a measurable metric.
usedBy: [maestro, architect]
version: 1.0.0
lastUpdated: 2026-03-23
copyright: Rodrigo Canuto © 2026.
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

This turns passive observation into active experimentation. While `continuous-learning` learns from what happens naturally, `experiment-loop` deliberately creates variations to find what works best.

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
| **Duration** | How long the experiment ran |

### Experiment Series

A group of experiments optimizing the same metric by varying the same thing.

| Field | Description |
|-------|-------------|
| **Series ID** | `SER-001`, `SER-002`, ... |
| **Goal** | What we're trying to optimize (plain language) |
| **Metric** | The number we're tracking |
| **Variable** | What we're changing between experiments |
| **Experiments** | List of experiment IDs in this series |
| **Best so far** | The variation with the best result |
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
   - Must be objective and measurable
   - Must have a clear direction (higher or lower is better)
   - Examples: response time (lower), test pass rate (higher), token usage (lower), first-pass approval rate (higher)

2. **Identify the variable.** Ask the user: "What can we change to move that number?"
   - Must be something the agent can modify programmatically
   - Examples: prompt wording, config values, template structure, thresholds, ordering

3. **Define the test method.** How do we measure the metric after each change?
   - Run a script, execute a command, count occurrences, measure time
   - The test must be repeatable and produce consistent results

4. **Set constraints:**
   - Max experiments per series (default: 10)
   - Time limit per experiment (default: 5 minutes)
   - Minimum improvement threshold to KEEP (default: 5%)
   - Stop condition: target metric value or max experiments reached

5. **Confirm with user before starting.** Present the experiment plan:
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

1. **Generate variation.** Create a new value for the variable. Strategies:
   - **Incremental:** Small step from current best (e.g., threshold 50 → 55)
   - **Exploratory:** Try a significantly different approach
   - **Informed:** Use results from previous experiments to guide the next variation

2. **Apply the change.** Modify the variable in the target file/config/script.

3. **Run the test.** Execute the test method and capture the metric.

4. **Record the result.** Log everything:
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

Present a summary at the end of the series:

```
Experiment Series: SER-001 — CONCLUDED
Goal: <goal>
Experiments run: N
Best result: <best metric value> (variation: <description>)
Improvement from original: +/-N%
Duration: X minutes total

Top 3 variations:
1. EXP-005: <variation> → <result> (KEEP)
2. EXP-003: <variation> → <result> (KEEP)
3. EXP-007: <variation> → <result> (DISCARD, close to best)

Recommendation: Apply <best variation> as the new default.
Apply? [Y/n]
```

### Phase 4: Store in Vault

Save the experiment series to `~/.canuto/vault/projects/{project-slug}/experiments/SER-XXX-slug.md`:

```markdown
---
type: experiment-series
id: SER-001
goal: "<goal>"
metric: "<metric>"
direction: higher-is-better | lower-is-better
variable: "<variable>"
status: concluded | active | paused
experiments-count: N
best-experiment: EXP-005
original-baseline: <value>
final-result: <value>
improvement: "+N%"
date-started: YYYY-MM-DD
date-concluded: YYYY-MM-DD
tags:
  - experiment
  - optimization
---

# SER-001: <Goal>

## Configuration
- **Metric:** <metric> (<direction>)
- **Variable:** <variable>
- **Test method:** <description>
- **Threshold:** <min improvement to keep>

## Experiments

| ID | Variation | Result | vs Baseline | Verdict |
|----|-----------|--------|-------------|---------|
| EXP-001 | <desc> | <value> | +N% | KEEP |
| EXP-002 | <desc> | <value> | -N% | DISCARD |
| ... | ... | ... | ... | ... |

## Conclusion

<What we learned. Best variation and why it works.>

## Applied

- [ ] Best variation applied as new default on YYYY-MM-DD
```

---

## Use Cases in Development Context

| Use Case | Metric | Variable | Test Method |
|----------|--------|----------|-------------|
| **Optimize build time** | Build duration (lower) | Webpack/Vite config options | `time npm run build` |
| **Reduce bundle size** | Bundle size in KB (lower) | Import strategies, tree-shaking config | `npm run build && du -sh dist/` |
| **Improve test speed** | Test suite duration (lower) | Parallelism settings, test grouping | `time npm test` |
| **Optimize rework threshold** | False positive rate (lower) | Rework detection threshold (currently 3) | Count rework warnings vs actual rework |
| **Template effectiveness** | Follow-up rate (lower) | Email/message template wording | Measure responses over N sends |
| **Prompt optimization** | Output quality score (higher) | Prompt phrasing for a persona | Score outputs against rubric |

---

## Examples

### ✅ Good — Well-defined experiment with clear metric

```
Experiment Series: SER-001
Goal: Reduce Vite build time for production
Metric: Build duration in seconds (lower is better)
Variable: Vite config — rollupOptions, minify strategy, chunk splitting
Test method: `time npx vite build 2>&1 | grep "built in"`
Constraints: max 8 experiments, 2 min each, threshold 10%

EXP-001: Changed minify from 'terser' to 'esbuild' → 12.3s → 8.1s (-34%) → KEEP
EXP-002: Added manualChunks for vendor split → 8.1s → 7.8s (-4%) → DISCARD (below 10% threshold)
EXP-003: Set build.target to 'es2020' → 8.1s → 7.2s (-11%) → KEEP
...
```

### ❌ Bad — Vague metric, no test method

```
Goal: Make the app better
Metric: "user satisfaction"
Variable: "the code"
```

This is bad because: metric is not measurable by the agent, variable is too broad, no test method defined.

---

## Guardrails

- **Always get user approval before starting.** Never run experiments autonomously without confirmation.
- **Always get user approval before applying the winner.** The report is a recommendation, not an automatic change.
- **Revert on DISCARD.** Every discarded variation must be fully reverted before the next experiment.
- **Log everything.** Every experiment, every result, every decision — stored in the vault.
- **Don't experiment on production.** Experiments run on local/dev environments only.
- **Respect time limits.** If a single experiment exceeds its time limit, abort and record as `TIMEOUT`.
- **Max experiments per series: 20.** Prevent runaway loops. User can extend if needed.
- **No destructive experiments.** The variable being changed must be reversible. Never modify data, delete files, or change permissions as an experiment variable.
- **Separate from instincts.** Experiment results are NOT instincts. If a finding is universally useful, the user can manually promote it to an instinct via `continuous-learning`.
