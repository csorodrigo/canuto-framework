#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["mcp[cli]>=1.12.4,<2"]
# ///
"""Claude MCP bridge with explicit role routing.

O cabecalho PEP 723 acima nao e enfeite: e a correcao de um apagao real.

Ate 2026-07-29 este script era lancado por `uvx --from codex-as-mcp python
claude-agent-mcp.py`. Nao usavamos UMA linha de codigo do codex-as-mcp — ele
servia so de doador de dependencia, porque tinha `mcp` no virtualenv dele. O
pedido dele e `mcp[cli]>=1.12.4`, sem teto. Quando o `mcp` 2.0.0 saiu, o
resolvedor pegou o 2.0.0, e o 2.0.0 REMOVEU `mcp.server.fastmcp` (a API virou
`MCPServer` em `mcp.server.mcpserver`). O import da linha de baixo passou a
morrer com ModuleNotFoundError, o processo saia com rc=1 antes de responder o
`initialize`, e o Codex reportava:

    MCP client for `claude-architect` failed to start: handshaking with MCP
    server failed: connection closed: initialize response

Ninguem mexeu neste arquivo. Quebrou porque um pacote de terceiro que a gente
nao usa subiu de major. Emprestar o virtualenv dos outros e emprestar o
calendario de releases deles junto.

Agora o script declara o que precisa, com teto, e roda por `uv run --script`.
O `<2` e proposital: a porta para a API 2.x e trabalho de verdade (decoradores
de tool e Context mudaram) e nao se faz porta de API para apagar incendio.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import re
import shutil
import signal
import subprocess
import tempfile
import time
from dataclasses import dataclass, replace
from functools import lru_cache
from pathlib import Path

from mcp.server.fastmcp import Context, FastMCP


MAX_RETRIES = 2

# ALIAS, nao versao fixa. `claude --model` aceita "fable"/"opus"/"sonnet" como
# "an alias for the latest model" (claude --help). Pinar versao e exatamente o
# que apodrece: ate 2026-07-26 isto pinava claude-opus-4-7 e claude-sonnet-4-6,
# ambos defasados, enquanto a sessao ja rodava Opus 5. Alias resolve para o mais
# recente sozinho, inclusive modelos lancados depois desta linha.
MODE_DEFAULTS = {
    "maestro": "fable",
    "architect": "fable",
    "coder": "opus",
    "reviewer": "opus",
    "investigator": "fable",
    "contextualizer": "sonnet",
    "cheap": "sonnet",
}

# `--fallback-model` e nativo: "automatic fallback ... when the default model is
# overloaded or not available. Accepts a comma-separated list to try each in
# order." So funciona com --print, que e o caso aqui (-p em _build_claude_cmd).
MODE_FALLBACKS = {
    "maestro": "opus",
    "architect": "opus",
    "investigator": "opus",
}
READ_ONLY_MODES = frozenset(MODE_DEFAULTS) - {"coder"}

ARCHITECT_SYSTEM_PROMPT = (
    "You are acting as Architect in a multi-agent AI framework. "
    "Respond with structured plans and analysis only. Be concise and direct."
)

CHEAP_SYSTEM_PROMPT = (
    "You are a bounded read-only leaf. Inspect only the requested scope, do not "
    "delegate, and return one evidence artifact to the parent agent."
)


@dataclass(frozen=True)
class ServerConfig:
    server_name: str
    model: str | None
    mode: str
    env_overrides: dict[str, str]
    models_yaml: str | None = None


@dataclass(frozen=True)
class AgentResult:
    text: str
    status: str
    effective_models: tuple[str, ...] = ()
    partial: str | None = None


def _parse_env_kv(pair: str) -> tuple[str, str]:
    if "=" not in pair:
        raise ValueError(f"Invalid --env value {pair!r}. Expected KEY=VALUE.")
    key, value = pair.split("=", 1)
    if not key:
        raise ValueError(f"Invalid --env value {pair!r}. KEY must be non-empty.")
    return key, value


def _parse_args() -> ServerConfig:
    parser = argparse.ArgumentParser(prog="claude-agent-mcp", add_help=True)
    parser.add_argument("--server-name", required=True)
    parser.add_argument("--model")
    parser.add_argument("--mode", choices=list(MODE_DEFAULTS), required=True)
    parser.add_argument("--models-yaml")
    parser.add_argument(
        "--env",
        action="append",
        default=[],
        metavar="KEY=VALUE",
        help="Set env vars for spawned Claude CLI processes.",
    )

    args = parser.parse_args()

    overrides: dict[str, str] = {}
    for pair in args.env:
        key, value = _parse_env_kv(pair)
        overrides[key] = value

    return ServerConfig(
        server_name=args.server_name,
        model=args.model,
        mode=args.mode,
        env_overrides=overrides,
        models_yaml=args.models_yaml,
    )


def _resolve_claude_executable() -> str:
    claude = shutil.which("claude")
    if not claude:
        raise FileNotFoundError(
            "Claude CLI not found in PATH. Install it and ensure the binary is available."
        )
    return claude


def _project_dir() -> str:
    return os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()


def _build_child_env(config: ServerConfig) -> dict[str, str]:
    env = dict(os.environ)
    env.update(config.env_overrides)
    return env


def _role_config(config: ServerConfig) -> dict[str, str]:
    if config.mode not in MODE_DEFAULTS:
        raise ValueError("papel Claude inválido")
    path = Path(config.models_yaml or os.environ.get("CANUTO_MODELS_YAML") or
                str(Path(_project_dir()) / ".agents/config/models.yaml"))
    if not path.exists():
        return {}
    section = False
    values = None
    for line in path.read_text(encoding="utf-8").splitlines():
        if line == "claude:":
            section = True
            continue
        if line and not line[0].isspace() and not line.startswith("#"):
            section = False
        if not section:
            continue
        match = re.fullmatch(r"  " + re.escape(config.mode) + r":\s*\{([^}]+)\}\s*", line)
        if match:
            if values is not None:
                raise ValueError("papel Claude duplicado na configuração")
            values = {}
            for field in match[1].split(","):
                key, value = field.strip().split(":", 1)
                values[key] = value.strip()
            continue
        if re.match(r"\s+" + re.escape(config.mode) + r":", line):
            raise ValueError("entrada de papel deve usar flow-style em uma linha")
    return values or {}


def _model(config: ServerConfig) -> str:
    if config.mode not in MODE_DEFAULTS:
        raise ValueError("papel Claude inválido")
    model = config.model or _role_config(config).get("model") or MODE_DEFAULTS[config.mode]
    if not re.fullmatch(r"[A-Za-z0-9._:-]+", model):
        raise ValueError("modelo Claude inválido")
    return model


def _fallback(config: ServerConfig) -> str | None:
    value = _role_config(config).get("fallback", MODE_FALLBACKS.get(config.mode, "none"))
    if config.mode == "reviewer":
        if value != "none":
            raise ValueError("reviewer não permite fallback automático")
        return None
    if value == "none":
        return None
    if value not in {"fable", "opus", "sonnet", "haiku"} or value == _model(config):
        raise ValueError("alternativa Claude deve ser única, explícita e compatível")
    return value


def _timeout(config: ServerConfig) -> float:
    value = float(_role_config(config).get("timeout", "900"))
    if not 0 < value <= 86400:
        raise ValueError("timeout Claude inválido")
    return value


def _capacity_error() -> str | None:
    path = Path.home() / ".codex/guard/backpressure.json"
    if not path.exists():
        return None
    try:
        state = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return "BACKPRESSURE: atualizar evidência de capacidade inválida"
    if not isinstance(state, dict) or not isinstance(state.get("active"), bool):
        return "BACKPRESSURE: atualizar evidência de capacidade inválida"
    if state.get("active"):
        return "BACKPRESSURE: atualizar capacidade antes de iniciar processos"
    return None


@lru_cache(maxsize=4)
def _check_executor(executable: str) -> None:
    help_result = subprocess.run([executable, "--help"], capture_output=True,
                                 text=True, timeout=5, check=False)
    if help_result.returncode != 0:
        raise ValueError("preflight do Claude CLI falhou")
    for flag in ("--restricted", "--strict-mcp-config", "--tools", "--output-format",
                 "--no-session-persistence"):
        if flag not in help_result.stdout:
            raise ValueError(f"Claude CLI sem capacidade obrigatória: {flag}")


def _build_claude_cmd(*, claude_exec: str, config: ServerConfig) -> list[str]:
    cmd = [
        claude_exec,
        "-p",
        "--model",
        _model(config),
        "--output-format",
        "json",
        "--no-session-persistence",
    ]

    if config.mode in READ_ONLY_MODES:
        cmd.extend(
            [
                "--restricted",
                "--strict-mcp-config",
                "--permission-mode",
                "dontAsk",
                "--tools",
                "Read",
                "Glob",
                "Grep",
                "--append-system-prompt",
                CHEAP_SYSTEM_PROMPT + (" " + ARCHITECT_SYSTEM_PROMPT if config.mode == "architect" else ""),
            ]
        )
    else:
        cmd.extend(["--permission-mode", "auto"])

    # A alternativa é executada pelo adaptador uma única vez, com receipt próprio.

    return cmd


def _log_telemetry(
    config: ServerConfig,
    prompt: str,
    duration_s: float,
    attempts: int,
    success: bool,
    model: str,
    thread_id: str,
    result: AgentResult,
    requested_model: str,
) -> None:
    """Log spawn_agent telemetry to event log."""
    import json

    project_dir = _project_dir()
    log_dir = Path(project_dir) / ".agents" / "tmp" / "claude"
    log_file = log_dir / "spawn-events.jsonl"

    event = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "server": config.server_name,
        "profile": None,
        "model": model,
        "requested_model": requested_model,
        "effective_models": list(result.effective_models),
        "model_evidence": "CLI_RESPONSE" if result.effective_models else "UNVERIFIED",
        "result": result.status,
        "partial": result.partial,
        "mode": config.mode,
        "thread_id": thread_id,
        "prompt_length": len(prompt),
        "duration_s": round(duration_s, 2),
        "attempts": attempts,
        "success": success,
    }
    try:
        log_dir.mkdir(parents=True, exist_ok=True)
        with open(log_file, "a", encoding="utf-8") as f:
            f.write(json.dumps(event, ensure_ascii=True) + "\n")
    except OSError:
        pass


def _save_partial(text: str, work_directory: str) -> str | None:
    if not text.strip():
        return None
    target = Path(work_directory) / ".agents/tmp/claude"
    try:
        target.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", prefix="partial-",
                                         suffix=".txt", dir=target, delete=False) as handle:
            handle.write(text)
            return handle.name
    except OSError:
        return None


def _unavailable(text: str) -> bool:
    return bool(re.search(r"unknown model|model_not_found|overloaded|overload_error|"
                         r"model [\"'`][^\"'`]+[\"'`].{0,40}(not found|not supported|unavailable)|"
                         r"The [\"'`][^\"'`]+[\"'`] model is not supported", text, re.I))


def _kill_executor(proc: asyncio.subprocess.Process) -> None:
    if proc.returncode is not None:
        return
    try:
        if os.name == "posix":
            os.killpg(proc.pid, signal.SIGKILL)
        else:
            proc.kill()
    except ProcessLookupError:
        pass


async def _run_agent(ctx: Context, prompt: str, config: ServerConfig, thread_id: str) -> str:
    if not isinstance(prompt, str) or not prompt.strip():
        return "Error: 'prompt' must be a non-empty string."
    capacity = _capacity_error()
    if capacity:
        return f"Error: {capacity}"
    try:
        model = _model(config)
        fallback = _fallback(config)
        _timeout(config)
        claude_exec = _resolve_claude_executable()
        _check_executor(claude_exec)
    except (OSError, ValueError, subprocess.SubprocessError) as err:
        return f"Error: {err}"

    start_ts = time.monotonic()
    work_directory = _project_dir()
    current = config
    for attempt in range(MAX_RETRIES):
        result = await _run_agent_once(ctx, prompt, current, claude_exec, work_directory, attempt)
        _log_telemetry(config, prompt, time.monotonic() - start_ts, attempt + 1,
                       result.status == "OK", _model(current), thread_id, result, model)
        if result.status == "OK":
            return result.text
        if attempt == 0 and result.status == "MODEL_UNAVAILABLE" and fallback and not result.partial:
            current = replace(config, model=fallback)
            continue
        partial = f" Partial: {result.partial}" if result.partial else ""
        return f"Error: {result.status}. {result.text}{partial}"
    return "Error: executor exhausted configured attempts."


async def _run_agent_once(ctx: Context, prompt: str, config: ServerConfig,
                          claude_exec: str, work_directory: str, attempt: int) -> AgentResult:
    capacity = _capacity_error()
    if capacity:
        return AgentResult(capacity, "BACKPRESSURE")
    cmd = _build_claude_cmd(claude_exec=claude_exec, config=config)
    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd, stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE, env=_build_child_env(config), cwd=work_directory,
            start_new_session=os.name == "posix")
    except OSError as err:
        return AgentResult(str(err), "SPAWN_FAILED")

    communication = asyncio.create_task(proc.communicate(prompt.encode("utf-8")))
    try:
        stdout_bytes, stderr_bytes = await asyncio.wait_for(asyncio.shield(communication),
                                                           timeout=_timeout(config))
    except asyncio.TimeoutError:
        _kill_executor(proc)
        stdout_bytes, _ = await communication
        await proc.wait()
        partial = _save_partial(stdout_bytes.decode(errors="replace"), work_directory)
        return AgentResult("deadline exceeded; no automatic retry", "TIMEOUT", partial=partial)
    except asyncio.CancelledError:
        _kill_executor(proc)
        stdout_bytes, _ = await communication
        await proc.wait()
        _save_partial(stdout_bytes.decode(errors="replace"), work_directory)
        raise
    except Exception:
        _kill_executor(proc)
        await proc.wait()
        if not communication.done():
            communication.cancel()
        await asyncio.gather(communication, return_exceptions=True)
        raise

    stdout = stdout_bytes.decode(errors="replace").strip()
    stderr = stderr_bytes.decode(errors="replace")
    if proc.returncode != 0:
        status = "MODEL_UNAVAILABLE" if _unavailable(stderr) else "SPAWN_FAILED"
        return AgentResult(f"executor exit {proc.returncode}", status,
                           partial=_save_partial(stdout, work_directory))
    if not stdout:
        return AgentResult("executor returned no artifact", "EMPTY_OUTPUT")
    try:
        payload = json.loads(stdout)
    except ValueError:
        return AgentResult("missing structured completion receipt", "INVALID_OUTPUT",
                           partial=_save_partial(stdout, work_directory))
    if not isinstance(payload, dict) or payload.get("type") != "result":
        return AgentResult("missing result receipt", "INVALID_OUTPUT",
                           partial=_save_partial(stdout, work_directory))
    text = payload.get("result", "")
    if not isinstance(text, str):
        text = ""
    usage = payload.get("modelUsage", {})
    effective = tuple(sorted(usage)) if isinstance(usage, dict) else ()
    if payload.get("is_error") or payload.get("subtype") != "success":
        status = "MODEL_UNAVAILABLE" if _unavailable(text) else "EXECUTION_FAILED"
        return AgentResult("CLI reported unsuccessful completion", status, effective,
                           _save_partial(text, work_directory) if status != "MODEL_UNAVAILABLE" else None)
    if not text.strip():
        return AgentResult("result receipt contains no artifact", "EMPTY_OUTPUT", effective)
    return AgentResult(text.strip(), "OK", effective)


def _build_server(config: ServerConfig) -> FastMCP:
    mcp = FastMCP(config.server_name)
    _session_counter = {"n": 0}

    @mcp.tool()
    async def spawn_agent(ctx: Context, prompt: str, thread_id: str = "") -> str:
        """Spawn a Claude agent with the configured mode/model.

        Args:
            prompt: The task prompt for the Claude agent.
            thread_id: Optional thread ID for telemetry tagging.
                       Claude CLI is session-scoped; thread_id is telemetry only.
        """
        _session_counter["n"] += 1
        tid = thread_id or f"{config.server_name}-{_session_counter['n']}"

        return await _run_agent(ctx, prompt, config, tid)

    if config.mode == "architect":

        @mcp.tool()
        async def spawn_cheap_agent(ctx: Context, prompt: str, thread_id: str = "") -> str:
            """Spawn a low-cost read-only Claude leaf without another MCP server."""
            _session_counter["n"] += 1
            tid = thread_id or f"{config.server_name}-cheap-{_session_counter['n']}"
            cheap_config = replace(config, mode="cheap", model=None)
            return await _run_agent(ctx, prompt, cheap_config, tid)

    @mcp.tool()
    async def spawn_agents_parallel(
        ctx: Context,
        agents: list[dict],
        cancel_on_failure: bool = False,
    ) -> list[dict[str, str]]:
        """Spawn multiple Claude agents in parallel.

        Args:
            agents: List of dicts with 'prompt' field.
            cancel_on_failure: If True, cancel remaining agents when one fails.
        """
        if not isinstance(agents, list):
            return [{"index": "0", "error": "Error: 'agents' must be a list."}]
        if not agents:
            return [{"index": "0", "error": "Error: 'agents' list cannot be empty."}]

        if len(agents) > 2:
            return [{"index": "0", "error": "Error: at most two leaves per wave."}]

        cancel_event = asyncio.Event() if cancel_on_failure else None

        async def run_one(index: int, spec: dict) -> dict[str, str]:
            if cancel_event and cancel_event.is_set():
                return {"index": str(index), "error": "Cancelled: another agent failed."}

            if not isinstance(spec, dict):
                return {
                    "index": str(index),
                    "error": f"Agent {index}: spec must be a dictionary with a 'prompt' field.",
                }

            prompt = spec.get("prompt", "")
            output = await _run_agent(ctx, prompt, config, spec.get("thread_id", ""))
            if output.startswith("Error:"):
                if cancel_event:
                    cancel_event.set()
                return {"index": str(index), "error": output}
            return {"index": str(index), "output": output}

        tasks = [asyncio.create_task(run_one(i, agent)) for i, agent in enumerate(agents)]

        try:
            if cancel_on_failure:
                final_results: list[dict[str, str]] = [{}] * len(tasks)
                done: set[int] = set()
                while len(done) < len(tasks):
                    await asyncio.sleep(0.05)
                    for i, task in enumerate(tasks):
                        if i in done:
                            continue
                        if task.done():
                            done.add(i)
                            if task.cancelled():
                                final_results[i] = {"index": str(i), "status": "Cancelled: another agent failed."}
                                continue
                            exc = task.exception()
                            if exc:
                                final_results[i] = {"index": str(i), "error": f"Unexpected error: {exc}"}
                                cancel_event.set()  # type: ignore[union-attr]
                            else:
                                final_results[i] = task.result()
                                if "error" in final_results[i]:
                                    cancel_event.set()  # type: ignore[union-attr]
                            if cancel_event and cancel_event.is_set():
                                for j, t in enumerate(tasks):
                                    if j not in done and not t.done():
                                        t.cancel()
            else:
                results = await asyncio.gather(*tasks, return_exceptions=True)
                final_results = []
                for index, result in enumerate(results):
                    if isinstance(result, Exception):
                        final_results.append(
                            {"index": str(index), "error": f"Unexpected error: {result}"}
                        )
                    else:
                        final_results.append(result)

            return final_results
        finally:
            for task in tasks:
                if not task.done():
                    task.cancel()
            await asyncio.gather(*tasks, return_exceptions=True)

    return mcp


def main() -> None:
    config = _parse_args()
    server = _build_server(config)
    server.run()


if __name__ == "__main__":
    main()
