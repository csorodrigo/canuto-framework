---
skill: gemini-routing
trigger: Automatic — consulted before any Gemini MCP call or when editing cost-routing slots that involve Gemini
persona: maestro
version: 1.0.0
lastUpdated: 2026-04-17
shortDescription: >
  Cheat sheet for the jamubc/gemini-mcp-tool MCP (registered as `gemini` user-scope).
  Captures gotchas found during the 2026-04-17 POC so future calls don't rediscover them.
usedBy: [maestro, architect, contextualizer]
---

## Purpose

The `gemini` MCP (jamubc/gemini-mcp-tool) shells out to the local `gemini-cli` with OAuth auth.
It adds four capabilities to the stack that Codex does not cover well:

1. **Contextualizer / long-context digest** — `@folder` reads over repo at a fraction of Opus cost
2. **Multimodal** — screenshot OCR, design review via images
3. **Brainstorm tool** — structured SCAMPER/lateral/design-thinking ideation
4. **Bulk classifier** — flash-lite has a separate quota bucket, cheap for triage at volume

It does NOT replace Codex as executor: `sandbox: true` was tested and gemini-cli does
not expose `write_file` / `run_shell_command` through this MCP path (T9 POC fail).

## MCP setup

- **Name:** `gemini` (registered user-scope in `~/.claude.json`)
- **Command:** `npx -y gemini-mcp-tool`
- **Package version:** `gemini-mcp-tool@1.1.4` (pin via `npm view gemini-mcp-tool version` before upgrading)
- **Auth:** OAuth via local `gemini auth login`; no API key required
- **Tools exposed:** `ask-gemini`, `brainstorm`, `Help`, `ping`, `fetch-chunk`, `timeout-test`
- **Verify:** `claude mcp list | grep "gemini "` should show `✓ Connected`

## Enabled models

| Model | Status | Use for |
|---|---|---|
| `gemini-3.1-pro-preview` | ✅ **Primary** | Contextualizer, Multimodal, Brainstorm, emergency review fallback |
| `gemini-3.1-flash-lite-preview` | ✅ **Bulk tier** | Bulk classification / triage / intent detection |
| `gemini-3-flash-preview` | 🟡 Reserve | Available but not default |
| `gemini-2.5-flash-lite` | 🟡 Reserve | Fallback if 3.1-flash-lite-preview leaves preview status |
| `gemini-2.5-flash` | 🟡 Reserve | Fallback |
| `gemini-2.5-pro` | ❌ **BANNED** | ~50% intermittent 429 `MODEL_CAPACITY_EXHAUSTED` observed in POC. Each fail costs 10 internal retries. Revisit in 30 days. |

## Gotchas (from POC 2026-04-17)

### 1. Workspace sandbox blocks `/tmp` and `~/*` in `@file`

gemini-cli restricts `@` to paths inside the current workspace. T4 POC:

```
@/tmp/test-shot.png Descreva...
→ ERRO: "imagem não pôde ser carregada pois está localizada fora dos
         diretórios permitidos do workspace"
```

**Workaround:** copy the file into the repo first (`.context/` is a good staging area,
it is gitignored). Remember to delete after use.

### 2. stdio is single-connection — parallel calls return `Not connected`

6 calls fired in parallel returned 5 × `Not connected` + 1 success. The jamubc MCP
serves one call at a time. Always serialize:

```ts
// ❌ BAD
Promise.all([ask(a), ask(b), ask(c)])  // 2/3 fail

// ✅ GOOD
for (const prompt of [a, b, c]) {
  await ask(prompt)
}
```

### 3. `gemini-2.5-pro` is server-side flaky (not user quota)

Observed during T6-B: a single short call to `gemini-2.5-pro` returned
`429 RESOURCE_EXHAUSTED / MODEL_CAPACITY_EXHAUSTED` — a Google capacity issue,
not user quota (user Pro bar was at 2%). The gemini-cli then retries 10× internally,
wasting quota. **Do not route production traffic to 2.5-pro.** Prefer `gemini-3.1-pro-preview`.

