---
name: obsidian-cli
description: Interact with Obsidian vaults using the Obsidian CLI to read, create, search, and manage notes, tasks, properties, and more. Use when the user asks to interact with their Obsidian vault from the command line.
origin: kepano/obsidian-skills (adapted for Canuto Framework)
---

# Obsidian CLI Skill

Use the `obsidian` CLI to interact with a running Obsidian instance. Requires Obsidian to be open.

## When to Use

- When interacting with the Canuto vault from the command line
- When the user asks to read, create, or search notes via CLI
- When developing or debugging Obsidian plugins

## Command Reference

Run `obsidian help` to see all available commands. Full docs: https://help.obsidian.md/cli

## Syntax

**Parameters** take a value with `=`. Quote values with spaces:

```bash
obsidian create name="My Note" content="Hello world"
```

**Flags** are boolean switches with no value:

```bash
obsidian create name="My Note" silent overwrite
```

For multiline content use `\n` for newline and `\t` for tab.

## File Targeting

Many commands accept `file` or `path` to target a file. Without either, the active file is used.

- `file=<name>` — resolves like a wikilink (name only, no path or extension needed)
- `path=<path>` — exact path from vault root, e.g. `folder/note.md`

## Vault Targeting

Commands target the most recently focused vault by default. Use `vault=<name>` as the first parameter:

```bash
obsidian vault="My Vault" search query="test"
```

## Common Patterns

```bash
obsidian read file="My Note"
obsidian create name="New Note" content="# Hello" template="Template" silent
obsidian append file="My Note" content="New line"
obsidian search query="search term" limit=10
obsidian daily:read
obsidian daily:append content="- [ ] New task"
obsidian property:set name="status" value="done" file="My Note"
obsidian tasks daily todo
obsidian tags sort=count counts
obsidian backlinks file="My Note"
```

Use `--copy` on any command to copy output to clipboard. Use `silent` to prevent files from opening. Use `total` on list commands to get a count.

## Plugin Development

### Develop/Test Cycle

1. **Reload** the plugin: `obsidian plugin:reload id=my-plugin`
2. **Check errors**: `obsidian dev:errors`
3. **Verify visually**: `obsidian dev:screenshot path=screenshot.png`
4. **Check console**: `obsidian dev:console level=error`

### Additional Developer Commands

```bash
obsidian eval code="app.vault.getFiles().length"
obsidian dev:css selector=".workspace-leaf" prop=background-color
obsidian dev:mobile on
```

## Examples

### ✅ Good — Creating a decision note in the Canuto vault

```bash
obsidian create name="D-003-new-auth" path="decisions/D-003-new-auth.md" content="---\ntype: decision\nid: D-003\ndate: 2026-03-21\nstatus: active\ndomain: architecture\ntags:\n  - decision\n  - architecture\n---\n\n# Use JWT for auth\n\n**Context:** Needed auth strategy.\n**Decision:** JWT with refresh tokens.\n**Reason:** Stateless, scalable." silent
```

### ❌ Bad — Not specifying path, not using silent

```bash
obsidian create name="D-003-new-auth" content="Use JWT for auth"
```

## References

- [Obsidian CLI docs](https://help.obsidian.md/cli)
