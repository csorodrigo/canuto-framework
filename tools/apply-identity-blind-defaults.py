#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def write_text(path: str, content: str) -> None:
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")


def replace_region(path: str, start_marker: str, end_marker: str, replacement: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding="utf-8")
    start = text.find(start_marker)
    if start < 0:
        raise SystemExit(f"start marker not found in {path}: {start_marker!r}")
    end = text.find(end_marker, start)
    if end < 0:
        raise SystemExit(f"end marker not found in {path}: {end_marker!r}")
    target.write_text(text[:start] + replacement + text[end:], encoding="utf-8")


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
    """# Skill Gardener configuration\n\n`config/skill-gardener.json` is an **identity-blind bootstrap default**. It may\ncontain provider conventions, but it must not contain a real project slug, user\nname, host name, repository path, or workspace topology.\n\nThe installer copies that default only when the local configuration does not\nalready exist. The effective, machine-owned file is:\n\n```text\n~/.canuto/config/skill-gardener.json\n```\n\nAdd projects and remote surfaces only to the effective local file. Existing\nvalid local configuration is preserved byte-for-byte during install, update,\nrepair, and a failed runtime activation.\n\n## Minimal local project\n\n```json\n{\n  \"schemaVersion\": 1,\n  \"projects\": {\n    \"my-product\": {\n      \"surfaces\": {\n        \"local\": {\n          \"provider\": \"codex\",\n          \"roots\": [\"~/work/my-product\"],\n          \"historyRoots\": [\"~/.codex/sessions\"]\n        }\n      }\n    }\n  },\n  \"providers\": {\n    \"codex\": {\n      \"roots\": [\"~/.codex/skills\"],\n      \"pluginRoots\": [\"~/.codex/plugins\"],\n      \"systemRoots\": [\"~/.codex/system/skills\"],\n      \"historyRoots\": [\"~/.codex/sessions\"]\n    }\n  },\n  \"policy\": {\n    \"detailRetentionDays\": 180,\n    \"fingerprintFamilies\": {},\n    \"evalAdapter\": {\"enabled\": false, \"command\": \"agent-skill-eval\", \"version\": \"v1\"}\n  }\n}\n```\n\nThe repository schema is `config/skill-gardener.schema.json`. Paths beginning\nwith `~` are portable conventions; absolute paths belong only in the local\nconfiguration.\n""",
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

install_migration = r'''skill_gardener_migrate_legacy_config() {
  local library_file="$1"
  local config_file="$2"
  local candidate_file="$3"
  node - "$library_file" "$config_file" "$candidate_file" <<'NODE'
const fs = require('node:fs');
const path = require('node:path');
const library = require(path.resolve(process.argv[2]));
const configPath = path.resolve(process.argv[3]);
const candidatePath = path.resolve(process.argv[4]);
const canonicalRemoteHistory = ['~/.codex/sessions', '~/.codex/archived_sessions'];

function isProjectLocalCodexHistory(surface) {
  if (!surface || surface.remote !== true || surface.provider !== 'codex') return false;
  if (!Array.isArray(surface.historyRoots) || surface.historyRoots.length !== 1) return false;
  if (!Array.isArray(surface.roots) || surface.roots.length === 0) return false;
  const historyRoot = surface.historyRoots[0];
  if (typeof historyRoot !== 'string' || !path.isAbsolute(historyRoot)) return false;
  const normalizedHistory = path.resolve(historyRoot);
  return surface.roots.some((root) => {
    if (typeof root !== 'string' || !path.isAbsolute(root)) return false;
    return normalizedHistory === path.join(path.resolve(root), '.codex', 'sessions');
  });
}

let raw;
try {
  raw = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  library.loadConfig(configPath);
} catch {
  try { fs.unlinkSync(candidatePath); } catch {}
  process.exit(1);
}
let changed = false;
for (const project of Object.values(raw.projects || {})) {
  for (const surface of Object.values(project?.surfaces || {})) {
    if (isProjectLocalCodexHistory(surface)) {
      surface.historyRoots = [...canonicalRemoteHistory];
      changed = true;
    }
  }
}
if (raw.providers?.hermes && Array.isArray(raw.providers.hermes.historyRoots)
  && raw.providers.hermes.historyRoots.length === 2
  && raw.providers.hermes.historyRoots[0] === '~/.hermes/sessions'
  && raw.providers.hermes.historyRoots[1] === '~/.hermes/history') {
  raw.providers.hermes.historyRoots = ['~/.hermes/sessions'];
  changed = true;
}
if (!changed) {
  try { fs.unlinkSync(candidatePath); } catch {}
  process.exit(0);
}
try {
  if (!candidatePath || candidatePath === configPath) throw new Error('invalid-migration-candidate');
  const mode = fs.statSync(configPath).mode & 0o777;
  fs.writeFileSync(candidatePath, `${JSON.stringify(raw, null, 2)}\n`, { mode: mode || 0o600, flag: 'wx' });
  fs.chmodSync(candidatePath, mode || 0o600);
  library.loadConfig(candidatePath);
} catch {
  try { fs.unlinkSync(candidatePath); } catch {}
  process.exit(1);
}
NODE
}

'''
replace_region(
    "install.sh",
    "skill_gardener_migrate_legacy_config() {\n",
    "setup_skill_gardener() {\n",
    install_migration,
)

