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


DEFAULT_TIMEOUT_SECONDS = 8 * 60 * 60


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

        stdout_task = asyncio.create_task(proc.stdout.read()) if proc.stdout else None
        stderr_task = asyncio.create_task(proc.stderr.read()) if proc.stderr else None
        stdin_task = asyncio.create_task(proc.stdin.drain()) if proc.stdin else None
        if proc.stdin:
            proc.stdin.write(prompt.encode("utf-8"))
            proc.stdin.close()

        last_ping = time.monotonic()
        while True:
            try:
                returncode = await asyncio.wait_for(proc.wait(), timeout=2.0)
                break
            except asyncio.TimeoutError:
                now = time.monotonic()
                if now - last_ping >= 2.0:
                    last_ping = now
                    try:
                        await ctx.report_progress(1, None, f"{config.server_name} running...")
                    except Exception:
                        pass

        if stdin_task:
            try:
                await stdin_task
            except Exception:
                pass

        stdout = ""
        if stdout_task:
            stdout = (await stdout_task).decode(errors="replace")

        stderr = ""
        if stderr_task:
            stderr = (await stderr_task).decode(errors="replace")

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

    @mcp.tool()
    async def spawn_agent(ctx: Context, prompt: str) -> str:
        """Spawn a Codex agent with the configured profile/model."""
        return await _run_agent(ctx, prompt, config)

    @mcp.tool()
    async def spawn_agents_parallel(ctx: Context, agents: list[dict]) -> list[dict[str, str]]:
        """Spawn multiple Codex agents in parallel."""
        if not isinstance(agents, list):
            return [{"index": "0", "error": "Error: 'agents' must be a list."}]
        if not agents:
            return [{"index": "0", "error": "Error: 'agents' list cannot be empty."}]

        async def run_one(index: int, spec: dict) -> dict[str, str]:
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
                return {"index": str(index), "error": output}
            return {"index": str(index), "output": output}

        results = await asyncio.gather(
            *(run_one(i, agent) for i, agent in enumerate(agents)),
            return_exceptions=True,
        )

        final_results: list[dict[str, str]] = []
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
