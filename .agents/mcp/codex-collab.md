# Codex Dual-MCP Architecture (v1.6)

Two Codex MCP servers with different models for different roles.
Auto-configured by `install.sh` → `setup_codex()` + `setup_codex_mcps()`.

## Architecture

| MCP Server | Model | Role | Tools |
|------------|-------|------|-------|
| **codex-coder** | gpt-5-codex | Coder, Brainstorm, Tester | `spawn_agent`, `spawn_agents_parallel` |
| **codex-reviewer** | o1-pro | Reviewer (deep self-review) | `codex`, `codex-reply` |

**Principle**: gpt-5-codex writes code fast → o1-pro reviews with deep thinking. Cross-model review eliminates blind spots.

## Setup

**Automatic** (recommended): `bash install.sh` or `bash install.sh --update`
- `setup_codex()` installs CLI, configures profiles, trusts project, registers MCPs in Claude
- `setup_codex_mcps()` registers Obsidian, ast-grep, Playwright in Codex natively

**Manual** (if needed):
```bash
# Coder — fire-and-forget, writes code in filesystem
claude mcp add -s user codex-coder -- uvx codex-as-mcp@latest

# Reviewer — multi-turn, o1-pro deep review
claude mcp add -s user codex-reviewer -- codex mcp serve -c 'model=o1-pro'
```

### Prerequisites

- Codex CLI installed: `npm i -g @openai/codex` (v0.40+)
- OpenAI API key configured (`OPENAI_API_KEY` in environment)
- Codex authenticated: `codex login`
- Project trust: `~/.codex/config.toml` with `trust_level = "trusted"`

### Conductor-Aware Trust

install.sh auto-detects Conductor layout (`workspaces/{project}/{branch}/`):
- Trusts the specific worktree path
- Also trusts the workspace parent so new worktrees auto-trust
- Sets `approval_policy = "never"` + `sandbox_mode = "danger-full-access"`

### Verify

```bash
claude mcp list
# codex-coder: ✓ Connected
# codex-reviewer: ✓ Connected

codex mcp list
# obsidian-vault: registered
# ast-grep: registered
# playwright: registered
```

### Codex Native MCPs

Agents spawned via `codex exec` (used by `spawn_agent`) can access:

| MCP | Purpose | Fallback |
|-----|---------|----------|
| obsidian-vault | Read/write vault notes | `vault-bridge.sh` |
| ast-grep | Structural code search | `rg` / `grep` |
| playwright | Browser automation | Opus-driven `/browse` |

## Tools Reference

### codex-coder (gpt-5-codex)

#### `mcp__codex-coder__spawn_agent`

Spawn a single Codex agent that writes code directly in the filesystem.

**Parameters:**
- `prompt` (string, required) — Task description with plan, file paths, constraints

**Returns:**
- Final message from Codex with summary of changes made

**Note**: Runs `codex exec --dangerously-bypass-approvals-and-sandbox`. Only use in trusted repos.

#### `mcp__codex-coder__spawn_agents_parallel`

Spawn multiple Codex agents in parallel (useful for brainstorming).

**Parameters:**
- `agents` (list, required) — List of `{prompt: string}` objects

**Returns:**
- Array of responses from each agent

### codex-reviewer (o1-pro)

#### `mcp__codex-reviewer__codex`

Start a new Codex review session with o1-pro (ultra think).

**Parameters:**
- `prompt` (string, required) — Review request with plan or diff

**Returns:**
- `response` — Codex's review text
- `threadId` — Session ID for follow-up messages

#### `mcp__codex-reviewer__codex-reply`

Continue an existing review conversation.

**Parameters:**
- `threadId` (string, required) — Session ID from a previous call
- `message` (string, required) — Follow-up message

**Returns:**
- `response` — Codex's response text

## Pipeline: Code → Review

```
Opus (Architect) plans the task
  ↓
mcp__codex-coder__spawn_agent("Implement X per plan: ...")
  → Codex (gpt-5-codex) writes code in filesystem
  ↓
Opus reads git diff → high-level check
  ↓
mcp__codex-reviewer__codex("Review this diff as staff eng: ...")
  → Codex (o1-pro) deep self-review
  ↓
Opus consolidates: diff + review → presents to user
```

