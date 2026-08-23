#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_region(path: str, start_marker: str, end_marker: str, replacement: str) -> None:
    target = ROOT / path
    text = target.read_text(encoding="utf-8")
    start = text.find(start_marker)
    end = text.find(end_marker, start)
    if start < 0 or end < 0:
        raise SystemExit(f"markers not found in {path}")
    target.write_text(text[:start] + replacement + text[end:], encoding="utf-8")


migration = r'''skill_gardener_migrate_legacy_config() {
  local library_file="$1"
  local config_file="$2"
  local candidate_file="$3"

  # A config efetiva é propriedade da máquina. O instalador valida, mas não
  # reescreve uma configuração válida — nem mesmo quando reconhece um shape
  # antigo. Correções de topologia pertencem ao onboarding/local config, não
  # ao genótipo distribuível do framework (ADR-0003).
  rm -f -- "$candidate_file" 2>/dev/null || true
  validate_skill_gardener_config "$library_file" "$config_file"
}

'''
replace_region(
    "install.sh",
    "skill_gardener_migrate_legacy_config() {\n",
    "setup_skill_gardener() {\n",
    migration,
)

path = ROOT / "skill-gardener/canuto-skill-gardener.test.js"
text = path.read_text(encoding="utf-8")
start_marker = "test('installer atomically migrates only generic project-local history defaults', () => {"
end_marker = "test('installer cleanup refuses a lock nonce mismatch', () => {"
start = text.find(start_marker)
end = text.find(end_marker, start)
if start < 0 or end < 0:
    raise SystemExit("migration test markers not found")
replacement = r'''test('installer preserves existing valid machine-owned config byte-for-byte', () => {
  const root = tempDir();
  const home = path.join(root, 'home');
  fs.mkdirSync(home, { recursive: true });
  const first = runInstallerLibrary(home);
  assert.equal(first.status, 0, first.stderr);
  const configPath = path.join(home, '.canuto', 'config', 'skill-gardener.json');
  const machineOwned = makeSyntheticLegacyConfig();
  writeFile(configPath, `${JSON.stringify(machineOwned, null, 2)}\n`);
  const original = fs.readFileSync(configPath);

  const activated = runInstallerLibrary(home);
  assert.equal(activated.status, 0, activated.stderr);
  assert.deepEqual(fs.readFileSync(configPath), original);
  assert.deepEqual(fs.readdirSync(path.dirname(configPath)).filter((name) => name.includes('.tmp-migrate-')), []);
});

'''
path.write_text(text[:start] + replacement + text[end:], encoding="utf-8")

adr_path = ROOT / "docs/adr/0003-cegueira-de-identidade-no-genotipo.md"
adr = adr_path.read_text(encoding="utf-8")
old = "- Defaults instaláveis e configurações bootstrap são identidade-cegas: projetos, hosts e paths reais vivem somente em `~/.canuto/config/`.\n"
new = old + "- Configuração local válida é propriedade da máquina: o instalador valida e preserva seus bytes; não migra topologia ou paths silenciosamente.\n"
if old not in adr:
    raise SystemExit("ADR identity-default bullet not found")
if "Configuração local válida é propriedade da máquina" not in adr:
    adr = adr.replace(old, new, 1)
    adr_path.write_text(adr, encoding="utf-8")

print("identity preservation refinement applied")
