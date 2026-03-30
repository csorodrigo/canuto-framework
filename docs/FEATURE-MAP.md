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
| JSON health output | implemented | `install.sh --test --json`, `.agents/tools/codex-health-check.sh --json` | Machine-readable diagnostics for CI and dashboards |
| Context bootstrap | implemented | `.context.md`, `docs/FEATURE-MAP.md`, `.agents/vault/digests/00-bootstrap-digest.md` | Created automatically when missing |
| Passive hooks | implemented | `.agents/hooks/` | Session save, pre-compact save, plan review, Codex pretool guard |
| CLAUDE examples | implemented | `docs/CLAUDE-EXAMPLES.md` | Reference setups for common project types |
| Native Codex MCP auto-registration | partial | `install.sh`, `setup_codex_mcps` | Works when Codex CLI + required creds/tools are available |
| Obsidian vault integration | partial | `setup_obsidian_mcp`, `setup_codex_mcps` | Fully automatic if API key is already available; otherwise degrades gracefully |
