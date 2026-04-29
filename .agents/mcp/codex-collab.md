# Codex Dual-MCP Architecture (v1.7)

Two Codex MCP servers with deterministic role routing.
Auto-configured by `install.sh` via wrapper scripts in `~/.claude/scripts/`.

## Architecture

| MCP Server | Target Profile | Default Model | Sandbox | Role | Tools |
|------------|----------------|---------------|---------|------|-------|
| **codex-coder** | `coder` | `gpt-5.5` (high) | full write | Coder, Brainstorm, Tester | `spawn_agent`, `spawn_agents_parallel` |
| **codex-reviewer** | `reviewer` | `gpt-5.5` (high, reviewer profile) | read-only | Reviewer (deep review) | `spawn_agent` |
| **codex-maestro** | `maestro` | `gpt-5.5` (high, reviewer profile) | full write | Maestro orchestration (gpt-5.5 with reasoning: xhigh + write access) | `spawn_agent`, `spawn_agents_parallel` |

**Principle**: `gpt-5.5` (high) writes code fast. The `reviewer` profile performs the second-opinion review. If the preferred reviewer model is unavailable, the fallback must be reported explicitly.

## Setup

**Automatic** (recommended): `bash install.sh`, `bash install.sh --update`, or `bash install.sh --repair`
- installs Codex CLI profiles in `~/.codex/config.toml`
- copies wrapper scripts to `~/.claude/scripts/`
- registers `codex-coder` and `codex-reviewer` in `~/.claude/settings.json`
- registers native Codex MCPs (Obsidian, ast-grep, Playwright) when available

**Manual** (if needed):
```bash
claude mcp add -s user codex-coder -- ~/.claude/scripts/codex-coder.sh
claude mcp add -s user codex-reviewer -- ~/.claude/scripts/codex-reviewer.sh
```

## Prerequisites

- Codex CLI installed: `npm i -g @openai/codex`
- `uvx` available (used by the wrapper launcher)
- Codex authenticated: `codex login`
- Project trusted in `~/.codex/config.toml`

## Verify

```bash
claude mcp list
# codex-coder: ✓ Connected
# codex-reviewer: ✓ Connected

codex mcp list
# obsidian-vault: registered
# ast-grep: registered
# playwright: registered
```

## Tool Reference

### codex-coder

#### `codex exec --profile coder`

Spawn one Codex coding agent that writes directly to the filesystem.

#### `(parallel codex exec --profile coder)`

Spawn multiple Codex coding agents in parallel.

### codex-reviewer

#### `codex exec --profile reviewer`

Spawn one one-shot Codex reviewer using the `reviewer` profile.

**Important**:
- This wrapper is one-shot. It does **not** expose `threadId`.
- Treat it as a deterministic review call, not as a resumable conversation.
- If the preferred reviewer model is unavailable, report the actual fallback path and model used.

## Pipeline: Code -> Review

```text
Claude plans the task
  ↓
codex exec --profile coder("Implement X per plan: ...")
  ↓
Codex (coder profile) writes code in the filesystem
  ↓
Claude reads git diff
  ↓
codex exec --profile reviewer("Review this diff as staff engineer: ...")
  ↓
Codex (reviewer profile) returns one-shot review output
  ↓
Claude consolidates the result for the user
```

## Model Routing

- `codex-coder` always uses `--profile coder`
- `codex-reviewer` always uses `--profile reviewer`
- `reviewer` uses `gpt-5.5` with reasoning: high in `~/.codex/config.toml`, but account support is required
- if the reviewer profile model is unavailable, the framework may fall back to another reviewer path; that degradation must be surfaced in output and logs

## Fallback Chain

```text
codex-reviewer MCP -> codex exec --profile reviewer -> /ask codex (only with active CCB session) -> Claude-only
```

## Native Codex MCPs

Agents spawned via `codex exec` can access:

| MCP | Purpose | Fallback |
|-----|---------|----------|
| obsidian-vault | Read/write vault notes | `vault-bridge.sh` |
| ast-grep | Structural code search | `rg` / `grep` |
| playwright | Browser automation | Claude-driven browser flow |

## Session Continuity

The current reviewer wrapper is **not** multi-turn. There is no reviewer-side `threadId` contract to persist.

Persist instead:
- the generated markdown review report in `.agents/tmp/codex/`
- event entries in `codex-review-events.jsonl`
- any higher-level handoff metadata you need in the vault

## Troubleshooting

- **Wrapper command missing**: re-run `bash install.sh --repair`
- **Reviewer connected but failing**: test `codex exec --profile reviewer` directly; connection alone does not prove model availability
- **reviewer profile unsupported**: keep the reviewer path explicit and report the fallback path actually used
- **`/ask codex` unavailable**: open a CCB Codex session first; the bridge is not universal
