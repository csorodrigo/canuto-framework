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

## Semantic Search (Optional)

The default `obsidian_global_search` performs text-based search — it finds exact keyword matches. For cases where you need to find conceptually related notes even when they don't share exact words, add the **Smart Connections** MCP server.

### When to Use Semantic vs Text Search

| Use | Search Type | Tool |
|-----|-------------|------|
| Find a specific note by name/content | Text search | `obsidian_global_search(query="JWT auth")` |
| Find notes related to a concept | Semantic search | `smart_search(query="authentication patterns")` |
| Find notes with specific frontmatter | Text search | `obsidian_global_search(query="/confidence:\\s*high/")` |
| Find notes that discuss similar ideas | Semantic search | `smart_search(query="how to handle API errors")` |
| Find all notes mentioning a file | Text search | `obsidian_global_search(query="token-service.ts")` |

### Setup

Install the Smart Connections MCP server:

```bash
pip install smart-connections-mcp
```

Add to your MCP config (`.claude/settings.json` or project-level):

```json
{
  "mcpServers": {
    "smart-connections": {
      "command": "python",
      "args": ["-m", "smart_connections_mcp.server"],
      "env": {
        "OBSIDIAN_VAULT_PATH": "~/.canuto/vault"
      }
    }
  }
}
```

### Usage

```
# Find notes conceptually related to a topic
smart_search(query="optimizing build performance")

# Results come ranked by semantic similarity
# Titles alone often indicate relevance (especially with prose-as-title naming)
```

> [!note] Smart Connections is OPTIONAL. The framework works fully with text search alone. Semantic search is an enhancement for larger vaults where keyword search misses conceptually related notes.

---

## Additional MCP Connectors (Optional)

The Obsidian MCP is the primary connector for the Canuto vault. For broader context, you can optionally add connectors for other tools your team uses. These are supplementary — the vault remains the source of truth.

### Google Drive (Meeting Transcripts)

Useful when meeting transcripts are auto-saved to Drive (via Fathom, Otter, Fireflies, etc.). Combine with the `knowledge-ingest` skill to process transcripts into structured vault notes.

```json
{
  "mcpServers": {
    "google-drive": {
      "command": "npx",
      "args": ["-y", "@anthropic/mcp-google-drive"],
      "env": {
        "GOOGLE_DRIVE_FOLDER_ID": "<your-transcripts-folder-id>"
      }
    }
  }
}
```

### Slack (Team Context)

Useful for pulling team discussions, decisions made in channels, and status updates.

```json
{
  "mcpServers": {
    "slack": {
      "command": "npx",
      "args": ["-y", "@anthropic/mcp-slack"],
      "env": {
        "SLACK_BOT_TOKEN": "<your-bot-token>"
      }
    }
  }
}
```

### Google Calendar (Schedule Context)

Useful for understanding upcoming meetings, deadlines, and time blocks.

```json
{
  "mcpServers": {
    "google-calendar": {
      "command": "npx",
      "args": ["-y", "@anthropic/mcp-google-calendar"]
    }
  }
}
```

> [!warning] Additional MCP connectors require separate authentication setup. Refer to each connector's documentation for auth configuration. Never store API keys or tokens in vault notes — use environment variables.

---

## References

- [obsidian-mcp-server](https://github.com/cyanheads/obsidian-mcp-server)
- [smart-connections-mcp](https://github.com/brianpetro/smart-connections)
- [Setup guide](.agents/mcp/setup.md)
