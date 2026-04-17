# Canuto Framework Feature Map

## Status Legend
- `implemented`: shipped and exercised in runtime or tests
- `partial`: present but still depends on manual setup or limited validation
- `planned`: intended but not implemented yet

| Area | Status | Entry Points | Notes |
|------|--------|--------------|-------|
| Fresh install | implemented | `install.sh` | Bootstraps `.agents/`, hooks, vault, Codex, and docs |
| Update flow | implemented | `install.sh --update` | Designed to refresh installer logic from `main` before applying updates |
| Runtime repair | implemented | `install.sh --repair` | Reinstalls hooks, rewires MCP/config, recreates missing bootstrap files |
| One-command diagnosis | implemented | `install.sh --doctor`, `install.sh --health` | Runs repair plus consumer/Codex health validation |
| Consumer smoke test | implemented | `install.sh --test`, `.agents/tools/canuto-consumer-smoke.sh` | Validates project-facing install state |
| Codex health check | implemented | `.agents/tools/codex-health-check.sh` | Verifies CLI, profiles, trust, hooks, MCPs, contexts |
| Cross-project session audit | implemented | `.agents/tools/framework-session-audit.js`, `.agents/tools/framework-session-audit-lib.js` | Audits the latest up-to-200 sessions per project across workspaces, vault artifacts, and Codex logs; emits inventory, NDJSON dataset, JSON summaries, and markdown report |
| Cost dashboard telemetry | implemented | `.agents/tools/framework-session-audit.js`, `.agents/tools/framework-session-audit-lib.js` | Report-only cost dashboard for Codex, Claude project logs, Claude telemetry, and optional Codeburn exports; emits `04-cost-dashboard.json` and `.md` |
| JSON health output | implemented | `install.sh --test --json`, `.agents/tools/codex-health-check.sh --json` | Machine-readable diagnostics for CI and dashboards |
| Context bootstrap | implemented | `.context.md`, `docs/FEATURE-MAP.md`, `.agents/vault/digests/00-bootstrap-digest.md` | Created automatically when missing |
| Passive hooks | implemented | `.agents/hooks/` | Session save, pre-compact save, plan review, Codex pretool guard |
| CLAUDE examples | implemented | `docs/CLAUDE-EXAMPLES.md` | Reference setups for common project types |
| Native Codex MCP auto-registration | partial | `install.sh`, `setup_codex_mcps` | Works when Codex CLI + required creds/tools are available |
| Obsidian vault integration | partial | `setup_obsidian_mcp`, `setup_codex_mcps` | Fully automatic if API key is already available; otherwise degrades gracefully |
| Trace analysis (v1.8) | implemented | `.agents/skills/trace-analysis/SKILL.md` | Session-end trace mining — classifies signals, proposes blind spots and instincts. Gated by `CANUTO_TRACE_ANALYSIS=1` |
| Auto-generated blind spots (v1.8) | implemented | `.agents/blind-spots/_candidates/` | Staging area for trace-derived blind-spot candidates. Lifecycle: create → review → promote/dismiss |
| Adaptive routing (v1.8) | implemented | `.agents/skills/adaptive-routing/SKILL.md` | Mid-session routing-check after Architect/Coder handoff. User-confirmed reroutes only |
| Skill auto-discovery (v1.8) | implemented | `.agents/skills/trace-analysis/references/skill-proposer.md` | Detects recurring manual workflows (3+ sessions) and proposes skill creation |
| Experiment auto-triggers (v1.8) | implemented | `.agents/skills/experiment-loop/references/auto-triggers.md` | Proposes experiments when review scores trend below 7.0 (proposal only, never auto-start) |
