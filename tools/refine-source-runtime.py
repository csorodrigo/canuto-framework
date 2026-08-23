#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected one match, found {count}")
    return text.replace(old, new, 1)


# install.sh -----------------------------------------------------------------
install_path = root / "install.sh"
install = install_path.read_text(encoding="utf-8")
install = replace_once(
    install,
    'SOURCE_TRANSPORT=""\n',
    'SOURCE_TRANSPORT="${CANUTO_SOURCE_TRANSPORT:-}"\n',
    "installer inherited source transport",
)
install = replace_once(
    install,
    'ROLLBACK_REQUESTED=false\n',
    'ROLLBACK_REQUESTED="${CANUTO_ROLLBACK_REQUESTED:-false}"\n',
    "installer inherited rollback intent",
)
install = replace_once(
    install,
    '''  local env_version="${CANUTO_SOURCE_VERSION:-${CANUTO_VERSION:-}}"

  if [ -n "$REPO_URL_OVERRIDE" ]; then
''',
    '''  local env_version="${CANUTO_SOURCE_VERSION:-${CANUTO_VERSION:-}}"

  case "$ROLLBACK_REQUESTED" in
    true|false) ;;
    *) usage_error "CANUTO_ROLLBACK_REQUESTED must be true or false" ;;
  esac

  if [ -n "$REPO_URL_OVERRIDE" ]; then
''',
    "installer rollback env validation",
)
install = replace_once(
    install,
    '''    REPO_URL="${REPO_URL_OVERRIDE%/}"
    SOURCE_TRANSPORT="custom-url"
    return 0
''',
    '''    REPO_URL="${REPO_URL_OVERRIDE%/}"
    if [ -z "$SOURCE_TRANSPORT" ]; then
      if [ -n "$SOURCE_DIR" ]; then SOURCE_TRANSPORT="local"; else SOURCE_TRANSPORT="custom-url"; fi
    fi
    return 0
''',
    "installer override transport",
)
install = replace_once(
    install,
    '''  REPO_URL="${REPO_BASE%/}/$SOURCE_REF"
  if [ -n "$SOURCE_DIR" ]; then SOURCE_TRANSPORT="local"; else SOURCE_TRANSPORT="raw-github"; fi
''',
    '''  REPO_URL="${REPO_BASE%/}/$SOURCE_REF"
  if [ -z "$SOURCE_TRANSPORT" ]; then
    if [ -n "$SOURCE_DIR" ]; then
      SOURCE_TRANSPORT="local"
    elif [ "$REPO_BASE" = "https://raw.githubusercontent.com/csorodrigo/canuto-framework" ]; then
      SOURCE_TRANSPORT="raw-github"
    else
      SOURCE_TRANSPORT="remote-url"
    fi
  fi
''',
    "installer resolved transport",
)
install = replace_once(
    install,
    '''      CANUTO_SOURCE_CHANNEL="$SOURCE_CHANNEL" \
      CANUTO_SOURCE_VERSION="$SOURCE_VERSION" \
      bash "$remote_installer" "${REFRESH_ARGS[@]}"
''',
    '''      CANUTO_SOURCE_CHANNEL="$SOURCE_CHANNEL" \
      CANUTO_SOURCE_VERSION="$SOURCE_VERSION" \
      CANUTO_SOURCE_TRANSPORT="$SOURCE_TRANSPORT" \
      CANUTO_ROLLBACK_REQUESTED="$ROLLBACK_REQUESTED" \
      bash "$remote_installer" "${REFRESH_ARGS[@]}"
''',
    "installer child provenance propagation",
)
install_path.write_text(install, encoding="utf-8")