sg_test_path = ROOT / "skill-gardener/canuto-skill-gardener.test.js"
sg_test = sg_test_path.read_text(encoding="utf-8")
helper = r'''
function makeSyntheticLegacyConfig() {
  const config = JSON.parse(fs.readFileSync(path.join(__dirname, '..', 'config', 'skill-gardener.json'), 'utf8'));
  config.projects = {
    alpha: {
      surfaces: {
        local: {
          provider: 'codex',
          roots: ['~/work/alpha'],
          aliases: ['Local'],
          historyRoots: ['/custom/history'],
        },
        remote: {
          provider: 'codex',
          remote: true,
          roots: ['/opt/canuto-fixtures/alpha/main'],
          aliases: ['Remote'],
          historyRoots: ['/opt/canuto-fixtures/alpha/main/.codex/sessions'],
        },
      },
    },
    beta: {
      surfaces: {
        remote: {
          provider: 'codex',
          remote: true,
          roots: ['/opt/canuto-fixtures/beta/main'],
          aliases: ['Remote'],
          historyRoots: ['/opt/canuto-fixtures/beta/main/.codex/sessions'],
        },
        customRemote: {
          provider: 'codex',
          remote: true,
          roots: ['/opt/canuto-fixtures/beta/main'],
          aliases: ['Custom'],
          historyRoots: ['/custom/remote-history'],
        },
      },
    },
  };
  config.providers.hermes.historyRoots = ['~/.hermes/sessions', '~/.hermes/history'];
  config.providers.hermes.pluginRoots = ['/custom/hermes/plugins'];
  return config;
}
'''
if "function makeSyntheticLegacyConfig()" not in sg_test:
    marker = "\ntest('Skill Gardener installer runs through the isolated stock /bin/bash path'"
    if marker not in sg_test:
        raise SystemExit("Skill Gardener installer test marker not found")
    sg_test = sg_test.replace(marker, helper + marker, 1)

old_legacy_setup = """  const legacy = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  legacy.projects['lucrando-ai'].surfaces['ssh-papiro'].historyRoots = ['/srv/dev/worktrees/lucrando-ai/main/.codex/sessions'];
  legacy.projects.papiro.surfaces['ssh-papiro'].historyRoots = ['/srv/dev/worktrees/papiro/main/.codex/sessions'];
  legacy.projects['mecesa-v1'].surfaces['ssh-papiro'].roots = ['/srv/dev/worktrees/mecesa-v1/main'];
  legacy.projects['mecesa-v1'].surfaces['ssh-papiro'].historyRoots = ['/srv/dev/worktrees/mecesa-v1/main/.codex/sessions'];
  legacy.providers.hermes.historyRoots = ['~/.hermes/sessions', '~/.hermes/history'];
"""
if old_legacy_setup in sg_test:
    sg_test = sg_test.replace(old_legacy_setup, "  const legacy = makeSyntheticLegacyConfig();\n", 1)

migration_test_start = "test('installer atomically migrates only the exact legacy Skill Gardener defaults', () => {"
migration_test_end = "test('installer cleanup refuses a lock nonce mismatch', () => {"
start = sg_test.find(migration_test_start)
end = sg_test.find(migration_test_end, start)
if start < 0 or end < 0:
    raise SystemExit("Skill Gardener migration test markers not found")
new_migration_test = r'''test('installer atomically migrates only generic project-local history defaults', () => {
  const root = tempDir();
  const home = path.join(root, 'home');
  fs.mkdirSync(home, { recursive: true });
  const first = runInstallerLibrary(home);
  assert.equal(first.status, 0, first.stderr);
  const configPath = path.join(home, '.canuto', 'config', 'skill-gardener.json');
  const legacy = makeSyntheticLegacyConfig();
  writeFile(configPath, `${JSON.stringify(legacy, null, 2)}\n`);

  const migrated = runInstallerLibrary(home);
  assert.equal(migrated.status, 0, migrated.stderr);
  const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  assert.deepEqual(config.projects.alpha.surfaces.remote.historyRoots, ['~/.codex/sessions', '~/.codex/archived_sessions']);
  assert.deepEqual(config.projects.beta.surfaces.remote.historyRoots, ['~/.codex/sessions', '~/.codex/archived_sessions']);
  assert.deepEqual(config.projects.alpha.surfaces.remote.roots, ['/opt/canuto-fixtures/alpha/main']);
  assert.deepEqual(config.projects.beta.surfaces.customRemote.historyRoots, ['/custom/remote-history']);
  assert.deepEqual(config.providers.hermes.historyRoots, ['~/.hermes/sessions']);
  assert.deepEqual(config.projects.alpha.surfaces.local.historyRoots, ['/custom/history']);
  assert.deepEqual(config.providers.hermes.pluginRoots, ['/custom/hermes/plugins']);
});

'''
sg_test = sg_test[:start] + new_migration_test + sg_test[end:]
sg_test_path.write_text(sg_test, encoding="utf-8")


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
    "$SG_DEFAULT" "$FRAMEWORK_DIR/install.sh" >/dev/null 2>&1; then
  fail "20c default ou instalador contém identidade/topologia específica de máquina"
else
  pass "20c default e instalador não contêm identidade/topologia específica de máquina"
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
