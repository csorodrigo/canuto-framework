# Monitor Profiles

Profiles define default sampling + alert behavior per process class. Override only when process-specific nuances demand it.

## build
- **Processes:** webpack, tsc, cargo build, esbuild, vite build
- **Watch for:** compilation errors, warnings, bundle size anomalies
  - Regex samples: `/error\s*(TS|E)\d+/`, `/error\[E\d+\]/`, `/Module not found/`, `/Bundle size .* exceeds/i`
- **Scan rate:** every 5th line (Scan interval = 5)
- **Focus trigger:** first compilation error or repeated warning (>3 in 60s)
- **Alert persona:** Coder
- **Token budget allocation:** 40% of session monitor budget (2K tokens per 10m slice)

## test
- **Processes:** jest, vitest, pytest, cargo test, go test
- **Watch for:** failures, timeouts, coverage drops
  - Regex samples: `/FAIL|✗|×|failed/i`, `/AssertionError/`, `/Timeout - Async callback/i`, `/Coverage dropped below/`
- **Scan rate:** every 3rd line
- **Focus trigger:** any test failure line or coverage delta below threshold
- **Alert persona:** Coder (fluxo /fix)
- **Token budget allocation:** 30% (1.5K tokens per 10m)

## deploy
- **Processes:** docker build/push, vercel, fly.io, kubectl/k8s deploy, railway
- **Watch for:** failed stages, rollback triggers, health check failures
  - Regex samples: `/Deployment failed/i`, `/Rollback triggered/`, `/probe failed/`, `/CrashLoopBackOff/`
- **Scan rate:** every line (critical path)
- **Focus trigger:** any error or warning string, default immediate
- **Alert persona:** Maestro
- **Token budget allocation:** 60% (3K tokens per 10m) — can borrow from other sessions if needed

## dev-server
- **Processes:** next dev, vite dev, `rails s`, `flask run`, node/nodemon servers
- **Watch for:** crashes, unhandled errors, memory warnings, port conflicts
  - Regex samples: `/UnhandledPromiseRejection/`, `/Segmentation fault/`, `/address already in use/i`, `/heap out of memory/`
- **Scan rate:** every 10th line (dev servers noisy)
- **Focus trigger:** crash signature or repeated warning >2 times in 60s
- **Alert persona:** Coder
- **Token budget allocation:** 20% (1K tokens per 10m)

## ci-pipeline
- **Processes:** GitHub Actions, CircleCI, GitLab CI logs streamed locally
- **Watch for:** job failures, flaky test patterns, timeout warnings
  - Regex samples: `/Job .* failed/`, `/Retrying flaky test/`, `/timeout exceeded/i`, `/Cancelled due to inactivity/`
- **Scan rate:** every 5th line
- **Focus trigger:** job failure or 2+ retries detected
- **Alert persona:** Maestro
- **Token budget allocation:** 35% (1.75K tokens per 10m)

> Budget percentages are **priority weights**, not hard caps. When multiple profiles run concurrently, Maestro redistributes the session's 5K-token budget proportionally to active weights. Example: if `build` (40%) and `test` (30%) run together, they receive ~57% and ~43% of 5K respectively. Total per-session spend never exceeds 5K without explicit user override.
