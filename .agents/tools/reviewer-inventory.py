#!/usr/bin/env python3
"""Inventário somente leitura: fonte, arquivo instalado e registro são estados distintos."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def inspect(root, runtime_home):
    root, runtime_home = Path(root).resolve(), Path(runtime_home).resolve()
    def fingerprint(path):
        if not path.is_file(): return None
        return hashlib.sha256(path.read_bytes()).hexdigest()
    def git(*args):
        result = subprocess.run(['git', '-C', str(root), *args], capture_output=True, text=True)
        return result.stdout.strip() if result.returncode == 0 else None
    settings = [root/'.claude/settings.json', root/'.claude/settings.local.json', runtime_home/'.claude/settings.json']
    registrations = []
    settings_states = []
    for path in settings:
        try:
            data = json.loads(path.read_text())
            settings_states.append(dict(path=str(path), state='read', sha256=fingerprint(path), disabled=data.get('disableAllHooks', False)))
            for group in data.get('hooks', {}).get('PreToolUse', []):
                for hook in group.get('hooks', []):
                    command = hook.get('command', '')
                    if hook.get('type') == 'command' and 'codex-pretool-guard.sh' in command:
                        registrations.append(dict(settings=str(path), matcher=group.get('matcher'), command=command,
                            timeout=hook.get('timeout'), disabled=data.get('disableAllHooks', False)))
        except FileNotFoundError: settings_states.append(dict(path=str(path), state='missing'))
        except (ValueError, OSError, AttributeError, TypeError): settings_states.append(dict(path=str(path), state='UNVERIFIED'))
    pairs = [('codex-pretool-guard.sh', '.agents/hooks', '.claude/hooks'),
        ('codex-common.sh', '.agents/tools', '.claude/scripts'),
        ('codex-diff-context.sh', '.agents/tools', '.claude/scripts'),
        ('codex-delegate.sh', '.agents/tools', '.codex/bin')]
    files = []
    for name, source_dir, installed_dir in pairs:
        source = root/source_dir/name; installed = runtime_home/installed_dir/name
        source_hash, installed_hash = fingerprint(source), fingerprint(installed)
        files.append(dict(name=name, source=str(source), source_sha256=source_hash, installed=str(installed),
            installed_sha256=installed_hash, state='missing' if installed_hash is None else
            'matching' if source_hash == installed_hash else 'divergent'))
    return dict(schema_version=1, root=str(root), branch=git('branch','--show-current'), head=git('rev-parse','HEAD'),
        files=files, registrations=registrations, settings=settings_states,
        models_sha256=fingerprint(root/'.agents/config/models.yaml'),
        framework_receipt_sha256=fingerprint(root/'.agents/SOURCE-RECEIPT.json'),
        review_receipt_sha256=fingerprint(root/'.agents/review-runtime-receipt.json'),
        runtime_execution='UNVERIFIED',
        consumers=['codex-pretool-guard.sh (schema + deadline)', 'codex-health-check.sh (LGTM/CONCERNS)',
            'co-review (CLI/native)', 'codex-delegate.sh (role policy)'])

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', default='.')
    parser.add_argument('--runtime-home', default=str(Path.home()))
    args=parser.parse_args()
    print(json.dumps(inspect(args.root,args.runtime_home),indent=2))
