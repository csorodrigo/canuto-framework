---
skill: vault-maintenance
shortDescription: Periodic Obsidian vault cleanup and aggregation to keep memory searchable, compact, and useful.
trigger: /vault-maintenance
persona: maestro
version: 1.0.0
lastUpdated: 2026-03-21
---

# Vault Maintenance

Periodic maintenance of the Obsidian vault to prevent unbounded growth and keep queries fast.

---

## When to Run

- **Automatically**: Maestro checks vault size at session start. If total notes > 500, suggest running `/vault-maintenance`.
- **Manually**: User runs `/vault-maintenance` to trigger cleanup.
- **Quarterly**: Recommended as part of regular housekeeping.

---

## Procedure

### 1. Assess Vault Size

Count total notes across all project directories:

```
obsidian_global_search(query="type:", contextLength=10)
```

Report:
```
Vault Maintenance Assessment:
- Total notes: {count}
- Projects: {project_count}
- Oldest session: {date}
- Largest project: {name} ({count} notes)
```

### 2. Archive Old Sessions (> 90 days)

For each project:
1. Find sessions older than 90 days: `projects/{slug}/sessions/YYYY-MM-DD.md`
2. Group by quarter (Q1, Q2, Q3, Q4)
3. Create summary note: `projects/{slug}/sessions/archive/YYYY-Q{n}-summary.md`
   - Frontmatter: `type: session-archive`, `quarter`, `session_count`, `goals_achieved`, `goals_deferred`
   - Body: bullet list of each session's goals and outcomes (1 line per session)
4. Delete (or move) the individual session notes
5. Report: "Archived {n} sessions → {m} quarterly summaries"

### 3. Archive Pruned Instincts (pruned > 30 days)

1. Find instincts with `status: pruned` and `last-seen` > 30 days ago
2. Move to `projects/{slug}/instincts/archive/`
3. Report: "Archived {n} pruned instincts"

### 4. Aggregate Old Audit Events (> 60 days)

1. Find audit notes older than 60 days
2. Group by month
3. Create: `projects/{slug}/audit/YYYY-MM-summary.md`
   - Frontmatter: `type: audit-summary`, `month`, `event_count`, `types` (list)
   - Body: count per event type + notable events
4. Delete individual audit notes
5. Report: "Aggregated {n} audit events → {m} monthly summaries"

### 5. Aggregate Old Metrics (> 90 days)

1. Find metric notes older than 90 days
2. Group by quarter
3. Create: `projects/{slug}/metrics/YYYY-Q{n}-summary.md`
   - Frontmatter: `type: metrics-summary`, `quarter`, `session_count`
   - Body: averages for each metric (tasks_completed, rework_cycles, must_fix_count, etc.)
4. Delete individual metric notes
5. Report: "Aggregated {n} metric notes → {m} quarterly summaries"

### 6. Clean Snapshots

1. Check `.snapshots/` in each project
2. Delete snapshots older than 30 days (keep at most 10 per project)
3. Report: "Cleaned {n} old snapshots"

---

## Output Format

```markdown
## Vault Maintenance Report — YYYY-MM-DD

### Before
- Total notes: {before_count}
- Oldest unarchived session: {date}

### Actions Taken
- Sessions archived: {n} → {m} quarterly summaries
- Pruned instincts archived: {n}
- Audit events aggregated: {n} → {m} monthly summaries
- Metrics aggregated: {n} → {m} quarterly summaries
- Snapshots cleaned: {n}

### After
- Total notes: {after_count}
- Reduction: {percentage}%

### Recommendations
- {any additional suggestions}
```

---

## User Approval

**Always ask before executing.** Present the assessment and proposed actions, then:

```
Proceed with vault maintenance? [Y/n]
```

Never delete or archive without confirmation.

---

## Notes

- Archived notes are NOT deleted — they're moved to `archive/` subdirectories
- Summary notes preserve key data for trend analysis
- Bases still query archived notes if user navigates to `archive/` folder
- This skill complements `analyze.sh` (analysis) — this skill takes action

---

## Gemini integration — Bulk classify (FASE 2a+)

Quando este skill precisa classificar/triaga um volume de itens (instincts,
notas, audits), delegue ao slot `bulk-classify` via Gemini flash-lite:

```
mcp__gemini__ask-gemini({
  prompt: "Classifique cada linha em uma label do conjunto {X, Y, Z}:\n<itens>",
  model: "gemini-3.1-flash-lite-preview"
})
```

Flash-lite tem quota separada (bar Flash-Lite no TUI) — efetivamente grátis até
1k/dia. Ver `.agents/skills/bulk-classify.md` pro padrão completo.
