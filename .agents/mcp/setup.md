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
2. Select `~/.canuto/vault/` (the global vault created by `install.sh`)
3. Trust the vault when prompted

> **One vault for all projects.** Each project's memory is scoped under `projects/{project-name}/`. You only need to open this vault once — it persists across all projects.

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

## Optional Gemini MCP

Gemini MCP support is optional and adds a read-only consultant for long-context, multimodal, and bulk classification workflows. It does not require active OAuth for framework smoke checks.

### Install gemini-cli

```bash
npm install -g @google/gemini-cli
```

### Authenticate

```bash
gemini auth login
```

This starts the OAuth flow in your browser.

### Register the Gemini MCP

```bash
claude mcp add gemini -- npx -y gemini-mcp-tool
```

### Verify Gemini MCP

```bash
claude mcp list | grep gemini
```

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

---

## Observability (OTel + SigNoz)

The framework ships with OpenTelemetry wiring so Claude Code 2.1.116 and Codex CLI 0.122 stream sessions to a **local SigNoz** instance on `http://localhost:8080`. No data leaves the machine.

### Stack

```
Claude Code  ──OTLP/gRPC:4317──┐
Codex CLI    ──OTLP/gRPC:4317──┼──▶ SigNoz (Docker) ──▶ UI :8080
framework-session-audit-lib ───┘        └─ ClickHouse
```

### Bring up / down

```bash
# Up
cd ~/signoz/deploy/docker && docker compose up -d

# Down (preserve data)
cd ~/signoz/deploy/docker && docker compose down

# Down + wipe volumes (fresh start)
cd ~/signoz/deploy/docker && docker compose down -v
```

### Env vars (already set by install.sh in `~/.claude/settings.json`)

```json
"CLAUDE_CODE_ENABLE_TELEMETRY": "1",
"CLAUDE_CODE_ENHANCED_TELEMETRY_BETA": "1",
"OTEL_METRICS_EXPORTER": "otlp",
"OTEL_LOGS_EXPORTER": "otlp",
"OTEL_TRACES_EXPORTER": "otlp",
"OTEL_EXPORTER_OTLP_PROTOCOL": "grpc",
"OTEL_EXPORTER_OTLP_ENDPOINT": "http://localhost:4317",
"OTEL_RESOURCE_ATTRIBUTES": "service.name=claude-code,deployment.environment=local-dev,host.name=rod-mac,service.namespace=canuto"
```

Codex: `~/.codex/config.toml` contains `[otel] environment="local-dev" exporter = { otlp-grpc = { endpoint = "http://localhost:4317" } }`.

### Codex 0.122 emission matrix

Observed locally on 2026-04-21 (smoke in install.sh `--doctor`):

| Mode | Emits OTel spans? | Observed in SigNoz? | Notes |
|------|-------------------|---------------------|-------|
| `codex` interactive | yes | yes | needs TTY to smoke manually |
| `codex exec "..."` | **yes** | **yes** | confirmed — `BatchSpanProcessor` ran, transient `BrokenPipe` during collector warmup |
| `codex mcp-server` (via `mcp__codex-coder__spawn_agent`) | **not yet verified** | likely partial | tracked upstream at openai/codex#12913; mitigation: Claude's `claude_code.mcp_server_connection` + `claude_code.tool` spans cover scope/duration/success from the orchestrator side |

Re-run `.agents/tools/observability-smoke.sh` after any Codex upgrade to revalidate.

### Queries in SigNoz UI

- Traces tab → filter `service.name=claude-code` → see tool calls with durations.
- Metrics → search `claude_code.token.usage` (cumulative by model), `claude_code.cost.usage` (USD), `claude_code.code_edit_tool.decision`.
- Logs → search `user_prompt`, `tool_result`, `api_error`, `mcp_server_connection`.
- Custom Canuto metrics under `canuto.session.*` (rework_loop_rate, memory_miss_rate, etc.) are emitted by `.agents/tools/framework-session-audit-lib.js` when the audit runs (Stop hook).

### Privacy

Prompt bodies, tool args, and API bodies are **redacted by default**. To opt in (only on your local machine, never in shared configs):
- `OTEL_LOG_USER_PROMPTS=1`
- `OTEL_LOG_TOOL_DETAILS=1`
- `OTEL_LOG_TOOL_CONTENT=1`
- `OTEL_LOG_RAW_API_BODIES=1` (or `file:<dir>` to write to disk instead of span attrs)

### HTTP interception complementary — Proxyman

OTel shows *where time is spent* and *what tools were called*; Proxyman shows **the actual HTTP payload** (request/response bodies) — useful when OTel redacts content or when an MCP/external API returns a cryptic error.

Ad-hoc activation (not persistent, not global):

```bash
HTTPS_PROXY=http://localhost:9090 \
HTTP_PROXY=http://localhost:9090 \
NODE_EXTRA_CA_CERTS=$HOME/.proxyman-ca.pem \
claude
```

Prerequisites: Proxyman.app running, Proxyman CA installed in Keychain (Proxyman → Certificate → Install Certificate on this Mac). Export the CA to `~/.proxyman-ca.pem` once.

Both run simultaneously without conflict.

### Smoke check

```bash
.agents/tools/observability-smoke.sh            # human output
.agents/tools/observability-smoke.sh --json     # for install.sh --doctor
```

---

## Secrets (Bitwarden CLI)

