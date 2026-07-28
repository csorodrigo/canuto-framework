---
name: vault-sync
description: Sync offline session artifacts from `.agents/.cache/pending-sync/` back into the active vault or legacy `.agents/memory/` backend. Use after Obsidian/MCP downtime or any session that ran without a writable vault.
---

# Vault Sync Skill

Use this when the framework reports offline writes or when hooks tell you there is pending sync work.

## When to Use

- `.agents/.cache/pending-sync/` contains `.md` files
- `session-save.sh` tells you to run `/vault-sync`
- Obsidian crashed, MCP was unavailable, or the session completed in legacy-memory compatibility mode

## Command

```bash
bash .agents/tools/vault-sync.sh
```

## Expected Result

- Pending sync files are copied into the active backend
- Synced files are removed from `.agents/.cache/pending-sync/`
- The command prints `vault-sync complete: <synced> synced, <failed> failed.`

## Guardrails

- Do not delete pending-sync files manually before attempting a sync
- If the tool says no writable backend is available, repair the framework first (`bash install.sh --doctor`)
- If the project still uses legacy `.agents/memory/`, keep that backend intact; `vault-sync` is compatibility-aware
