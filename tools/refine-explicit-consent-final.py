#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]

update_path = root / ".agents/tools/canuto-update-all.sh"
update = update_path.read_text(encoding="utf-8")
old = '''    if [ "$new_ver" = "$REMOTE_VERSION" ]; then
      add_report "ATUALIZADO" "$name" "$local_ver" "$new_ver" "log: $plog"
    else
'''
new = '''    commit_note=""
    [ "$COMMIT" -eq 1 ] || commit_note="; mudanças não commitadas (--commit não informado)"
    if [ "$new_ver" = "$REMOTE_VERSION" ]; then
      add_report "ATUALIZADO" "$name" "$local_ver" "$new_ver" "log: $plog$commit_note"
    else
'''
if old not in update:
    raise SystemExit("update-all success report marker not found")
update = update.replace(old, new, 1)
old_partial = '"instalador aplicado, mas VERSION não chegou a $REMOTE_VERSION — rode de novo (o install.sh do projeto foi renovado nesta rodada); log: $plog"'
new_partial = '"instalador aplicado, mas VERSION não chegou a $REMOTE_VERSION — rode de novo (o install.sh do projeto foi renovado nesta rodada); log: $plog$commit_note"'
if old_partial not in update:
    raise SystemExit("update-all partial report marker not found")
update = update.replace(old_partial, new_partial, 1)
update_path.write_text(update, encoding="utf-8")

test_path = root / "test-framework.sh"
tests = test_path.read_text(encoding="utf-8")
marker = 'PARSER_DIR="$CONSENT_ROOT/parser"\n'
if marker not in tests:
    raise SystemExit("Test 21 parser marker not found")
preservation = r'''PRESERVE_REPO="$CONSENT_ROOT/preserve-user-index"
mkdir -p "$PRESERVE_REPO"
git -C "$PRESERVE_REPO" init -q
git -C "$PRESERVE_REPO" config user.name "Canuto Consent Test"
git -C "$PRESERVE_REPO" config user.email "consent@example.invalid"
printf 'framework-initial\n' > "$PRESERVE_REPO/framework.txt"
printf 'user-initial\n' > "$PRESERVE_REPO/user.txt"
git -C "$PRESERVE_REPO" add framework.txt user.txt
git -C "$PRESERVE_REPO" commit -q -m "test: initial paths"
printf 'framework-change\n' > "$PRESERVE_REPO/framework.txt"
printf 'user-change\n' > "$PRESERVE_REPO/user.txt"
git -C "$PRESERVE_REPO" add user.txt
if (
  cd "$PRESERVE_REPO"
  export CANUTO_INSTALL_LIBRARY_ONLY=1 HOME="$CONSENT_HOME"
  source "$FRAMEWORK_DIR/install.sh"
  GIT_AVAILABLE=true
  COMMIT_CHANGES=true
  HELPER_RC=0
  commit_declared_paths "test: framework-only commit" framework.txt || HELPER_RC=$?
  rm -rf "$TMP_DIR"
  exit "$HELPER_RC"
); then
  PRESERVE_COMMIT_PATHS=$(git -C "$PRESERVE_REPO" diff-tree --no-commit-id --name-only -r HEAD | LC_ALL=C sort | tr '\n' ' ')
  PRESERVE_STAGED_PATHS=$(git -C "$PRESERVE_REPO" diff --cached --name-only | LC_ALL=C sort | tr '\n' ' ')
  if [ "$PRESERVE_COMMIT_PATHS" = "framework.txt " ] \
     && [ "$PRESERVE_STAGED_PATHS" = "user.txt " ]; then
    pass "21c commit --only preserva staging não relacionado"
  else
    fail "21c commit absorveu ou removeu staging do usuário: commit=$PRESERVE_COMMIT_PATHS staged=$PRESERVE_STAGED_PATHS"
  fi
else
  fail "21c helper de commit por paths falhou"
fi

if ! grep -Eq 'confirm_yes[[:space:]]+"Commit|read[^\n]*Commit' "$FRAMEWORK_DIR/install.sh" \
   && [ "$(grep -c 'commit_declared_paths ' "$FRAMEWORK_DIR/install.sh")" -ge 5 ]; then
  pass "21d nenhum fluxo mantém prompt de commit implícito"
else
  fail "21d prompt de commit implícito ou fluxo fora do helper ainda existe"
fi

'''
tests = tests.replace(marker, preservation + marker, 1)
# Relabel the existing subsequent assertions for readable, unique receipts.
relabels = {
    'pass "21c --help sai 0 sem mutar o diretório"': 'pass "21e --help sai 0 sem mutar o diretório"',
    'fail "21c --help falhou ou criou artefatos"': 'fail "21e --help falhou ou criou artefatos"',
    'pass "21d --dry-run resolve o modo sem mutação"': 'pass "21f --dry-run resolve o modo sem mutação"',
    'fail "21d --dry-run falhou ou criou artefatos"': 'fail "21f --dry-run falhou ou criou artefatos"',
    'pass "21e parser rejeita $PARSER_CASE antes de mutar"': 'pass "21g parser rejeita $PARSER_CASE antes de mutar"',
    'fail "21e parser $PARSER_CASE retornou $PARSER_RC ou criou artefatos"': 'fail "21g parser $PARSER_CASE retornou $PARSER_RC ou criou artefatos"',
    'pass "21f update-all não encaminha --commit por padrão"': 'pass "21h update-all não encaminha --commit por padrão"',
    'fail "21f update-all encaminhou commit implícito ou falhou"': 'fail "21h update-all encaminhou commit implícito ou falhou"',
    'pass "21g update-all encaminha --commit somente quando explícito"': 'pass "21i update-all encaminha --commit somente quando explícito"',
    'fail "21g update-all não respeitou autorização explícita"': 'fail "21i update-all não respeitou autorização explícita"',
}
for old_label, new_label in relabels.items():
    if old_label not in tests:
        raise SystemExit(f"test label not found: {old_label}")
    tests = tests.replace(old_label, new_label, 1)

old_cases = 'for PARSER_CASE in unknown missing-skill missing-api conflicting-mode conflicting-commit commit-readonly positional; do'
new_cases = 'for PARSER_CASE in unknown missing-skill missing-api conflicting-mode conflicting-commit commit-readonly dryrun-commit positional; do'
if old_cases not in tests:
    raise SystemExit("parser case list not found")
tests = tests.replace(old_cases, new_cases, 1)
old_case_arm = '    commit-readonly) PARSER_ARGS=(--check --commit) ;;\n    positional) PARSER_ARGS=(unexpected-positional) ;;'
new_case_arm = '    commit-readonly) PARSER_ARGS=(--check --commit) ;;\n    dryrun-commit) PARSER_ARGS=(--dry-run --commit) ;;\n    positional) PARSER_ARGS=(unexpected-positional) ;;'
if old_case_arm not in tests:
    raise SystemExit("parser case arm not found")
tests = tests.replace(old_case_arm, new_case_arm, 1)
test_path.write_text(tests, encoding="utf-8")

print("final explicit-consent refinement applied")
