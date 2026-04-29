---
skill: codex-multi-vault
trigger: When working across projects, or /cross-project-insights
persona: maestro
version: 1.0.0
lastUpdated: 2026-03-30
shortDescription: >
  Codex reads notes from multiple projects in the vault via obsidian-vault MCP.
  Finds cross-project patterns, reusable decisions, shared instincts.
usedBy: [maestro, contextualizer]
evals:
  - prompt: "what patterns do we use across projects?"
    should_trigger: true
  - prompt: "find similar decisions in other projects"
    should_trigger: true
  - prompt: "read the auth module"
    should_trigger: false
---

## Purpose

The global vault at `~/.canuto/vault/` contains notes from ALL projects.
Cross-project insights (shared patterns, reusable decisions, common instincts)
are valuable but expensive for Opus to discover (reading many notes).

Delegate vault reading to Codex via obsidian-vault MCP.

---

## Procedure

### 1. Define Query

What cross-project insight is needed:
- "How did we handle auth in other projects?"
- "What instincts apply to API design?"
- "Are there reusable patterns for this stack?"

### 2. Spawn Codex Vault Reader

```
codex exec --profile coder({
  prompt: `
You have access to the obsidian-vault MCP. Search across all projects.

## Query
{cross_project_query}

## Instructions
1. Use obsidian-vault search to find relevant notes across projects/
2. Read matching notes (decisions/, instincts/, sessions/)
3. Look in global-instincts/ for promoted patterns
4. Synthesize findings into a cross-project report

## Output
Write to .agents/tmp/cross-project-insights.md:
- Relevant decisions from other projects (with project name)
- Applicable instincts (confidence level)
- Shared patterns and how they were implemented
- Recommendations for current project

## Rules
- Cite which project each insight comes from
- Note confidence levels on instincts
- Flag any contradictions between projects
`
})
```

### 3. Opus Applies Insights

Read the insights report and use it to inform current task planning.

---

## Use Cases

### Before Architecture Decisions
"How did we handle caching in project-X? Any instincts about Redis vs in-memory?"

### Before Tech Stack Choices
"Which projects use Supabase? Any recorded issues or workarounds?"

### Instinct Validation
"Is this instinct (always use RLS) consistent across projects?"

---

## Integration

- **continuous-learning**: instincts from one project inform others
- **setup_global_vault()**: creates the multi-project vault structure
- **global-instincts.base**: Obsidian base that shows cross-project instincts
- **cost-routing.md**: vault reading → Codex (90% savings)
