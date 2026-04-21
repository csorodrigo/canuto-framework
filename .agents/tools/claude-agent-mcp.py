#!/usr/bin/env python3
"""Claude MCP bridge with explicit role routing."""

from __future__ import annotations

import argparse
import asyncio
import os
import shutil
import time
from dataclasses import dataclass
from pathlib import Path

from mcp.server.fastmcp import Context, FastMCP


MAX_RETRIES = 3
RETRY_BASE_DELAY = 2.0

MODE_DEFAULTS = {
    "architect": "claude-opus-4-7",
    "reviewer": "claude-sonnet-4-6",
}

ARCHITECT_SYSTEM_PROMPT = (
    "You are Claude Opus acting as Architect in a multi-agent AI framework. "
    "Respond with structured plans and analysis only. Be concise and direct."
)


@dataclass(frozen=True)
class ServerConfig:
    server_name: str
    model: str | None
    mode: str
    env_overrides: dict[str, str]


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
    parser.add_argument("--mode", choices=["architect", "reviewer"], required=True)
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


def _model(config: ServerConfig) -> str:
    return config.model or MODE_DEFAULTS[config.mode]


def _build_claude_cmd(*, claude_exec: str, config: ServerConfig) -> list[str]:
    cmd = [
        claude_exec,
        "-p",
        "--model",
        _model(config),
        "--output-format",
        "text",
        "--permission-mode",
        "auto",
    ]

    if config.mode == "architect":
        cmd.extend(["--append-system-prompt", ARCHITECT_SYSTEM_PROMPT])

    return cmd


def _log_telemetry(
    config: ServerConfig,
    prompt: str,
    duration_s: float,
    attempts: int,
    success: bool,
    model: str,
    thread_id: str,
) -> None:
    """Log spawn_agent telemetry to event log."""
    import json

    project_dir = _project_dir()
    log_dir = Path(project_dir) / ".agents" / "tmp" / "claude"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / "spawn-events.jsonl"

    event = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "server": config.server_name,
        "profile": None,
        "model": model,
        "mode": config.mode,
        "thread_id": thread_id,
        "prompt_length": len(prompt),
        "duration_s": round(duration_s, 2),
        "attempts": attempts,
        "success": success,
    }
    try:
        with open(log_file, "a", encoding="utf-8") as f:
            f.write(json.dumps(event, ensure_ascii=True) + "\n")
    except OSError:
        pass


async def _run_agent(
    ctx: Context,
    prompt: str,
    config: ServerConfig,
    thread_id: str,
) -> str:
    if not isinstance(prompt, str):
        return "Error: 'prompt' must be a string."
    if not prompt.strip():
        return "Error: 'prompt' is required and cannot be empty."

    try:
        claude_exec = _resolve_claude_executable()
    except FileNotFoundError as err:
        return f"Error: {err}"

    work_directory = _project_dir()
    model = _model(config)
    start_ts = time.monotonic()
    last_error = ""

    for attempt in range(MAX_RETRIES):
        result = await _run_agent_once(
            ctx,
            prompt,
            config,
            claude_exec,
            work_directory,
            attempt,
        )
        if not result.startswith("Error:"):
            _log_telemetry(
                config,
                prompt,
                time.monotonic() - start_ts,
                attempt + 1,
                True,
                model,
                thread_id,
            )
            return result

        last_error = result
        if "must be a string" in result or "cannot be empty" in result:
            return result

        if attempt < MAX_RETRIES - 1:
            delay = RETRY_BASE_DELAY * (2 ** attempt)
            try:
                await ctx.report_progress(
                    attempt,
                    MAX_RETRIES,
                    f"{config.server_name}: attempt {attempt + 1} failed, retrying in {delay:.0f}s...",
                )
            except Exception:
                pass
            await asyncio.sleep(delay)

    _log_telemetry(
        config,
        prompt,
        time.monotonic() - start_ts,
        MAX_RETRIES,
        False,
        model,
        thread_id,
    )
    return last_error


async def _run_agent_once(
    ctx: Context,
    prompt: str,
    config: ServerConfig,
    claude_exec: str,
    work_directory: str,
    attempt: int,
) -> str:
    cmd = _build_claude_cmd(claude_exec=claude_exec, config=config)
    model = _model(config)

    try:
        await ctx.report_progress(
            attempt,
            MAX_RETRIES,
            f"{config.server_name}: launching {model}...",
        )
    except Exception:
        pass

    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
            env=_build_child_env(config),
            cwd=work_directory,
        )
    except Exception as err:
        return f"Error: Failed to launch Claude agent: {err}"

    if proc.stdin:
        proc.stdin.write(prompt.encode("utf-8"))
        try:
            await proc.stdin.drain()
        except Exception:
            pass
        proc.stdin.close()

    stdout_task = asyncio.create_task(proc.stdout.read()) if proc.stdout else None
    stderr_chunks: list[bytes] = []

    async def _stream_stderr() -> None:
        if not proc.stderr:
            return
        while True:
            chunk = await proc.stderr.read(4096)
            if not chunk:
                break
            stderr_chunks.append(chunk)
            last_line = chunk.decode(errors="replace").strip().split("\n")[-1]
            if last_line:
                try:
                    await ctx.report_progress(
                        attempt,
                        MAX_RETRIES,
                        f"{config.server_name}: {last_line[:120]}",
                    )
                except Exception:
                    pass

    stderr_task = asyncio.create_task(_stream_stderr())

    start_time = time.monotonic()
    last_heartbeat = start_time
    while True:
        try:
            returncode = await asyncio.wait_for(proc.wait(), timeout=5.0)
            break
        except asyncio.TimeoutError:
            now = time.monotonic()
            if now - last_heartbeat >= 5.0:
                elapsed = int(now - start_time)
                last_heartbeat = now
                try:
                    await ctx.report_progress(
                        attempt,
                        MAX_RETRIES,
                        f"{config.server_name} running ({elapsed}s)...",
                    )
                except Exception:
                    pass

    if stderr_task:
        try:
            await asyncio.wait_for(stderr_task, timeout=5.0)
        except (asyncio.TimeoutError, Exception):
            pass

    stdout = ""
    if stdout_task:
        stdout = (await stdout_task).decode(errors="replace")

    stderr = b"".join(stderr_chunks).decode(errors="replace")

    if returncode != 0:
        details = [
            "Error: Claude agent exited with a non-zero status.",
            f"Command: {' '.join(cmd)}",
            f"Exit Code: {returncode}",
        ]
        if stderr:
            details.append(f"Stderr: {stderr}")
        if stdout:
            details.append(f"Stdout: {stdout}")
        return "\n".join(details)

    return stdout.strip()


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
            try:
                await ctx.report_progress(
                    index,
                    len(agents),
                    f"Starting agent {index + 1}/{len(agents)}...",
                )
            except Exception:
                pass

            output = await _run_agent(ctx, prompt, config, spec.get("thread_id", ""))
            if output.startswith("Error:"):
                if cancel_event:
                    cancel_event.set()
                return {"index": str(index), "error": output}
            return {"index": str(index), "output": output}

        tasks = [asyncio.create_task(run_one(i, agent)) for i, agent in enumerate(agents)]

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

    return mcp


def main() -> None:
    config = _parse_args()
    server = _build_server(config)
    server.run()


if __name__ == "__main__":
    main()
