---
skill: codex-github-ops
trigger: /codex-gh, or when GitHub operations needed and Codex has GitHub MCP
persona: maestro
version: 1.0.0
lastUpdated: 2026-03-30
shortDescription: >
  Codex handles GitHub operations via GitHub MCP — issue triage, PR creation,
  branch management, code search. Opus only orchestrates.
usedBy: [maestro]
evals:
  - prompt: "triage the open issues"
    should_trigger: true
  - prompt: "create a PR for this branch"
    should_trigger: true
  - prompt: "review the code"
    should_trigger: false
---

## Purpose

GitHub operations (issue triage, PR management, code search) consume Opus tokens
for mechanical tasks. Delegate to Codex via GitHub MCP registered natively.

---

## Prerequisites

Codex needs GitHub MCP registered:
```bash
codex mcp add github -- npx @anthropic-ai/mcp-server-github
```

Or via `install.sh` → `setup_codex_mcps()` (auto-detected).

Requires `GITHUB_PERSONAL_ACCESS_TOKEN` env var.

---

## Capabilities

### Issue Triage
```
mcp__codex-coder__spawn_agent({
  prompt: `
You have access to the GitHub MCP. Triage open issues for {repo}.
1. List all open issues
2. Categorize: bug, feature, docs, question
3. Estimate size: XS/S/M/L
4. Suggest priority: P0 (critical), P1 (high), P2 (medium), P3 (low)
5. Write triage report to .agents/tmp/issue-triage.md
`
})
```

### PR Creation
```
mcp__codex-coder__spawn_agent({
  prompt: `
Create a PR for the current branch.
1. Run git diff main...HEAD to understand changes
2. Generate PR title and description
3. Create PR via GitHub MCP
4. Report the PR URL
`
})
```

### Code Search
```
mcp__codex-coder__spawn_agent({
  prompt: `
Search the GitHub repo for: {query}
1. Use GitHub MCP code search
2. Report matching files and line numbers
3. Write results to .agents/tmp/search-results.md
`
})
```

---

## install.sh Integration

`setup_codex_mcps()` registers GitHub MCP if `GITHUB_PERSONAL_ACCESS_TOKEN` is set:
```bash
if [ -n "$GITHUB_PERSONAL_ACCESS_TOKEN" ]; then
  codex mcp add github -- npx @anthropic-ai/mcp-server-github
fi
```

---

## Graceful Degradation

- GitHub MCP not available → Codex uses `gh` CLI directly (shell access)
- Codex unavailable → Opus uses `gh` CLI or GitHub MCP from Claude's side
