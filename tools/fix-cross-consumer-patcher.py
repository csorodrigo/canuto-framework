#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).resolve().parent / "apply-cross-platform-release.py"
text = path.read_text(encoding="utf-8")

old_library_seam = r'''# shellcheck source=/dev/null
source "$FRAMEWORK_DIR/install.sh"

cleanup() {
'''
new_library_seam = r'''# shellcheck source=/dev/null
source "$FRAMEWORK_DIR/install.sh"
unset CANUTO_INSTALL_LIBRARY_ONLY

cleanup() {
'''
if text.count(old_library_seam) != 1:
    raise SystemExit(f"library seam expected once, found {text.count(old_library_seam)}")
text = text.replace(old_library_seam, new_library_seam, 1)

old_locals = r'''assert_consumer_green() {
  local destination="$1" slug="$2" smoke_json="$E2E_ROOT/$slug-smoke.json" check_log="$E2E_ROOT/$slug-check.log"
'''
new_locals = r'''assert_consumer_green() {
  local destination="$1"
  local slug="$2"
  local smoke_json="$E2E_ROOT/$slug-smoke.json"
  local check_log="$E2E_ROOT/$slug-check.log"
'''
if text.count(old_locals) != 1:
    raise SystemExit(f"assert_consumer_green declaration expected once, found {text.count(old_locals)}")
text = text.replace(old_locals, new_locals, 1)

old_assembly = r'''  (
    cd "$destination"
    CLAUDE_MD=CLAUDE.md
    merge_claude_md >/dev/null
    merge_agents_md >/dev/null
    render_codex_md >/dev/null
    write_source_receipt .agents/SOURCE-RECEIPT.json framework install "${FRAMEWORK_FILES[@]}" >/dev/null
  )
'''
new_assembly = r'''  (
    cd "$destination"
    CLAUDE_MD=CLAUDE.md
    merge_claude_md >/dev/null
    merge_agents_md >/dev/null
    ensure_shared_operating_contract_reference "$CLAUDE_MD" >/dev/null
    ensure_shared_operating_contract_reference "AGENTS.md" >/dev/null
    ensure_project_bootstrap_files >/dev/null
    render_codex_md >/dev/null
    setup_local_script_permissions
    write_source_receipt .agents/SOURCE-RECEIPT.json framework install "${FRAMEWORK_FILES[@]}" >/dev/null
  )
'''
assembly_count = text.count(old_assembly)
if assembly_count != 2:
    raise SystemExit(f"consumer render blocks expected twice, found {assembly_count}")
text = text.replace(old_assembly, new_assembly)

old_smoke = r'''  HOME="$E2E_HOME" CLAUDE_PROJECT_DIR="$destination" \
    /bin/bash "$destination/.agents/tools/canuto-consumer-smoke.sh" --json > "$smoke_json" \
    || fail "$slug consumer smoke failed"
  python3 - "$smoke_json" <<'PYEOF' || fail "$slug consumer smoke was not HEALTHY"
'''
new_smoke = r'''  local smoke_rc=0
  local smoke_parse_rc=0
  HOME="$E2E_HOME" CLAUDE_PROJECT_DIR="$destination" \
    /bin/bash "$destination/.agents/tools/canuto-consumer-smoke.sh" --json > "$smoke_json" \
    || smoke_rc=$?
  if [ "$smoke_rc" -ne 0 ]; then
    cat "$smoke_json" >&2 || true
    fail "$slug consumer smoke failed (rc=$smoke_rc)"
  fi
  python3 - "$smoke_json" <<'PYEOF' || smoke_parse_rc=$?
'''
if text.count(old_smoke) != 1:
    raise SystemExit(f"consumer smoke prefix expected once, found {text.count(old_smoke)}")
text = text.replace(old_smoke, new_smoke, 1)

old_smoke_tail = r'''assert result["verdict"] == "HEALTHY", result
assert result["counts"]["fail"] == 0, result
PYEOF

  (
'''
new_smoke_tail = r'''assert result["verdict"] == "HEALTHY", result
assert result["counts"]["fail"] == 0, result
PYEOF
  if [ "$smoke_parse_rc" -ne 0 ]; then
    cat "$smoke_json" >&2 || true
    fail "$slug consumer smoke was not HEALTHY"
  fi

  (
'''
if text.count(old_smoke_tail) != 1:
    raise SystemExit(f"consumer smoke heredoc tail expected once, found {text.count(old_smoke_tail)}")
text = text.replace(old_smoke_tail, new_smoke_tail, 1)

old_check_tail = r'''  grep -q "All framework files are up to date" "$check_log" || fail "$slug check lacked green receipt"
'''
new_check_tail = r'''  if ! grep -q "All framework files are up to date" "$check_log"; then
    cat "$check_log" >&2 || true
    fail "$slug check lacked green receipt"
  fi
'''
if text.count(old_check_tail) != 1:
    raise SystemExit(f"consumer check tail expected once, found {text.count(old_check_tail)}")
text = text.replace(old_check_tail, new_check_tail, 1)

path.write_text(text, encoding="utf-8")
print("cross-consumer E2E now confines library-only mode, creates project bootstrap files, and emits diagnostic failures")
