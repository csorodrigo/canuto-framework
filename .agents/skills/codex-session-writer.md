---
skill: codex-session-writer
trigger: On session end (via session-save hook), or /save-session
persona: maestro
version: 1.0.0
lastUpdated: 2026-03-30
shortDescription: >
  Delegates session note writing to Codex via vault MCP. Opus provides a brief
  summary, Codex formats and writes the full session note. Saves formatting tokens.
usedBy: [maestro]
evals:
  - prompt: "save the session notes"
    should_trigger: true
  - prompt: "write session summary to vault"
    should_trigger: true
  - prompt: "plan the next feature"
    should_trigger: false
---

## Purpose

Session notes require structured markdown with frontmatter, goals, decisions,
instincts, and metrics. Formatting this is expensive in Opus tokens.
Delegate the formatting to Codex — Opus provides raw bullet points,
Codex writes the polished note to vault.

---

## Procedure

### 1. Opus Prepares Raw Summary

Maestro collects session data (minimal formatting):
```
goals: auth middleware implemented, tests passing
decisions: JWT over sessions, Supabase for storage
instincts: always check RLS before deploy
pending: dashboard page, settings form
metrics: 3 files changed, 2 codex delegations, 1 escalation
```

### 2. Spawn Codex Session Writer

```
codex exec --profile coder({
  prompt: `
You have access to the obsidian-vault MCP. Write a session note.

## Raw Data
{raw_summary_from_opus}

## Session Metadata
- Date: {date}
- Project: {project_slug}
- Branch: {branch}

## Instructions
1. Format as a proper session note with YAML frontmatter
2. Write to the vault using obsidian-vault MCP:
   Path: projects/{project_slug}/sessions/{date}-session.md
3. Include sections: Goals, Decisions, Instincts, Pending, Metrics
4. Extract any high-confidence instincts to separate notes in instincts/
5. Update pending/ with any deferred tasks

## Frontmatter Template
---
title: Session {date}
date: {date}
project: {project_slug}
branch: {branch}
tags:
  - session
goals_met: N/M
---
`
})
```

### 3. Verify

Codex writes directly to vault via MCP. Opus confirms:
```
[Session] Note saved: projects/{slug}/sessions/{date}-session.md
```

---

## Fallback

- Codex vault MCP unavailable → Codex writes to `.agents/vault/sessions/` on disk
- Codex MCP unavailable entirely → Opus writes the session note directly
- vault-bridge.sh as final fallback for vault writes

---

## Integration

- **session-save.sh hook**: calls this skill at session end
- **vault-maintenance.md**: archives old session notes
- **continuous-learning**: instincts extracted by Codex go to instincts/
