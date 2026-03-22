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

### Phase 1: Explore

1. **Codebase scan**: Search the project for files, patterns, and dependencies related to the topic.
2. **Vault lookup**: Query the Obsidian vault for related notes:
   - `obsidian_global_search(query="<topic keywords>")` — find prior sessions, decisions, instincts.
   - `obsidian_list_notes(path="projects/{project-slug}/decisions/")` — check for related ADRs.
   - `obsidian_list_notes(path="projects/{project-slug}/pending/")` — check for related pending tasks.
3. **External context** (if needed): Check documentation, changelogs, or API references relevant to the topic.

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
