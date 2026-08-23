#!/usr/bin/env python3
from pathlib import Path

reference_replacements = {
    ".agents/vault/sessions/2026-03-23.md": [
        ("[[instincts/I-013-hard-gate-pattern]]", "[[instincts/I-017-hard-gate-pattern]]"),
    ],
    ".agents/vault/sessions/2026-03-23b.md": [
        ("[[design-consultation]]", "[design-consultation](../../skills/design-consultation.md)"),
        ("[[colorize]]", "[colorize](../../skills/colorize.md)"),
        ("[[typeset]]", "[typeset](../../skills/typeset.md)"),
        ("[[audit]]", "[audit](../../skills/audit.md)"),
    ],
    ".agents/vault/decisions/D-003-github-template-distribution.md": [
        ("[[decisions/D-009-stack-lock]]", "[[decisions/D-009-stack-lock-library-drift]]"),
    ],
    ".agents/vault/decisions/D-011-hard-gate-protocol.md": [
        ("[[instincts/I-013-hard-gate-pattern]]", "[[instincts/I-017-hard-gate-pattern]]"),
    ],
    ".agents/vault/decisions/D-013-skill-creator-methodology.md": [
        ("[[instincts/I-013-evals-inline-frontmatter]]", "[[instincts/I-016-evals-inline-frontmatter]]"),
        ("[[instincts/I-014-near-misses-mais-valiosos]]", "[[instincts/I-018-near-misses-mais-valiosos]]"),
    ],
}

for rel_path, replacements in reference_replacements.items():
    note_path = Path(rel_path)
    body = note_path.read_text(encoding="utf-8")
    for old, new in replacements:
        count = body.count(old)
        if count != 1:
            raise SystemExit(
                f"{rel_path}: expected one historical reference {old!r}, found {count}"
            )
        body = body.replace(old, new, 1)
    note_path.write_text(body, encoding="utf-8")

references_path = Path(".agents/hooks/check-references.sh")
references = references_path.read_text(encoding="utf-8")

old_wikilink_check = r'''    target_base="${target%%#*}"
    [ -z "$target_base" ] && continue

    if ! note_index_contains "$target_base" && \
       ! note_index_contains "$target_base.md" && \
       [ ! -f "$file_dir/$target_base" ] && \
       [ ! -f "$file_dir/$target_base.md" ] && \
       [ ! -f "$VAULT_DIR/$target_base" ] && \
       [ ! -f "$VAULT_DIR/$target_base.md" ]; then
'''
new_wikilink_check = r'''    target_base="${target%%#*}"
    [ -z "$target_base" ] && continue

    # Obsidian templates intentionally contain unresolved {{date:...}} links.
    # They are valid only inside the template directory; the same placeholder
    # in a normal note must still fail closed.
    if [[ "$file" == "$VAULT_DIR/.obsidian/templates/"* \
      && "$target_base" == *"{{"* \
      && "$target_base" == *"}}"* ]]; then
      continue
    fi

    if ! note_index_contains "$target_base" && \
       ! note_index_contains "$target_base.md" && \
       [ ! -e "$file_dir/$target_base" ] && \
       [ ! -e "$file_dir/$target_base.md" ] && \
       [ ! -e "$VAULT_DIR/$target_base" ] && \
       [ ! -e "$VAULT_DIR/$target_base.md" ]; then
'''
if references.count(old_wikilink_check) != 1:
    raise SystemExit(
        "wikilink existence block expected once, "
        f"found {references.count(old_wikilink_check)}"
    )
references = references.replace(old_wikilink_check, new_wikilink_check, 1)

old_absolute_link = r'''      if [ ! -f "$link_path_base" ]; then
'''
new_absolute_link = r'''      if [ ! -e "$link_path_base" ]; then
'''
if references.count(old_absolute_link) != 1:
    raise SystemExit(
        "absolute relative-link check expected once, "
        f"found {references.count(old_absolute_link)}"
    )
references = references.replace(old_absolute_link, new_absolute_link, 1)

