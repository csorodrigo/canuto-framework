# Improvement Patterns by Signal Category

Use this cheat sheet when classifying traces. Evidence must come from vault markdown (audit, metrics, session note). Each bullet lists common triggers plus the recommended improvement.

## playbook-gap
- **Missing instructions** — repeated "Need clarification" comments or ad-hoc steps added mid-session. *Fix*: update persona instructions or stack docs with explicit step.
- **Unclear handoff criteria** — Architect/Coder handoffs that leave Reviewer without test scope. *Fix*: append acceptance checklist.
- **Unhandled edge cases** — fluxo /fix finds scenario absent from playbook. *Fix*: add branch to relevant skill or stack section.

## blind-spot-gap
- **Domain pitfalls not covered** — Two or more reviewers flag same domain error (e.g., caching, auth). Generate candidate per `blind-spot-generator`.
- **New technology areas** — Files referencing libraries unseen in current blind spots; same mistakes repeated. Add candidate targeting that tech.
- **Regression loops** — Same bug reopened after fix; treat as blind-spot gap if not already documented.

## instinct-candidate
- **Recurring rework** — Same file edited 3+ times across personas.
- **Repeated debugging cycle** — fluxo /fix or Reviewer re-runs same fix path >2 times.
- **Workflow friction** — User feedback repeating ("remember to run smoke tests"). Feed to `continuous-learning` pending user approval.

## routing-misfire
- **Task re-planned** — Architect forced to re-issue plan due to underestimated scope.
- **Blast radius** — `git diff --stat` shows file count above sizing expectation (XS=1, S=≤2, M≤5, L>6). Trigger reroute recommendation.
- **Review loop** — Two or more REQUEST CHANGES for same scope => wrong persona order or insufficient gating.

## skill-gap
- **Manual workflow repeated** — Same persona runs multi-step CLI workflow in ≥3 sessions; automate via new skill.
- **Command macros** — Audit logs show identical command sequences within or across sessions.
- **Plan-pattern deficiency** — Similar plan adjustments needed each time (e.g., always add instrumentation). Suggest skill to encode sequence.