### 4. Silent fallback to 2.5-flash on specific quota match

`geminiExecutor.ts:101-118` has a hard-coded string match:
`"Quota exceeded for quota metric 'Gemini 2.5 Pro Requests'"` — if that exact
error fires AND the requested model is not already 2.5-flash, jamubc re-runs the
call in 2.5-flash **silently**. In practice this only triggers for 2.5-pro user-quota
exhaustion (different from the server-capacity 429 above), so it is dormant for 3.x
since 2.5-pro is banned. If we ever re-enable 2.5-pro, this is the canonical reason
for unexplained output degradations.

### 5. `screencapture` captures the full screen — PII / 2FA risk

During T4 the test screenshot inadvertently captured an iFood 2FA code. Any
automated multimodal flow that uses `screencapture` must:

- Crop / mask sensitive regions before invoking Gemini
- Delete the captured file immediately after the call
- Prefer headless browser screenshots scoped to one element

### 6. OAuth quota is 1000 req/day total with separate bars per tier

The `gemini` TUI shows three bars: Pro / Flash / Flash-Lite. POC confirmed they
move roughly independently (Pro moved +1% with 2 pro calls while Flash/Flash-Lite
stayed flat). Flash-Lite is the cheapest per-call on the bar, making it the right
choice for bulk-classify. If bulk usage approaches 1k/day, migrate to Vertex ADC
(`GOOGLE_GENAI_USE_VERTEXAI=true` + `gcloud auth application-default login`).

### 7. Models do not self-declare version reliably

Asking "qual modelo e versão você é?" returns generic "sou Gemini" from 5 of 6
models. Do not rely on echo to detect silent fallback — use `model_reasoning_effort`
or external evidence (Vertex logs, quota bar movement).

### 8. Sandbox mode flag passes but tools are restricted

`ask-gemini({ sandbox: true, ... })` forwards the `-s` flag to gemini-cli, but
the write/exec tools are not exposed through the MCP path. The returned output
is a hypothetical ("em um ambiente padrão de Python 3...") rather than an actual run.
For real execution use `mcp__codex-coder__spawn_agent`.

## Example calls (one per slot)

### Contextualizer
```
mcp__gemini__ask-gemini({
  prompt: "@.agents/skills/ Liste em bullets cada skill e sua finalidade.",
  model: "gemini-3.1-pro-preview"
})
```

### Multimodal
```
cp ~/Desktop/mockup.png .context/mockup.png
mcp__gemini__ask-gemini({
  prompt: "@.context/mockup.png Identifique issues de hierarquia visual e a11y.",
  model: "gemini-3.1-pro-preview"
})
rm .context/mockup.png
```

### Brainstorm
```
mcp__gemini__brainstorm({
  prompt: "5 ideias pra reduzir tempo de cold-start do nosso worker",
  methodology: "scamper",
  domain: "engineering",
  ideaCount: 5
})
```

### Bulk classifier
```
mcp__gemini__ask-gemini({
  prompt: "Classifique em 1 palavra (XS/S/M/L): 'adicionar coluna created_at em users'",
  model: "gemini-3.1-flash-lite-preview"
})
```

## When NOT to use Gemini

- Writing code (no sandbox). Route to `mcp__codex-coder__spawn_agent`.
- Formal code review gate — Codex reviewer profile stays primary. Gemini is valid as
  second-opinion for cross-model audit, especially on refactors or security diffs.
- Decisions that require `AskUserQuestion` or tier-1 orchestration — Claude Opus only.
- Anything that depends on the Codex spawn_agents_parallel primitive — Gemini MCP
  serializes everything, so a parallel batch will be strictly slower.

## See also

- `.agents/skills/cost-routing.md` — full routing matrix including Gemini slots
- `.agents/skills/multi-provider.md` — tier table and fallback chain
- `.agents/skills/bulk-classify.md` — dedicated flash-lite slot
- `.context/gemini-mcp-poc.md` — full POC test log and findings
