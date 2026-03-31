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
| tier-1 | Strategic (Maestro, Architect, Contextualizer) | Active runtime (`claude` by default, `codex` in direct Codex sessions) | opus / o1-pro | — | No — stays on the active runtime |
| tier-2 | Coder | Codex | gpt-5-codex | `mcp__codex-coder__spawn_agent` | Yes — writes code in filesystem |
| tier-2 | Reviewer | Codex | o1-pro | `mcp__codex-reviewer__codex` | Yes — deep self-review (cross-model) |
| tier-2 | Tester, Debugger | Codex | gpt-5-codex | `mcp__codex-coder__spawn_agent` | Yes — can use Codex or Claude |

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

4. **Codex writes code directly in filesystem** (gpt-5-codex).

5. **Post-code**: Opus reads `git diff`, then triggers Code Review via `mcp__codex-reviewer__codex` (o1-pro self-review).

6. For **XS/S tasks**: Claude codes directly — MCP overhead not justified. No context preload needed.

#### B. Review Delegation (preferred: MCP)

1. **Send plan or diff** to `mcp__codex-reviewer__codex` (o1-pro):
   - Include full plan between `--- PLAN START/END ---` delimiters.
   - Or include `git diff` between `--- CHANGES START/END ---` delimiters.

2. **Codex reviews with o1-pro** (ultra think, cross-model perspective).

3. **Multi-turn**: Use `mcp__codex-reviewer__codex-reply(threadId, msg)` for follow-ups.

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

### 3. Auto-Escalation: gpt-5-codex → o1-pro

When `codex-coder` (gpt-5-codex) fails a task:

| Failure Type | Detection | Action |
|-------------|-----------|--------|
| Tests fail after code | Test runner reports failures | Re-attempt with `/test-fix` loop (3 iterations) |
| Malformed output | Output doesn't match expected format | Retry once with clarified prompt |
| Timeout | No response in 120s | Escalate to o1-pro |
| Logic error | Review catches fundamental flaw | Escalate to o1-pro with error context |

**Escalation procedure:**
1. Collect: original prompt + gpt-5-codex's output + error/failure details
2. Send to `mcp__codex-reviewer__codex` (o1-pro) with escalation tag:
   ```
   [ESCALATION: gpt-5-codex → o1-pro]
   The fast model failed this task. Use maximum reasoning depth.

   ## Original Task
   {original_prompt}

   ## What Failed
   {failure_details}

   ## gpt-5-codex's Attempt
   {codex_output_or_diff}

   Please provide the correct implementation.
   ```
3. Apply o1-pro's fix
4. Log escalation in session metrics

**Cost note:** o1-pro is significantly more expensive. Only escalate after gpt-5-codex genuinely fails (not for first attempt).

### 4. Fallback Strategy

```
codex-coder MCP (gpt-5-codex) → escalate to codex-reviewer MCP (o1-pro) → CCB ask → Claude-only
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
| codex-collab MCP | MCP tools (threadId) | Background subagent | Yes | No |
| CCB panes | CLI terminal panes (WezTerm/tmux) | Visible terminal panes | Yes | Yes (JSONL, resumable) |

### Backend Selection

Maestro chooses the backend based on:

1. **MCP available** (preferred): `codex-coder` for coding, `codex-reviewer` for reviews
2. **User preference**: if user says "use CCB", "show me the panes", "visible execution" → CCB
3. **CCB available**: CCB installed? → fallback to `ask codex`
4. **Default**: Claude does everything (all-in-one)

### Fallback Chain

```
codex-coder/codex-reviewer MCP → CCB panes → API delegation → Claude (all-in-one)
```

If CCB is not installed, the fallback is transparent. No user action needed.

See `.agents/plugins/ccb/skills/ccb-delegate.md` for the full CCB delegation procedure.

---

## Environment Variables

```
ANTHROPIC_API_KEY=...     # Claude (always required)
OPENAI_API_KEY=...        # Codex (optional)
GLM_API_KEY=...           # GLM (optional)
# CCB (optional — only if CCB plugin is installed)
# CCB reads provider keys from its own config but uses the same env vars above
```

These MUST be in `.env` (never committed). See `security-practices` skill.

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
