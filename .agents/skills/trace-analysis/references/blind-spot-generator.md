# Blind-Spot Candidate Generator

Use this when `trace-analysis` flags a blind-spot gap. Candidates live under `.agents/blind-spots/_candidates/`.

## Dedupe Workflow
1. Determine `target-domain` (file, feature, tech stack).
2. Search existing blind spots + `_candidates/` for similar titles: `rg --files -g "*.md" .agents/blind-spots | xargs rg -n "<keyword>"`.
3. If a pitfall already exists (title similarity or matching keywords), reference it instead of creating a duplicate.
4. If new, craft filename: `_candidates/{target-domain}--{slug}.md`. Use `NEW-{domain}--{slug}.md` only when domain undefined.

## File Schema
```markdown
---
type: blind-spot-candidate
target: backend-routing
source: trace-analysis
signal: BS-001
created: 2026-04-04
status: pending
keywords: [routing, blast radius]
lastReviewed: 2026-04-04
---

# Domain: Backend Routing
Keywords: routing, blast radius, scope sizing

## Pitfall: Oversized diffs for S scope
**Trigger:** When Maestro sizes scope as S but diff touches 5+ files.
**Common mistake:** Proceeding without rerouting, causing reviewer churn.
**Correct approach:** Pause, rerun adaptive-routing, and split work or promote to M scope before coding.

**Overfitting check:** Applies to any S-sized change, not only the original session.
```

Notes:
- Always include `source: trace-analysis` and the `signal` ID tying back to the digest.
- Keep `status: pending` until user promotes/dismisses.
- `keywords` array powers Maestro's lookup; keep ≤5 concise entries.
- `lastReviewed` updates when user decides to promote/dismiss.
- Archive resolved candidates by moving to `_candidates/.archive/`.
