#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def write_text(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")


neutral_config = {
    "schemaVersion": 1,
    "projects": {},
    "providers": {
        "codex": {
            "roots": ["~/.codex/skills"],
            "pluginRoots": ["~/.codex/plugins"],
            "systemRoots": ["~/.codex/system/skills"],
            "historyRoots": ["~/.codex/sessions", "~/.codex/archived_sessions"],
        },
        "claude": {
            "roots": ["~/.claude/skills"],
            "pluginRoots": ["~/.claude/plugins"],
            "systemRoots": ["~/.claude/system/skills"],
            "historyRoots": ["~/.claude/projects", "~/.claude/telemetry"],
        },
        "hermes": {
            "roots": ["~/.hermes/skills"],
            "pluginRoots": ["~/.hermes/plugins"],
            "systemRoots": ["~/.hermes/system/skills"],
            "historyRoots": ["~/.hermes/sessions"],
        },
        "opencode": {
            "roots": [],
            "pluginRoots": [],
            "systemRoots": [],
            "historyRoots": [],
        },
    },
    "policy": {
        "detailRetentionDays": 180,
        "fingerprintFamilies": {
            "tools": ["read", "search", "edit", "test", "git", "shell", "delegate"],
            "executables": [
                "node",
                "npm",
                "pnpm",
                "yarn",
                "bun",
                "git",
                "rg",
                "grep",
                "sed",
                "awk",
                "jq",
                "bash",
                "python3",
            ],
            "results": ["success", "failure", "error", "timeout", "partial", "unknown"],
        },
        "evalAdapter": {
            "enabled": False,
            "command": "agent-skill-eval",
            "version": "v1",
        },
    },
}
write_text("config/skill-gardener.json", json.dumps(neutral_config, indent=2) + "\n")

schema = {
    "$schema": "https://json-schema.org/draft/2020-12/schema",
    "$id": "https://github.com/csorodrigo/canuto-framework/config/skill-gardener.schema.json",
    "title": "Canuto Federated Skill Gardener configuration",
    "type": "object",
    "additionalProperties": False,
    "required": ["schemaVersion", "projects", "providers", "policy"],
    "properties": {
        "schemaVersion": {"const": 1},
        "projects": {
            "type": "object",
            "additionalProperties": {
                "type": "object",
                "additionalProperties": False,
                "required": ["surfaces"],
                "properties": {
                    "surfaces": {
                        "type": "object",
                        "additionalProperties": {
                            "type": "object",
                            "additionalProperties": True,
                            "required": ["provider", "roots"],
                            "properties": {
                                "provider": {"type": "string", "minLength": 1},
                                "roots": {
                                    "type": "array",
                                    "items": {"type": "string", "minLength": 1},
                                },
                                "historyRoots": {
                                    "type": "array",
                                    "items": {"type": "string", "minLength": 1},
                                },
                                "aliases": {
                                    "type": "array",
                                    "items": {"type": "string", "minLength": 1},
                                },
                                "remote": {"type": "boolean"},
                            },
                        },
                    }
                },
            },
        },
        "providers": {
            "type": "object",
            "additionalProperties": {
                "type": "object",
                "additionalProperties": False,
                "required": ["roots", "pluginRoots", "systemRoots", "historyRoots"],
                "properties": {
                    "roots": {"type": "array", "items": {"type": "string"}},
                    "pluginRoots": {"type": "array", "items": {"type": "string"}},
                    "systemRoots": {"type": "array", "items": {"type": "string"}},
                    "historyRoots": {"type": "array", "items": {"type": "string"}},
                },
            },
        },
        "policy": {
            "type": "object",
            "additionalProperties": True,
            "required": ["detailRetentionDays", "fingerprintFamilies", "evalAdapter"],
            "properties": {
                "detailRetentionDays": {"type": "integer", "minimum": 0},
                "fingerprintFamilies": {"type": "object"},
                "evalAdapter": {"type": "object"},
            },
        },
    },
}
write_text("config/skill-gardener.schema.json", json.dumps(schema, indent=2) + "\n")

write_text(
    "docs/SKILL-GARDENER-CONFIG.md",
    """# Skill Gardener configuration\n\n`config/skill-gardener.json` is an **identity-blind bootstrap default**. It may\ncontain provider conventions, but it must not contain a real project slug, user\nname, host name, repository path, or workspace topology.\n\nThe installer copies that default only when the local configuration does not\nalready exist. The effective, machine-owned file is:\n\n```text\n~/.canuto/config/skill-gardener.json\n```\n\nAdd projects and remote surfaces only to the effective local file. Existing\nvalid local configuration is preserved during install, update, repair, and\nruntime activation.\n\n## Minimal local project\n\n```json\n{\n  \"schemaVersion\": 1,\n  \"projects\": {\n    \"my-product\": {\n      \"surfaces\": {\n        \"local\": {\n          \"provider\": \"codex\",\n          \"roots\": [\"~/work/my-product\"],\n          \"historyRoots\": [\"~/.codex/sessions\"]\n        }\n      }\n    }\n  },\n  \"providers\": {\n    \"codex\": {\n      \"roots\": [\"~/.codex/skills\"],\n      \"pluginRoots\": [\"~/.codex/plugins\"],\n      \"systemRoots\": [\"~/.codex/system/skills\"],\n      \"historyRoots\": [\"~/.codex/sessions\"]\n    }\n  },\n  \"policy\": {\n    \"detailRetentionDays\": 180,\n    \"fingerprintFamilies\": {},\n    \"evalAdapter\": {\"enabled\": false, \"command\": \"agent-skill-eval\", \"version\": \"v1\"}\n  }\n}\n```\n\nThe repository schema is `config/skill-gardener.schema.json`. Paths beginning\nwith `~` are portable conventions; absolute paths belong only in the local\nconfiguration.\n""",
)

