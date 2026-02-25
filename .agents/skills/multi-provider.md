shortDescription: How Maestro delegates work to different AI providers (Claude, Codex, GLM).
usedBy: [maestro]
version: 1.0.0
lastUpdated: 2026-02-25
copyright: Rodrigo Canuto © 2026.

## Purpose

Enable the Maestro to orchestrate multiple AI providers for different personas, optimizing cost, speed, and quality. Claude remains the primary provider (always runs Maestro), but execution personas (Coder, Tester, Debugger) can be delegated to other providers.

---

## Provider Tiers

| Tier | Role | Default Provider | Can Delegate? |
|------|------|-----------------|---------------|
| tier-1 | Strategic (Maestro, Architect, Contextualizer) | Claude | No — always Claude |
| tier-2 | Execution (Coder, Tester, Debugger, Reviewer) | Claude | Yes — can use Codex, GLM, etc. |

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

### 2. Delegation Protocol

When Maestro delegates to a tier-2 persona on a non-Claude provider:

1. **Prepare the handoff package**:
   - Goal statement (same as normal handoff).
   - Relevant context files (`.context.md`, feature map sections).
   - The Architect's plan (for Coder) or implementation summary (for Tester/Reviewer).
   - The persona's playbook (the full `.md` file content).

2. **Format for the target provider**:
   - Strip Canuto-specific metadata headers if the provider doesn't understand them.
   - Include the playbook instructions as a system prompt or preamble.
   - Attach context files as reference documents.

3. **Send via API** (when available):
   - Use the provider's API to submit the task.
   - Collect the response.

4. **Validate the response**:
   - Check that the output follows the expected format (implementation summary, test report, etc.).
   - If the output is malformed, retry once with a clarification prompt.
   - If still malformed, fall back to Claude for that task.

### 3. Fallback Strategy

```
Attempt provider → Malformed output → Retry with clarification → Still bad → Fall back to Claude
```

Maestro logs every fallback in the session summary.

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

## Environment Variables

```
ANTHROPIC_API_KEY=...     # Claude (always required)
OPENAI_API_KEY=...        # Codex (optional)
GLM_API_KEY=...           # GLM (optional)
```

These MUST be in `.env` (never committed). See `security-practices` skill.

---

## Guardrails

- Maestro (tier-1) MUST always run on Claude. Never delegate orchestration.
- Never send secrets, API keys, or credentials to any provider as part of the handoff.
- If a provider is configured but its API key is missing, fall back to Claude silently and log it.
- Never retry more than once. If two attempts fail, fall back.
- The user must be informed when a non-Claude provider is being used for a task.
