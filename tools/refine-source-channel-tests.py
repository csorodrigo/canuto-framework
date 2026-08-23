#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[1]
path = root / "test-framework.sh"
text = path.read_text(encoding="utf-8")

old_expected = "contract_expected=$(printf '%s\\n' .agents/OPERATING-CONTRACT.md AGENTS.md CLAUDE.md | sort)"
new_expected = "contract_expected=$(printf '%s\\n' .agents/CONTRACT-RECEIPT.json .agents/OPERATING-CONTRACT.md AGENTS.md CLAUDE.md | sort)"
if old_expected not in text:
    raise SystemExit("contract-only expected pathset not found")
text = text.replace(old_expected, new_expected, 1)

old_track = '  && git -C "$contract_only_tmp" ls-files --error-unmatch .agents/OPERATING-CONTRACT.md >/dev/null 2>&1 \\\n'
new_track = '''  && git -C "$contract_only_tmp" ls-files --error-unmatch .agents/OPERATING-CONTRACT.md >/dev/null 2>&1 \\
  && git -C "$contract_only_tmp" ls-files --error-unmatch .agents/CONTRACT-RECEIPT.json >/dev/null 2>&1 \\
'''
if old_track not in text:
    raise SystemExit("contract-only tracked-file assertion not found")
text = text.replace(old_track, new_track, 1)

old_paths = '[ "$COMMIT_PATHS" = ".agents/OPERATING-CONTRACT.md AGENTS.md CLAUDE.md " ]'
new_paths = '[ "$COMMIT_PATHS" = ".agents/CONTRACT-RECEIPT.json .agents/OPERATING-CONTRACT.md AGENTS.md CLAUDE.md " ]'
if old_paths not in text:
    raise SystemExit("explicit-commit contract pathset assertion not found")
text = text.replace(old_paths, new_paths, 1)

path.write_text(text, encoding="utf-8")
print("contract provenance expectations refined")
