#!/usr/bin/env python3
from pathlib import Path

path = Path(__file__).resolve().parent / "apply-explicit-commit-consent.py"
text = path.read_text(encoding="utf-8")
start = text.find("install_pattern = r'''")
end = text.find("\n\nupdate_pattern =", start)
if start < 0 or end < 0:
    raise SystemExit("fresh-install patch block not found")

new_block = r"""install_pattern = r'''  if \[ "\$GIT_AVAILABLE" = true \]; then\n    echo ""\n    log "Staging files for git\.\.\.".*?\n  fi(?=\n\n  echo ""\n  echo -e "\$\{GREEN\})'''
install_replacement = r'''  INSTALL_FW_VER=$(head -1 "$AGENTS_DIR/VERSION" 2>/dev/null | tr -d '[:space:]')
  [ -n "$INSTALL_FW_VER" ] || INSTALL_FW_VER="?"
  if [ "$GIT_AVAILABLE" = true ]; then
    INSTALL_COMMIT_PATHS=("${FRAMEWORK_FILES[@]}" "${INSTALL_ONLY_FILES[@]}" \
      "$CLAUDE_MD" "AGENTS.md" "CODEX.md" ".context.md" ".gitignore" \
      ".agents/plugins/.gitkeep")
    for install_vault_dir in "${VAULT_DIRS[@]}"; do
      INSTALL_COMMIT_PATHS+=("$install_vault_dir/.gitkeep")
    done
    commit_declared_paths "chore: add Canuto Framework v$INSTALL_FW_VER" \
      "${INSTALL_COMMIT_PATHS[@]}" \
      || error "Framework installation commit failed; inspect the staged paths."
  fi'''
install = sub_once(install, install_pattern, install_replacement, "fresh install commit block", re.S)"""

path.write_text(text[:start] + new_block + text[end:], encoding="utf-8")
print("consent patcher boundary fixed")
