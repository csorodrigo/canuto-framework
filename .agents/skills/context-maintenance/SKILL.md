---
shortDescription: How to maintain .context.md, FEATURE-MAP.md, and the Repo Index (evaluate-repo pipeline) as the project evolves.
usedBy: [contextualizer, coder, architect, maestro]
version: 2.2.0
lastUpdated: 2026-03-23
copyright: Rodrigo Canuto © 2026.
evals:
  - prompt: "we moved auth logic to a new /lib/auth directory, update the context files"
    should_trigger: true
  - prompt: "added 3 new features this week, the FEATURE-MAP is outdated"
    should_trigger: true
  - prompt: "create a new context.md file for this new project from scratch"
    should_trigger: false
  - prompt: "read the context.md for the payments module"
    should_trigger: false
---

## When to Use

**Triggers:**
- A directory's purpose, structure, or responsibility has changed
- Files, components, or dependencies were added or removed
- A new user-facing feature was created or significantly altered
- Coder or Architect needs to decide whether `.context.md` needs updating after a change

**Not for:**
- Bug fixes that don't change architecture or directory structure
- Style, formatting, or test-only changes
- Internal refactors that preserve the same external structure

---

## Purpose

Every meaningful directory in a project should have a `.context.md` that orients whoever arrives next — human or agent.

The project also keeps a single `docs/FEATURE-MAP.md`, a feature index that maps every user-facing feature to the code path that implements it.

Together, `.context.md` answers **"what lives here?"** and the feature map answers **"how does this feature work, end-to-end?"**.

---

## Scan Rules

- Start from `src/` as the root. Most projects keep source code there.
- Skip hidden and tooling directories: `.git`, `.idea`, `.vscode`, `.cache`, `dist`, `build`, `node_modules`, `venv`, `__pycache__`, `.next`, `.turbo`.
- A directory is "meaningful" if it has 2+ source files or represents a clear domain boundary.

---

## .context.md

### When to Update

An update is **required** when a change alters:
- The purpose or responsibility of a directory.
- The addition or removal of files, components, or dependencies.
- Naming conventions or structural patterns within the directory.

An update is **NOT required** for:
- Bug fixes that do not change architecture.
- Style or formatting-only changes.
- Internal refactors that preserve the same external behavior and structure.
- Adding or modifying files that fit the existing documented pattern.

### Schema Detection

- If the file starts with a `<context …>` tag, `Summary`, `Constraints`, and `Guidance` sections → **Canuto schema**.
- If the file uses another recognizable structure → **foreign schema**.

**Behavior:** On Canuto schema — keep and enforce the structure below. On foreign schema — do NOT rewrite the structure; update content in the same style.

### Canuto .context.md Schema

```markdown
<context path="relative/path" updated="YYYY-MM-DD">

One to two sentences describing what this directory contains and why it exists.

## Summary

- filename.ext – short description of what this file does.
- subdirectory/ – short description of what this subdirectory contains.

## Constraints

- MUST / MUST NOT statements. Non-negotiable constraints specific to this directory.

## Guidance

- SHOULD / SHOULD NOT statements. Recommendations that may be deviated from with justification.

</context>
```

**Rules:** `<context>` tag carries path + last-updated date. Description is prose. Summary covers every file/subdirectory (one line each). Constraints and Guidance are optional. Use RFC language (MUST, SHOULD). The update MUST be in the same commit as the code change it documents.

---

## docs/FEATURE-MAP.md

### When to Update

An update is **required** when a change:
- Adds, removes, or renames a user-facing feature.
- Alters the information flow of an existing feature.
- Moves or renames files that appear in an existing feature path.

An update is **NOT required** for: bug fixes, internal refactors preserving same entry points, style/test-only changes.

### Schema Detection

- Sections per feature with Flow lists of paths → **Canuto schema**.
- Another style (tables, other headings) → **foreign schema**. Extend using its own pattern.

### Canuto FEATURE-MAP.md Schema

```markdown
# Feature Map

---

## [Feature Name]

Brief description of what this feature does from the user's perspective.

**Flow:**

1. `path/to/entry_point.ext` – what happens here.
2. `path/to/service.ext` – what happens here.
3. `path/to/repository.ext` – what happens here.
```

**Rules:** One section per feature. Feature name = user-visible name. Flow lists files in order information travels (entry → output). One line per step. Feature map update MUST be in the same commit as feature code changes.

---

## Evaluate Repo Pipeline

A 4-stage pipeline that produces a comprehensive, searchable index of the entire repository. Run during bootstrap or on-demand after major structural changes.

→ **Full pipeline spec** (all 4 stages, schemas, procedure, persona usage): read `references/evaluate-repo-pipeline.md`

**When to run:**
- Bootstrap: first session on a new project (after `.context.md` + `FEATURE-MAP.md`)
- On demand: user requests `evaluate-repo` or major structural changes detected
- Periodic refresh: `repo-index.json` older than 7 days + significant commits landed

**NOT for:** minor fixes or projects with fewer than 10 source files.

**Outputs:**
- `docs/REPO-INDEX.md` — human-readable domain map
- `~/.canuto/vault/projects/{project-slug}/repo-index.json` — machine-readable index

---

## Guardrails

- Never invent purpose. If a directory's role is unclear, say so.
- Never add a feature to the map that you cannot trace end-to-end.
- Never update the `updated` date in a `.context.md` unless the content actually changed.
- On non-standard projects: detect the existing schema, adapt to it, never overwrite with Canuto schema without explicit instruction.
- Never generate a repo index for projects under 10 source files.
- Always present the repo index summary to the user before saving. Never auto-save.

→ **Examples** (good/bad .context.md, FEATURE-MAP, and repo-index entities): read `references/examples.md`