old_relative_link = r'''    if [ ! -f "$file_dir/$link_path_base" ] && \
       [ ! -f "$ROOT_DIR/$link_path_base" ] && \
       [ ! -f "$VAULT_DIR/$link_path_base" ]; then
'''
new_relative_link = r'''    if [ ! -e "$file_dir/$link_path_base" ] && \
       [ ! -e "$ROOT_DIR/$link_path_base" ] && \
       [ ! -e "$VAULT_DIR/$link_path_base" ]; then
'''
if references.count(old_relative_link) != 1:
    raise SystemExit(
        "relative-link existence block expected once, "
        f"found {references.count(old_relative_link)}"
    )
references = references.replace(old_relative_link, new_relative_link, 1)
references_path.write_text(references, encoding="utf-8")

tests_path = Path("test-framework.sh")
tests = tests_path.read_text(encoding="utf-8")

old_reference_fixture = r'''PORTABILITY_HOME="$(mktemp -d)"
mkdir -p "$PORTABILITY_HOME/.canuto/vault"
cat > "$PORTABILITY_HOME/.canuto/vault/A.md" <<'EOF'
[[B]]
[Local](B.md)
EOF
cat > "$PORTABILITY_HOME/.canuto/vault/B.md" <<'EOF'
[[A]]
EOF

if HOME="$PORTABILITY_HOME" CLAUDE_PROJECT_DIR="$FRAMEWORK_DIR" bash "$AGENTS_DIR/hooks/check-references.sh" >/dev/null 2>&1; then
  pass "check-references.sh portable runtime"
else
  fail "check-references.sh portable runtime failed"
fi

if HOME="$PORTABILITY_HOME" CLAUDE_PROJECT_DIR="$FRAMEWORK_DIR" bash "$AGENTS_DIR/hooks/check-orphans.sh" >/dev/null 2>&1; then
  pass "check-orphans.sh portable runtime"
else
  fail "check-orphans.sh portable runtime failed"
fi

rm -rf "$PORTABILITY_HOME"
'''
new_reference_fixture = r'''PORTABILITY_HOME="$(mktemp -d)"
mkdir -p \
  "$PORTABILITY_HOME/.canuto/vault/.obsidian/templates" \
  "$PORTABILITY_HOME/.canuto/vault/sessions"
cat > "$PORTABILITY_HOME/.canuto/vault/A.md" <<'EOF'
[[B]]
[Local](B.md)
[[sessions/]]
EOF
cat > "$PORTABILITY_HOME/.canuto/vault/B.md" <<'EOF'
[[A]]
EOF
cat > "$PORTABILITY_HOME/.canuto/vault/.obsidian/templates/session.md" <<'EOF'
[[sessions/{{date:YYYY-MM-DD}}]]
EOF

if HOME="$PORTABILITY_HOME" CLAUDE_PROJECT_DIR="$FRAMEWORK_DIR" bash "$AGENTS_DIR/hooks/check-references.sh" >/dev/null 2>&1; then
  pass "check-references.sh accepts notes, directory navigation and template placeholders"
else
  fail "check-references.sh rejected a valid portable vault fixture"
fi

cat > "$PORTABILITY_HOME/.canuto/vault/Broken.md" <<'EOF'
[[definitely-missing-note]]
EOF
if HOME="$PORTABILITY_HOME" CLAUDE_PROJECT_DIR="$FRAMEWORK_DIR" bash "$AGENTS_DIR/hooks/check-references.sh" >/dev/null 2>&1; then
  fail "check-references.sh accepted a genuinely broken wikilink"
else
  pass "check-references.sh still fails closed for a genuinely broken wikilink"
fi
rm -f "$PORTABILITY_HOME/.canuto/vault/Broken.md"
rm -rf "$PORTABILITY_HOME/.canuto/vault/.obsidian"

if HOME="$PORTABILITY_HOME" CLAUDE_PROJECT_DIR="$FRAMEWORK_DIR" bash "$AGENTS_DIR/hooks/check-orphans.sh" >/dev/null 2>&1; then
  pass "check-orphans.sh portable runtime"
else
  fail "check-orphans.sh portable runtime failed"
fi

rm -rf "$PORTABILITY_HOME"
'''
if tests.count(old_reference_fixture) != 1:
    raise SystemExit(
        "portable reference fixture expected once, "
        f"found {tests.count(old_reference_fixture)}"
    )
tests = tests.replace(old_reference_fixture, new_reference_fixture, 1)
tests_path.write_text(tests, encoding="utf-8")

print(
    "vault references migrated; directory navigation and template placeholders "
    "are accepted without weakening broken-link failures"
)
