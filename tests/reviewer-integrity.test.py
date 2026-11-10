#!/usr/bin/env python3
"""Contratos reais de contexto, executor e hook, sem chamar modelos externos."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / '.agents/tools'
HOOK = ROOT / '.agents/hooks/codex-pretool-guard.sh'

class ReviewFixture(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='review-contract-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = dict(os.environ, CLAUDE_PROJECT_DIR=str(self.root), CANUTO_GUARD_MODE='2')
        for key in list(self.env):
            if key.startswith(('GIT_', 'CODEX_DELEGATE_', 'CODEX_DIFF_', 'CODEX_REVIEW', 'CODEX_FAST_')):
                self.env.pop(key)
        self.git('init', '-q')
        for name in ('codex-common.sh', 'codex-diff-context.sh', 'codex-delegate.sh'):
            target = self.root / '.agents/tools' / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(TOOLS / name, target)
        config = self.root / '.agents/config/models.yaml'
        config.parent.mkdir(parents=True)
        config.write_text('roles:\n  reviewer: { model: fixture-reviewer, effort: medium, timeout: 1200, sandbox: read-only, fallback: none }\n')
        # Somente diretórios de runtime mudam no fixture; executor e política são reais.
        with (self.root / '.agents/tools/codex-common.sh').open('a') as handle:
            handle.write('\ncodex_review_exec_dir() { mkdir -p "$CLAUDE_PROJECT_DIR/runtime"; printf "%s\\n" "$CLAUDE_PROJECT_DIR/runtime"; }\ncodex_vault_dir() { printf "\\n"; }\n')
        self.bin = self.root / 'bin'; self.bin.mkdir()
        self.fake = self.bin / 'codex'
        self.fake.write_text(f'#!{sys.executable}\n' + '''import json, os, pathlib, sys
root = pathlib.Path(os.environ['CLAUDE_PROJECT_DIR'])
args = sys.argv[1:]
with (root / 'calls.jsonl').open('a') as handle: handle.write(json.dumps(args) + '\\n')
(root / 'received-prompt.txt').write_text(sys.stdin.read())
output = pathlib.Path(args[args.index('-o') + 1])
mode = os.environ.get('REVIEW_FIXTURE_MODE', 'ok')
if mode == 'empty': raise SystemExit(0)
result = json.loads((root / 'result.json').read_text())
output.write_text(json.dumps(result))
if mode == 'partial': raise SystemExit(1)
if mode == 'timeout': raise SystemExit(124)
''')
        self.fake.chmod(0o700)
        self.env['PATH'] = str(self.bin) + os.pathsep + os.environ['PATH']
        self.env['CODEX_DELEGATE_MODELS_CACHE'] = str(self.root / 'no-cache')
        self.result = dict(schema_version='1.0', verdict='COMMIT', summary='fixture evidence', score=9, issues=[])
        self.set_result(self.result)
        self.schema = self.root / 'schema.json'
        self.schema.write_text(re.search(r'cat > "\$schema_file" <<\'EOF\'\n(.*?)\nEOF', HOOK.read_text(), re.S)[1])
        self.prompt = self.root / 'prompt.txt'; self.prompt.write_text('Bounded review task.\n')
        self.output = self.root / 'output.json'
        self.receipt = self.root / 'context.json'
    def set_result(self, result): (self.root / 'result.json').write_text(json.dumps(result))
    def run_cmd(self, command, **kwargs):
        return subprocess.run(command, cwd=self.root, env=self.env, capture_output=True, text=True, timeout=20, **kwargs)
    def git(self, *args):
        result = self.run_cmd(['git', '-c', 'core.hooksPath=/dev/null', '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', *args])
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.strip()
    def put(self, path, text):
        target=self.root / path; target.parent.mkdir(parents=True, exist_ok=True); target.write_text(text)
    def baseline(self, path='auth/policy.ts'):
        self.path=path
        self.put(path, 'export interface AuthDecision { allowed: boolean }\n')
        self.git('add', path); self.git('commit', '-qm', 'baseline')
        return self.git('rev-parse', 'HEAD')
    def context(self, *args):
        return self.run_cmd(['bash', str(TOOLS / 'codex-diff-context.sh'), *args, '--receipt', str(self.receipt)])
    def runner(self, mode='ok'):
        self.env['REVIEW_FIXTURE_MODE']=mode
        return self.run_cmd(['bash', '-c', 'source "$1"; codex_run_reviewer "$2" "$3" "$4" "$5" "$6" "$7"', 'fixture',
            str(self.root / '.agents/tools/codex-common.sh'), str(self.root / 'runtime'), str(self.schema), str(self.output),
            str(self.prompt), str(self.root / 'used'), str(self.root / 'errors')])
    def calls(self):
        path=self.root / 'calls.jsonl'
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []
    def hook(self, mode='ok', pr=False):
        self.env['REVIEW_FIXTURE_MODE']=mode
        args=['bash', str(HOOK)]
        pr = pr or 'PR_REVIEW_MODE=0' in HOOK.read_text()
        if pr: args += ['--pr-review', self.base]
        payload=json.dumps(dict(tool_name='Bash', tool_input=dict(command='git commit -m fixture'), session_id='fixture'))
        return self.run_cmd(args, input=payload)
    def events(self):
        paths=list(self.root.rglob('codex-review-events.jsonl'))
        return [json.loads(line) for path in paths for line in path.read_text().splitlines()]

    def test_staged_signatures_and_receipt_use_index_not_worktree(self):
        self.baseline()
        self.put(self.path, 'export interface AuthDecision { allowed: boolean; checked: true }\n')
        self.git('add', self.path)
        staged=self.git('write-tree')
        index=(self.root / '.git/index').read_bytes()
        self.put(self.path, 'export interface AuthDecision { allowed: string; checked: false }\n')
        result=self.context('--staged')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('checked: false', result.stdout)
        self.assertIn('1:export interface AuthDecision { allowed: boolean; checked: true }', result.stdout)
        receipt=json.loads(self.receipt.read_text())
        self.assertEqual(receipt['candidate_tree'], staged)
        self.assertEqual(receipt['payload_sha256'], hashlib.sha256(result.stdout.encode()).hexdigest())
        self.assertEqual((self.root / '.git/index').read_bytes(), index)
        self.put(self.path, 'export interface AuthDecision { allowed: number }\n'); self.git('add', self.path)
        self.context('--staged')
        self.assertNotEqual(json.loads(self.receipt.read_text())['candidate_tree'], staged)

    def test_worktree_modes_and_unborn_index(self):
        self.put('new.ts', 'export const added = true;\n'); self.git('add', 'new.ts')
        result=self.context('--staged'); self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('+export const added', result.stdout)
        self.git('commit', '-qm', 'initial')
        self.put('new.ts', 'export const added = false;\n')
        for mode in (['--uncommitted'], ['--commit-candidate','all-tracked']):
            result=self.context(*mode); self.assertEqual(result.returncode,0,result.stderr)
            self.assertIn('1:export const added = false;', result.stdout)

    def test_base_ignores_index_worktree_and_pins_ref(self):
        base=self.baseline(); self.git('branch','review-base',base)
        self.put(self.path, 'export interface AuthDecision { committed: true }\n')
        self.git('add', self.path); self.git('commit','-qm','candidate')
        self.put(self.path, 'export interface AuthDecision { poison: true }\n'); self.git('add',self.path)
        result=self.context('--base','review-base'); self.assertEqual(result.returncode,0,result.stderr)
        receipt=json.loads(self.receipt.read_text()); self.assertEqual(receipt['base_sha'],base)
        self.assertNotIn('poison:',result.stdout)
        self.git('branch','-f','review-base','HEAD')
        self.assertEqual(receipt['base_sha'],base)
        self.assertEqual(self.context('--base','review-base').returncode,0)
        self.assertIn('No changes detected.', self.context('--base','review-base').stdout)

    def test_ref_and_index_changes_during_build_do_not_mix_snapshots(self):
        base=self.baseline();self.git('branch','moving-base',base)
        self.put(self.path,'export interface AuthDecision { frozen: true }\n');self.git('add',self.path)
        self.git('commit','-qm','candidate');candidate=self.git('rev-parse','HEAD')
        original_tree=self.git('write-tree');real_git=shutil.which('git')
        wrapper=self.bin/'git'
        wrapper.write_text(f'#!{sys.executable}\n' + f"""import os, pathlib, subprocess, sys
