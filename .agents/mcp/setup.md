# MCP Server Setup — Obsidian Integration

> Required for the Canuto Framework's Obsidian-native memory system.

## Prerequisites

- **Node.js** v18+
- **Obsidian** desktop app installed and running
- **obsidian-local-rest-api** community plugin installed in Obsidian

## Step 1: Install Obsidian Local REST API Plugin

1. Open Obsidian → Settings → Community Plugins → Browse
2. Search for "Local REST API"
3. Install and enable it
4. Go to the plugin settings → copy the **API Key**

## Step 2: Open the Canuto Vault in Obsidian

1. Open Obsidian → Open folder as vault
2. Select the `.agents/vault/` directory from your project
3. Trust the vault when prompted

## Step 3: Configure the MCP Server

### For Claude Desktop

Add to `~/.claude/settings.json` or copy from `.agents/mcp/server.json`:

```json
{
  "mcpServers": {
    "obsidian-mcp-server": {
      "command": "npx",
      "args": ["obsidian-mcp-server"],
      "env": {
        "OBSIDIAN_API_KEY": "YOUR_API_KEY_HERE",
        "OBSIDIAN_BASE_URL": "https://127.0.0.1:27124",
        "OBSIDIAN_VERIFY_SSL": "false"
      }
    }
  }
}
```

Replace `YOUR_API_KEY_HERE` with the key from Step 1.

### For VS Code (Cline/Continue)

Add to your MCP settings following the same format above.

## Step 4: Verify Connection

Test that the MCP server can reach Obsidian:

```bash
curl -k -H "Authorization: Bearer YOUR_API_KEY" https://127.0.0.1:27124/
```

You should get a JSON response with vault info.

## Available MCP Tools

| Tool | Purpose |
|------|---------|
| `obsidian_read_note` | Read note content and metadata |
| `obsidian_update_note` | Create, append, prepend, or overwrite notes |
| `obsidian_delete_note` | Delete a note from the vault |
| `obsidian_list_notes` | List notes and directories with filtering |
| `obsidian_global_search` | Full-text/regex search across the vault |
| `obsidian_search_replace` | Find-and-replace within a note |
| `obsidian_manage_frontmatter` | Get, set, or delete frontmatter keys |
| `obsidian_manage_tags` | Add, remove, or list tags |

## Troubleshooting

### MCP server can't connect
- Ensure Obsidian is running and the Local REST API plugin is enabled
- Check the API key is correct
- Default port is 27123 — verify it's not blocked

### HTTPS / SSL errors
- The Local REST API plugin uses HTTPS with a self-signed certificate on port **27124**
- Set `OBSIDIAN_VERIFY_SSL=false` in the MCP server config (already set in the template)
- Use `-k` flag with curl for manual testing

### Cache staleness
- The MCP server caches vault contents and refreshes every 10 minutes
- After bulk edits, restart the MCP server to force a cache rebuild
