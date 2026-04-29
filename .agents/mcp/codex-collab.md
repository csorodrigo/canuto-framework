# Codex CLI Collaboration (v2.0, 2026-04-29)

Codex is invoked via CLI (`codex exec --profile <name>`), not MCP. Maestro
delegates tier-2 work to Codex profiles using direct shell invocation.

> Historical note: 2026-03-30 → 2026-04-29 used dual MCP servers
> (`codex-coder`, `codex-reviewer`, `codex-maestro`). Retired because MCP
> schema overhead consumes 10-35% extra tokens per call vs raw `codex exec`,
> and only amortizes after ~50 calls/session (rare). See
> `.agents/skills/cost-routing.md` for the full rationale.

## Architecture

| Profile | Default Model | Sandbox | Role | Invocation |
|---------|---------------|---------|------|------------|
| `coder` | `gpt-5.5` (high) | full write | Coder, Brainstorm, Tester | `codex exec --color never --profile coder` |
| `reviewer` | `gpt-5.5` (high) | read-only | Reviewer (deep review) | `codex exec --color never --profile reviewer` |
| `architect` | `gpt-5.5` (xhigh) | read-only | Deep planning, escalation, large-diff review | `codex exec --color never --profile architect` |
| `maestro` | `gpt-5.5` (xhigh) | full write | Direct Codex runtime orchestration | `codex --profile maestro` (interactive launcher) |
| `fast` | `gpt-5.5` (high) | full write | Quick edits, formatting, docs | `codex exec --color never --profile fast` |

**Source of truth for model versions**: `.agents/config/models.yaml`.

## Setup

**Automatic**: `bash install.sh`, `bash install.sh --update`, or `bash install.sh --doctor`
- creates/patches `~/.codex/config.toml` with the 5 profiles above
- updates existing profiles to the canonical model (no longer just appends)
- removes any legacy `codex-coder` / `codex-reviewer` / `codex-maestro` MCP entries from `~/.claude/settings.json`
- installs Codex shared libs (`codex-common.sh`, `codex-diff-context.sh`) to `~/.claude/scripts/`

## Prerequisites

- Codex CLI installed: `npm i -g @openai/codex`
- Codex authenticated: `codex login`
- Project trusted in `~/.codex/config.toml`

## Verify

```bash
codex --version                        # CLI present
ls ~/.codex/config.toml                # config exists
grep -A2 '\[profiles\.' ~/.codex/config.toml | head -20  # 5 profiles, gpt-5.5

# Smoke test: each profile responds
echo 'Reply with: OK' | codex exec --color never --profile coder \
  --skip-git-repo-check -s read-only \
  -o /tmp/codex-smoke.md - >/dev/null && cat /tmp/codex-smoke.md
```

## Standard invocation pattern

```bash
codex exec --color never --profile coder \
  -s workspace-write \
  --skip-git-repo-check \
  -o /tmp/codex-result-$$.md \
  "$(cat <<'PROMPT'
Read .agents/tmp/context-package.md for full task context.
Implement per plan. Output: brief summary of files changed.
PROMPT
)"
# Read result via: cat /tmp/codex-result-$$.md
```

**Key flags**:
- `--color never` — strips ANSI/banners (saves 5-15% tokens)
- `-o <file>` — final message to file, keeps stdout clean
- `--profile <name>` — routes to coder/reviewer/architect/fast/maestro in `~/.codex/config.toml`
- `-s read-only` for review tasks; `-s workspace-write` for code-gen
- `--skip-git-repo-check` when running from `/tmp` or detached HEAD scenarios

## Pipeline: Code -> Review

```text
Claude (Maestro) plans the task
  ↓
codex exec --profile coder "Implement X per plan: ..."
  ↓
Codex writes code directly to filesystem
  ↓
Claude reads git diff
  ↓
codex exec --profile reviewer "Review this diff as staff engineer: ..."
  ↓
Reviewer returns one-shot review output via -o flag
  ↓
Claude consolidates the result for the user
```

## Fallback Chain

```text
codex exec --profile coder failed
  ↓ retry with clarified prompt
  ↓ if fail: escalate to --profile reviewer (deeper reasoning)
  ↓ if fail: escalate to --profile architect (xhigh)
  ↓ if fail: Claude implements directly + log incident
```

## Native Codex MCPs (read by Codex itself)

When Codex runs, it can call these MCPs:

| MCP | Purpose | Fallback |
|-----|---------|----------|
| obsidian-vault | Read/write vault notes | `vault-bridge.sh` |
| ast-grep | Structural code search | `rg` / `grep` |
| playwright | Browser automation | Claude-driven browser flow |

These are MCPs **inside the Codex runtime** (registered via `codex mcp add ...`),
not Claude-side MCPs. They are independent of the retired Codex MCP wrappers.

## Session Continuity

`codex exec` is one-shot. For multi-turn, re-invoke with extended context.

Persist for follow-up:
- Generated markdown via `-o /tmp/codex-result-*.md`
- Event entries in `codex-review-events.jsonl` (when using reviewer helper)
- Higher-level handoff metadata in the vault

## Troubleshooting

- **`codex` not in PATH**: re-run `bash install.sh --doctor`
- **Reviewer hanging**: timeout via `gtimeout 600 codex exec ...` (install with `brew install coreutils`)
- **Profile not found**: `~/.codex/config.toml` missing the profile block — re-run `bash install.sh --doctor`
- **Model drifted (still on gpt-5.4)**: `bash install.sh --doctor` now updates existing profiles to canonical model (single source: `.agents/config/models.yaml`)
- **Legacy MCP entries still present**: `bash install.sh --doctor` removes them automatically; or manually:
  ```bash
  claude mcp remove codex-coder codex-reviewer codex-maestro 2>/dev/null
  ```
