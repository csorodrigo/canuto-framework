---
skill: cost-routing
trigger: Automatic — Maestro consults before every tier-2 delegation
persona: maestro
version: 2.0.0
lastUpdated: 2026-04-29
shortDescription: >
  Cost-aware task routing table. Routes work to Codex CLI (gpt-5.5) for tier-2
  by default; Claude Opus 4.7 owns tier-1. CLI invocation chosen over MCP for
  10-35% lower token overhead per call.
usedBy: [maestro]
evals:
  - prompt: "implement the auth module"
    should_trigger: true
  - prompt: "plan the architecture"
    should_trigger: false
---

## Purpose

Before delegating ANY tier-2 task, Maestro consults this routing table to determine
which provider should handle it. **Goal: minimize Anthropic spend without losing quality.**

Canonical model reference: `.agents/config/models.yaml` (human-readable; keep
`install.sh` profile values synced manually).

**Principle: Use the cheapest provider that meets quality requirements.**

**Why CLI over MCP** (decided 2026-04-29): MCP schema overhead consumes 400-1500
tokens residentes + 10-35% extra per call vs raw `codex exec`. Schema only amortizes
after ~50 calls/session, which is rare in this framework's profile (typical: 3-15
spawns). CLI also has no MCP-server dependency — sessões não param se server cai.

---

## Cost Routing Matrix

All Codex invocations use the CLI: `codex exec --color never -q --profile <profile>`.
Add `--output-last-message <path>` for clean stdout when output is large.

| Task Type | Size | Provider | Invocation | Est. Savings vs Opus |
|-----------|------|----------|------------|---------------------|
| **Code generation** | M/L | Codex (gpt-5.5, high) | `codex exec --profile coder` | 60-70% |
| **Code generation** | XS/S | Claude (direct) | — | 0% (CLI overhead not justified) |
| **Code review** | M/L | Codex (reviewer profile) | `codex exec --profile reviewer` | 40-50% |
| **Code review (big diff / cross-model)** | L+ | Codex (architect profile, xhigh) | `codex exec --profile architect` | 30% |
| **Code review** | XS/S | Claude (direct) | — | 0% |
| **Test-fix loop** | Any | Codex (gpt-5.5, high) | `codex exec --profile coder` | 80% |
| **Browser QA (exec + capture)** | Any | Codex (Playwright) | `codex exec --profile coder` | 70% |
| **Planning** | Any | Claude Opus 4.7 (xhigh) | — (Maestro plans direct) | N/A (tier-1 quality required) |
| **Architecture** | Any | Claude Opus 4.7 (xhigh) | — (Maestro plans direct) | N/A |
| **User interview** | Any | Claude Opus 4.7 | — (needs AskUserQuestion tool) | N/A |
| **Brainstorm (parallel)** | Any | Codex (parallel via xargs) | `codex exec --profile coder` × N in shell | 60% |
| **Security scan** | Any | Codex (reviewer profile) | `codex exec --profile reviewer` | 40% |
| **Security review (cross-model)** | M/L | Codex reviewer + Claude | 2 calls (Codex CLI + Claude direct) | — |
| **Documentation** | Any | Codex (gpt-5.5, high) | `codex exec --profile coder` | 70% |
| **Context loading** | Any | Codex (context-loader) | `codex exec --profile coder` | 90% |
| **Session notes** | Any | Codex (session-writer) | `codex exec --profile coder` | 80% |
| **PR description** | Any | Codex (pr-writer) | `codex exec --profile coder` | 70% |
| **GitHub ops** | Any | Codex via gh CLI | `codex exec --profile coder` | 60% |
| **Refactoring prep** | M/L | Codex (refactor-prep) | `codex exec --profile architect` | 60% |
| **Onboarding (Codex path)** | Any | Codex (onboarding) | `codex exec --profile coder` | 90% |
| **Vault reading** | Any | Codex (obsidian MCP) | `codex exec --profile coder` | 90% |
| **Planning / Architecture (Codex runtime)** | M/L | Claude Opus 4.7 (cross-model back-delegation) | optional `mcp__claude-architect__spawn_agent` if present | — (tier-1, Codex runtime only) |
| **Code review cruzada (Codex→Claude)** | Any | Claude Sonnet 4.6 | optional `mcp__claude-reviewer__spawn_agent` if present | 40% vs Opus solo |

---

## Decision Procedure

Before each delegation, Maestro follows this flowchart:

```
1. Is this a tier-1 task (planning, architecture, orchestration)?
   → YES: Opus handles directly. STOP.
   → NO: continue.

2. Is this XS/S size?
   → YES: Opus handles directly (CLI overhead not justified). STOP.
   → NO: continue.

3. Does this task require AskUserQuestion or interactive tools?
   → YES: Opus handles directly. STOP.
   → NO: continue.

4. Route per the matrix above using `codex exec --profile <profile>` via Bash.
   → Standard fallback chain (by task type):
     - code-gen: codex coder → codex reviewer (escalation) → codex architect (xhigh) → Claude direct
     - code-review: codex reviewer → codex architect (xhigh) → optional claude-reviewer MCP → Claude direct
     - security review: codex reviewer + Claude direct (two perspectives, no triple)
```

### Standard CLI invocation pattern

