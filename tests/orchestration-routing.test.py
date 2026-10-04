#!/usr/bin/env python3
"""Contratos de roteamento com executores locais simulados, sem inferência."""
import asyncio
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import textwrap
import types
import unittest
from unittest.mock import AsyncMock, patch

ROOT = Path(__file__).resolve().parents[1]
WRAPPER = ROOT / ".agents/tools/codex-delegate.sh"
CONFIG = ROOT / ".agents/config/models.yaml"


class FakeMCP:
    def __init__(self, name):
        self.tools = {}

    def tool(self):
        def register(function):
            self.tools[function.__name__] = function
            return function
        return register


for name in ("mcp", "mcp.server", "mcp.server.fastmcp"):
    sys.modules[name] = types.ModuleType(name)
sys.modules["mcp.server.fastmcp"].Context = object
sys.modules["mcp.server.fastmcp"].FastMCP = FakeMCP
spec = importlib.util.spec_from_file_location("bridge", ROOT / ".agents/tools/claude-agent-mcp.py")
bridge = importlib.util.module_from_spec(spec)
sys.modules["bridge"] = bridge
spec.loader.exec_module(bridge)


class CodexRouting(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.bin = self.base / "bin"
        self.bin.mkdir()
        self.fixture_home = self.base / "home"
        self.fixture_home.mkdir()
        self.config = self.base / "models.yaml"
        shutil.copyfile(CONFIG, self.config)
        self.output = self.base / "artifact.md"
        self.metrics = self.base / "metrics.jsonl"
        cache = self.fixture_home / ".codex/models_cache.json"
        cache.parent.mkdir()
        cache.write_text(json.dumps({"models": [
            {"slug": name, "supported_reasoning_levels": [{"effort": effort} for effort in
             ("low", "medium", "high", "xhigh", "max")]} for name in
            ("gpt-6-luna", "gpt-6.1-sol", "gpt-6-sol")]}))
        self.executable("timeout", "import os,sys\nos.execvp(sys.argv[2],sys.argv[2:])\n")
        self.executable("codex", textwrap.dedent('''
            import json, os, pathlib, sys
            args = sys.argv[1:]
            if '--help' in args:
                print('--sandbox --output-last-message --model --color')
                raise SystemExit(0)
            if args[:2] == ['login', 'status']:
                raise SystemExit(0)
            calls = pathlib.Path(os.environ['FAKE_CALLS'])
            with calls.open('a') as handle:
                handle.write(json.dumps(args) + '\\n')
            out = pathlib.Path(args[args.index('-o') + 1])
            mode = os.environ.get('FAKE_MODE', 'ok')
            if mode == 'unavailable' or (mode == 'fallback' and 'model=gpt-6-luna' in args):
                if os.environ.get('FAKE_ACTIVATE_GUARD'):
                    guard = pathlib.Path(os.environ['HOME']) / '.codex/guard/backpressure.json'
                    guard.parent.mkdir(parents=True, exist_ok=True)
                    guard.write_text(json.dumps({'active': True, 'severity': 'critical'}))
                print("The 'gpt-6-luna' model is not supported when using Codex with a ChatGPT account.")
                raise SystemExit(1)
            if mode == 'partial-unavailable':
                out.write_text('partial evidence')
                print('model_not_found')
                raise SystemExit(1)
            if mode == 'timeout':
                out.write_text('partial evidence')
                print('deadline reached')
                raise SystemExit(124)
            if mode == 'error':
                print('503 service unavailable; model configuration remains unchanged')
                raise SystemExit(1)
            if mode == 'empty':
                raise SystemExit(0)
            if mode == 'whitespace':
                out.write_text('  \\n\\t')
                raise SystemExit(0)
            print('discussion: model_not_found is an example, not an executor failure')
            out.write_text('file:42 verified evidence')
        '''))
        self.environment = dict(os.environ, HOME=str(self.fixture_home),
                                PATH=str(self.bin) + os.pathsep + os.environ["PATH"],
                                CODEX_DELEGATE_MODELS_YAML=str(self.config),
                                CODEX_DELEGATE_METRICS=str(self.metrics),
                                FAKE_CALLS=str(self.base / "calls.jsonl"))
        for key in ("CODEX_DELEGATE_MODEL", "CODEX_DELEGATE_SANDBOX", "CODEX_DELEGATE_TIMEOUT",
                    "CODEX_DELEGATE_FALLBACK_MODEL", "CODEX_DELEGATE_MODELS_CACHE",
                    "CODEX_DELEGATE_REQUIRE_REPO", "CODEX_DELEGATE_SNAPSHOT_ACTIVE"):
            self.environment.pop(key, None)

    def executable(self, name, code):
        target = self.bin / name
        target.write_text(f"#!{sys.executable}\n" + code)
        target.chmod(0o700)

    def run_wrapper(self, role="leaf", mode="ok", overrides=None, preflight=False, cwd=None):
        arguments = ["bash", str(WRAPPER)]
        if preflight:
            arguments.append("--preflight-only")
        arguments.extend([role, "read the bounded scope", str(self.output), str(cwd or self.base)])
        environment = dict(self.environment, FAKE_MODE=mode, **(overrides or {}))
        return subprocess.run(arguments, cwd=self.base, env=environment,
                              capture_output=True, text=True, timeout=12)

    def events(self):
        return [json.loads(line) for line in self.metrics.read_text().splitlines()]

    def calls(self):
        target = self.base / "calls.jsonl"
        return [json.loads(line) for line in target.read_text().splitlines()] if target.exists() else []

    def test_every_codex_role_uses_its_configuration(self):
        for role, model, effort, access in (
            ("leaf", "gpt-6-luna", "low", "read-only"),
            ("fast", "gpt-6-luna", "low", "workspace-write"),
            ("coder", "gpt-6.1-sol", "medium", "workspace-write"),
            ("reviewer", "gpt-6.1-sol", "high", "read-only"),
            ("architect", "gpt-6.1-sol", "high", "read-only"),
            ("maestro", "gpt-6.1-sol", "high", "workspace-write"),
        ):
            with self.subTest(role=role):
                extra = {"CODEX_DELEGATE_MODEL": model} if role == "maestro" else None
                result = self.run_wrapper(role, overrides=extra)
                self.assertEqual(result.returncode, 0, result.stderr)
                call = self.calls()[-1]
                self.assertIn(f"model={model}", call)
                self.assertIn(f"model_reasoning_effort={effort}", call)
                self.assertEqual(call[call.index("-s") + 1], access)
                self.assertIsNone(self.events()[-1]["effective_model"])

    def test_model_override_wins_without_confusing_claude_section(self):
        self.config.write_text(self.config.read_text().replace("model: sonnet", "model: bad-model"))
        result = self.run_wrapper(overrides={"CODEX_DELEGATE_MODEL": "gpt-6.1-sol"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.events()[-1]["requested_model"], "gpt-6.1-sol")

    def test_missing_optional_fields_do_not_turn_into_models(self):
        self.config.write_text("roles:\n  leaf: { model: gpt-6-luna }\n")
        result = self.run_wrapper()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("model_reasoning_effort=low", self.calls()[-1])

    def test_malformed_and_duplicate_configurations_fail_closed(self):
        for text in ("roles:\n  leaf:\n    model: gpt-6-luna\n",
                     "roles:\n  leaf: { model: gpt-6-luna }\n  leaf: { model: gpt-6.1-sol }\n"):
            with self.subTest(text=text):
                self.config.write_text(text)
                self.assertNotEqual(self.run_wrapper().returncode, 0)
                self.assertEqual(self.calls(), [])

    def test_preflight_is_not_execution_success(self):
        self.assertEqual(self.run_wrapper(preflight=True).returncode, 0)
        self.assertEqual(self.events()[-1]["execution_status"], "PREFLIGHT")
        self.assertEqual(self.events()[-1]["phase"], "PREFLIGHT")
        self.assertEqual(self.calls(), [])

    def test_successful_preflight_does_not_create_ledger_pending(self):
        self.assertEqual(self.run_wrapper(preflight=True).returncode, 0)
        ledger = self.base / "ledger.sh"
        shutil.copyfile(ROOT / ".agents/tools/delegation-ledger.sh", ledger)
        environment = dict(self.environment, CANUTO_METRICS_FILE=str(self.metrics),
                           CANUTO_LEDGER_ROOT=str(self.base), CLAUDE_PROJECT_DIR=str(self.base))
        for no_jq in (False, True):
            with self.subTest(no_jq=no_jq):
                override = 'command() { if [[ "$1" == "-v" && "$2" == "jq" ]]; then return 1; fi; builtin command "$@"; }; ' if no_jq else ''
                result = subprocess.run(["bash", "-c", override + 'source "$1"; delegation_ledger_pending', "test", str(ledger)],
                                        cwd=self.base, env=environment, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout.strip(), "")
        # O wrapper também precisa coexistir com consumidores ainda não atualizados.
        previous_ledger = subprocess.check_output(["git", "show", "HEAD:.agents/tools/delegation-ledger.sh"], cwd=ROOT)
        old_ledger = self.base / "old-ledger.sh"
        old_ledger.write_bytes(previous_ledger)
        legacy = subprocess.run(["bash", str(old_ledger), "pending"], cwd=self.base, env=environment,
                                capture_output=True, text=True)
        self.assertEqual(legacy.returncode, 0, legacy.stderr)
        self.assertEqual(legacy.stdout.strip(), "")
        failed = dict(ts="2099-01-01T00:00:00Z", result="PREFLIGHT", rc=5, role="leaf", cwd=str(self.base))
        with self.metrics.open("a") as handle:
            handle.write(json.dumps(failed) + "\n")
        result = subprocess.run(["bash", str(ledger), "pending"], cwd=self.base, env=environment,
                                capture_output=True, text=True)
        self.assertIn("2099-01-01", result.stdout)

    def test_configuration_is_resolved_from_git_root_in_subdirectory(self):
        subprocess.run(["git", "init", "--quiet", str(self.base)], check=True, capture_output=True)
        project_config = self.base / ".agents/config/models.yaml"
        project_config.parent.mkdir(parents=True)
        project_config.write_text("roles:\n  leaf: { model: gpt-6.1-sol, effort: low, sandbox: read-only }\n")
        child = self.base / "apps/web"
        child.mkdir(parents=True)
        result = self.run_wrapper(cwd=child, overrides={"CODEX_DELEGATE_MODELS_YAML": ""})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("model=gpt-6.1-sol", self.calls()[-1])

    def test_invalid_roles_are_not_model_failures(self):
        result = self.run_wrapper("typo")
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.events()[-1]["result"], "INVALID_ROLE")
        self.assertEqual(self.calls(), [])

    def test_maestro_requires_parent_model(self):
        result = self.run_wrapper("maestro")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("session_model_required", result.stderr)

    def test_read_only_roles_reject_access_escalation(self):
        for role in ("leaf", "reviewer", "architect"):
            for access in ("workspace-write", "danger-full-access"):
                with self.subTest(role=role, access=access):
                    result = self.run_wrapper(role, overrides={"CODEX_DELEGATE_SANDBOX": access})
                    self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_yaml_cannot_make_leaf_mutable(self):
        self.config.write_text(self.config.read_text().replace(
            "timeout: 900, sandbox: read-only", "timeout: 900, sandbox: workspace-write"))
        self.assertNotEqual(self.run_wrapper().returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_explicit_compatible_fallback_is_tried_once(self):
        result = self.run_wrapper(mode="fallback", overrides={"CODEX_DELEGATE_FALLBACK_MODEL": "gpt-6.1-sol"})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(self.calls()), 2)
        self.assertEqual(self.events()[-1]["requested_model"], "gpt-6-luna")
        self.assertEqual(self.events()[-1]["model"], "gpt-6.1-sol")
        self.assertTrue(list(self.base.glob("artifact.md.log.attempt1.*")))

    def test_no_fallback_is_invented(self):
        self.assertNotEqual(self.run_wrapper(mode="unavailable").returncode, 0)
        self.assertEqual(len(self.calls()), 1)

    def test_capacity_is_rechecked_before_fallback(self):
        result = self.run_wrapper(mode="fallback", overrides={
            "CODEX_DELEGATE_FALLBACK_MODEL": "gpt-6.1-sol", "FAKE_ACTIVATE_GUARD": "1"})
        self.assertEqual(result.returncode, 75)
        self.assertEqual(len(self.calls()), 1)
        self.assertTrue(list(self.base.glob("artifact.md.log.attempt1.*")))

    def test_fallback_stops_after_second_failure(self):
        result = self.run_wrapper(mode="unavailable", overrides={"CODEX_DELEGATE_FALLBACK_MODEL": "gpt-6.1-sol"})
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(self.calls()), 2)

    def test_reviewer_rejects_fallback(self):
        result = self.run_wrapper("reviewer", overrides={"CODEX_DELEGATE_FALLBACK_MODEL": "gpt-6-sol"})
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_unknown_fallback_is_rejected_before_spawn(self):
        result = self.run_wrapper(overrides={"CODEX_DELEGATE_FALLBACK_MODEL": "gpt-6.1-luna"})
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_incompatible_effort_is_rejected(self):
        self.config.write_text(self.config.read_text().replace("effort: low", "effort: ultra"))
        self.assertNotEqual(self.run_wrapper().returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_registry_effort_compatibility(self):
        cache = self.fixture_home / ".codex/models_cache.json"
        cache.write_text(json.dumps({"models": [{"slug": "gpt-6-luna",
                                                  "supported_reasoning_levels": [{"effort": "high"}]}]}))
        self.assertNotEqual(self.run_wrapper().returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_non_model_failure_is_not_retried(self):
        result = self.run_wrapper(mode="error", overrides={"CODEX_DELEGATE_FALLBACK_MODEL": "gpt-6.1-sol"})
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(self.calls()), 1)
        self.assertEqual(self.events()[-1]["result"], "SPAWN_FAILED")

    def test_timeout_preserves_partial_and_does_not_retry(self):
        result = self.run_wrapper(mode="timeout", overrides={"CODEX_DELEGATE_FALLBACK_MODEL": "gpt-6.1-sol"})
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(self.calls()), 1)
        self.assertEqual(self.events()[-1]["result"], "TIMEOUT")
        self.assertEqual(Path(str(self.output) + ".partial.md").read_text(), "partial evidence")
        self.assertTrue(list((self.fixture_home / ".codex/delegate-partials").glob("*.partial.md")))

    def test_partial_model_failure_does_not_retry(self):
        result = self.run_wrapper(mode="partial-unavailable", overrides={"CODEX_DELEGATE_FALLBACK_MODEL": "gpt-6.1-sol"})
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(self.calls()), 1)
        self.assertTrue(Path(str(self.output) + ".partial.md").exists())

    def test_empty_and_whitespace_artifacts_are_failures(self):
        for mode in ("empty", "whitespace"):
            with self.subTest(mode=mode):
                self.assertNotEqual(self.run_wrapper(mode=mode).returncode, 0)
                self.assertEqual(self.events()[-1]["result"], "EMPTY_OUTPUT")

    def test_stale_active_capacity_cannot_be_bypassed(self):
        target = self.fixture_home / ".codex/guard/backpressure.json"
        target.parent.mkdir()
        target.write_text(json.dumps({"active": True, "stamp": "2000-01-01T00:00:00Z", "severity": "critical"}))
        result = self.run_wrapper(overrides={"CODEX_DELEGATE_IGNORE_BACKPRESSURE": "1"})
        self.assertEqual(result.returncode, 75)
        self.assertEqual(self.calls(), [])

    def test_invalid_capacity_shape_does_not_clear_guard(self):
        target = self.fixture_home / ".codex/guard/backpressure.json"
        target.parent.mkdir()
        for text in ("broken-json", "[]", "{}", '{"active": "false"}'):
            with self.subTest(text=text):
                target.write_text(text)
                self.assertEqual(self.run_wrapper().returncode, 75)
                self.assertEqual(self.calls(), [])

    def test_invalid_timeout_fails_even_in_preflight(self):
        result = self.run_wrapper(overrides={"CODEX_DELEGATE_TIMEOUT": "0"}, preflight=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), [])