# update-all ----------------------------------------------------------------
update_path = root / ".agents/tools/canuto-update-all.sh"
update = update_path.read_text(encoding="utf-8")
update = replace_once(
    update,
    'SOURCE_VERSION=""\nCLI_SOURCE_SELECTOR_COUNT=0\n',
    'SOURCE_VERSION=""\nSOURCE_TRANSPORT="${CANUTO_SOURCE_TRANSPORT:-}"\nCLI_SOURCE_SELECTOR_COUNT=0\n',
    "update-all transport state",
)
update = replace_once(
    update,
    '''  local env_version="${CANUTO_SOURCE_VERSION:-${CANUTO_VERSION:-}}"
  if [ -n "$REPO_URL_OVERRIDE" ]; then
''',
    '''  local env_version="${CANUTO_SOURCE_VERSION:-${CANUTO_VERSION:-}}"
  if [ -n "$REPO_URL_OVERRIDE" ]; then
''',
    "update-all resolve header",
)
update = replace_once(
    update,
    '''    SOURCE_CHANNEL="$env_channel"; SOURCE_VERSION="$env_version"
    REPO_RAW="${REPO_URL_OVERRIDE%/}"
    return 0
''',
    '''    SOURCE_CHANNEL="$env_channel"; SOURCE_VERSION="$env_version"
    REPO_RAW="${REPO_URL_OVERRIDE%/}"
    if [ -z "$SOURCE_TRANSPORT" ]; then
      if [ -n "${CANUTO_SOURCE_DIR:-}" ]; then SOURCE_TRANSPORT="local"; else SOURCE_TRANSPORT="custom-url"; fi
    fi
    return 0
''',
    "update-all override transport",
)
update = replace_once(
    update,
    '''  validate_ref "$SOURCE_REF" || { err "source ref resolvida é inválida: $SOURCE_REF"; exit 64; }
  REPO_RAW="${REPO_BASE%/}/$SOURCE_REF"
}
''',
    '''  validate_ref "$SOURCE_REF" || { err "source ref resolvida é inválida: $SOURCE_REF"; exit 64; }
  REPO_RAW="${REPO_BASE%/}/$SOURCE_REF"
  if [ -z "$SOURCE_TRANSPORT" ]; then
    if [ -n "${CANUTO_SOURCE_DIR:-}" ]; then
      SOURCE_TRANSPORT="local"
    elif [ "$REPO_BASE" = "https://raw.githubusercontent.com/csorodrigo/canuto-framework" ]; then
      SOURCE_TRANSPORT="raw-github"
    else
      SOURCE_TRANSPORT="remote-url"
    fi
  fi
}
''',
    "update-all resolved transport",
)
update = replace_once(
    update,
    '''export CANUTO_SOURCE_CHANNEL="$SOURCE_CHANNEL"
export CANUTO_SOURCE_VERSION="$SOURCE_VERSION"
SOURCE_SUPPORTS_RECEIPT=0
''',
    '''export CANUTO_SOURCE_CHANNEL="$SOURCE_CHANNEL"
export CANUTO_SOURCE_VERSION="$SOURCE_VERSION"
export CANUTO_SOURCE_TRANSPORT="$SOURCE_TRANSPORT"
if [ "$ROLLBACK" -eq 1 ]; then
  export CANUTO_ROLLBACK_REQUESTED=true
else
  export CANUTO_ROLLBACK_REQUESTED=false
fi
SOURCE_SUPPORTS_RECEIPT=0
''',
    "update-all provenance env",
)
update = update.replace(
    "# DENTRO do projeto (o instalador do projeto se auto-atualiza do main antes de\n",
    "# DENTRO do projeto usando o instalador fresco do source ref selecionado.\n",
    1,
)
update_path.write_text(update, encoding="utf-8")

# test-framework.sh ----------------------------------------------------------
test_path = root / "test-framework.sh"
tests = test_path.read_text(encoding="utf-8")
tests = replace_once(
    tests,
    '''printf '%s|%s|%s|%s\\n' "${CANUTO_SOURCE_KIND:-}" "${CANUTO_SOURCE_REF:-}" "${CANUTO_SOURCE_CHANNEL:-}" "${CANUTO_SOURCE_VERSION:-}" > .captured-source
''',
    '''printf '%s|%s|%s|%s|%s|%s\\n' "${CANUTO_SOURCE_KIND:-}" "${CANUTO_SOURCE_REF:-}" "${CANUTO_SOURCE_CHANNEL:-}" "${CANUTO_SOURCE_VERSION:-}" "${CANUTO_SOURCE_TRANSPORT:-}" "${CANUTO_ROLLBACK_REQUESTED:-}" > .captured-source
''',
    "test source capture fields",
)
tests = replace_once(
    tests,
    '[ "$(cat "$EDGE_REPO/.captured-source")" = "edge|main|edge|" ]',
    '[ "$(cat "$EDGE_REPO/.captured-source")" = "edge|main|edge||local|false" ]',
    "test edge provenance",
)
tests = replace_once(
    tests,
    '[ "$(cat "$ROLLBACK_REPO/.captured-source")" = "version|releases/1.7.0||1.7.0" ]',
    '[ "$(cat "$ROLLBACK_REPO/.captured-source")" = "version|releases/1.7.0||1.7.0|local|true" ]',
    "test rollback provenance",
)

