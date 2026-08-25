# Canuto Framework Feature Map

## Status Legend
- `implemented`: shipped and exercised in runtime or tests
- `partial`: present but still depends on manual setup or limited validation
- `planned`: intended but not implemented yet

| Area | Status | Entry Points | Notes |
|------|--------|--------------|-------|
| Fresh install | implemented | `install.sh` | Bootstraps `.agents/`, hooks, vault, Codex, and docs; leaves changes unstaged unless `--commit` is explicit |
| Update flow | implemented | `install.sh --update` | Defaults to `stable`; supports explicit edge, release/version and exact-ref pinning; never treats `--yes` as commit authorization |
| Runtime repair | implemented | `install.sh --repair` | Provisions strict runtime dependencies, reinstalls hooks, rewires MCP/config, recreates missing bootstrap files |
| One-command diagnosis | implemented | `install.sh --doctor`, `install.sh --health` | Installs/verifies dependencies, runs repair plus consumer/Codex health validation, and fails if the complete environment is not ready |
| Consumer smoke test | implemented | `install.sh --test`, `.agents/tools/canuto-consumer-smoke.sh` | Validates project-facing install state and source receipt structure |
| Codex health check | implemented | `.agents/tools/codex-health-check.sh` | Verifies CLI, profiles, trust, hooks, MCPs, contexts, dependency checks, and RTK activation |
| Cross-project session audit | implemented | `.agents/tools/framework-session-audit.js`, `.agents/tools/framework-session-audit-lib.js` | Audits the latest up-to-200 sessions per project across workspaces, vault artifacts, and Codex logs; emits inventory, NDJSON dataset, JSON summaries, and markdown report |
| Federated skill gardener | partial | `~/.canuto/bin/canuto-skill-gardener`, `skill-gardener/`, `global-skills/skill-gardener/SKILL.md` | Deterministic report-only inventory/usage audit with HMAC keys, coverage-aware classifications, remote read-only collection, receipts and explicit cron; remains partial until post-merge canary and real cron validation |
| Resumable skill estate refactor | partial | `skill-refactor/canuto-skill-refactor.js`, `global-skills/skill-refactor/SKILL.md` | Classifies the complete configured estate and stages bounded, hash-verified candidates without mutating live skills; remains partial until the real full-estate queue and human promotion gate complete |
| Governed third-party skill bundles | implemented | `.agents/tools/skill-bundle-publisher.js`, `distribution/matt-pocock-skills.json` | Exact-SHA Matt Pocock bundle with source fingerprints and explicit `plan`, `apply`, `verify`, and recoverable `rollback`; refuses unmanaged conflicts and remains separate from the report-only Skill Gardener |
| Cost dashboard telemetry | implemented | `.agents/tools/framework-session-audit.js`, `.agents/tools/framework-session-audit-lib.js` | Report-only cost dashboard for Codex, Claude project logs, Claude telemetry, and optional Codeburn exports; emits `04-cost-dashboard.json` and `.md` |
| Gemini MCP integration | removed (2026-04-29) | — | Removed in cleanup PR. Provider stack simplified to Claude (tier-1) + Codex CLI (tier-2). Migration history preserved in vault/sessions/2026-04-17.md, 04-18.md. |
| Claude MCP back-delegation | partial | `.agents/tools/claude-agent-mcp.py`, `.agents/tools/claude-architect.sh`, `.agents/tools/claude-reviewer.sh`, `.agents/hooks/install.sh` | Lets Codex Maestro call Claude Opus/Sonnet through MCP when `ANTHROPIC_API_KEY` is configured |
| JSON health output | implemented | `install.sh --test --json`, `.agents/tools/codex-health-check.sh --json` | Machine-readable diagnostics for CI and dashboards |
| Context bootstrap | implemented | `.context.md`, `docs/FEATURE-MAP.md`, `.agents/vault/digests/00-bootstrap-digest.md` | Created automatically when missing |
| Passive hooks | implemented | `.agents/hooks/` | Session save, pre-compact save, Codex pretool guard, event log, gates de PR/delegação (plan-review aposentado 2026-06-11: 0 firings) |
| Hook governance baseline | implemented | `.agents/hooks/audit/capture-hooks-baseline.mjs`, `.agents/hooks/audit/provenance-manifest.json` | Read-only, sanitized 81/81 inventory; installed-only or divergent sources remain blocked and are never imported automatically |
| CLAUDE examples | implemented | `docs/CLAUDE-EXAMPLES.md` | Reference setups for common project types |
| Native Codex MCP auto-registration | partial | `install.sh`, `setup_codex_mcps` | Works when Codex CLI + required creds/tools are available |
| Obsidian vault integration | partial | `setup_obsidian_mcp`, `setup_codex_mcps` | Fully automatic if API key is already available; otherwise degrades gracefully |
| Trace analysis (v1.8) | implemented | `.agents/skills/trace-analysis/SKILL.md` | Session-end trace mining — classifies signals, proposes blind spots and instincts. Gated by `CANUTO_TRACE_ANALYSIS=1` |
| Auto-generated blind spots (v1.8) | implemented | `.agents/blind-spots/_candidates/` | Staging area for trace-derived blind-spot candidates. Lifecycle: create → review → promote/dismiss |
| Adaptive routing (v1.8) | implemented | `.agents/skills/adaptive-routing/SKILL.md` | Mid-session routing-check after Architect/Coder handoff. User-confirmed reroutes only |
| Skill auto-discovery (v1.8) | implemented | `.agents/skills/trace-analysis/references/skill-proposer.md` | Detects recurring manual workflows (3+ sessions) and proposes skill creation |
| Experiment auto-triggers (v1.8) | implemented | `.agents/skills/experiment-loop/references/auto-triggers.md` | Proposes experiments when review scores trend below 7.0 (proposal only, never auto-start) |
| Context maintenance | implemented | `.agents/skills/context-maintenance/SKILL.md` | Keeps `.context.md` files, FEATURE-MAP.md, and repo index fresh after structural or feature changes. Auto-fires on directory moves, renames, or new features |
| Codex GitHub ops | archived (2026-06-11 — 0 leituras em 200 sessões) | `.agents/skills/_archive/codex-github-ops.md` | Issue triage, PR creation/comments, release notes, label management, github code search via Codex + GitHub MCP. `/codex-gh` or natural-language GitHub verbs |
| Codex browser QA | archived (2026-06-11 — 0 leituras em 200 sessões) | `.agents/skills/_archive/codex-browser-qa.md` | Browser QA (visual regression, a11y audits, smoke flows, screenshot diffs) via Codex + Playwright MCP. `/codex-qa` or any "test the UI" / "screenshot" request. 70% cost savings vs Opus-driven |
| Codex PR writer | archived (2026-06-11 — 0 leituras em 200 sessões) | `.agents/skills/_archive/codex-pr-writer.md` | Generates PR descriptions, merge summaries, and changelog entries from git diff via Codex. `/pr-write` or "describe this PR" / "summary for merge" |