class ClaudeRouting(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name)
        self.config = self.base / "models.yaml"
        shutil.copyfile(CONFIG, self.config)
        self.addCleanup(patch.stopall)
        patch.object(bridge, "_project_dir", return_value=str(self.base)).start()
        patch.object(bridge, "_capacity_error", return_value=None).start()

    def role(self, mode, model=None):
        return bridge.ServerConfig("test", model, mode, {}, str(self.config))

    def test_every_claude_role_uses_config_and_tools(self):
        for mode, model in bridge.MODE_DEFAULTS.items():
            with self.subTest(mode=mode):
                command = bridge._build_claude_cmd(claude_exec="claude", config=self.role(mode))
                self.assertEqual(command[command.index("--model") + 1], model)
                self.assertEqual(command[command.index("--output-format") + 1], "json")
                self.assertNotIn("--fallback-model", command)
                if mode != "coder":
                    self.assertIn("--restricted", command)
                    self.assertIn("--strict-mcp-config", command)
                    self.assertEqual(command[command.index("--tools") + 1:command.index("--tools") + 4],
                                     ["Read", "Glob", "Grep"])
                    self.assertNotIn("auto", command)
                else:
                    self.assertIn("auto", command)

    def test_configuration_and_override_precedence(self):
        self.config.write_text(self.config.read_text().replace("model: sonnet", "model: opus"))
        self.assertEqual(bridge._model(self.role("cheap")), "opus")
        self.assertEqual(bridge._model(self.role("cheap", "sonnet")), "sonnet")

    def test_invalid_role_and_fallback_are_rejected(self):
        with self.assertRaises(ValueError):
            bridge._model(self.role("invalid"))
        self.config.write_text(self.config.read_text().replace(
            "model: opus, fallback: none, timeout: 1200", "model: opus, fallback: sonnet, timeout: 1200"))
        with self.assertRaises(ValueError):
            bridge._fallback(self.role("reviewer"))

    def test_duplicate_role_is_rejected(self):
        self.config.write_text("claude:\n  cheap: { model: sonnet }\n  cheap: { model: opus }\n")
        with self.assertRaises(ValueError):
            bridge._model(self.role("cheap"))

    async def test_one_explicit_fallback_with_individual_receipts(self):
        patch.object(bridge, "_resolve_claude_executable", return_value="claude").start()
        patch.object(bridge, "_check_executor").start()
        runner = patch.object(bridge, "_run_agent_once", new=AsyncMock(side_effect=[
            bridge.AgentResult("unavailable", "MODEL_UNAVAILABLE"),
            bridge.AgentResult("evidence", "OK", ("claude-opus-observed",))])).start()
        result = await bridge._run_agent(object(), "inspect code", self.role("architect"), "task-1")
        self.assertEqual(result, "evidence")
        self.assertEqual(runner.await_count, 2)
        self.assertEqual(runner.await_args_list[1].args[2].model, "opus")
        events = [json.loads(line) for line in (self.base / ".agents/tmp/claude/spawn-events.jsonl").read_text().splitlines()]
        self.assertEqual(events[0]["result"], "MODEL_UNAVAILABLE")
        self.assertEqual(events[1]["requested_model"], "fable")
        self.assertEqual(events[1]["effective_models"], ["claude-opus-observed"])

    async def test_timeout_empty_and_partial_never_trigger_fallback(self):
        patch.object(bridge, "_resolve_claude_executable", return_value="claude").start()
        patch.object(bridge, "_check_executor").start()
        for status, partial in (("TIMEOUT", None), ("EMPTY_OUTPUT", None), ("MODEL_UNAVAILABLE", "partial.txt")):
            with self.subTest(status=status, partial=partial):
                with patch.object(bridge, "_run_agent_once", new=AsyncMock(
                        return_value=bridge.AgentResult("failure", status, partial=partial))) as runner:
                    result = await bridge._run_agent(object(), "inspect code", self.role("architect"), "task")
                    self.assertTrue(result.startswith("Error:"))
                    self.assertEqual(runner.await_count, 1)

    async def test_reviewer_does_not_fallback(self):
        patch.object(bridge, "_resolve_claude_executable", return_value="claude").start()
        patch.object(bridge, "_check_executor").start()
        with patch.object(bridge, "_run_agent_once", new=AsyncMock(
                return_value=bridge.AgentResult("unavailable", "MODEL_UNAVAILABLE"))) as runner:
            await bridge._run_agent(object(), "inspect code", self.role("reviewer"), "task")
            self.assertEqual(runner.await_count, 1)

    async def test_parallel_wave_is_bounded(self):
        server = bridge._build_server(self.role("architect"))
        result = await server.tools["spawn_agents_parallel"](object(), [{"prompt": "read"}] * 3)
        self.assertIn("at most two", result[0]["error"])

    async def test_cancelling_parallel_tool_cancels_and_awaits_children(self):
        server = bridge._build_server(self.role("architect"))
        started = asyncio.Event()
        finished = []

        async def child(*arguments):
            started.set()
            try:
                await asyncio.sleep(20)
            finally:
                finished.append(True)

        with patch.object(bridge, "_run_agent", side_effect=child):
            parent = asyncio.create_task(server.tools["spawn_agents_parallel"](
                object(), [{"prompt": "read"}, {"prompt": "read"}], cancel_on_failure=True))
            await started.wait()
            parent.cancel()
            with self.assertRaises(asyncio.CancelledError):
                await parent
        self.assertEqual(len(finished), 2)

    async def test_capacity_prevents_executor_preflight(self):
        with patch.object(bridge, "_capacity_error", return_value="BACKPRESSURE"), \
             patch.object(bridge, "_resolve_claude_executable") as resolve:
            result = await bridge._run_agent(object(), "inspect", self.role("cheap"), "task")
            self.assertIn("BACKPRESSURE", result)
            resolve.assert_not_called()

    async def invoke(self, payload, returncode=0, stderr=""):
        executable = self.base / "fake-claude"
        executable.write_text(f"#!{sys.executable}\nimport sys\nsys.stdin.read()\n"
                              f"print({json.dumps(payload)!r})\n"
                              f"print({stderr!r}, file=sys.stderr)\nraise SystemExit({returncode})\n")
        executable.chmod(0o700)
        return await bridge._run_agent_once(object(), "read code", self.role("cheap"),
                                            str(executable), str(self.base), 0)

    async def test_success_requires_receipt_and_artifact(self):
        result = await self.invoke({"type": "result", "subtype": "success", "is_error": False,
                                    "result": "Error: documented finding", "modelUsage": {"actual-model": {}}})
        self.assertEqual(result.status, "OK")
        self.assertEqual(result.effective_models, ("actual-model",))
        result = await self.invoke({"type": "result", "subtype": "success", "result": "   "})
        self.assertEqual(result.status, "EMPTY_OUTPUT")
        result = await self.invoke({"type": "result", "subtype": "success", "is_error": True, "result": "failed"})
        self.assertEqual(result.status, "EXECUTION_FAILED")
        self.assertTrue(Path(result.partial).exists())

    async def test_missing_identity_is_not_inferred_from_alias(self):
        result = await self.invoke({"type": "result", "subtype": "success", "result": "evidence"})
        self.assertEqual(result.status, "OK")
        self.assertEqual(result.effective_models, ())

    async def test_exit_zero_without_result_receipt_is_rejected(self):
        result = await self.invoke({"type": "other", "result": "text"})
        self.assertEqual(result.status, "INVALID_OUTPUT")

    async def test_real_subprocess_timeout_is_reaped_and_partial_saved(self):
        self.config.write_text(self.config.read_text().replace("timeout: 900", "timeout: 1"))
        executable = self.base / "fake-claude"
        executable.write_text(f"#!{sys.executable}\nimport time\nprint('partial', flush=True)\ntime.sleep(20)\n")
        executable.chmod(0o700)
        result = await bridge._run_agent_once(object(), "read code", self.role("cheap"),
                                            str(executable), str(self.base), 0)
        self.assertEqual(result.status, "TIMEOUT")
        self.assertEqual(Path(result.partial).read_text().strip(), "partial")


if __name__ == "__main__":
    unittest.main()
