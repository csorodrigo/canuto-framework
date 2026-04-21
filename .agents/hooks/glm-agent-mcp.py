#!/usr/bin/env python3
"""GLM MCP bridge for Z.AI's OpenAI-compatible API."""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import time
from dataclasses import dataclass
from pathlib import Path

import openai
from mcp.server.fastmcp import Context, FastMCP


ZAI_BASE_URL = "https://api.z.ai/api/coding/paas/v4"
MAX_RETRIES = 3
RETRY_BASE_DELAY = 2.0

SYSTEM_PROMPTS = {
    "coder": (
        "You are an expert software engineer. Produce complete, working code changes. "
        "When modifying files, output the complete updated file content or a unified diff. "
        "Be precise and thorough."
    ),
    "reviewer": (
        "You are an expert code reviewer. Analyze the provided code or diff. Score each "
        "dimension (correctness, security, design, tests, readability) from 0-10. Provide "
        "an overall score and specific actionable feedback."
    ),
}


@dataclass(frozen=True)
class ServerConfig:
    server_name: str
    mode: str
    primary_model: str
    fallback_model: str


def _parse_args() -> ServerConfig:
    parser = argparse.ArgumentParser(prog="glm-agent-mcp", add_help=True)
    parser.add_argument("--server-name", required=True)
    parser.add_argument("--mode", choices=["coder", "reviewer"], required=True)
    parser.add_argument("--primary-model", default="glm-4.6")
    parser.add_argument("--fallback-model", default="glm-4.5")
    args = parser.parse_args()
    return ServerConfig(
        server_name=args.server_name,
        mode=args.mode,
        primary_model=args.primary_model,
        fallback_model=args.fallback_model,
    )


def _project_dir() -> str:
    return os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()


def _load_api_key() -> str:
    if os.environ.get("ZAI_API_KEY"):
        return os.environ["ZAI_API_KEY"]

    env_file = Path.home() / ".config" / "canuto" / "zai.env"
    if not env_file.exists():
        return ""

    try:
        for line in env_file.read_text(encoding="utf-8").splitlines():
            stripped = line.strip()
            if not stripped or stripped.startswith("#") or "=" not in stripped:
                continue
            key, value = stripped.split("=", 1)
            if key.strip() == "ZAI_API_KEY":
                return value.strip().strip("\"'")
    except OSError:
        return ""

    return ""


def _response_text(response: object) -> str:
    choices = getattr(response, "choices", None) or []
    if not choices:
        return ""

    message = getattr(choices[0], "message", None)
    content = getattr(message, "content", "") if message is not None else ""
    if isinstance(content, str):
        return content.strip()
    if isinstance(content, list):
        parts: list[str] = []
        for item in content:
            text = getattr(item, "text", None)
            if text is None and isinstance(item, dict):
                text = item.get("text")
            if text:
                parts.append(str(text))
        return "\n".join(parts).strip()
    return str(content).strip() if content else ""


def _log_fallback(origin: str, destination: str) -> None:
    log_dir = Path.home() / ".claude" / "logs"
    try:
        log_dir.mkdir(parents=True, exist_ok=True)
        event = {
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "origin": origin,
            "destination": destination,
            "reason": "http_429_concurrency_limit",
        }
        with (log_dir / "glm-fallback.log").open("a", encoding="utf-8") as f:
            f.write(json.dumps(event, ensure_ascii=True, separators=(",", ":")) + "\n")
    except OSError:
        pass


def _log_telemetry(
    config: ServerConfig,
    prompt: str,
    duration_s: float,
    attempts: int,
    success: bool,
    model: str,
) -> None:
    log_dir = Path(_project_dir()) / ".agents" / "tmp" / "codex"
    try:
        log_dir.mkdir(parents=True, exist_ok=True)
        event = {
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "server": config.server_name,
            "profile": None,
            "model": model,
            "mode": config.mode,
            "prompt_length": len(prompt),
            "duration_s": round(duration_s, 2),
            "attempts": attempts,
            "success": success,
        }
        with (log_dir / "spawn-events.jsonl").open("a", encoding="utf-8") as f:
            f.write(json.dumps(event, ensure_ascii=True) + "\n")
    except OSError:
        pass


