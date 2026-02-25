shortDescription: How to maintain .context.md files and docs/FEATURE-MAP.md as the project evolves.
usedBy: [contextualizer, coder, architect]
version: 1.0.0
lastUpdated: 2026-02-25
copyright: Rodrigo Canuto © 2026.

## Purpose

Every meaningful directory in a project should have a `.context.md` that orients whoever arrives next — human or agent.

The project also keeps a single `docs/FEATURE-MAP.md`, a feature index that maps every user-facing feature to the code path that implements it.

Together, `.context.md` answers **"what lives here?"** and the feature map answers **"how does this feature work, end-to-end?"**.

This skill defines **when** to update these files, **how** to keep them accurate, and **how to behave when the project uses a different schema**.

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

**Behavior:**
- On Canuto schema: keep and enforce the structure below.
- On foreign schema: do NOT rewrite the structure. Update content in the same style.

### Canuto .context.md Schema

```markdown
<context path="relative/path" updated="YYYY-MM-DD">

One to two sentences describing what this directory contains and why it exists.

## Summary

- filename.ext – short description of what this file does.
- otherfile.ext – short description of what this file does.
- subdirectory/ – short description of what this subdirectory contains.

## Constraints

- MUST / MUST NOT statements. Non-negotiable constraints specific to this directory.

## Guidance

- SHOULD / SHOULD NOT statements. Recommendations that may be deviated from with justification.

</context>
```

**Schema rules:**
- The `<context>` tag carries the relative path and a last-updated date.
- The description is prose, not a list. Answer "what is here" and "why does it exist".
- Summary covers every file and subdirectory. One line each.
- Constraints and Guidance are optional — only include when the directory has rules worth stating.
- Use RFC-style language (MUST, SHOULD, MUST NOT, SHOULD NOT).
- Keep it short. This file is read frequently by multiple personas.
- The `.context.md` update MUST be in the same commit as the code change it documents.

---

## docs/FEATURE-MAP.md

### When to Update

An update is **required** when a change:
- Adds, removes, or renames a user-facing feature.
- Alters the information flow of an existing feature.
- Moves or renames files that appear in an existing feature path.

An update is **NOT required** for:
- Bug fixes that do not change the flow.
- Internal refactors that preserve the same entry points and layers.
- Style, formatting, or test-only changes.

### Schema Detection

- If the file has sections per feature with Flow lists of paths → **Canuto schema**.
- If the file uses another style (tables, other headings) → **foreign schema**. Extend using its own pattern.

### Canuto FEATURE-MAP.md Schema

```markdown
# Feature Map

Auto-maintained index of every user-facing feature and the code path that implements it.
Updated alongside the code — not after the fact.

---

## [Feature Name]

Brief description of what this feature does from the user's perspective.

**Flow:**

1. `path/to/entry_point.ext` – what happens here (e.g., route handler, CLI command).
2. `path/to/service.ext` – what happens here (e.g., validation, orchestration).
3. `path/to/repository.ext` – what happens here (e.g., persistence, external calls).
4. `path/to/presenter.ext` – what happens here (e.g., response formatting).
```

**Schema rules:**
- One section per feature.
- The feature name is the user-visible name, not an internal module name.
- The flow lists files in the order information travels — from entry point to final output.
- Each step is a file path plus a short phrase describing that file's role.
- Keep descriptions to one line.
- If a feature branches (e.g., sync vs async), show the primary path and note the branch.
- The feature map update MUST be in the same commit as the feature code changes.

---

## Guardrails

- Never invent purpose. If a directory's role is unclear, say so.
- Never add a feature to the map that you cannot trace end-to-end. If the path is unclear, say so.
- Never update the `updated` date in a `.context.md` unless the content actually changed.
- On non-standard projects: detect the existing schema, adapt to it, never overwrite with Canuto schema without explicit user instruction.
