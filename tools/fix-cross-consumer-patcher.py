#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).resolve().parent / "apply-cross-platform-release.py"
text = path.read_text(encoding="utf-8")
old = r'''assert_consumer_green() {
  local destination="$1" slug="$2" smoke_json="$E2E_ROOT/$slug-smoke.json" check_log="$E2E_ROOT/$slug-check.log"
'''
new = r'''assert_consumer_green() {
  local destination="$1"
  local slug="$2"
  local smoke_json="$E2E_ROOT/$slug-smoke.json"
  local check_log="$E2E_ROOT/$slug-check.log"
'''
if text.count(old) != 1:
    raise SystemExit(f"assert_consumer_green declaration expected once, found {text.count(old)}")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
print("cross-consumer derived locals now initialize after slug")
