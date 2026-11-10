#!/usr/bin/env bash
# Congela o candidato em objetos Git antes de construir qualquer parte do review.
set -euo pipefail
common_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/codex-common.sh"
[ -f "$common_script" ] || common_script="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/scripts/codex-common.sh"
exec python3 - "$common_script" "$@" <<'PY'
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

common_script = sys.argv.pop(1)
parser = argparse.ArgumentParser()
modes = parser.add_mutually_exclusive_group()
modes.add_argument('--staged', action='store_true')
modes.add_argument('--uncommitted', action='store_true')
modes.add_argument('--commit-candidate', choices=('index', 'all-tracked'))
modes.add_argument('--base')
parser.add_argument('--output')
parser.add_argument('--receipt')
parser.add_argument('--max-output-bytes', type=int, default=int(os.environ.get('CODEX_DIFF_MAX_TOTAL_BYTES', '420000')))
args = parser.parse_args()
root = os.environ.get('CLAUDE_PROJECT_DIR', os.getcwd())
# Variáveis de outra worktree não podem trocar o repositório ou o índice revisado.
env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
env.update(GIT_CONFIG_NOSYSTEM='1', GIT_LITERAL_PATHSPECS='1')
def git(*command, data=None, index=None):
    call_env = dict(env)
    if index is not None: call_env['GIT_INDEX_FILE'] = str(index)
    return subprocess.check_output(['git', '-c', 'core.fsmonitor=false', '-c', 'diff.external=',
        '-c', 'core.quotePath=true', *command], cwd=root, env=call_env, input=data, stderr=subprocess.PIPE)
def oid(*command, **kwargs): return git(*command, **kwargs).decode().strip()
def limit(name, default):
    value = int(os.environ.get(name, str(default)))
    if value < 0: raise ValueError('negative context budget')
    return value

def sensitive_paths(paths):
    # A mesma política do hook, incluindo adaptações locais do consumidor.
    script = 'source "$1"; while IFS= read -r -d "" path; do if codex_is_security_sensitive_path "$path"; then printf "1\\0"; else printf "0\\0"; fi; done'
    payload = b''.join(os.fsencode(path) + b'\0' for path in paths)
    result = subprocess.run(['bash', '-c', script, 'review-policy', common_script],
        input=payload, capture_output=True, check=True)
    flags = result.stdout.split(b'\0')[:-1]
    if len(flags) != len(paths) or any(flag not in (b'0', b'1') for flag in flags):
        raise ValueError('invalid path classification')
    return {path: flag == b'1' for path, flag in zip(paths, flags)}

def mask(text):
    if os.environ.get('CODEX_DIFF_MASK_SECRETS', 'true').lower() in ('false', '0'): return text
    text = re.sub(r'(api[_-]?key|secret|token|password|bearer|credentials?)\s*[:=]\s*"?[A-Za-z0-9+/_.~-]{8,}"?', r'\1=<REDACTED>', text, flags=re.I)
    for pattern in (r'(?:sk_live_|pk_live_|sk_test_|pk_test_|xox[bpsar])-[A-Za-z0-9]{8,}',
        r'gh[po]_[A-Za-z0-9]{36,}', r'github_pat_[A-Za-z0-9_]{20,}',
        r'eyJ[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{15,}'):
        text = re.sub(pattern, '<REDACTED_KEY>', text)
    return text

def save(path, data):
    target = Path(path)
    with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as handle:
        temporary = Path(handle.name)
        handle.write(data)
    try: os.replace(temporary, target)
    finally: temporary.unlink(missing_ok=True)

