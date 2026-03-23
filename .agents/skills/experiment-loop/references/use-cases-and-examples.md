# Use Cases & Examples — experiment-loop

## Common Use Cases in Development

| Use Case | Metric | Variable | Test Method |
|----------|--------|----------|-------------|
| **Optimize build time** | Build duration in seconds (lower) | Webpack/Vite config options | `time npm run build` |
| **Reduce bundle size** | Bundle size in KB (lower) | Import strategies, tree-shaking config | `npm run build && du -sh dist/` |
| **Improve test speed** | Test suite duration in seconds (lower) | Parallelism settings, test grouping | `time npm test` |
| **Optimize rework threshold** | False positive rate (lower) | Rework detection threshold (currently 3) | Count rework warnings vs actual rework |
| **Prompt optimization** | Output quality score (higher) | Prompt phrasing for a persona | Score outputs against rubric |
| **Template effectiveness** | Follow-up rate (lower) | Email/message template wording | Measure responses over N sends |

---

## Examples

### ✅ Good — well-defined experiment with clear metric

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
```

### ❌ Bad — vague metric, no test method

```
Goal: Make the app better
Metric: "user satisfaction"
Variable: "the code"
```

Metric is not measurable by the agent, variable is too broad, no test method defined. Cannot run this experiment.
