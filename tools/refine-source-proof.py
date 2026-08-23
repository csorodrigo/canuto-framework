#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


# update-all: version/ref are routing hints; full content check is the receipt.
update_path = root / ".agents/tools/canuto-update-all.sh"
update = update_path.read_text(encoding="utf-8")
update = replace_once(
    update,
    '''  source_current=0
  if [ "$SOURCE_SUPPORTS_RECEIPT" -eq 1 ]; then
    [ "$local_ref" = "$SOURCE_REF" ] && source_current=1
  else
    source_current=1
  fi

  # Trabalho em curso''',
    '''  source_current=0
  if [ "$SOURCE_SUPPORTS_RECEIPT" -eq 1 ]; then
    [ "$local_ref" = "$SOURCE_REF" ] && source_current=1
  else
    source_current=1
  fi

  # Branches `stable` e `releases/*` são promovidas deliberadamente, mas
  # continuam sendo refs móveis do Git. Versão + nome da ref não provam que o
  # conteúdo não mudou. Antes de declarar OK, execute o check completo do
  # instalador fresco contra o mesmo source selecionado. Falha/UNKNOWN nunca é
  # verde; em árvore limpa leva ao update, em árvore suja leva a SKIP honesto.
  content_current=0
  check_log=""
  if [ "$local_ver" = "$REMOTE_VERSION" ] \
     && [ "$source_current" -eq 1 ] \
     && [ "$FORCE" = 0 ]; then
    check_log="$LOG_DIR/$PROJ_IDX-$name.check.log"
    if (cd "$proj" && bash "$FRESH_INSTALLER" --check </dev/null) >"$check_log" 2>&1; then
      content_current=1
    fi
  fi

  # Trabalho em curso''',
    "update-all full source proof",
)
update = update.replace(
    'if [ "$local_ver" = "$REMOTE_VERSION" ] && [ "$source_current" -eq 1 ] && [ "$FORCE" = 0 ]; then',
    'if [ "$local_ver" = "$REMOTE_VERSION" ] && [ "$source_current" -eq 1 ] && [ "$content_current" -eq 1 ] && [ "$FORCE" = 0 ]; then',
    2,
)
update = update.replace(
    '"já na versão e source remotos (árvore suja; source=$SOURCE_REF) — $proj"',
    '"versão, source e conteúdo comprovados (árvore suja; source=$SOURCE_REF) — $proj"',
    1,
)
update = update.replace(
    '"mudanças não commitadas — commit/stash antes — $proj"',
    '"mudanças não commitadas e update necessário/não comprovado — commit/stash antes; check: ${check_log:-não executado} — $proj"',
    1,
)
update = update.replace(
    '"já na versão e source remotos (source=$SOURCE_REF) — $proj"',
    '"versão, source e conteúdo comprovados (source=$SOURCE_REF; check=$check_log) — $proj"',
    1,
)
update_path.write_text(update, encoding="utf-8")

# Tests: make the update-all stub distinguish proof from update.
test_path = root / "test-framework.sh"
tests = test_path.read_text(encoding="utf-8")
old_stub = '''#!/usr/bin/env bash
# SOURCE-RECEIPT.json support marker
printf '%s|%s|%s|%s|%s|%s\\n' "${CANUTO_SOURCE_KIND:-}" "${CANUTO_SOURCE_REF:-}" "${CANUTO_SOURCE_CHANNEL:-}" "${CANUTO_SOURCE_VERSION:-}" "${CANUTO_SOURCE_TRANSPORT:-}" "${CANUTO_ROLLBACK_REQUESTED:-}" > .captured-source
mkdir -p .agents
'''
new_stub = '''#!/usr/bin/env bash
# SOURCE-RECEIPT.json support marker
if [ "${1:-}" = "--check" ]; then
  [ -f .source-check-ok ] && exit 0
  exit 1
fi
printf '%s|%s|%s|%s|%s|%s\\n' "${CANUTO_SOURCE_KIND:-}" "${CANUTO_SOURCE_REF:-}" "${CANUTO_SOURCE_CHANNEL:-}" "${CANUTO_SOURCE_VERSION:-}" "${CANUTO_SOURCE_TRANSPORT:-}" "${CANUTO_ROLLBACK_REQUESTED:-}" > .captured-source
mkdir -p .agents
'''
tests = replace_once(tests, old_stub, new_stub, "Test22 check-aware installer stub")

marker = 'ROLLBACK_REPO="$SOURCE_ROOT/rollback-consumer"\n'
proof_tests = r'''SAME_REF_DRIFT_REPO="$SOURCE_ROOT/same-ref-drift"
make_source_consumer "$SAME_REF_DRIFT_REPO" 9.9.9 main
if CANUTO_SOURCE_DIR="$UPDATE_SOURCE" CANUTO_VAULT_DIR="$SOURCE_ROOT/empty-vault" TMPDIR="$UPDATE_TMP" \
   /bin/bash "$FRAMEWORK_DIR/.agents/tools/canuto-update-all.sh" --channel edge "$SAME_REF_DRIFT_REPO" >/dev/null 2>&1 \
   && [ -f "$SAME_REF_DRIFT_REPO/.captured-source" ]; then
  pass "22f update-all atualiza quando VERSION/ref coincidem mas conteúdo não é provado"
else
  fail "22f update-all declarou OK sem prova completa de conteúdo"
fi

SAME_REF_OK_REPO="$SOURCE_ROOT/same-ref-ok"
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
if marker not in tests:
    raise SystemExit("Test22 rollback marker not found")
tests = tests.replace(marker, proof_tests + marker, 1)
# Renumber later Test22 receipts.
relabels = {
    'pass "22f update-all propaga rollback fixado"': 'pass "22h update-all propaga rollback fixado"',
    'fail "22f update-all não propagou rollback fixado"': 'fail "22h update-all não propagou rollback fixado"',
    'pass "22g bootstrap preserva rollback, ref fixado e transporte no instalador filho"': 'pass "22i bootstrap preserva rollback, ref fixado e transporte no instalador filho"',
    'fail "22g bootstrap perdeu rollback/ref/transporte:': 'fail "22i bootstrap perdeu rollback/ref/transporte:',
}
for old, new in relabels.items():
    if old not in tests:
        raise SystemExit(f"Test22 label not found: {old}")
    tests = tests.replace(old, new, 1)
test_path.write_text(tests, encoding="utf-8")

# ADR: explain ref mobility and the full content proof.
adr_path = root / "docs/adr/0017-stable-edge-e-source-receipt.md"
adr = adr_path.read_text(encoding="utf-8")
adr = replace_once(
    adr,
    '''- `update-all` compara versão e receipt; source divergente não é `OK`.
''',
    '''- `update-all` compara versão e receipt, mas não declara `OK` apenas com
  esses metadados: quando ambos coincidem, executa `install.sh --check` completo
  contra o source selecionado. Ref móvel com conteúdo novo não passa por verde.
''',
    "ADR full content proof",
)
adr = replace_once(
    adr,
    '''- (-) a branch `stable` e os refs `releases/*` passam a exigir promoção
  deliberada depois dos receipts de CI/canário.
''',
    '''- (-) a branch `stable` e os refs `releases/*` passam a exigir promoção
  deliberada depois dos receipts de CI/canário. São refs móveis por natureza;
  `--ref <SHA>` continua sendo o pin mais forte, e o check completo impede que
  mobilidade de branch seja confundida com conteúdo já comprovado.
''',
    "ADR ref mobility consequence",
)
adr_path.write_text(adr, encoding="utf-8")

print("source content proof refined")
