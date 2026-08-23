#!/usr/bin/env python3
from pathlib import Path

path = Path("test-framework.sh")
text = path.read_text(encoding="utf-8")

old = r'''  (cd "$SOURCE_EMPTY" && env HOME="$SOURCE_HOME" "${SOURCE_ENV[@]}" /bin/bash "$FRAMEWORK_DIR/install.sh" "${SOURCE_ARGS[@]}" >/dev/null 2>&1) || SOURCE_RC=$?
'''
new = r'''  # Bash 3.2 + `set -u` rejects expansion of SOURCE_ENV when the
  # environment list is intentionally empty. Keep the exact same parser cases,
  # but call env without an empty-array expansion in that branch.
  if [ "${#SOURCE_ENV[@]}" -gt 0 ]; then
    (cd "$SOURCE_EMPTY" && env HOME="$SOURCE_HOME" "${SOURCE_ENV[@]}" /bin/bash "$FRAMEWORK_DIR/install.sh" "${SOURCE_ARGS[@]}" >/dev/null 2>&1) || SOURCE_RC=$?
  else
    (cd "$SOURCE_EMPTY" && env HOME="$SOURCE_HOME" /bin/bash "$FRAMEWORK_DIR/install.sh" "${SOURCE_ARGS[@]}" >/dev/null 2>&1) || SOURCE_RC=$?
  fi
'''
count = text.count(old)
if count != 1:
    raise SystemExit(f"SOURCE_ENV invocation expected once, found {count}")

path.write_text(text.replace(old, new, 1), encoding="utf-8")
print("test-framework source-env fixture is portable to Bash 3.2")
