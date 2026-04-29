---
skill: codex-github-ops
trigger: /codex-gh, or any GitHub operation — keywords "issue triage", "PR comment", "release notes", "open PR", "merge PR", "label issues", "close issue", "github action", "branch cleanup", "code search on github", "gh cli"
persona: maestro
version: 1.1.0
lastUpdated: 2026-04-17
shortDescription: >
  Codex handles GitHub operations via GitHub MCP — issue triage, PR creation,
  PR comments, release notes, branch management, code search. Opus only orchestrates.
usedBy: [maestro]
evals:
  - prompt: "triage the open issues"
    should_trigger: true
  - prompt: "create a PR for this branch"
    should_trigger: true
  - prompt: "comment on PR #42 with the test results"
    should_trigger: true
  - prompt: "draft release notes for v0.3"
    should_trigger: true
  - prompt: "close all stale PRs older than 90 days"
    should_trigger: true
  - prompt: "search the repo on github for all TODOs with my name"
    should_trigger: true
  - prompt: "review the code"
    should_trigger: false
  - prompt: "run the tests"
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
```bash
codex exec --color never --profile coder \
  -o /tmp/codex-triage-$$.md \
  "$(cat <<'PROMPT'
You have access to the GitHub MCP. Triage open issues for {repo}.
1. List all open issues
2. Categorize: bug, feature, docs, question
3. Estimate size: XS/S/M/L
4. Suggest priority: P0 (critical), P1 (high), P2 (medium), P3 (low)
5. Write triage report to .agents/tmp/issue-triage.md
PROMPT
)"
```

### PR Creation
```bash
codex exec --color never --profile coder \
  -o /tmp/codex-pr-$$.md \
  "$(cat <<'PROMPT'
Create a PR for the current branch.
1. Run git diff main...HEAD to understand changes
2. Generate PR title and description
3. Create PR via GitHub MCP
4. Report the PR URL
PROMPT
)"
```

### Code Search
```bash
codex exec --color never --profile coder \
  -o /tmp/codex-search-$$.md \
  "$(cat <<'PROMPT'
Search the GitHub repo for: {query}
1. Use GitHub MCP code search
2. Report matching files and line numbers
3. Write results to .agents/tmp/search-results.md
PROMPT
)"
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
