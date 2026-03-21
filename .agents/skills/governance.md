shortDescription: Define approval gates where human decision is required before proceeding with high-impact actions.
usedBy: [maestro]
version: 1.0.0
lastUpdated: 2026-03-18
copyright: Rodrigo Canuto © 2026.
inspiration: Paperclip — governance with approval gates, configuration versioning, and board-level oversight.

## When to Use

**Triggers:**
- Before any destructive or hard-to-reverse action (deploy, database migration, dependency upgrade)
- Before architectural decisions that affect multiple modules
- Before merging or pushing to shared branches
- Before creating or modifying external-facing APIs
- User configures custom gates in `CLAUDE.md` under `## Governance`

**Not for:**
- Routine code changes within an approved plan
- XS/S tasks (unless they touch governance-gated areas)
- Decisions already approved by the user in the current session

---

## Purpose

The framework already requires user confirmation for Git commands. Governance extends this to **product and architectural decisions** — ensuring that high-impact choices have explicit human approval with a documented paper trail.

This is the "board of directors" pattern from Paperclip: agents execute, humans decide.

---

## Concepts

### Approval Gate

A checkpoint where Maestro pauses and requires explicit user approval before proceeding:

```
🚦 Governance Gate: [gate-name]
Action: [what will happen]
Impact: [what this affects]
Reversibility: [easy / hard / irreversible]

Approve? [Y/n]
```

### Default Gates

These gates are always active, regardless of configuration:

| Gate | Trigger | Why |
|------|---------|-----|
| `deploy` | Any deployment action | Production impact |
| `migration` | Database schema changes | Data integrity |
| `api-breaking` | Breaking changes to public APIs | External consumers |
| `dependency-major` | Major version upgrades of dependencies | Compatibility risk |
| `security-config` | Changes to auth, permissions, or secrets config | Security impact |

### Custom Gates

Projects can define additional gates in `CLAUDE.md`:

```markdown
## Governance

- gates:
  - payment-logic: any changes to billing or payment flows
  - user-data: any changes to PII handling or data export
  - third-party: any new external service integration
```

### Gate Log

Every gate decision is logged as an audit note in `.agents/vault/audit/`:

```markdown
### GATE-2026-03-18-001
- **Gate:** api-breaking
- **Action:** Remove deprecated `/v1/users/legacy` endpoint
- **Decision:** APPROVED
- **Reason:** "v1 sunset was communicated 3 months ago, no active consumers"
- **Decided by:** User
- **Timestamp:** 2026-03-18T14:30
```

---

## Procedure

### Gate Detection

Before each persona handoff, Maestro evaluates if the planned action touches any gate:

1. Check the Architect's plan (or Coder's intended changes) against default gates
2. Check against custom gates from `CLAUDE.md`
3. If a gate is triggered, pause and present the gate to the user

### Gate Presentation

```
🚦 Governance Gate: migration
Action: Add `refresh_token` column to `users` table with NOT NULL constraint
Impact: Requires backfill for existing rows. Affects all user queries.
Reversibility: Hard (rollback migration needed, potential data loss)

Context:
- Plan step 3 of 5 (from Architect)
- Downstream: Coder will reference this column in auth flow

Approve? [Y/n/modify]
```

**Options:**
- **Y** — Approve and continue
- **n** — Reject and re-plan (route back to Architect)
- **modify** — Approve with modifications (user specifies changes)

### Post-Approval

After user approves:
1. Log the decision in `audit-log.md`
2. Include the approval in the handoff to the next persona:
   ```
   [Maestro → Coder] Implementing auth with refresh tokens.
   ✅ Governance: migration gate approved (backfill strategy: default value + lazy migration)
   ```

### Gate Rejection

If the user rejects a gate:
1. Log the rejection in `audit-log.md`
2. Route back to Architect for re-planning:
   ```
   [Maestro → Architect] Re-plan needed: migration gate rejected.
   User feedback: "Use a separate table instead of modifying users"
   ```

---

## Examples

### ✅ Good — gate with clear context and options

```
🚦 Governance Gate: dependency-major
Action: Upgrade `next` from v14 to v15 (major version)
Impact: Breaking changes in middleware API, new App Router conventions
Reversibility: Medium (can revert package.json, but code changes may be needed)

Notable breaking changes:
- Middleware now uses `NextRequest` instead of `NextApiRequest`
- `getServerSideProps` deprecated in favor of Server Components

Approve? [Y/n/modify]
```

### ✅ Good — gate log entry

```markdown
### GATE-2026-03-18-002
- **Gate:** dependency-major
- **Action:** Upgrade Next.js v14 → v15
- **Decision:** APPROVED with condition
- **Reason:** "Approve, but keep getServerSideProps for now — migrate to RSC in a separate session"
- **Decided by:** User
- **Timestamp:** 2026-03-18T15:45
```

### ❌ Bad — gate without context

```
🚦 Gate: migration
Approve? [Y/n]
```

This is bad because: no description of the action, impact, or reversibility. The user can't make an informed decision.

---

## Guardrails

- **Default gates are always active.** They can't be disabled — only custom gates are configurable.
- **Gates are not speed bumps.** Every gate must have a clear reason. Don't gate trivial actions.
- **Log every decision.** Approvals AND rejections go into `audit-log.md`.
- **Gates don't stack.** If an action triggers multiple gates, present them together, not sequentially.
- **Re-approval not needed for same action in same session.** If user approved a migration plan, don't re-gate the implementation.
- **Maestro never auto-approves gates.** Even if the action seems safe, always ask.
