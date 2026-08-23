#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]

install_path = root / "install.sh"
install = install_path.read_text(encoding="utf-8")
parse_marker = "# ── Strict argument parsing ─────────────────────────────────────────────────\nwhile [ $# -gt 0 ]; do\n"
parse_replacement = """# ── Strict argument parsing ─────────────────────────────────────────────────
# A sourced library must not parse the caller's positional parameters as CLI
# options. Save/clear them for the library seam and restore them before return.
if [ "${CANUTO_INSTALL_LIBRARY_ONLY:-0}" = "1" ]; then
  set --
fi
while [ $# -gt 0 ]; do
"""
if parse_marker not in install:
    raise SystemExit("strict parser marker not found")
install = install.replace(parse_marker, parse_replacement, 1)

seam_marker = """if [ "${CANUTO_INSTALL_LIBRARY_ONLY:-0}" = "1" ]; then
  return 0 2>/dev/null || exit 0
fi
"""
seam_replacement = """if [ "${CANUTO_INSTALL_LIBRARY_ONLY:-0}" = "1" ]; then
  set -- "${ORIGINAL_ARGS[@]}"
  return 0 2>/dev/null || exit 0
fi
"""
if seam_marker not in install:
    raise SystemExit("library seam marker not found")
install = install.replace(seam_marker, seam_replacement, 1)
install_path.write_text(install, encoding="utf-8")

test_path = root / "test-framework.sh"
tests = test_path.read_text(encoding="utf-8")
for old, new in (
    ('--test)    MODE="test"', '--test) set_requested_mode "test"'),
    ('--repair)  MODE="repair"', '--repair) set_requested_mode "repair"'),
    ('--doctor|--health) MODE="doctor"', '--doctor|--health) set_requested_mode "doctor"'),
):
    if old not in tests:
        raise SystemExit(f"legacy static parser expectation not found: {old}")
    tests = tests.replace(old, new, 1)

region_start = tests.find("# 12f0d. Rollout mínimo")
region_end = tests.find("codex_render_tmp=$(mktemp -d)", region_start)
if region_start < 0 or region_end < 0:
    raise SystemExit("contract-only legacy test region not found")
region = tests[region_start:region_end]
count = region.count("--contract-only --yes")
if count != 3:
    raise SystemExit(f"expected 3 legacy contract commit invocations, found {count}")
region = region.replace("--contract-only --yes", "--contract-only --yes --commit")
tests = tests[:region_start] + region + tests[region_end:]
test_path.write_text(tests, encoding="utf-8")

print("explicit consent output refined")