async def _chat_once(
    client: openai.AsyncOpenAI,
    config: ServerConfig,
    prompt: str,
    model: str,
) -> str:
    response = await client.chat.completions.create(
        model=model,
        messages=[
            {"role": "system", "content": SYSTEM_PROMPTS[config.mode]},
            {"role": "user", "content": prompt},
        ],
    )
    return _response_text(response)


async def _run_agent(ctx: Context, prompt: str, config: ServerConfig) -> str:
    if not isinstance(prompt, str):
        return "Error: 'prompt' must be a string."
    if not prompt.strip():
        return "Error: 'prompt' is required and cannot be empty."

    api_key = _load_api_key()
    if not api_key:
        return (
            "Error: ZAI_API_KEY not configured. Set ZAI_API_KEY or create "
            "~/.config/canuto/zai.env with ZAI_API_KEY=..."
        )

    client = openai.AsyncOpenAI(base_url=ZAI_BASE_URL, api_key=api_key, max_retries=0)
    start_ts = time.monotonic()
    model = config.primary_model
    last_error = ""
    fallback_used = False

    for attempt in range(1, MAX_RETRIES + 1):
        try:
            await ctx.report_progress(
                attempt - 1,
                MAX_RETRIES,
                f"{config.server_name}: calling {model}...",
            )
        except Exception:
            pass

        try:
            result = await _chat_once(client, config, prompt, model)
            _log_telemetry(
                config,
                prompt,
                time.monotonic() - start_ts,
                attempt,
                True,
                model,
            )
            return result or "Error: GLM returned an empty response."
        except openai.APIStatusError as err:
            status_code = getattr(err, "status_code", None)
            if status_code == 429 and model == config.primary_model and not fallback_used:
                _log_fallback(config.primary_model, config.fallback_model)
                model = config.fallback_model
                fallback_used = True
                last_error = "HTTP 429 from primary model; retried with fallback model."
                continue

            last_error = f"Error: Z.AI API request failed with HTTP {status_code}: {err}"
        except Exception as err:
            last_error = f"Error: Z.AI API request failed: {err}"

        if attempt < MAX_RETRIES:
            delay = RETRY_BASE_DELAY * (2 ** (attempt - 1))
            try:
                await ctx.report_progress(
                    attempt,
                    MAX_RETRIES,
                    f"{config.server_name}: attempt {attempt} failed, retrying in {delay:.0f}s...",
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
    )
    return last_error or "Error: Z.AI API request failed."


def _build_server(config: ServerConfig) -> FastMCP:
    mcp = FastMCP(config.server_name)
    session_counter = {"n": 0}

    @mcp.tool()
    async def spawn_agent(ctx: Context, prompt: str, thread_id: str = "") -> str:
        """Spawn a GLM agent through Z.AI."""
        session_counter["n"] += 1
        _ = thread_id or f"{config.server_name}-{session_counter['n']}"
        return await _run_agent(ctx, prompt, config)

    @mcp.tool()
    async def spawn_agents_parallel(
        ctx: Context,
        agents: list[dict],
        cancel_on_failure: bool = False,
    ) -> list[dict[str, str]]:
        """Spawn multiple GLM agents in parallel."""
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

            try:
                await ctx.report_progress(
                    index,
                    len(agents),
                    f"Starting GLM agent {index + 1}/{len(agents)}...",
                )
            except Exception:
                pass

            output = await _run_agent(ctx, spec.get("prompt", ""), config)
            if output.startswith("Error:"):
                if cancel_event:
                    cancel_event.set()
                return {"index": str(index), "error": output}
            return {"index": str(index), "output": output}

        tasks = [asyncio.create_task(run_one(i, agent)) for i, agent in enumerate(agents)]
        results = await asyncio.gather(*tasks, return_exceptions=True)

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
