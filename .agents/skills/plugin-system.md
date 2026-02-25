shortDescription: How to create, install, and manage opt-in plugins that extend the framework.
usedBy: [maestro, architect, coder]
version: 1.0.0
lastUpdated: 2026-02-25
copyright: Rodrigo Canuto © 2026.

## Purpose

Allow the Canuto Framework to be extended with optional plugins without modifying core files. Plugins add new skills, personas, or workflows that are activated by their presence in the `.agents/plugins/` folder.

---

## Structure

```
.agents/
  plugins/
    <plugin-name>/
      plugin.md          — Plugin manifest (required). Describes what the plugin provides.
      personas/           — Optional. Additional personas this plugin adds.
        <persona>.md
      skills/             — Optional. Additional skills this plugin adds.
        <skill>.md
      templates/          — Optional. File templates the plugin provides.
        <template>.*
```

### plugin.md Manifest

Every plugin MUST have a `plugin.md` at its root:

```markdown
name: <plugin-name>
version: 1.0.0
description: One-line description of what this plugin adds.
author: <name>
requires: [<core-skill-1>, <core-skill-2>]

## What This Plugin Adds

- Personas: <list, or "none">
- Skills: <list, or "none">
- Templates: <list, or "none">

## Activation

This plugin is active when the folder exists in `.agents/plugins/`.
To deactivate, remove or rename the folder.

## Usage

<How to use this plugin. What changes for the user.>
```

---

## Procedure

### 1. Installing a Plugin

1. Copy the plugin folder into `.agents/plugins/<plugin-name>/`.
2. The Maestro detects the plugin on session start by scanning `.agents/plugins/`.
3. The Maestro announces available plugins in the session briefing:
   ```
   Active plugins: <plugin-name-1>, <plugin-name-2>.
   ```

### 2. Creating a Plugin

1. Create a folder in `.agents/plugins/<plugin-name>/`.
2. Write the `plugin.md` manifest.
3. Add personas, skills, and/or templates as needed.
4. Personas and skills inside plugins follow the **same format** as core ones.
5. Plugin personas can reference core skills and vice versa.

### 3. Plugin Resolution Order

When a persona or skill name conflicts between core and a plugin:
- **Core always wins.** Plugin must use a namespaced name (e.g., `plugin-name:skill-name`).

When multiple plugins provide the same persona or skill name:
- **First alphabetically wins.** Maestro warns about the conflict.

### 4. Plugin Discovery by Maestro

On session start, Maestro:
1. Lists directories in `.agents/plugins/`.
2. For each directory with a `plugin.md`:
   - Reads the manifest.
   - Registers additional personas and skills.
   - Reports them in the session briefing.
3. Directories without `plugin.md` are ignored (with a warning).

---

## Example Plugins

### `ci-pipeline` Plugin

```
.agents/plugins/ci-pipeline/
  plugin.md
  skills/
    ci-pipeline.md       — How to configure and maintain CI/CD pipelines.
  templates/
    github-actions.yml   — Starter GitHub Actions workflow.
```

### `database-migrations` Plugin

```
.agents/plugins/database-migrations/
  plugin.md
  skills/
    migration-management.md  — How to create, run, and rollback migrations.
  personas/
    dba.md                   — Database specialist persona.
```

---

## Guardrails

- Plugins MUST NOT modify core files (personas, skills, memory).
- Plugins MUST NOT override core persona behavior. They can add new personas only.
- A plugin without `plugin.md` is ignored.
- Plugins should be self-contained. Dependencies on other plugins must be declared in `requires`.
- The `plugins/` folder is git-tracked. Each project chooses which plugins to include.
