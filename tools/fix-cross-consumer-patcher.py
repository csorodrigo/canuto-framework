#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).resolve().parent / "apply-cross-platform-release.py"
text = path.read_text(encoding="utf-8")

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
    render_codex_md >/dev/null
    setup_local_script_permissions
    write_source_receipt .agents/SOURCE-RECEIPT.json framework install "${FRAMEWORK_FILES[@]}" >/dev/null
  )
'''
if text.count(old_assembly) != 1:
    raise SystemExit(f"consumer assembly block expected once, found {text.count(old_assembly)}")
text = text.replace(old_assembly, new_assembly, 1)

old_smoke = r'''  HOME="$E2E_HOME" CLAUDE_PROJECT_DIR="$destination" \
    /bin/bash "$destination/.agents/tools/canuto-consumer-smoke.sh" --json > "$smoke_json" \
    || fail "$slug consumer smoke failed"
  python3 - "$smoke_json" <<'PYEOF' || fail "$slug consumer smoke was not HEALTHY"
'''
new_smoke = r'''  local smoke_rc=0
  HOME="$E2E_HOME" CLAUDE_PROJECT_DIR="$destination" \
    /bin/bash "$destination/.agents/tools/canuto-consumer-smoke.sh" --json > "$smoke_json" \
    || smoke_rc=$?
  if [ "$smoke_rc" -ne 0 ]; then
    cat "$smoke_json" >&2 || true
    fail "$slug consumer smoke failed (rc=$smoke_rc)"
  fi
  python3 - "$smoke_json" <<'PYEOF' || {
    cat "$smoke_json" >&2 || true
    fail "$slug consumer smoke was not HEALTHY"
  }
'''
if text.count(old_smoke) != 1:
    raise SystemExit(f"consumer smoke block expected once, found {text.count(old_smoke)}")
text = text.replace(old_smoke, new_smoke, 1)

path.write_text(text, encoding="utf-8")
print("cross-consumer assembly now enforces contract references, permissions, and diagnostic smoke output")