adr_path = ROOT / "docs/adr/0003-cegueira-de-identidade-no-genotipo.md"
adr = adr_path.read_text(encoding="utf-8")
adr_bullet = (
    "- Defaults instaláveis e configurações bootstrap são identidade-cegas: "
    "projetos, hosts e paths reais vivem somente em `~/.canuto/config/`.\n"
)
if adr_bullet not in adr:
    marker = "## Consequências\n"
    if marker not in adr:
        raise SystemExit("ADR-0003 consequence marker not found")
    adr = adr.replace(marker, adr_bullet + "\n" + marker, 1)
    adr_path.write_text(adr, encoding="utf-8")


test_path = ROOT / "test-framework.sh"
test_text = test_path.read_text(encoding="utf-8")
if "TEST 20: Defaults identidade-cegos" not in test_text:
    marker = "# ═══════════════════════════════════════════════════════════════════════════\n# SUMMARY\n"
    if marker not in test_text:
        raise SystemExit("test-framework summary marker not found")
    block = r'''# ═══════════════════════════════════════════════════════════════════════════
# TEST 20: Defaults identidade-cegos (ADR-0003)
# ═══════════════════════════════════════════════════════════════════════════
echo "── Test 20: Defaults identidade-cegos ──"

SG_DEFAULT="$FRAMEWORK_DIR/config/skill-gardener.json"
SG_SCHEMA="$FRAMEWORK_DIR/config/skill-gardener.schema.json"
if [ ! -s "$SG_DEFAULT" ]; then
  fail "20a config/skill-gardener.json ausente ou vazio"
elif python3 - "$SG_DEFAULT" "$SG_SCHEMA" <<'PYEOF'
import json
import os
import re
import sys

config_path, schema_path = sys.argv[1:]
with open(config_path, encoding="utf-8") as fh:
    cfg = json.load(fh)
with open(schema_path, encoding="utf-8") as fh:
    schema = json.load(fh)

assert cfg.get("schemaVersion") == 1
assert cfg.get("projects") == {}, "bootstrap default must not enumerate real projects"
assert isinstance(cfg.get("providers"), dict) and cfg["providers"]
assert isinstance(cfg.get("policy"), dict)
assert schema.get("properties", {}).get("schemaVersion", {}).get("const") == 1

identity_path = re.compile(r"^/(Users|home)/[^/]+/|^/srv/dev/(worktrees|repos)/")
for provider, provider_cfg in cfg["providers"].items():
    for key in ("roots", "pluginRoots", "systemRoots", "historyRoots"):
        values = provider_cfg.get(key, [])
        assert isinstance(values, list), f"{provider}.{key} must be an array"
        for value in values:
            assert isinstance(value, str)
            assert not identity_path.search(value), f"identity-bearing path in {provider}.{key}: {value}"
            assert value.startswith("~") or not os.path.isabs(value), f"absolute path in bootstrap default: {value}"
PYEOF
then
  pass "20a Skill Gardener bootstrap é neutro, parseável e compatível com o schema"
else
  fail "20a Skill Gardener bootstrap contém identidade, path absoluto ou shape inválido"
fi

if grep -nE '"projects"[[:space:]]*:[[:space:]]*\{[[:space:]]*"' "$SG_DEFAULT" >/dev/null 2>&1; then
  fail "20b bootstrap default enumera projeto real"
else
  pass "20b bootstrap default não enumera projetos"
fi

if grep -nE '/(Users|home)/[^/[:space:]\"]+|/srv/dev/(worktrees|repos)/[^/[:space:]\"]+' \
    "$SG_DEFAULT" >/dev/null 2>&1; then
  fail "20c bootstrap default contém topologia de máquina ou workspace"
else
  pass "20c bootstrap default não contém topologia de máquina ou workspace"
fi

if grep -qF 'config/skill-gardener.json' "$FRAMEWORK_DIR/install.sh" 2>/dev/null \
   && grep -qF '$HOME/.canuto/config' "$FRAMEWORK_DIR/install.sh" 2>/dev/null; then
  pass "20d instalador materializa a config efetiva fora do repositório"
else
  fail "20d instalador não mantém a config efetiva em ~/.canuto/config"
fi

if [ -s "$FRAMEWORK_DIR/docs/SKILL-GARDENER-CONFIG.md" ]; then
  pass "20e política de configuração local está documentada"
else
  fail "20e docs/SKILL-GARDENER-CONFIG.md ausente"
fi

echo ""
'''
    test_text = test_text.replace(marker, block + marker, 1)
    test_path.write_text(test_text, encoding="utf-8")

print("identity-blind defaults applied")
