shortDescription: Standardized analysis + migration planning workflow for investigating topics, features, or problems.
usedBy: [maestro, architect]
version: 1.0.0
lastUpdated: 2026-03-21
copyright: Rodrigo Canuto © 2026.

## When to Use

**Triggers:**
- User says: `"research"`, `"investigate"`, `"analyze this"`, `"what's the best approach for"`, `"migration plan"`
- Maestro receives a new topic that requires deep analysis before planning
- Architect needs structured investigation of a feature, library, or migration path

**Not for:**
- Quick lookups or simple questions (use direct answers instead)
- Tasks already planned — use the existing plan, don't re-research

---

## Purpose

Provide a structured, repeatable workflow for investigating topics, features, or migration paths. Ensures that prior work in the vault is consulted, risks are identified, and the output is a concrete plan — not just observations.

---

## Procedure

### Phase 0: Community Intelligence (when applicable)

Before diving into the codebase, check what the broader community knows about the topic. This phase is **optional** — use it when the topic involves library/tool choices, migration paths, best practices, or any decision where real-world experience from others is valuable.

**When to run this phase:**
- Choosing between libraries or tools (e.g., "Playwright vs Cypress")
- Evaluating a new technology or approach
- Investigating production issues that others may have encountered
- Any decision where "what are people actually saying about this?" would help

**How:**
1. **Parallel web searches** across community sources. Run multiple WebSearch queries simultaneously:
   - `site:reddit.com <topic>` — community discussions, real experience reports
   - `site:news.ycombinator.com <topic>` — technical deep dives, contrarian takes
   - `site:stackoverflow.com <topic>` — specific problems and solutions
   - `<topic> 2026` — general web results with recency bias
   - `<topic> comparison OR vs OR alternative` — head-to-head evaluations

2. **Consolidate findings:**
   - **Community consensus**: What does the majority recommend? (note sample size)
   - **Common pitfalls**: What problems do people report?
   - **Controversial points**: Where does the community disagree?
   - **Key threads**: Top 3-5 most upvoted/engaged discussions with brief summaries

3. **Feed into Phase 1**: The community intelligence becomes "External context" for the Explore phase below.

> **Optional tool:** [/last30days](https://github.com/mvanhorn/last30days-skill) is a Claude Code skill that automates parallel search across Reddit, X, YouTube, HN, Polymarket, and the web. Install for deeper community research: `claude skill install mvanhorn/last30days-skill`

---

### Phase 1: Explore

1. **Codebase scan**: Search the project for files, patterns, and dependencies related to the topic.
2. **Vault lookup**: Query the Obsidian vault for related notes:
   - `obsidian_global_search(query="<topic keywords>")` — find prior sessions, decisions, instincts.
   - `obsidian_list_notes(path="projects/{project-slug}/decisions/")` — check for related ADRs.
   - `obsidian_list_notes(path="projects/{project-slug}/pending/")` — check for related pending tasks.
3. **External context** (if needed): Check documentation, changelogs, or API references relevant to the topic.
4. **Community context** (from Phase 0): Integrate community findings — consensus, pitfalls, recommendations.

### Phase 2: Analyze

1. **Pattern identification**: What patterns exist in the codebase? What conventions are followed?
2. **Risk assessment**: What could go wrong? Breaking changes, data loss, regressions?
3. **Dependency mapping**: What other files/modules/services are affected?
4. **Prior work synthesis**: What did the vault reveal? Are there instincts or decisions that apply?

### Phase 3: Plan

1. **Steps**: Ordered list of implementation steps with files affected.
2. **Risks & mitigations**: Each risk paired with a concrete mitigation.
3. **Validation steps**: How to verify the change is correct (tests, manual checks, CI).
4. **Rollback strategy**: How to undo the change if something goes wrong.

### Phase 4: Report

1. **Save to vault**: Create a decision note in `projects/{project-slug}/decisions/D-XXX-<slug>.md` or a pending task in `pending/` depending on whether the user approves the plan.
2. **Present to user**: Use the standard output format below.

---

## Output Format

```markdown
## Research: {topic}

### Findings
- <key finding 1>
- <key finding 2>
- ...

### Community Intelligence (if Phase 0 was run)
- **Consensus:** <what the community recommends>
- **Pitfalls:** <common problems reported>
- **Key threads:** <top 3 discussions with brief summaries>

### Prior Work (vault)
- <related session/decision/instinct with wikilinks, or "None found">

### Proposed Plan
1. <step 1> — files: `path/to/file`
2. <step 2> — files: `path/to/file`
3. ...

### Risks & Mitigations
| Risk | Impact | Mitigation |
|------|--------|------------|
| ... | ... | ... |

### Validation Steps
- [ ] <test or check 1>
- [ ] <test or check 2>

### Rollback Strategy
- <how to undo if needed>
```

---

## Handoff

After presenting the research report:
- If the user approves → Maestro routes to Architect (or directly to Coder for XS/S tasks).
- If the user wants changes → iterate on the plan inline.
- If the user defers → save as pending task in vault.
