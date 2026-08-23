#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
path = root / ".agents/tools/canuto-update-all.sh"
text = path.read_text(encoding="utf-8")
old = r'''receipt_ref() {
  local receipt="$1"
  [ -f "$receipt" ] || return 1
  sed -n 's/^[[:space:]]*"sourceRef":[[:space:]]*"\([^"]*\)".*/\1/p' "$receipt" | head -1
}
'''
new = r'''receipt_ref() {
  local receipt="$1"
  [ -f "$receipt" ] || return 1
  python3 - "$receipt" <<'PYREF'
import json
import sys
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        value = json.load(fh).get("sourceRef", "")
except (OSError, ValueError, TypeError, AttributeError):
    value = ""
if isinstance(value, str) and value:
    print(value)
else:
    raise SystemExit(1)
PYREF
}
'''
if text.count(old) != 1:
    raise SystemExit(f"receipt_ref legacy parser expected once, found {text.count(old)}")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
print("update-all source receipt parser now accepts compact and pretty JSON")
