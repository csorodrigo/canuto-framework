# Skill Gardener configuration

`config/skill-gardener.json` is an **identity-blind bootstrap default**. It may
contain provider conventions, but it must not contain a real project slug, user
name, host name, repository path, or workspace topology.

The installer copies that default only when the local configuration does not
already exist. The effective, machine-owned file is:

```text
~/.canuto/config/skill-gardener.json
```

Add projects and remote surfaces only to the effective local file. Existing
valid local configuration is preserved byte-for-byte during install, update,
repair, and a failed runtime activation.

## Minimal local project

```json
{
  "schemaVersion": 1,
  "projects": {
    "my-product": {
      "surfaces": {
        "local": {
          "provider": "codex",
          "roots": ["~/work/my-product"],
          "historyRoots": ["~/.codex/sessions"]
        }
      }
    }
  },
  "providers": {
    "codex": {
      "roots": ["~/.codex/skills"],
      "pluginRoots": ["~/.codex/plugins"],
      "systemRoots": ["~/.codex/system/skills"],
      "historyRoots": ["~/.codex/sessions"]
    }
  },
  "policy": {
    "detailRetentionDays": 180,
    "fingerprintFamilies": {},
    "evalAdapter": {"enabled": false, "command": "agent-skill-eval", "version": "v1"}
  }
}
```

The repository schema is `config/skill-gardener.schema.json`. Paths beginning
with `~` are portable conventions; absolute paths belong only in the local
configuration.
