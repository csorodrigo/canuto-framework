# Instinct Promotion — Full Workflow

When an instinct reaches `high` confidence and has been applied 5+ times, Maestro suggests promotion.

## Promotion Dialog

```
Instinct I-003 has been reinforced across 6 sessions.
Promote to:
(a) Project rule in stack.md
(b) Custom skill in .agents/skills/
(c) Global instinct (visible in ALL projects)
(d) Keep as instinct
```

## Promotion to Project Rule / Custom Skill

1. Add the rule to `stack.md` or create the skill in `.agents/skills/`.
2. Mark the instinct as `promoted-to: "stack.md"` (keep for history, stop enforcing as instinct).

## Promotion to Global Instinct

Use when the pattern is **universal** (not project-specific), e.g.: "always validate env vars at startup", "never swallow errors silently".

1. Copy the instinct note to `~/.canuto/vault/global-instincts/I-XXX-slug.md`
2. Add to the copy's frontmatter:
   ```yaml
   source_project: {project-slug}
   promoted_from: "[[projects/{project-slug}/instincts/I-XXX-slug]]"
   ```
3. Mark the original as `promoted-to: "[[global-instincts/I-XXX-slug]]"`
4. Global instincts appear in **all projects** during session start, tagged as `[GLOBAL]`
