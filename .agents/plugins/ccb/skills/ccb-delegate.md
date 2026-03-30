---
skill: ccb-delegate
trigger: /ccb-delegate
persona: maestro
version: 1.0.0
lastUpdated: 2026-03-29
plugin: ccb
shortDescription: >
  Delegate tier-2 persona tasks to visible CCB terminal panes. Supports
  fire-and-forget via `ask`, async retrieval via `pend`, and MCP delegation
  via ccb-delegation server. Gracefully degrades when CCB is not installed.
usedBy: [maestro]
evals:
  - prompt: "delegate the coder task to codex in a visible pane"
    should_trigger: true
  - prompt: "run the implementation on gemini via ccb"
    should_trigger: true
  - prompt: "send this to codex using terminal panes"
    should_trigger: true
  - prompt: "ask codex to review this plan"
    should_trigger: false
  - prompt: "run tests"
    should_trigger: false
  - prompt: "delegate to codex via api"
    should_trigger: false
---

## When to Use

**Triggers:**
- User explicitly requests CCB/pane-based delegation
- Maestro delegates a tier-2 persona task AND CCB plugin is configured in CLAUDE.md
- User wants to see provider work in real-time (visual terminal panes)

**Not for:**
- Tier-1 personas (Maestro, Architect, Contextualizer) — always Claude
- When CCB is not installed (degrade gracefully to multi-provider API or codex-collab MCP)
- Simple co-review tasks (use co-review skill + codex-collab MCP instead)
- When no terminal multiplexer (WezTerm/tmux) is available

---

## Prerequisites

- CCB installed: `which ccb && which ask && which pend`
- Terminal multiplexer: WezTerm or tmux running
- Provider CLIs authenticated (claude, codex, gemini)

---

## Procedure

### 1. Availability Check

Run `which ccb` to verify installation.

If not found:
```
[CCB] Not installed. Falling back to standard delegation.
```
Continue with multi-provider.md API delegation or codex-collab MCP. Never block.

### 2. Prepare Handoff Package

Same protocol as multi-provider.md:
- Goal statement
- Relevant context files (`.context.md`, feature map sections)
- The Architect's plan (for Coder) or implementation summary (for Tester/Reviewer)
- The persona's playbook content
- Strip Canuto-specific metadata headers if the provider doesn't understand them

### 3. Choose Delegation Method

**Method A: CLI `ask` command (recommended for fire-and-forget)**

```bash
ask <provider> "<prompt with handoff package>"
```

Where `<provider>` is one of: `codex`, `gemini`, `claude`.

The task runs in a visible pane. Use `pend <task-id>` to retrieve results asynchronously.

**Method B: MCP delegation server (recommended for programmatic integration)**

If CCB's MCP delegation server is configured (see `docs/mcp-delegation.md`):
- `ccb_ask_codex(prompt)` — route to Codex pane
- `ccb_ask_gemini(prompt)` — route to Gemini pane
- `ccb_ask_claude(prompt)` — route to Claude pane

These MCP tools route through CCB's `askd` daemon with visible pane output.

### 4. Collect Results

- For `ask` CLI: use `pend <task-id>` to retrieve when complete
- For MCP: response returned directly from the MCP tool call
- Validate output follows expected format (same validation as multi-provider.md step 4)
- If output malformed: retry once, then fall back

### 5. Fallback Strategy

```
CCB installed?
  → YES: delegate via pane
  → NO:  codex-collab MCP available?
           → YES: delegate via MCP
           → NO:  API keys configured?
                    → YES: delegate via API (multi-provider.md)
                    → NO:  Claude handles it directly
```

Maestro logs every fallback in the session summary.

---

## Output Format

```
[CCB] Delegating to {provider} via terminal pane.
Task: {goal summary}
Method: ask CLI | MCP delegation
Pane: {pane identifier}

--- (after result) ---

[CCB] Result from {provider}:
{validated output}
```

---

## Examples

### Good — CCB delegation with fallback logging

```
[CCB] Delegating Step 3 (implement auth middleware) to Codex pane.
Method: ask codex "Implement auth middleware per plan..."
[pend task-20260329-143022-001-12345] Codex response received (47s).
Validating output format... accepted.
```

### Good — graceful degradation

```
[CCB] ccb not found in PATH. Falling back to codex-collab MCP.
[codex-collab] Starting new thread for implementation delegation...
```

### Bad — blocking on CCB when not installed

```
[CCB] ccb not found. Waiting for installation...
```

This is bad because: must degrade gracefully, never block.

---

## Guardrails

- Tier-1 personas (Maestro, Architect, Contextualizer) MUST NOT be delegated via CCB. Only tier-2.
- Never send secrets, API keys, or credentials in the handoff prompt.
- Maximum 3 concurrent CCB panes (terminal real estate constraint).
- If CCB `ask` hangs >120s, timeout and fall back to next backend.
- Always log the delegation method used in the audit trail.
- The `-a` (auto-approval) flag on CCB should only be used when the user has explicitly opted in via CLAUDE.md or runtime flag.
- For large handoff packages that exceed shell argument limits, write to a temp file and reference it instead of inlining.