```bash
codex exec --color never -q --profile coder \
  --output-last-message /tmp/codex-result-$$.md \
  "$(cat <<'EOF'
<full task prompt with plan + files + constraints>
EOF
)"
# Read result via: cat /tmp/codex-result-$$.md
```

**Key flags**:
- `--color never -q` → strips ANSI/banners (saves 5-15% tokens)
- `--output-last-message <path>` → final message to file, keeps stdout clean
- `--profile <name>` → routes to coder/reviewer/architect/fast profiles in `~/.codex/config.toml`
- `--full-auto` → auto-approves edits (use with caution; default is `--auto-edit`)

---

## Context Optimization Rules

To minimize Opus token consumption:

1. **Never read raw source files just to pass them to Codex.** Use context preload instead:
   - Write context to `.agents/tmp/context-package.md`
   - Codex reads from disk (zero Opus tokens)

2. **Use vault digests** (from context-digest skill) instead of reading full files:
   - 500-line file → 50-line digest = 10x token savings

3. **Let Codex self-serve context** via its native MCPs:
   - obsidian-vault: reads vault notes directly
   - ast-grep: searches code patterns directly
   - Opus doesn't need to pre-read for Codex

---

## External token-saving layers

These run **outside** the routing matrix — they compress data before it reaches any
provider's context. Use them in addition to (not instead of) the matrix routing.

### rtk (Rust Token Killer)

CLI proxy that filters/groups/dedupes Bash command output before it reaches the LLM
context. Targets a layer none of our skills cover: raw stdout from `git`, `rg`, `cat`,
test runners, build tools.

| Property | Value |
|----------|-------|
| Coverage | Bash tool calls only (Read/Grep/Glob bypass it) |
| Savings | 60-90% on covered commands (-80% typical 30-min session) |
| Overhead | <10ms per call |
| License | Apache-2.0 |
| Install | `brew install rtk` (optional — `install.sh` only nudges, never requires) |

**Bootstrap per project** (run once after install):
```bash
rtk init -g                  # Claude Code (default)
rtk init -g --codex          # Codex CLI
```

**Orthogonality with existing skills:**
- `context-digest` — compresses **file content** (10x on 500-line files). rtk doesn't touch files.
- `smart-token-metering` — **measures** Opus consumption. rtk reduces what gets measured.
- `codex-context-loader` — preloads context to disk for Codex. rtk only affects Bash output.

**When NOT to use rtk output:**
- Debugging unfamiliar errors (rtk truncates → may hide root cause). Override with `command 2>&1 | cat`.
- Writing PR descriptions where exact stdout is required. Run the command outside rtk.

### Repomix MCP

MCP server that packs the codebase into a compressed Tree-sitter view (~70% token
reduction on code repos). Targets a layer rtk doesn't cover: bulk codebase context
needed when Codex/Claude must reason about many files at once.

| Property | Value |
|----------|-------|
| Coverage | Codebase reads via MCP query (replaces "read N files manually") |
| Savings | ~70% on code-heavy contexts (TypeScript/Rust/Python). Negligible on prose/markdown |
| Mode | MCP server (`repomix --mcp`) — registered in `.mcp.json` of the project |
| License | MIT |
| Install | `npx repomix --mcp` (no install needed — runs via npx) |

**Project config** (already wired in `.mcp.json` at repo root):
```json
{
  "mcpServers": {
    "repomix": { "command": "npx", "args": ["-y", "repomix@latest", "--mcp"], "type": "stdio" }
  }
}
```

**When to route to Repomix instead of `codex-context-loader`:**
- Bulk codebase summarization (>15 files) — let Repomix Tree-sitter pack first
- Codex needs cross-file reasoning (call sites, type usage) — packed XML is denser than raw reads
- One-shot exports for handoff/review — `npx repomix --compress -o handoff.xml`

**When NOT to use Repomix:**
- Single-file reads — overhead exceeds benefit (use Read tool)
- Prose/markdown-heavy paths (`.agents/`, `docs/`) — Tree-sitter doesn't help; use `context-digest` instead
- Strict secret scanning — Repomix has built-in Security Check but is not a replacement for dedicated scanning

---

## Cost Tracking

After each session, log provider usage to vault metrics:
```yaml
provider_tokens:
  claude: {input_tokens}
  codex: {input_tokens}
estimated_cost:
  claude: ${cost}
  codex: ${cost}
savings_pct: {percentage vs all-opus baseline}
```

See: `.agents/vault/bases/cost-dashboard.base` for trend visualization.

---

## When to Override

Sometimes Opus should handle despite the matrix saying Codex:
- Task requires deep understanding of framework internals
- Previous Codex attempt failed and escalation didn't fix it
- User explicitly requests Claude to handle it
- Task involves sensitive operations (deploy, migration, data mutation)

Always log overrides in the session summary with justification.

---

## CLI-specific gotchas

- **Always pass `--color never -q`** — without it, ANSI escape codes inflate stdout 5-15%.
- **Use `--output-last-message <path>`** for outputs >2KB — keeps Bash tool_result lean.
- **`--skip-git-repo-check`** when running from `/tmp` or non-git dirs.
- **`--ephemeral`** for one-off review/check tasks where session persistence is wasteful.
- **Profile inheritance**: `coder` profile is the default fallback when `--profile` is omitted.
- **Timeout safety**: long-running edits should wrap in `timeout 600 codex exec ...` to prevent runaway sessions.
