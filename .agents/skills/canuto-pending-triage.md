shortDescription: Deduplicate, classify, and prioritize pending tasks across project memory and Canuto vault notes.
usedBy: [maestro, architect, reviewer]
version: 1.0.0
lastUpdated: 2026-04-17
copyright: Rodrigo Canuto © 2026.

## Purpose

Keep pending tasks useful. A pending file that only grows becomes noise. This skill turns accumulated pending items into a short backlog with duplicates removed, owners or next actions clarified, and stale items marked for archive.

---

## Inputs

- `.agents/memory/pending.md`
- `.agents/memory/last-session.md`
- `.agents/memory/decisions.md`
- Canuto vault `pending/` notes, if available
- user goals for the current session
- current project status from `canuto-project-doctor`

---

## Triage Categories

| Category | Meaning | Action |
|----------|---------|--------|
| `keep-now` | Still relevant and actionable this week | keep near top |
| `dedupe` | Same task appears multiple times | merge into one item |
| `convert-decision` | Pending item is really a decision gap | move/propose to decisions |
| `convert-instinct` | Pending item is a reusable lesson | propose as instinct |
| `blocked` | Needs user/external dependency | mark blocker explicitly |
| `archive` | stale, obsolete, or already done | remove only with approval |

---

## Procedure

1. Read pending sources.
2. Normalize each item into one action sentence.
3. Group duplicates by project area, file path, feature, or intent.
4. Assign each group a triage category.
5. Keep a maximum of 10 active pending items unless the user asks for full backlog.
6. Produce a proposed diff or replacement block.
7. Ask for approval before deleting, archiving, or rewriting memory.

---

## Output Format

```markdown
## Pending Triage

### Active Pending
- [ ] <task> — source: <file/line or note>

### Duplicates To Merge
- <canonical task>
  - duplicate: <old wording/source>

### Convert
- Decision: <item> -> <decision note>
- Instinct: <item> -> <candidate instinct>

### Archive Candidates
- <item> — reason: stale/obsolete/done

### Proposed Next Action
<one practical next step>
```

---

## Guardrails

- Never delete or rewrite pending memory without approval.
- Do not keep broad goals as pending tasks.
- Preserve source traceability when merging duplicates.
- Prefer fewer, sharper tasks over complete but unusable backlog dumps.
