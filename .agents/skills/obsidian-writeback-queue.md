shortDescription: Stage safe write-back proposals for Obsidian or Canuto vault memory with preview, approval, and offline fallback.
usedBy: [maestro, contextualizer]
version: 1.1.0
lastUpdated: 2026-08-23
copyright: Rodrigo Canuto © 2026.

## Purpose

Connect session learning to Obsidian/Canuto vaults without unsafe automatic writes. This skill creates a reviewable queue of proposed memory writes, validates target paths, and supports offline sync when the Obsidian bridge is unavailable.

Automatically extracted **memory claims** are not written as active instincts or decisions. They must pass the `canuto-memory-candidate/v1` gate and remain in `memory-candidates/` until human review.

---

## Modes

### Preview Mode

Default for curated writes. Produce proposed notes and target paths, but do not write anything.

### Candidate Stage Mode

Automatic extracted memory uses:

```bash
bash .agents/tools/vault-sync.sh stage-candidate /tmp/candidate.md
```

The tool validates the envelope and writes only to `memory-candidates/`. When no backend is available, it queues the same validated file in `pending-sync/`.

### Queue Mode

With user approval, write other proposed items to `.agents/memory/writeback-queue.md` or another configured local queue file. This is still local project memory, not the vault.

### Live Write Mode

Only use for curated content when the user explicitly approves and the Obsidian/Canuto bridge is verified. Live writes require:

- target vault path;
- target project slug;
- target note path;
- write method: filesystem, Local REST API, or MCP bridge;
- backup or exact diff preview;
- explicit approval tied to that diff.

---

## Target Mapping

| Learning Type | Preferred Target | Authority |
|---------------|------------------|-----------|
| automatic memory claim | `projects/<slug>/memory-candidates/<id>.md` | hypothesis only |
| session summary | `projects/<slug>/sessions/YYYY-MM-DD.md` | session record |
| pending task | `projects/<slug>/pending/YYYY-MM-DD.md` or project pending index | operational |
| decision | `projects/<slug>/decisions/YYYY-MM-DD-<topic>.md` | curated; approval required |
| approved instinct | `projects/<slug>/instincts/I-XXX-<topic>.md` | curated; approval required |
| metric | `projects/<slug>/metrics/YYYY-MM-DD.md` | measured record |
| audit finding | `projects/<slug>/audit/YYYY-MM-DD.md` | audit record |

A candidate cannot select a curated destination. `target-kind` expresses intent only; the human review workflow determines the final path.

---

## Candidate Contract

Required frontmatter:

```yaml
schema: canuto-memory-candidate/v1
type: memory-candidate
id: MC-20260823-001
project: <resolved-slug>
tier: hypothesis
authority: memory
status: proposed
confidence: low
target-kind: instinct
source-system: canuto
source-session: sessions/2026-08-23
source-evidence: reviewer:MUST-FIX-2
```

The mechanical gate rejects:

- `tier: curated`, `status: approved`, `confidence: medium/high`;
- approval or promotion fields;
- project mismatch;
- unsafe IDs or conflicting overwrite;
- secret-like assignments;
- target kinds outside `instinct|session|pending|metric|audit`;
- missing source session, source system, evidence or body;
- files above 32 KiB.

`vault-sync.sh promote`, `approve` and `curate` always fail. Promotion is intentionally outside the automatic sync tool.

---

## Procedure

1. Receive proposed writes from `canuto-session-end-learning`, `canuto-pending-triage` or another agent.
2. Resolve project slug and memory backend.
3. Classify the write:
   - **automatic memory claim** → candidate quarantine;
   - **session/pending/metric/audit record** → normal reversible write;
   - **decision, approved instinct, stack/global rule** → curated preview and approval.
4. For an automatic memory claim:
   - create the required candidate envelope;
   - include a concrete source locator, not only a summary;
   - run `validate-candidate`;
   - run `stage-candidate`;
   - report the resulting candidate path and status as `STAGED`, never `LEARNED`.
5. For normal reversible records, resolve and validate the expected project path.
6. For curated content, show:
   - exact target;
   - create/append/update action;
   - before/after diff;
   - source candidates and evidence;
   - rollback path.
7. Ask for explicit approval before any curated write.
8. If the bridge is unavailable, preserve the validated candidate or proposal in `pending-sync/` and record the reason.

---

## Output Format

```markdown
## Write-back Result

### Target
- Vault: <path>
- Project: <slug>
- Mode: candidate-stage | preview | queue | live-write

### Writes
| Target | Action | Authority | Status | Summary |
|--------|--------|-----------|--------|---------|
| <path> | create/append/update | hypothesis/curated | staged/pending/approved | <summary> |

### Required Approval
<exact curated change requiring approval, or “none — candidate quarantined”>
```

---

## Guardrails

- Never route automatic memory directly to `instincts/`, `decisions/`, `stack.md` or global memory.
- Candidate quarantine is automatic; candidate promotion is never automatic.
- Session notes, pending, metrics and audit records remain reversible but must stay inside the resolved project.
- Never write secrets, raw tokens, private IDs or full session logs to the vault.
- Never write outside the resolved vault/project directory.
- Never require Obsidian Local REST API for read-only work.
- If live write fails, queue the proposal and report the failure instead of retrying blindly.
- An unavailable backend is not approval and never changes authority.
