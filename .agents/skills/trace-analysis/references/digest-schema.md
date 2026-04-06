# Trace Digest Schema

Every digest lives at `vault/traces/{date}-{suffix}-digest.md`.

## Frontmatter

```markdown
---
type: trace-digest
date: 2026-04-04
session: "[[sessions/2026-04-04]]"
session-link: https://codex.local/sessions/2026-04-04-01
suffix: autoagent-x-canuto
author: maestro
signals-found: 3
improvements-proposed: 2
improvements-applied: 0
categories:
  - playbook-gap
  - blind-spot-gap
  - instinct-candidate
missing-sources: []
overfitting-guard: "All signals useful beyond this task"
---
```

Required fields:
- `type` always `trace-digest`.
- `date` = session date (YYYY-MM-DD).
- `session` = wikilink to vault session note.
- `session-link` = canonical log or Conductor URL if available, else `""`.
- `suffix` = short slug (task-id, persona, timestamp) to avoid collisions.
- `signals-found` = total signals accepted after guardrails.
- `improvements-proposed` = subset with concrete action (new blind spot, skill, experiment, routing change).
- `improvements-applied` stays `0` until user confirms follow-up.
- `categories` = distinct list of signal categories present.
- `missing-sources` = array of source file names that were absent (optional).
- `overfitting-guard` = short summary of the guard result.

## Body Structure

```
# Trace Digest — <task name or slug>

## Session Overview
- Task: AutoAgent routing hardening
- Scope: S
- Personas: Architect → Coder → Reviewer
- Files touched: 6 (exceeds S threshold)
- Highlights: scope creep flagged twice, reviewer score drop to 6.8/10

## Signals
### playbook-gap
- `PG-001` — Hand-off lacked reroute criteria (evidence: audit/2026-04-04-architect.md line 42). _Improvement_: add routing checklist to Maestro briefing.

### blind-spot-gap
- `BS-001` — Adaptive routing mis-sized diff >5 files for S scope. Candidate created: `_candidates/routing--blast-radius.md`. _Overfitting check_: still relevant for any S task touching many files.

### instinct-candidate
- `IC-001` — Same middleware file reworked 3 times. Forwarded to `continuous-learning` (awaiting approval).

### routing-misfire
- `RM-001` — Blast radius triggered (git diff --stat = 9 files). Suggested reroute to Architect.

### skill-gap
- `SG-001` — Manual blind-spot dedupe run in 3 sessions. Proposal drafted via `skill-proposer`.

## Next Actions
- Present blind-spot candidate(s) during next session start.
- Ask user to approve instinct + skill proposals.
- If review dimension "Quality" average <7 (last 5), propose experiment series per `experiment-loop`.
```

Always include empty headings for missing categories to keep layout stable, but note `"No signals"` in their section.
