"""Git and receipt helpers for the Canuto vault integrator."""

from __future__ import annotations

import contextlib
import os
import re
import shutil
import subprocess
import time
from pathlib import Path
from typing import Any, Iterable

from vault_integrator_common import (
    SCHEMA_VERSION,
    CommitError,
    atomic_write_bytes,
    utc_now,
)

def run_git(vault: Path, args: Iterable[str], check: bool = True) -> subprocess.CompletedProcess[str]:
    command = ["git", "-C", str(vault), *args]
    return subprocess.run(
        command,
        check=check,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def git_head(vault: Path) -> str | None:
    try:
        return run_git(vault, ["rev-parse", "HEAD"]).stdout.strip() or None
    except (OSError, subprocess.CalledProcessError):
        return None


def ensure_git_repo(vault: Path) -> None:
    try:
        run_git(vault, ["rev-parse", "--is-inside-work-tree"])
    except (OSError, subprocess.CalledProcessError) as exc:
        raise CommitError("--commit requires the vault to be a Git working tree") from exc


def ensure_git_ready(vault: Path, expected_branch: str) -> None:
    ensure_git_repo(vault)
    try:
        branch = run_git(vault, ["symbolic-ref", "--quiet", "--short", "HEAD"]).stdout.strip()
    except (OSError, subprocess.CalledProcessError) as exc:
        raise CommitError("vault integrator refuses a detached HEAD") from exc
    if branch != expected_branch:
        raise CommitError(
            f"vault integrator expected branch '{expected_branch}', found '{branch}'"
        )
    try:
        dirty = run_git(
            vault, ["status", "--porcelain", "--untracked-files=all"]
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError) as exc:
        raise CommitError("could not inspect vault Git status") from exc
    if dirty:
        preview = " | ".join(dirty.splitlines()[:5])
        raise CommitError(f"vault Git working tree is not clean: {preview}")


def rollback_target(target: Path, previous: bytes | None, previous_mode: int) -> None:
    if previous is None:
        with contextlib.suppress(FileNotFoundError):
            target.unlink()
        return
    atomic_write_bytes(target, previous, previous_mode)


def commit_target(vault: Path, target_rel: str, envelope_id: str) -> str:
    if os.getenv("CANUTO_INTEGRATOR_TEST_FAIL_COMMIT") == "1":
        raise CommitError("commit failure injected for test")
    ensure_git_repo(vault)
    try:
        run_git(vault, ["add", "-A", "--", target_rel])
        result = run_git(
            vault,
            [
                "-c",
                "user.name=canuto-integrator",
                "-c",
                "user.email=canuto@localhost",
                "commit",
                "--only",
                "-m",
                f"vault: apply {envelope_id}",
                "--",
                target_rel,
            ],
        )
    except (OSError, subprocess.CalledProcessError) as exc:
        detail = getattr(exc, "stderr", "") or str(exc)
        raise CommitError(f"git commit failed: {detail.strip()}") from exc
    if not result.stdout and not result.stderr:
        raise CommitError("git commit returned no receipt")
    head = git_head(vault)
    if not head:
        raise CommitError("git commit succeeded but HEAD could not be resolved")
    return head


def receipt_filename(envelope_id: str) -> str:
    safe = re.sub(r"[^A-Za-z0-9._-]", "_", envelope_id)
    return f"{safe}.json"


def archive_envelope(source: Path, destination_dir: Path, envelope_hash: str) -> Path:
    destination_dir.mkdir(parents=True, exist_ok=True)
    destination = destination_dir / f"{source.stem}-{envelope_hash[:12]}.json"
    if destination.exists():
        if destination.read_bytes() == source.read_bytes():
            source.unlink()
            return destination
        destination = destination_dir / f"{source.stem}-{envelope_hash[:12]}-{time.time_ns()}.json"
    try:
        os.replace(source, destination)
    except OSError as exc:
        if getattr(exc, "errno", None) != 18:  # EXDEV
            raise
        shutil.copy2(source, destination)
        source.unlink()
    return destination


def base_receipt(
    envelope_id: str,
    envelope_hash: str,
    source_file: Path,
    status: str,
    reason: str | None = None,
) -> dict[str, Any]:
    receipt: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "id": envelope_id,
        "envelope_sha256": envelope_hash,
        "source_file": source_file.name,
        "status": status,
        "recorded_at": utc_now(),
    }
    if reason:
        receipt["reason"] = reason
    return receipt