insert_marker = 'rm -rf "$SOURCE_ROOT"\necho ""\n# ═══════════════════════════════════════════════════════════════════════════\n# SUMMARY\n'
bootstrap_test = r'''BOOTSTRAP_SOURCE="$SOURCE_ROOT/bootstrap-source"
BOOTSTRAP_WORK="$SOURCE_ROOT/bootstrap-work"
BOOTSTRAP_CAPTURE="$SOURCE_ROOT/bootstrap-capture"
mkdir -p "$BOOTSTRAP_SOURCE/releases/1.7.0" "$BOOTSTRAP_WORK"
cat > "$BOOTSTRAP_SOURCE/releases/1.7.0/install.sh" <<'BOOTEOF'
#!/usr/bin/env bash
printf '%s|%s|%s|%s|%s|%s\n' "${CANUTO_SOURCE_KIND:-}" "${CANUTO_SOURCE_REF:-}" "${CANUTO_SOURCE_CHANNEL:-}" "${CANUTO_SOURCE_VERSION:-}" "${CANUTO_SOURCE_TRANSPORT:-}" "${CANUTO_ROLLBACK_REQUESTED:-}" > "$CANUTO_BOOTSTRAP_CAPTURE"
BOOTEOF
chmod +x "$BOOTSTRAP_SOURCE/releases/1.7.0/install.sh"
if (cd "$BOOTSTRAP_WORK" \
    && HOME="$SOURCE_HOME" \
       CANUTO_REPO_BASE="file://$BOOTSTRAP_SOURCE" \
       CANUTO_BOOTSTRAP_CAPTURE="$BOOTSTRAP_CAPTURE" \
       /bin/bash "$FRAMEWORK_DIR/install.sh" --rollback 1.7.0 --yes </dev/null >/dev/null 2>&1) \
   && [ "$(cat "$BOOTSTRAP_CAPTURE" 2>/dev/null)" = "version|releases/1.7.0||1.7.0|remote-url|true" ]; then
  pass "22g bootstrap preserva rollback, ref fixado e transporte no instalador filho"
else
  fail "22g bootstrap perdeu rollback/ref/transporte: $(cat "$BOOTSTRAP_CAPTURE" 2>/dev/null || echo ausente)"
fi

'''
if insert_marker not in tests:
    raise SystemExit("Test 22 summary boundary not found")
tests = tests.replace(insert_marker, bootstrap_test + insert_marker, 1)
tests = tests.replace(
    'pass "21b --commit cria um commit limitado aos três paths declarados"',
    'pass "21b --commit cria um commit limitado aos paths declarados"',
    1,
)
test_path.write_text(tests, encoding="utf-8")

# ADR -----------------------------------------------------------------------
adr_path = root / "docs/adr/0017-stable-edge-e-source-receipt.md"
adr = adr_path.read_text(encoding="utf-8")
adr = replace_once(
    adr,
    '''- O bootstrap remove os seletores da argv do instalador filho e propaga o
  endpoint/ref por ambiente, mantendo compatibilidade com instaladores antigos.
''',
    '''- O bootstrap remove os seletores da argv do instalador filho e propaga o
  endpoint/ref, o transporte e a intenção de rollback por ambiente, mantendo
  compatibilidade com instaladores antigos.
''',
    "ADR bootstrap provenance",
)
adr_path.write_text(adr, encoding="utf-8")

print("source runtime provenance refined")
