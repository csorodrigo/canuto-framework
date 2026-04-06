#!/usr/bin/env python3
"""Codex MCP bridge with explicit role routing.

This wrapper exists because the stock ``codex-as-mcp`` server always spawns the
default Codex CLI profile. Here we expose the same ``spawn_agent`` and
``spawn_agents_parallel`` tools, but force the caller onto a specific profile
or model so ``codex-coder`` and ``codex-reviewer`` are deterministic.
"""

from __future__ import annotations

import argparse
import asyncio
import os
import shutil
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path

from mcp.server.fastmcp import Context, FastMCP


def _safe_int(val: str, default: int) -> int:
    try:
        return int(val)
    except (ValueError, TypeError):
        return default


def _safe_float(val: str, default: float) -> float:
    try:
        return float(val)
    except (ValueError, TypeError):
        return default


DEFAULT_TIMEOUT_SECONDS = _safe_int(os.environ.get("CODEX_TIMEOUT_SECONDS", ""), 8 * 60 * 60)
MAX_RETRIES = _safe_int(os.environ.get("CODEX_MAX_RETRIES", ""), 3)
RETRY_BASE_DELAY = _safe_float(os.environ.get("CODEX_RETRY_DELAY", ""), 2.0)


@dataclass(frozen=True)
class ServerConfig:
    server_name: str
    profile: str | None
    model: str | None
    reasoning_effort: str | None
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
    parser = argparse.ArgumentParser(prog="codex-agent-mcp", add_help=True)
    parser.add_argument("--server-name", required=True)
    parser.add_argument("--profile")
    parser.add_argument("--model")
    parser.add_argument("--reasoning-effort")
    parser.add_argument("--mode", choices=["coder", "reviewer"], required=True)
    parser.add_argument(
        "--env",
        action="append",
        default=[],
        metavar="KEY=VALUE",
        help="Set env vars for spawned Codex CLI processes.",
    )

    args = parser.parse_args()

    overrides: dict[str, str] = {}
    for pair in args.env:
        key, value = _parse_env_kv(pair)
        overrides[key] = value

    return ServerConfig(
        server_name=args.server_name,
        profile=args.profile,
        model=args.model,
        reasoning_effort=args.reasoning_effort,
        mode=args.mode,
        env_overrides=overrides,
    )


def _resolve_codex_executable() -> str:
    codex = shutil.which("codex")
    if not codex:
        raise FileNotFoundError(
            "Codex CLI not found in PATH. Install it and ensure the binary is available."
        )
    return codex


def _project_dir() -> str:
    return os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()


def _build_child_env(config: ServerConfig) -> dict[str, str]:
    env = dict(os.environ)
    env.update(config.env_overrides)
    return env


def _build_codex_cmd(
    *,
    codex_exec: str,
    config: ServerConfig,
    work_directory: str,
    output_path: Path,
) -> list[str]:
    cmd = [
        codex_exec,
        "exec",
        "--cd",
        work_directory,
        "--skip-git-repo-check",
    ]

    if config.mode == "coder":
        cmd.append("--dangerously-bypass-approvals-and-sandbox")
    else:
        cmd.extend(["-s", "read-only", "--ephemeral"])

    if config.profile:
        cmd.extend(["--profile", config.profile])
    elif config.model:
        cmd.extend(["-m", config.model])

    if config.reasoning_effort:
        cmd.extend(["-c", f'model_reasoning_effort="{config.reasoning_effort}"'])

    cmd.extend(["--output-last-message", str(output_path), "-"])
    return cmd


async def _run_agent(ctx: Context, prompt: str, config: ServerConfig) -> str:
    if not isinstance(prompt, str):
        return "Error: 'prompt' must be a string."
    if not prompt.strip():
        return "Error: 'prompt' is required and cannot be empty."

    try:
        codex_exec = _resolve_codex_executable()
    except FileNotFoundError as err:
        return f"Error: {err}"

    work_directory = _project_dir()
    start_ts = time.monotonic()
    last_error = ""

    for attempt in range(MAX_RETRIES):
        result = await _run_agent_once(
            ctx, prompt, config, codex_exec, work_directory, attempt
        )
        if not result.startswith("Error:"):
            _log_telemetry(config, prompt, time.monotonic() - start_ts, attempt + 1, True)
            return result

        last_error = result
        # Don't retry on user errors (empty prompt, bad config)
        if "must be a string" in result or "cannot be empty" in result:
            return result

        if attempt < MAX_RETRIES - 1:
            delay = RETRY_BASE_DELAY * (2 ** attempt)
            try:
                await ctx.report_progress(
                    0, None,
                    f"{config.server_name}: attempt {attempt + 1} failed, retrying in {delay:.0f}s..."
                )
            except Exception:
                pass
            await asyncio.sleep(delay)

    _log_telemetry(config, prompt, time.monotonic() - start_ts, MAX_RETRIES, False)
    return last_error


