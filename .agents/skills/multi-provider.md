shortDescription: How Maestro delegates work to different AI providers (Claude, Codex, GLM).
usedBy: [maestro]
version: 1.0.0
lastUpdated: 2026-02-25
copyright: Rodrigo Canuto © 2026.

## When to Use

**Triggers:**
- CLAUDE.md has a `## Providers` section with non-Claude entries configured
- User explicitly requests a specific provider for a task
- A tier-2 persona (Coder, Tester, Debugger, Reviewer) is being handed off

**Not for:**
- Switching the active runtime automatically mid-session
- Tier-1 personas when the runtime is already fixed for the session
- Projects without API keys configured for secondary providers (fall back to Claude silently)

---

## Purpose

Enable the Maestro to orchestrate multiple AI providers for different personas, optimizing cost, speed, and quality. Claude remains the default runtime, but a direct Codex session can also run Maestro via the `maestro` profile. Execution personas (Coder, Tester, Debugger, Reviewer) can still be delegated independently.

---

## Provider Tiers

| Tier | Role | Default Provider | Model | MCP Tool | Can Delegate? |
|------|------|-----------------|-------|----------|---------------|
| tier-1 | Strategic (Maestro, Architect, Contextualizer) | Active runtime (`claude` by default, `codex` in direct Codex sessions) | opus / reviewer profile | — | No — stays on the active runtime |
| tier-2 | Coder | Codex | gpt-5.4 (reasoning: high) | `mcp__codex-coder__spawn_agent` | Yes — writes code in filesystem |
| tier-2 | Reviewer | Codex | reviewer profile (`gpt-5.4`, reasoning: high) | `mcp__codex-reviewer__spawn_agent` | Yes — deep self-review (cross-model) |
| tier-2 | Tester, Debugger | Codex | gpt-5.4 (reasoning: high) | `mcp__codex-coder__spawn_agent` | Yes — can use Codex or Claude |
| tier-2 | Contextualizer (long-context digest) | Gemini | gemini-3.1-pro-preview | `mcp__gemini__ask-gemini` | Yes — reads repo via `@folder`, outputs digest |
| tier-2 | Multimodal (OCR / screenshots) | Gemini | gemini-3.1-pro-preview | `mcp__gemini__ask-gemini` | Yes — images passed via `@file` |
| tier-2 | Brainstorm (structured ideation) | Gemini | gemini-3.1-pro-preview | `mcp__gemini__brainstorm` | Yes — SCAMPER / lateral / design-thinking |
| tier-2 | Bulk classifier | Gemini | gemini-3.1-flash-lite-preview | `mcp__gemini__ask-gemini` | Yes — labeling, triagem at volume |

---

## Procedure

### 1. Provider Configuration

Configure providers in `CLAUDE.md`:

```markdown
## Providers
- primary: claude
- coder: codex | claude | glm
- tester: claude | codex
- debugger: claude
- reviewer: claude
```

If no provider section exists, all personas default to Claude.

Direct Codex sessions are an exception: the active runtime becomes Codex for tier-1 orchestration, using `codex --profile maestro` or `bash .agents/tools/codex-maestro.sh`.

### 2. Delegation Protocol

When Maestro delegates to a tier-2 persona:

#### A. Coding Delegation (preferred: MCP + Context Preload)

1. **Consult cost-routing** (`.agents/skills/cost-routing.md`) — confirm Codex is the right provider.

2. **Prepare context package** (M/L tasks only):
   - Write `.agents/tmp/context-package.md` with: plan, digests, types, constraints.
   - See `context-preload` skill for the full procedure.
   - Codex reads from disk — zero Opus tokens for context.

3. **Spawn Codex agent**:
   ```
   mcp__codex-coder__spawn_agent({
     prompt: "Read .agents/tmp/context-package.md for full task context. Implement per plan."
   })
   ```

4. **Codex writes code directly in filesystem** (gpt-5.4 (reasoning: high)).

5. **Post-code**: Opus reads `git diff`, then triggers Code Review via `mcp__codex-reviewer__spawn_agent` (reviewer profile self-review).

6. For **XS/S tasks**: Claude codes directly — MCP overhead not justified. No context preload needed.

#### B. Review Delegation (preferred: MCP)

1. **Send plan or diff** to `mcp__codex-reviewer__spawn_agent` (reviewer profile):
   - Include full plan between `--- PLAN START/END ---` delimiters.
   - Or include `git diff` between `--- CHANGES START/END ---` delimiters.

2. **Codex reviews with the reviewer profile** (cross-model perspective).

3. The current wrapper is **one-shot**. There is no reviewer-side `threadId` contract for follow-ups.

#### C. Legacy Delegation (fallback: API/CCB)

1. **Prepare the handoff package**:
   - Goal statement (same as normal handoff).
   - Relevant context files (`.context.md`, feature map sections).
   - The Architect's plan (for Coder) or implementation summary (for Tester/Reviewer).
   - The persona's playbook (the full `.md` file content).

2. **Send via CCB** (`ask codex`) or **API** (when MCP unavailable).

3. **Validate the response**:
   - Check that the output follows the expected format.
   - If the output is malformed, retry once with a clarification prompt.
   - If still malformed, fall back to Claude for that task.

### 3. Auto-Escalation: gpt-5.4 (reasoning: high) → reviewer profile

When `codex-coder` (gpt-5.4 (reasoning: high)) fails a task:

| Failure Type | Detection | Action |
|-------------|-----------|--------|
| Tests fail after code | Test runner reports failures | Re-attempt with `/test-fix` loop (3 iterations) |
| Malformed output | Output doesn't match expected format | Retry once with clarified prompt |
| Timeout | No response in 120s | Escalate to reasoning: xhigh (architect profile) |
| Logic error | Review catches fundamental flaw | Escalate to reasoning: xhigh (architect profile) with error context |