Runtime helpers now installed with the framework:
- `.agents/hooks/plan-review.sh` → `PostToolUse: ExitPlanMode`
- `.agents/hooks/codex-pretool-guard.sh` → `PreToolUse` guard for `git commit` and Codex delegation
- `.agents/tools/codex-diff-context.sh` → deterministic diff compression
- `.agents/tools/codex-context-package.sh` → generates `.agents/tmp/context-package.md`
- `.agents/tools/codex-health-check.sh` → end-to-end integration diagnostics

## Model Override Mechanism

The `codex-reviewer` uses `-c model=o1-pro` flag on `codex mcp serve`, which overrides `~/.codex/config.toml` for that MCP session only.

The `codex-coder` uses the default model from `config.toml` (gpt-5-codex).

To change models:
```bash
# Remove and re-add with different model
claude mcp remove codex-reviewer
claude mcp add -s user codex-reviewer -- codex mcp serve -c 'model=o3'
```

## Fallback Chain

```
codex-reviewer MCP → codex-coder MCP (one-shot) → CCB ask codex → Claude-only
```

## Codex Profiles

Profiles are defined in `~/.codex/config.toml` for quick model switching:

```toml
[profiles.coder]
model = "gpt-5-codex"
model_reasoning_effort = "medium"

[profiles.reviewer]
model = "o1-pro"
model_reasoning_effort = "high"

[profiles.architect]
model = "o3"
model_reasoning_effort = "high"

[profiles.fast]
model = "gpt-5-codex"
model_reasoning_effort = "low"
```

Usage: `codex --profile reviewer` or `codex --profile coder`.

## Extended Skills

### Phase 2 — Integration
| Skill | Description | MCP Used |
|-------|-------------|----------|
| `/co-brainstorm` | Parallel ideation (3+ agents) | codex-coder `spawn_agents_parallel` |
| `/co-plan` | Independent parallel planning | codex-reviewer `codex` |
| `/co-validate` | Staff engineer plan review | codex-reviewer `codex` |
| `/parallel-impl` | Break feature into subtasks, implement in parallel | codex-coder `spawn_agents_parallel` |
| `/test-fix` | Autonomous test-fix loop (3 iterations) | codex-coder `spawn_agent` |
| `/compete` | Dual implementation, compare, pick best | codex-coder + codex-reviewer |
| `/security-gate` | OWASP security scan before merge | codex-reviewer `codex` |
| Pre-commit gate | Auto-review staged changes | codex-reviewer `codex` |

### Phase 3 — Economy + Deep Integration
| Skill | Description | Savings |
|-------|-------------|---------|
| `/codex-context-loader` | Codex reads codebase, generates digests | 90% context tokens |
| `/codex-session-writer` | Codex writes session notes to vault | 80% formatting tokens |
| `/codex-pr-writer` | Codex generates PR description + changelog | 70% doc tokens |
| `/smart-token-metering` | Auto-switch to economy mode at budget threshold | Variable |
| `/codex-gh` | Codex handles GitHub ops via GitHub MCP | 60% GitHub tokens |
| `/codex-refactor-prep` | Codex prepares codebase before feature impl | 60% refactor tokens |
| `/lazy-opus-review` | Confidence-gated review (skip when >= 8) | 50% review tokens |
| `/codex-onboard` | Codex runs deep analysis on new projects | 90% onboarding tokens |
| `/cross-project-insights` | Codex reads multi-project vault notes | 90% vault reading |
| `/codex-test` | Smoke test for Codex MCP integration | N/A (diagnostic) |

## Auto-Escalation

```
gpt-5-codex fails → retry once → escalate to o1-pro → Claude fallback
```

Tracked in vault: `.agents/vault/metrics/review-scores-template.md`

## Session Continuity

`threadId` from codex-reviewer is persisted in `.agents/vault/sessions/review-threads.md`.
Enables cross-session multi-turn reviews: "did I fix the issues from yesterday?"

## Troubleshooting

- **"MCP tool not found"**: Run the setup commands above
- **"OPENAI_API_KEY not set"**: Export your API key in your shell profile
- **Timeout**: o1-pro reviews may take 30-90s. Accept the latency for better quality.
- **Model not available**: Check `codex --model o1-pro` works. If not, try `o3` or `gpt-5-codex`.
- **Not available**: Skills degrade gracefully → CCB fallback → Claude-only.
- **Profile not working**: Verify `~/.codex/config.toml` has the `[profiles.X]` sections.
- **Escalation loop**: Max 1 escalation per task. After o1-pro fails, Claude takes over.