def _log_telemetry(
    config: ServerConfig,
    prompt: str,
    duration_s: float,
    attempts: int,
    success: bool,
) -> None:
    """C3: Log spawn_agent telemetry to event log."""
    import json

    project_dir = _project_dir()
    log_dir = Path(project_dir) / ".agents" / "tmp" / "codex"
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / "spawn-events.jsonl"

    event = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "server": config.server_name,
        "profile": config.profile,
        "model": config.model,
        "mode": config.mode,
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


async def _run_agent_once(
    ctx: Context,
    prompt: str,
    config: ServerConfig,
    codex_exec: str,
    work_directory: str,
    attempt: int,
) -> str:
    with tempfile.TemporaryDirectory(prefix="codex_output_") as temp_dir:
        output_path = Path(temp_dir) / "last_message.md"
        output_path.touch()

        cmd = _build_codex_cmd(
            codex_exec=codex_exec,
            config=config,
            work_directory=work_directory,
            output_path=output_path,
        )

        try:
            await ctx.report_progress(0, None, f"Launching {config.server_name}...")
        except Exception:
            pass

        try:
            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
                env=_build_child_env(config),
            )
        except Exception as err:
            return f"Error: Failed to launch Codex agent: {err}"

        # Write prompt to stdin, then close
        if proc.stdin:
            proc.stdin.write(prompt.encode("utf-8"))
            try:
                await proc.stdin.drain()
            except Exception:
                pass
            proc.stdin.close()

        # C5: Read stdout and stderr concurrently to avoid deadlock.
        # Use asyncio tasks for stdout (full read) and stderr (streamed chunks).
        stdout_task = asyncio.create_task(proc.stdout.read()) if proc.stdout else None
        stderr_chunks: list[bytes] = []

        async def _stream_stderr() -> None:
            """Read stderr in chunks, forward last line as progress."""
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
                            1, None,
                            f"{config.server_name}: {last_line[:120]}"
                        )
                    except Exception:
                        pass

        stderr_task = asyncio.create_task(_stream_stderr())

        # Heartbeat while waiting for process to finish
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
                            1, None,
                            f"{config.server_name} running ({elapsed}s)..."
                        )
                    except Exception:
                        pass

        # Wait for stream tasks to complete
        if stderr_task:
            try:
                await asyncio.wait_for(stderr_task, timeout=5.0)
            except (asyncio.TimeoutError, Exception):
                pass

        stdout = ""
        if stdout_task:
            stdout = (await stdout_task).decode(errors="replace")

        stderr = b"".join(stderr_chunks).decode(errors="replace")

        output = output_path.read_text(encoding="utf-8").strip()

        if returncode != 0:
            details = [
                "Error: Codex agent exited with a non-zero status.",
                f"Command: {' '.join(cmd)}",
                f"Exit Code: {returncode}",
            ]
            if stderr:
                details.append(f"Stderr: {stderr}")
            if stdout:
                details.append(f"Stdout: {stdout}")
            if output:
                details.append(f"Captured Output: {output}")
            return "\n".join(details)

        return output or stdout.strip()


def _build_server(config: ServerConfig) -> FastMCP:
    mcp = FastMCP(config.server_name)
    # C8: Session continuity — track thread IDs for multi-turn reviews
    _session_counter = {"n": 0}

    @mcp.tool()
    async def spawn_agent(ctx: Context, prompt: str, thread_id: str = "") -> str:
        """Spawn a Codex agent with the configured profile/model.

        Args:
            prompt: The task prompt for the Codex agent.
            thread_id: Optional thread ID for session continuity. If provided,
                       the agent's output is tagged with this ID for follow-up.
                       If empty, a new thread ID is generated automatically.
        """
        _session_counter["n"] += 1
        tid = thread_id or f"{config.server_name}-{_session_counter['n']}"

        result = await _run_agent(ctx, prompt, config)

        return result

    @mcp.tool()
    async def spawn_agents_parallel(
        ctx: Context,
        agents: list[dict],
        cancel_on_failure: bool = False,
    ) -> list[dict[str, str]]:
        """Spawn multiple Codex agents in parallel.

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

            output = await _run_agent(ctx, prompt, config)
            if output.startswith("Error:"):
                if cancel_event:
                    cancel_event.set()
                return {"index": str(index), "error": output}
            return {"index": str(index), "output": output}

        tasks = [asyncio.create_task(run_one(i, agent)) for i, agent in enumerate(agents)]

        if cancel_on_failure:
            # Wait for tasks individually so we can cancel on first failure
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
                        # Cancel remaining tasks if failure detected
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