The framework wraps `bw` to sync `.env` files between a project and your Bitwarden vault as **secure notes** (attachments are Premium-only on the Free plan; we use base64-encoded notes which cover typical `.env` sizes).

### One-time setup

```bash
brew install bitwarden-cli
bw config server https://vault.bitwarden.com   # skip if default
bw login                                       # interactive
eval "$(bw unlock | grep 'export BW_SESSION')" # capture session
# put the export line in ~/.zshrc (manual — keep BW_SESSION private, never commit)
```

### Sync `.env`

```bash
cd <project>
.agents/tools/env-bitwarden-sync.sh push <project-slug>   # uploads .env to note "canuto-env-<slug>"
.agents/tools/env-bitwarden-sync.sh pull <project-slug>   # downloads note → .env (backs up existing to .env.bak.$ts)
```

### Caveats

- **Never** commit `BW_SESSION` — rotate if exposed (`bw lock && bw unlock`).
- Secure note size limit ~10 KB of plaintext (more than enough for typical `.env`).
- Attachments (binary) require Premium; out of scope.

---

## Vault Git

The global vault at `~/.canuto/vault` is versioned locally with `git` (no remote by default). The Obsidian-Git community plugin auto-commits every 10 minutes.

### Install

```bash
cd ~/.canuto/vault
git init -b main
cat > .gitignore <<'EOF'
.obsidian/workspace*
.obsidian/cache/
.trash/
*.tmp
.DS_Store
EOF
git add -A && git commit -m "initial vault snapshot"
```

In Obsidian:
1. Settings → Community Plugins → Browse → install **Obsidian Git**.
2. Enable it. Plugin settings: `autoSaveInterval: 10` (min), `autoPushInterval: 0`, `autoPullInterval: 0`, `commitMessage: "vault: {{date}} auto-commit"`, `mergeOnPull: "merge"`.

### Recovery / rollback

```bash
cd ~/.canuto/vault
git log --oneline | head -20
git checkout <sha> -- <file>         # restore single note
git reset --hard <sha>               # full rewind (destructive — ensure no uncommitted work)
```

### Conflict resolution (manual)

Obsidian-Git uses `mergeOnPull: "merge"`. If a conflict appears (you edited on two devices), open the `.md` in Obsidian, resolve `<<<<<<<` markers, save, commit.

### Add a remote later

```bash
cd ~/.canuto/vault
git remote add origin git@github.com:<you>/canuto-vault-private.git
git push -u origin main
# Then in Obsidian-Git: autoPushInterval > 0 if you want auto-push
```

---

## Raycast integration

Raycast is Mac's command palette / launcher. Canuto ships no auto-install — the UI is interactive — but the framework recommends these snippets and extensions for a smoother flow:

### Extensions (install via Raycast Store)

- **Obsidian** — create quick notes into `~/.canuto/vault`. Point the extension's vault path to `/Users/<you>/.canuto/vault` in its settings.
- **GitHub** — for quick PR/issue triage alongside `mcp__github__*`.
- **Brew** — see what's installed, search casks.

### Snippets (Raycast → Settings → Snippets → "+")

Type `//brief` in any text field and Raycast expands it to the slash command. Use these triggers:

| Snippet | Expands to | Keyword |
|---------|------------|---------|
| `//brief` | `/briefing` | briefing |
| `//ship` | `/ship` | ship |
| `//qa` | `/qa` | qa |
| `//co` | `/co-plan` | coplan |
| `//test` | `/test` | test |
| `//fix` | `/fix` | fix |
| `//sig` | `http://localhost:8080` | signoz |
| `//reset` | `/session-reset` | reset |

### Quicklinks (Raycast → Create Quicklink)

- Name: `SigNoz Dashboard`, URL: `http://localhost:8080`.
- Name: `Obsidian Canuto`, URL: `obsidian://open?vault=vault`.
- Name: `Conductor Workspaces`, URL: `file:///Users/<you>/conductor/workspaces`.

These are **manual steps** — Raycast's UI doesn't expose a safe import format for bulk snippet/quicklink config. Add them once and they persist.

---

## Rollback

Everything installed by this integration has a rollback path. Pick the scope you need.

### Full rollback (pre-integration state)

```bash
# Replace TS with the timestamp used at install (see install.sh output or ls ~/.claude/*.bak.*)
TS=<timestamp>

# Global Claude / Codex configs
cp ~/.claude/settings.json.bak.$TS  ~/.claude/settings.json
cp ~/.claude/CLAUDE.md.bak.$TS      ~/.claude/CLAUDE.md
cp ~/.codex/config.toml.bak.$TS     ~/.codex/config.toml

# SigNoz stack
cd ~/signoz/deploy/docker && docker compose down -v
# rm -rf ~/signoz   # optional: fully remove the clone

# Mac automation
rm -f ~/.hammerspoon/init.lua ~/.wezterm.lua

# Framework hooks (from ~/.claude/hooks/ if installed there)
# Revert by editing ~/.claude/settings.json → "hooks" block back to backup
```

### Just disable OTel (keep SigNoz data)

Remove the `CLAUDE_CODE_ENABLE_TELEMETRY` and `OTEL_*` keys from `~/.claude/settings.json`'s `env` block, comment out `[otel]` in `~/.codex/config.toml`.

### Just stop SigNoz (keep configs)

```bash
cd ~/signoz/deploy/docker && docker compose down
```

### Just remove a hook

Edit `~/.claude/settings.json` → `hooks` array → remove the entry. No restart needed.

