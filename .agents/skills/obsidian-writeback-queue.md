shortDescription: Stage safe write-back proposals for Obsidian or Canuto vault memory with preview, approval, and offline fallback.
usedBy: [maestro, contextualizer]
version: 1.0.0
lastUpdated: 2026-04-17
copyright: Rodrigo Canuto © 2026.

## Purpose

Connect session learning to Obsidian/Canuto vaults without unsafe automatic writes. This skill creates a reviewable queue of proposed memory writes, validates target paths, and supports offline sync when the Obsidian bridge is unavailable.

---

## Modes

### Preview Mode

Default mode. Produce proposed notes and target paths, but do not write anything.

### Queue Mode

With user approval, write proposed items to `.agents/memory/writeback-queue.md` or another configured local queue file. This is still local project memory, not the vault.

### Live Write Mode

Only use when the user explicitly approves and the Obsidian/Canuto bridge is verified. Live writes require:

- target vault path
- target project slug
- target note path
- write method: filesystem, Local REST API, or MCP bridge
- backup or diff preview

---

## Target Mapping

| Learning Type | Preferred Target |
|---------------|------------------|
| session summary | `projects/<slug>/sessions/YYYY-MM-DD.md` |
| pending task | `projects/<slug>/pending/YYYY-MM-DD.md` or project pending index |
| decision | `projects/<slug>/decisions/YYYY-MM-DD-<topic>.md` |
| instinct | `projects/<slug>/instincts/YYYY-MM-DD-<topic>.md` |
| metric | `projects/<slug>/metrics/YYYY-MM-DD.md` |
| audit finding | `projects/<slug>/audit/YYYY-MM-DD.md` |

---

## Procedure

1. Receive proposed writes from `canuto-session-end-learning` or `canuto-pending-triage`.
2. Resolve project slug.
3. Resolve vault path:
   - explicit user-provided path
   - `.canuto/vault` convention
   - project config, if present
4. Validate that every target is inside the intended vault/project.
5. Show a compact preview:
   - target path
   - action: create, append, update
   - 1-3 line content summary
6. Ask for approval before queueing or writing.
7. If the bridge is unavailable, keep the item queued and record the reason.

---

## Output Format

```markdown
## Write-back Preview

### Target
- Vault: <path>
- Project: <slug>
- Mode: preview | queue | live-write

### Proposed Writes
| Target | Action | Summary | Risk |
|--------|--------|---------|------|
| <path> | create/append/update | <summary> | low/medium/high |

### Required Approval
<what the user must approve before any write>
```

---

## Guardrails

- Preview mode is the default.
- Never write secrets, raw tokens, private IDs, or full session logs to the vault.
- Never write outside the resolved vault/project directory.
- Never require Obsidian Local REST API for read-only work.
- If live write fails, queue the proposal and report the failure instead of retrying blindly.