**Escalation procedure:**
1. Collect: original prompt + gpt-5.4 (reasoning: high)'s output + error/failure details
2. Send to `mcp__codex-reviewer__spawn_agent` (reviewer profile) with escalation tag:
   ```
   [ESCALATION: gpt-5.4 (reasoning: high) -> reviewer profile]
   The fast model failed this task. Use deeper reasoning than the coding pass.

   ## Original Task
   {original_prompt}

   ## What Failed
   {failure_details}

   ## gpt-5.4 (reasoning: high)'s Attempt
   {codex_output_or_diff}

   Please provide the correct implementation.
   ```
3. Apply the reviewer guidance
4. Log escalation in session metrics

**Cost note:** reviewer-grade paths are more expensive. Only escalate after gpt-5.4 (reasoning: high) genuinely fails.

### 4. Fallback Strategy

Fallback matrix by task type:

```
code-gen (escrita):
  codex-coder → codex-reviewer → Claude   (NÃO Gemini — sem sandbox)

code-review (formal gate):
  codex-reviewer → gemini-3.1-pro-preview (second opinion) → Claude

context-digest / @folder:
  gemini-3.1-pro-preview (primary) → codex context-preload → Claude

multimodal (screenshot, image):
  gemini-3.1-pro-preview (primary) → Claude (sem plano B real)

brainstorm / research Phase 0:
  gemini-3.1-pro-preview + codex parallel (em paralelo) → Claude consolida

bulk classify:
  gemini-3.1-flash-lite-preview (primary) → Claude (limite de volume)

security review (auth/crypto/payment):
  triple obrigatório: codex-reviewer + gemini + Opus

plan review estratégico:
  triple via /co-plan --triple: opus (self) + codex-reviewer + gemini
```

Maestro logs every fallback and escalation in the session summary.

### 4. Quality Tracking

For each delegated task, Maestro records:
- Provider used.
- Whether output was accepted on first try, retried, or fell back.
- Any format compliance issues.

This data feeds into the metrics system (see `metrics` skill).

---

## Current Limitations

- **API access**: Multi-provider delegation requires API keys configured as environment variables. Not all environments support this.
- **Context window**: Different providers have different context limits. Maestro should estimate and warn if the handoff package exceeds the target provider's limit.
- **Tool use**: Some providers don't support tool use (file reading, command execution). The handoff package must include all necessary context inline.

---

## CCB Backend (Optional)

When the CCB plugin is installed (`.agents/plugins/ccb/`), delegation gains a third backend with visible terminal panes:

| Backend | Mechanism | Visibility | Multi-turn | Session Persistence |
|---------|-----------|------------|------------|---------------------|
| API (default) | Provider API calls | Invisible | No | No |
| codex-collab MCP | MCP tools (`spawn_agent`) | Background subagent | No | No |
| CCB panes | CLI terminal panes (WezTerm/tmux) | Visible terminal panes | Yes | Yes (JSONL, resumable) |

### Backend Selection

Maestro chooses the backend based on:

1. **MCP available** (preferred): `codex-coder` for coding, `codex-reviewer` for reviews
2. **User preference**: if user says "use CCB", "show me the panes", "visible execution" → CCB
3. **CCB available**: CCB installed? → fallback to `ask codex`
4. **Default**: Claude does everything (all-in-one)

### Fallback Chain

```
codex-coder/codex-reviewer MCP -> CCB panes -> API delegation -> Claude (all-in-one)
```

If CCB is not installed, the fallback is transparent. No user action needed.

See `.agents/plugins/ccb/skills/ccb-delegate.md` for the full CCB delegation procedure.

---

## Environment Variables

```
ANTHROPIC_API_KEY=...     # Claude (always required)
OPENAI_API_KEY=...        # Codex (optional — ChatGPT-account Codex CLI uses its own login)
GLM_API_KEY=...           # GLM (optional)
# Gemini: uses OAuth (no env var). Run `gemini auth login` once; `mcp__gemini__*` inherits.
# CCB (optional — only if CCB plugin is installed)
# CCB reads provider keys from its own config but uses the same env vars above
```

These MUST be in `.env` (never committed). See `security-practices` skill.

**Gemini auth note:** `jamubc/gemini-mcp-tool` (registered as `gemini` user-scope) is
OAuth-only — it shells out to the local `gemini-cli`. No `GEMINI_API_KEY` is needed,
and per gotcha in `gemini-routing.md` we do NOT add one (would change quota tier
and trigger different fallback behavior). Quota: 1000 req/day on OAuth, split across
Pro / Flash / Flash-Lite buckets.

---

## Examples

### ✅ Good — transparent delegation with fallback logging

```
Delegating Step 3 (implement auth middleware) to Codex.
Handoff package: plan step 3 + src/auth/.context.md + coder.md playbook.
[Codex responds with implementation summary]
Validating output format... ✅ accepted.
```

User is informed, delegation is logged, output is validated before accepting.

### ❌ Bad — silent failure and fabricated output

```
[Codex API call fails, no response]
[Maestro continues as if Coder completed the task]
```

This is bad because: Maestro must fall back to Claude and log the failure — never silently pretend a delegation succeeded when it didn't.

---

## Guardrails

- Maestro (tier-1) MUST stay on the active runtime for the session. Never switch runtimes automatically mid-session.
- Never send secrets, API keys, or credentials to any provider as part of the handoff.
- If a provider is configured but its API key is missing, fall back to Claude silently and log it.
- Never retry more than once. If two attempts fail, fall back.
- The user must be informed when a non-Claude provider is being used for a task.
