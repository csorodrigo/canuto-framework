shortDescription: Close sessions by extracting proposed memory, decisions, pending tasks, metrics, and learning notes before any write-back.
usedBy: [maestro]
version: 1.1.0
lastUpdated: 2026-08-23
copyright: Rodrigo Canuto © 2026.

## Purpose

Convert the end of each work session into durable learning without turning model output into authority. The skill captures what happened, what failed, what was repeated, and what may deserve future memory.

Session facts, pending work, metrics and audit records remain normal reversible records. Reusable **memory claims** become quarantined candidates. Decisions, approved instincts and rules remain curated content and require explicit human approval.

---

## When To Run

Run at session end, before the final summary, and after any task with:

- failed tests or failed tool calls;
- repeated implementation attempts;
- review fix cycles;
- unresolved decisions;
- unfinished tasks;
- changed project assumptions;
- new claims that could affect future agent behavior.

---

## Authority Classification

Before writing, classify every extracted item:

| Item | Destination | Automatic? |
|------|-------------|------------|
| measured session event | `sessions/`, `metrics/`, `audit/` | yes, reversible |
| actionable unfinished work | `pending/` | yes, reversible |
| reusable claim or lesson | `memory-candidates/` | yes, quarantined |
| decision | `decisions/` | no; explicit approval |
| approved instinct | `instincts/` | no; explicit approval |
| stack/global rule | project/global rule path | no; explicit approval |

A candidate is not a decision, rule, fact or approved instinct. It must be reported as `STAGED`, not `LEARNED` or `APPROVED`.

---

## Procedure

1. Summarize the session in 3-7 bullets.
2. Mark session goals as achieved, deferred, or not started, naming evidence.
3. Extract concrete pending tasks.
4. Extract measured events and metrics; use `N/A` when not measured.
5. Identify proposed decisions separately; do not write them yet.
6. Extract candidate memories only from real signals:
   - reviewer findings;
   - test/gate failures;
   - root-cause diagnoses;
   - repeated user corrections;
   - measured rework;
   - externally supplied memory diffs with a source locator.
7. For each memory claim, search existing decisions, skills, approved instincts and candidates:
   - conflict with curated knowledge → mark `CONFLICT`, do not stage as truth;
   - duplicate candidate → reference it or create a new evidence-linked candidate; never overwrite different content;
   - reinforcement of approved instinct → stage a reinforcement candidate; do not mutate confidence;
   - new claim → create `confidence: low` candidate.
8. Build the candidate envelope:

   ```yaml
   schema: canuto-memory-candidate/v1
   type: memory-candidate
   id: MC-YYYYMMDD-NNN
   project: <resolved-slug>
   tier: hypothesis
   authority: memory
   status: proposed
   confidence: low
   target-kind: instinct
   source-system: <canuto|hermes|external>
   source-session: <session locator>
   source-evidence: <test, review, log, diff or line locator>
   ```

9. Validate and stage each candidate mechanically:

   ```bash
   bash .agents/tools/vault-sync.sh validate-candidate /tmp/<candidate>.md
   bash .agents/tools/vault-sync.sh stage-candidate /tmp/<candidate>.md
   ```

10. Write normal reversible session, pending, metric and audit records through the resolved Canuto backend.
11. Present exact previews for decisions, instinct approval/promotion and rules. Ask for approval before writing any curated content.
12. Register the closeout in the append-only event log:

   ```bash
   bash .agents/tools/event-log.sh append CLOSEOUT actor=maestro summary="<3-8 palavras>"
   ```

---

## Candidate Rules

A memory candidate is worth staging when it is:

- caused by a real observation, not a theoretical concern;
- linked to a concrete source session and evidence locator;
- likely to affect future behavior;
- specific enough to be falsified or reviewed;
- concise enough to fit Pattern + Learning in a few lines.

Bad candidate:

> Be careful with tests.

Good candidate:

> Pattern: the dashboard date filter failed at the local-day boundary in `timezone.test.ts:84`. Learning: run the fixed timezone-boundary fixture before changing UI date logic.

Discard a claim when evidence is missing, the project cannot be resolved, or the content duplicates a generic skill.

---

## Candidate Failure Semantics

`vault-sync.sh` fails closed:

- invalid schema or authority → rejected;
- curated tier or approval fields → rejected;
- project mismatch → rejected;
- possible secret → rejected;
- conflicting candidate ID → rejected;
- unavailable backend → validated file stays in `pending-sync/`;
- promotion commands → rejected.

Never convert a rejection or unavailable backend into a successful memory write. Report the candidate ID, reason and next review step.

---

## Output Format

```markdown
## Session Learning Draft — YYYY-MM-DD

### Session Summary
- <what changed>

### Goals
- ✅/⏳/❌ <goal> — <evidence>

### Pending Tasks Written
- [ ] <specific next action>

### Memory Candidates
- [STAGED] <candidate-id> — <short claim> — source: <locator>
- [REJECTED] <candidate-id> — <reason>
- [CONFLICT] <candidate-id> — conflicts with <curated source>

### Curated Proposals Requiring Approval
- <decision/instinct/rule and exact target>

### Metrics
- Review verdict: APPROVE | REQUEST CHANGES | N/A
- Test failures: N/M or N/A
- Rework cycles: N
- Rework files: <paths or none>
- Escalations: N

### Writes
| Target | Action | Authority | Status | Approval Needed |
|--------|--------|-----------|--------|-----------------|
| `projects/<slug>/sessions/YYYY-MM-DD.md` | append | session record | written | no |
| `projects/<slug>/memory-candidates/<id>.md` | create | hypothesis | staged | no |
| `projects/<slug>/decisions/<topic>.md` | create/update | curated | preview | yes |
```

---

## Guardrails

- Automatic extraction never writes directly to `instincts/`, `decisions/`, `stack.md` or global memory.
- Candidate quarantine does not require approval; curated promotion always does.
- Never claim that a candidate is learned, approved or authoritative.
- Every candidate must name project, source system, source session and evidence.
- Never fabricate metrics or evidence. Use `N/A` or reject the candidate.
- Never record vague pending items. Pending tasks must be directly actionable.
- Do not duplicate an existing decision, skill, pending item or candidate; reference it.
- Never include secrets, raw tokens, private IDs or full session transcripts.
- Keep written session memory concise; long evidence belongs in source logs and traces.
- An external memory engine may propose candidates, but it never changes Canuto's curated tier directly.
