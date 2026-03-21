---
name: mcp-obsidian
description: How the Canuto Framework uses the Obsidian MCP server to interact with the vault memory system. Covers reading, writing, searching, and managing notes via MCP tools.
---

# MCP Obsidian Integration Skill

How the Canuto Framework interacts with the Obsidian vault via the MCP server (`obsidian-mcp-server`).

## When to Use

- When any persona needs to read or write to the vault (`~/.canuto/vault/`)
- When searching for decisions, instincts, or audit events across sessions
- When managing frontmatter properties on vault notes
- When creating new memory notes (sessions, decisions, instincts, etc.)

## Prerequisites

- Obsidian running with the Local REST API plugin enabled
- MCP server configured (see `.agents/mcp/setup.md`)

## Available MCP Tools

### Reading

```
obsidian_read_note(path="projects/{project-slug}/decisions/D-001-lucide-animated.md")
obsidian_read_note(path="projects/{project-slug}/instincts/I-001.md", format="json")
```

### Creating / Updating

```
# Create a new decision note
obsidian_update_note(
  path="projects/{project-slug}/decisions/D-003-new-auth.md",
  content="---\ntype: decision\nid: D-003\n...",
  createIfNotExists=true
)

# Append to an existing session note
obsidian_update_note(
  path="sessions/2026-03-21.md",
  content="\n## Instincts Extracted\n- [[I-005]]",
  mode="append"
)
```

### Searching

```
# Search for all notes mentioning "JWT"
obsidian_global_search(query="JWT")

# Search with regex
obsidian_global_search(query="/confidence:\\s*high/")
```

### Frontmatter Management

```
# Set confidence on an instinct
obsidian_manage_frontmatter(
  path="instincts/I-001.md",
  action="set",
  key="confidence",
  value="medium"
)

# Increment applied count
obsidian_manage_frontmatter(
  path="instincts/I-001.md",
  action="set",
  key="applied",
  value=3
)
```

### Tag Management

```
# Add a tag to a decision
obsidian_manage_tags(
  path="decisions/D-001.md",
  action="add",
  tag="reviewed"
)
```

### Listing Notes

```
# List all decisions
obsidian_list_notes(path="decisions/")

# List all instincts
obsidian_list_notes(path="instincts/")
```

## Canuto-Specific Patterns

### Session Start (Maestro reads)

1. `obsidian_list_notes(path="sessions/")` → find latest session
2. `obsidian_read_note(path="sessions/YYYY-MM-DD.md")` → read last session
3. `obsidian_list_notes(path="pending/")` → list pending tasks
4. `obsidian_global_search(query="confidence: high")` → find high-confidence instincts

### Session End (Maestro writes)

1. Create session note: `obsidian_update_note(path="sessions/YYYY-MM-DD.md", ...)`
2. Create instinct notes: `obsidian_update_note(path="instincts/I-XXX.md", ...)`
3. Update pending tasks: move completed, create new
4. Create metric note: `obsidian_update_note(path="metrics/YYYY-MM-DD-metrics.md", ...)`
5. Create audit events: `obsidian_update_note(path="audit/YYYY-MM-DD-SESSION_END.md", ...)`

### Decision Recording

1. `obsidian_list_notes(path="decisions/")` → determine next D-ID
2. `obsidian_update_note(path="decisions/D-XXX-slug.md", ...)` → create note
3. Update session note with wikilink: `[[decisions/D-XXX-slug]]`

### Instinct Reinforcement

1. `obsidian_read_note(path="instincts/I-XXX.md")` → read current state
2. `obsidian_manage_frontmatter(action="set", key="applied", value=N+1)`
3. `obsidian_manage_frontmatter(action="set", key="last-seen", value="YYYY-MM-DD")`
4. If applied >= 4: `obsidian_manage_frontmatter(action="set", key="confidence", value="high")`

## Examples

### ✅ Good — Using MCP to search and cross-reference

```
# Find all decisions about auth
obsidian_global_search(query="auth")

# Read the relevant decision
obsidian_read_note(path="decisions/D-003-jwt-auth.md")

# Link it to the current session
obsidian_update_note(
  path="sessions/2026-03-21.md",
  content="\n- Referenced [[decisions/D-003-jwt-auth]] for API design",
  mode="append"
)
```

### ❌ Bad — Reading files directly instead of using MCP

```
# Don't do this — bypasses MCP and loses search/cache benefits
Read(~/.canuto/vault/projects/{project-slug}/decisions/D-003-jwt-auth.md)
```

## References

- [obsidian-mcp-server](https://github.com/cyanheads/obsidian-mcp-server)
- [Setup guide](.agents/mcp/setup.md)