try:
    root = oid('rev-parse', '--show-toplevel')
    empty = oid('hash-object', '-t', 'tree', '--stdin', data=b'')
    try: head = oid('rev-parse', '--verify', 'HEAD^{commit}')
    except subprocess.CalledProcessError: head = None
    base_commit = merge_base = None
    if args.base:
        mode = 'base'
        base_commit = oid('rev-parse', '--verify', args.base + '^{commit}')
        merge_base = oid('merge-base', base_commit, head or 'HEAD')
        before = oid('rev-parse', merge_base + '^{tree}')
        candidate = oid('rev-parse', (head or 'HEAD') + '^{tree}')
    else:
        mode = 'uncommitted' if args.uncommitted else 'commit-candidate' if args.commit_candidate else 'staged'
        # Copiar o índice evita que write-tree atualize inclusive o cache do índice real.
        index_path = Path(oid('rev-parse', '--git-path', 'index'))
        if not index_path.is_absolute(): index_path = Path(root) / index_path
        with tempfile.TemporaryDirectory(prefix='codex-review-index-') as temp:
            index = Path(temp) / 'index'
            if index_path.exists(): index.write_bytes(index_path.read_bytes())
            else: git('read-tree', empty, index=index)
            staged = oid('write-tree', index=index)
            before = staged if args.uncommitted else oid('rev-parse', head + '^{tree}') if head else empty
            if args.uncommitted or args.commit_candidate == 'all-tracked':
                git('add', '-u', '--', '.', index=index)
            candidate = oid('write-tree', index=index)
    context = limit('CODEX_DIFF_CONTEXT_LINES', 3)
    max_files = limit('CODEX_DIFF_MAX_FILES', 40)
    max_lines = limit('CODEX_DIFF_MAX_LINES', 8000)
    max_bytes = limit('CODEX_DIFF_MAX_BYTES', 400000)
    if args.max_output_bytes <= 0: raise ValueError('invalid total budget')
    raw = git('diff', '--name-status', '-z', '-M', before, candidate).split(b'\0')
    gitlink_paths = set()
    for tree in (before, candidate):
        for item in git('ls-tree', '-rz', tree).split(b'\0'):
            if item:
                metadata, path = item.split(b'\t', 1)
                if metadata.split()[0] == b'160000': gitlink_paths.add(os.fsdecode(path))
    changes = []
    while raw and raw[0]:
        status = raw.pop(0).decode()
        paths = [os.fsdecode(raw.pop(0))]
        if status[0] in ('R', 'C'): paths.append(os.fsdecode(raw.pop(0)))
        changes.append((status, paths))
    classification = sensitive_paths(list(dict.fromkeys(path for _, paths in changes for path in paths)))
    entries = []
    for status, paths in changes:
        patch = mask(git('diff', '--no-ext-diff', '--no-textconv', '--no-color', '-M', f'-U{context}',
            before, candidate, '--', *paths).decode('utf-8', errors='replace'))
        label = ' → '.join(json.dumps(path, ensure_ascii=True) for path in paths)
        entry = dict(paths=paths, label=label, status=status, patch=patch,
            lines=len(patch.splitlines()), bytes=len(patch.encode()), sensitive=any(classification[path] for path in paths),
            signatures='', binary='Binary files ' in patch, gitlink=any(path in gitlink_paths for path in paths))
        if status[0] != 'D' and not entry['binary'] and not entry['gitlink']:
            blob = git('show', candidate + ':' + paths[-1]).decode('utf-8', errors='replace')
            identifiers = set(re.findall(r'\b[A-Za-z_][A-Za-z_0-9]*\b', '\n'.join(
                line for line in patch.splitlines() if line[:1] in ('+', '-') and line[:3] not in ('+++', '---'))))
            signatures = []
            for number, line in enumerate(blob.splitlines(), 1):
                match = re.match(r'^\s*(?:export\s+)?(?:(?:async\s+)?function|type|interface|enum|class|const|let|var)\s+([A-Za-z_][A-Za-z_0-9]*)', line)
                if match and match[1] in identifiers:
                    signatures.append(f'{number}:{mask(line)}')
                    if len(signatures) >= 20: break
            if signatures:
                entry['signatures'] = '\n### ' + label + '\n```text\n' + '\n'.join(signatures) + '\n```\n'
        entries.append(entry)
    identity = dict(mode=mode, head_sha=head, base_sha=base_commit, merge_base_sha=merge_base,
        base_tree=before, candidate_tree=candidate, signature_tree=candidate)
    selected = set()
    def render():
        omitted = [entry for i, entry in enumerate(entries) if i not in selected]
        lines = ['# Compressed Diff Context', '', '## Review Scope']
        lines += [f'- {key}: {value or "none"}' for key, value in identity.items()]
        if args.commit_candidate: lines.append('- commit_target: ' + args.commit_candidate)
        lines += [f'- files: {len(entries)}', f'- files_in_patch: {len(entries)}',
            f'- files_included_full: {len(selected)}', f'- files_omitted: {len(omitted)}',
            '- sensitive_files_omitted: ' + str(any(entry['sensitive'] for entry in omitted)).lower(),
            '- coverage: ' + ('partial' if omitted or any(entry['gitlink'] for entry in entries) else 'complete'),
            f'- budget: {max_files} files / {max_lines} patch lines / {max_bytes} patch bytes / {args.max_output_bytes} total bytes',
            '', '## Diff Summary']
        lines += [f'- {entry["status"]} {entry["label"]}' for entry in entries]
        lines += ['', '## Patch Excerpt', '_Included files have complete hunks; omitted files were NOT reviewed._', '```diff']
        lines += [entry['patch'].rstrip('\n') for i, entry in enumerate(entries) if i in selected]
        if not entries: lines.append('No changes detected.')
        lines += ['```', '']
        if omitted:
            lines += ['## Omitted Files (not reviewed)']
            lines += [f'- {entry["label"]} ({entry["lines"]} diff lines)' + (' [SECURITY-SENSITIVE]' if entry['sensitive'] else '')
                + (' [BINARY: content not reviewed]' if entry['binary'] else ' [context budget]') for entry in omitted]
        gitlinks = [entry for entry in entries if entry['gitlink']]
        if gitlinks:
            lines += ['', '## Unreviewed Content', '_Gitlink changes show commit pointers only; submodule contents were NOT reviewed._']
            lines += ['- ' + entry['label'] + ' [GITLINK]' for entry in gitlinks]
        lines += ['', '## Referenced Signatures', '- source_tree: ' + candidate]
        lines += [entry['signatures'] for i, entry in enumerate(entries) if i in selected and entry['signatures']]
        return ('\n'.join(lines) + '\n').encode()
    # Até a lista de omissões precisa caber; nunca escondê-la para aparentar cobertura.
    if len(render()) > args.max_output_bytes:
        raise ValueError('scope and omission list exceed complete context budget')
    total_lines = total_bytes = 0
    order = sorted(range(len(entries)), key=lambda i: (not entries[i]['sensitive'], i if entries[i]['sensitive'] else entries[i]['lines'], i))
    for i in order:
        entry = entries[i]
        if entry['binary'] or len(selected) >= max_files or total_lines + entry['lines'] > max_lines or total_bytes + entry['bytes'] > max_bytes: continue
        selected.add(i)
        if len(render()) > args.max_output_bytes:
            selected.remove(i)
            continue
        total_lines += entry['lines']; total_bytes += entry['bytes']
    payload = render()
    receipt = dict(identity, payload_sha256=hashlib.sha256(payload).hexdigest(), payload_bytes=len(payload),
        coverage='partial' if len(selected) < len(entries) or any(entry['gitlink'] for entry in entries) else 'complete',
        unreviewed_content=[entry['paths'] for entry in entries if entry['gitlink']],
        included=[entry['paths'] for i, entry in enumerate(entries) if i in selected],
        omitted=[entry['paths'] for i, entry in enumerate(entries) if i not in selected])
    if args.output: save(args.output, payload)
    if args.receipt: save(args.receipt, (json.dumps(receipt) + '\n').encode())
    sys.stdout.buffer.write(payload)
except (ValueError, OSError, subprocess.CalledProcessError) as error:
    print('codex-diff-context: ' + str(error), file=sys.stderr)
    raise SystemExit(1)
PY