args=sys.argv[1:]
if '--name-status' in args:
    root=pathlib.Path(os.environ['CLAUDE_PROJECT_DIR'])
    (root/{self.path!r}).write_text('export interface AuthDecision {{ leaked: true }}\\n')
    subprocess.check_call([{real_git!r},'add',{self.path!r}])
    subprocess.check_call([{real_git!r},'branch','-f','moving-base','HEAD'])
os.execv({real_git!r},[{real_git!r},*args])
""")
        wrapper.chmod(0o700)
        result=self.context('--base','moving-base');self.assertEqual(result.returncode,0,result.stderr)
        self.assertNotIn('leaked:',result.stdout)
        self.assertIn('frozen: true',result.stdout)
        receipt=json.loads(self.receipt.read_text())
        self.assertEqual(receipt['base_sha'],base);self.assertEqual(receipt['head_sha'],candidate)
        self.assertEqual(receipt['candidate_tree'],original_tree)
        self.assertNotEqual(self.git('write-tree'),original_tree)

    def test_inventory_separates_file_hash_registration_and_execution(self):
        home=self.root/'installation';tools=home/'.claude/scripts';tools.mkdir(parents=True)
        shutil.copy2(TOOLS/'codex-common.sh',tools/'codex-common.sh')
        settings=home/'.claude/settings.json'
        settings.write_text(json.dumps({'hooks':{'PreToolUse':[{'matcher':'Bash','hooks':[{'type':'command','command':'~/.claude/hooks/codex-pretool-guard.sh','timeout':240}]}]}}))
        result=self.run_cmd([sys.executable,str(TOOLS/'reviewer-inventory.py'),'--root',str(ROOT),'--runtime-home',str(home)])
        self.assertEqual(result.returncode,0,result.stderr);report=json.loads(result.stdout)
        self.assertEqual(report['runtime_execution'],'UNVERIFIED')
        self.assertEqual(len(report['registrations']),1)
        files={row['name']:row for row in report['files']}
        self.assertEqual(files['codex-common.sh']['state'],'matching')
        self.assertEqual(files['codex-pretool-guard.sh']['state'],'missing')
        settings.write_text('{invalid')
        report=json.loads(self.run_cmd([sys.executable,str(TOOLS/'reviewer-inventory.py'),'--root',str(ROOT),'--runtime-home',str(home)]).stdout)
        self.assertEqual(report['registrations'],[])
        self.assertTrue(any(row['state']=='UNVERIFIED' for row in report['settings']))

    def test_rename_and_delete_include_source_risk_and_odd_paths(self):
        self.baseline('auth/with space.ts')
        self.git('mv',self.path,'plain.ts')
        self.env['CODEX_DIFF_MAX_FILES']='0'
        result=self.context('--staged'); self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn('sensitive_files_omitted: true', result.stdout)
        self.assertEqual(json.loads(self.receipt.read_text())['omitted'],[['auth/with space.ts','plain.ts']])
        self.env.pop('CODEX_DIFF_MAX_FILES'); self.git('rm','-f','plain.ts')
        result=self.context('--staged'); self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn('deleted file mode',result.stdout)
        self.assertEqual(json.loads(self.receipt.read_text())['included'],[['auth/with space.ts']])
        self.put('strange\nname.ts','export const value = 1;\n');self.git('add','strange\nname.ts')
        self.assertEqual(self.context('--staged').returncode,0)

    def test_complete_budget_and_omitted_signatures(self):
        self.baseline(); self.put(self.path, 'export interface AuthDecision { '+('long: boolean; '*600)+'}\n');self.git('add',self.path)
        self.env['CODEX_DIFF_MAX_TOTAL_BYTES']='1800'
        result=self.context('--staged'); self.assertEqual(result.returncode,0,result.stderr)
        self.assertLessEqual(len(result.stdout.encode()),1800)
        self.assertIn('coverage: partial',result.stdout)
        self.assertNotIn('long: boolean', result.stdout)
        self.env['CODEX_DIFF_MAX_TOTAL_BYTES']='10'
        result=self.context('--staged');self.assertNotEqual(result.returncode,0);self.assertEqual(result.stdout,'')

    def test_context_uses_consumer_sensitive_policy(self):
        self.baseline('lib/authService.ts')
        self.put(self.path, 'export interface AuthDecision { changed: true }\n'); self.git('add',self.path)
        # A regra adicional só do consumidor precisa valer na priorização e no receipt.
        with (self.root/'.agents/tools/codex-common.sh').open('a') as handle:
            handle.write('\ncodex_is_security_sensitive_path() { [[ "$1" == "lib/authService.ts" ]]; }\n')
        self.env['CODEX_DIFF_MAX_FILES']='0'
        result=self.run_cmd(['bash', str(self.root/'.agents/tools/codex-diff-context.sh'), '--staged'])
        self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn('sensitive_files_omitted: true',result.stdout)
        self.assertIn('[SECURITY-SENSITIVE]',result.stdout)

    def test_gitlink_preserves_other_patches_and_reports_unreviewed_content(self):
        self.baseline();self.put(self.path,'export interface AuthDecision { changed: true }\n');self.git('add',self.path)
        self.git('update-index','--add','--cacheinfo','160000,'+'1'*40+',vendor/module')
        result=self.context('--staged');self.assertEqual(result.returncode,0,result.stderr)
        self.assertIn('+export interface AuthDecision { changed: true }',result.stdout)
        self.assertIn('Subproject commit '+'1'*40,result.stdout)
        self.assertIn('submodule contents were NOT reviewed',result.stdout)
        receipt=json.loads(self.receipt.read_text());self.assertEqual(receipt['coverage'],'partial')
        self.assertEqual(receipt['unreviewed_content'],[['vendor/module']])

    def test_runner_preserves_adapter_and_project_policy(self):
        self.assertEqual(self.runner().returncode,0)
        call=self.calls()[0]
        self.assertEqual(call[call.index('-m')+1],'fixture-reviewer')
        self.assertIn('model_reasoning_effort="medium"',call)
        self.assertEqual(call[call.index('-s')+1],'read-only')
        self.assertIn('--ephemeral',call);self.assertIn('--output-schema',call)
        self.assertEqual(call[-1],'-');self.assertEqual((self.root/'received-prompt.txt').read_text(),self.prompt.read_text())
        receipt=json.loads(Path(str(self.output)+'.receipt.json').read_text())
        self.assertIsNone(receipt['effective_model']);self.assertEqual(receipt['status'],'OK')

    def test_failed_partial_and_following_empty_never_publish_old_result(self):
        self.output.write_text(json.dumps(self.result))
        self.assertNotEqual(self.runner('partial').returncode,0)
        self.assertFalse(self.output.exists());self.assertEqual(len(self.calls()),1)
        self.assertNotEqual(self.runner('empty').returncode,0)
        self.assertFalse(self.output.exists());self.assertFalse((self.root/'used').exists())
        self.assertEqual(len(self.calls()),2)
        self.assertEqual(json.loads(Path(str(self.output)+'.receipt.json').read_text())['status'],'EMPTY_OUTPUT')

    def test_timeout_and_entire_schema(self):
        self.assertNotEqual(self.runner('timeout').returncode,0)
        self.assertEqual(json.loads(Path(str(self.output)+'.receipt.json').read_text())['status'],'TIMEOUT')
        variants=[dict(self.result, verdict='APPROVED'),dict(self.result,schema_version='2'),dict(self.result,extra=True),
            dict(self.result, issues=[dict(severity='urgent',file='x',line=None,issue='bad',fix='fix')]),
            dict(self.result, issues=[dict(severity='high',file='x',line=True,issue='bad',fix='fix')])]
        for result in variants:
            self.set_result(result);self.assertNotEqual(self.runner().returncode,0);self.assertFalse(self.output.exists())

    def test_health_consumer_schema(self):
        text=(TOOLS/'codex-health-check.sh').read_text()
        self.schema.write_text(re.search(r'cat > "\$schema_file" <<\'EOF\'\n(.*?)\nEOF',text,re.S)[1])
        self.set_result(dict(verdict='LGTM',summary='ok',score=1,issues=[]))
        self.assertEqual(self.runner().returncode,0)

    def test_config_rejects_fallback_and_write_access_without_spawn(self):
        config=self.root/'.agents/config/models.yaml'; original=config.read_text()
        for text in (original.replace('fallback: none','fallback: architect'),original.replace('read-only','workspace-write')):
            config.write_text(text);self.assertNotEqual(self.runner().returncode,0);self.assertEqual(self.calls(),[])

    def test_complete_prompt_budget_prevents_spawn(self):
        self.env['CODEX_REVIEW_MAX_PROMPT_BYTES']='5'
        self.assertNotEqual(self.runner().returncode,0);self.assertEqual(self.calls(),[])

    def prepare_hook(self,path='auth/policy.ts'):
        self.base=self.baseline(path)
        self.put(path,'export const policy = [\n'+''.join(f'  "item-{i}",\n' for i in range(25))+'];\n')
        self.git('add',path)
        if 'PR_REVIEW_MODE=0' in HOOK.read_text(): self.git('commit','-qm','candidate')
    def test_hook_partial_degrades_and_success_binds_candidate(self):
        self.prepare_hook()
        failed=self.hook('partial');self.assertEqual(failed.returncode,0,failed.stderr)
        self.assertEqual(len(self.calls()),1)
        self.assertFalse(any(event.get('status')=='COMMIT' for event in self.events()))
        self.assertIn('DEGRADED', next((self.root/'.agents/tmp/codex').glob('latest-*-review.md')).read_text())
        success=self.hook();self.assertEqual(success.returncode,0,success.stderr)
        event=next(event for event in reversed(self.events()) if event.get('status')=='COMMIT')
        self.assertEqual(event['context']['candidate_tree'],self.git('write-tree'))
        self.assertEqual(event['execution']['status'],'OK');self.assertIsNone(event['effective_model'])
    def test_hook_invalid_enum_is_never_approval(self):
        self.prepare_hook();self.set_result(dict(self.result,verdict='SURPRISE'))
        result=self.hook();self.assertEqual(result.returncode,0,result.stderr)
        self.assertFalse(any(event.get('status')=='SURPRISE' for event in self.events()))
    def test_fast_consumer_still_uses_reviewer_policy(self):
        self.prepare_hook('plain.ts')
        pr='PR_REVIEW_MODE=0' in HOOK.read_text()
        result=self.hook(pr=pr);self.assertEqual(result.returncode,0,result.stderr)
        self.assertEqual(len(self.calls()),1,result.stderr)
        self.assertNotIn('--profile',self.calls()[0]);self.assertIn('fixture-reviewer',self.calls()[0])
    def test_local_hold_policy_remains_blocking(self):
        self.prepare_hook();self.set_result(dict(self.result,verdict='HOLD'))
        for _ in range(4 if 'PR_REVIEW_MODE=0' in HOOK.read_text() else 1):
            result=self.hook();self.assertEqual(result.returncode,2,result.stderr)

class DelegateInstall(unittest.TestCase):
    def test_new_managed_update_custom_preservation_and_rollback(self):
        with tempfile.TemporaryDirectory(prefix='delegate-install-') as temp:
            root=Path(temp); source=root/'.agents/tools/codex-delegate.sh'
            source.parent.mkdir(parents=True); source.write_bytes((TOOLS/'codex-delegate.sh').read_bytes())
            text=(ROOT/'install.sh').read_text(); start=text.index('install_codex_delegate_wrapper() {')
            function=text[start:text.index('\nsetup_codex() {',start)]
            script=root/'install-function.sh';script.write_text(function+'\ninstall_codex_delegate_wrapper "$1"\n')
            destdir=root/'runtime-bin';dest=destdir/'codex-delegate.sh';receipt=destdir/'.codex-delegate.canuto.sha256'
            def install():
                result=subprocess.run(['bash',str(script),str(destdir)],cwd=root,capture_output=True,text=True)
                self.assertEqual(result.returncode,0,result.stderr)
            install(); self.assertEqual(dest.read_bytes(),source.read_bytes())
            old=dest.read_bytes();source.write_bytes(old+b'\n# managed revision\n');install()
            self.assertEqual(dest.read_bytes(),source.read_bytes())
            backup=next(destdir.glob('*.canuto-backup.*'));self.assertEqual(backup.read_bytes(),old)
            # Restauração explícita: bytes anteriores e seu receipt, sem tocar HOME.
            dest.write_bytes(backup.read_bytes());receipt.write_text(hashlib.sha256(old).hexdigest()+'\n')
            self.assertEqual(dest.read_bytes(),old)
            custom=old+b'\n# local customization retaining canonical header\n';dest.write_bytes(custom)
            install();self.assertEqual(dest.read_bytes(),custom)
            receipt.unlink();install();self.assertEqual(dest.read_bytes(),custom)
            dest.unlink();dest.symlink_to(root, target_is_directory=True)
            install();self.assertTrue(dest.is_symlink());self.assertFalse(receipt.exists())

if __name__=='__main__': unittest.main()
