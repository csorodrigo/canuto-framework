#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).resolve().parent / "refine-source-proof.py"
text = path.read_text(encoding="utf-8")
old = r'''SAME_REF_OK_REPO="$SOURCE_ROOT/same-ref-ok"
make_source_consumer "$SAME_REF_OK_REPO" 9.9.9 main
touch "$SAME_REF_OK_REPO/.source-check-ok"
if CANUTO_SOURCE_DIR="$UPDATE_SOURCE" CANUTO_VAULT_DIR="$SOURCE_ROOT/empty-vault" TMPDIR="$UPDATE_TMP" \
   /bin/bash "$FRAMEWORK_DIR/.agents/tools/canuto-update-all.sh" --channel edge "$SAME_REF_OK_REPO" >/dev/null 2>&1 \
   && [ ! -e "$SAME_REF_OK_REPO/.captured-source" ]; then
  pass "22g update-all pula somente após check completo verde"
else
  fail "22g update-all ignorou check verde ou executou update desnecessário"
fi
'''
new = r'''SAME_REF_OK_REPO="$SOURCE_ROOT/same-ref-ok"
make_source_consumer "$SAME_REF_OK_REPO" 9.9.9 main
touch "$SAME_REF_OK_REPO/.source-check-ok"
git -C "$SAME_REF_OK_REPO" add .source-check-ok
git -C "$SAME_REF_OK_REPO" commit -q -m "test: full source check is green"
SOURCE_OK_RC=0
SOURCE_OK_OUTPUT=$(CANUTO_SOURCE_DIR="$UPDATE_SOURCE" CANUTO_VAULT_DIR="$SOURCE_ROOT/empty-vault" TMPDIR="$UPDATE_TMP" \
   /bin/bash "$FRAMEWORK_DIR/.agents/tools/canuto-update-all.sh" --channel edge "$SAME_REF_OK_REPO" 2>&1) || SOURCE_OK_RC=$?
if [ "$SOURCE_OK_RC" -eq 0 ] && [ ! -e "$SAME_REF_OK_REPO/.captured-source" ]; then
  pass "22g update-all pula somente após check completo verde"
else
  fail "22g update-all ignorou check verde ou executou update desnecessário (rc=$SOURCE_OK_RC): $SOURCE_OK_OUTPUT"
fi
'''
if old not in text:
    raise SystemExit("source-proof green fixture block not found")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
print("source-proof green fixture made tracked and diagnostic")
