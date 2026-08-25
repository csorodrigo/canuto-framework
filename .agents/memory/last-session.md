# Last Session — 2026-04-01

> **Note (atualizado 2026-04-29):** Current config uses `gpt-5.5` across all profiles —
> single source of truth: `.agents/config/models.yaml`. Invocation moved from MCP
> (`mcp__codex-*`) to CLI (`codex exec --profile <name>`) for 10-35% lower token overhead.
> Historical note: 2026-04-17 used `gpt-5.4`; before that, `gpt-5-codex` (phantom slug —
> see I-025).


## What Was Done

### Validação Codex + GitHub
- Validou 4 commits (maestro handoff, fallback mode, delegation rules, reviewer routing)
- Confirmou compatibilidade com Codex CLI v0.117.0→v0.118.0 (sem breaking changes)

### 27 Melhorias Implementadas
- **Rodada 1 (A-H):** pre-commit threshold, stat portability, hook telemetry, maestro MCP, auto-update CLI, maestro fallback chain, o1-pro smoke test
- **Rodada 2 — XS:** cleanup hook, fallback logging, timeout reviewer (120s), architect abbreviated mode, env var overrides, fallback stderr notification
- **Rodada 2 — S:** retry+backoff MCP bridge (3x, 2s/4s/8s), telemetria spawn_agent, cancel-on-failure parallel, prompt injection guard, secret masking diff, schema versioning, vault atomic writes, auto-sync session load, config validation, contextualizer trigger pós-coder
- **Rodada 2 — M:** streaming output, session continuity (thread_id), centralized logging lib, framework smoke test suite (50 tests)
- **R1:** Self-extending skills (OpenClaw pattern) no skill-creator.md

### Code Review + 12 Bug Fixes
- 2 CRITICAL: deadlock stderr+proc.wait, stdin drain antes do write
- 4 HIGH: elapsed calc lixo, always-0 progress, logging.sh short-circuit, env var crash
- 6 MEDIUM: unused import, HTML comment em JSON, grep pattern, secret regex, cleanup mindepth, degraded telemetry

## Key Decisions
- Manter gpt-5-codex no coder profile (melhor pra code gen)
- Novo MCP `codex-maestro` (o1-pro + full write)
- Pre-commit tiers: <20 skip, 20-100 fast, >100/sensível full

## Pending
- [ ] Commit das 27 mudanças
- [ ] PR para main (branch `csorodrigo/check-codex-calls`)
- [ ] Atualizar Codex CLI v0.117.0 → v0.118.0 (`bash install.sh --update`)
- [ ] Explorar: Lightpanda, LangGraph, MCPJungle
