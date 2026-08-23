#!/usr/bin/env python3
"""Create and transport idempotent Canuto vault write envelopes.

Submissions are written atomically to a per-host outbox. Delivery is explicit:
copy to a local integrator inbox or flush over SSH. Failed delivery leaves the
outbox intact so an offline host never loses a proposed write.
"""

from __future__ import annotations

import argparse
import base64
import contextlib
import datetime as dt
import fcntl
import hashlib
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path, PurePosixPath
from typing import Any

SCHEMA_VERSION = 1
DEFAULT_MAX_CONTENT_BYTES = 5 * 1024 * 1024
ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$")
ENVELOPE_FILENAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}\.json$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
SSH_HOST_RE = re.compile(r"^[A-Za-z0-9_.@-]+$")
REMOTE_PATH_RE = re.compile(r"^/[A-Za-z0-9_./-]+$")


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def fsync_enabled() -> bool:
    return os.getenv("CANUTO_VAULT_TEST_NO_FSYNC") != "1"


def atomic_create_json(path: Path, value: dict[str, Any]) -> None:
    """Publish a new JSON file without ever replacing an existing ID."""
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.canuto-", dir=path.parent)
    tmp_path = Path(tmp_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", closefd=True) as handle:
            json.dump(value, handle, ensure_ascii=True, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            if fsync_enabled():
                os.fsync(handle.fileno())
        os.chmod(tmp_path, 0o600)
        os.link(tmp_path, path)
        if fsync_enabled():
            directory_fd = os.open(path.parent, os.O_RDONLY)
            try:
                os.fsync(directory_fd)
            finally:
                os.close(directory_fd)
    finally:
        try:
            tmp_path.unlink()
        except FileNotFoundError:
            pass


def generated_id() -> str:
    stamp = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    return f"we-{stamp}-{uuid.uuid4().hex[:16]}"


def load_content(path: Path, max_bytes: int) -> bytes:
    if not path.is_file():
        raise ValueError(f"content file does not exist: {path}")
    size = path.stat().st_size
    if size > max_bytes:
        raise ValueError(f"content exceeds {max_bytes} bytes")
    return path.read_bytes()


def submit(args: argparse.Namespace) -> int:
    envelope_id = args.id or generated_id()
    if not ID_RE.fullmatch(envelope_id):
        print("--id has an invalid format", file=sys.stderr)
        return 2
    if args.operation == "replace" and not (
        args.expected_sha256 and SHA256_RE.fullmatch(args.expected_sha256)
    ):
        print("replace requires --expected-sha256", file=sys.stderr)
        return 2
    if args.operation == "create" and args.expected_sha256:
        print("create must not include --expected-sha256", file=sys.stderr)
        return 2
    if args.tier == "curated" and not args.approval_by:
        print("curated submissions require --approval-by", file=sys.stderr)
        return 2
    try:
        content = load_content(args.content_file.expanduser(), args.max_content_bytes)
    except (OSError, ValueError) as exc:
        print(str(exc), file=sys.stderr)
        return 2

    created_at = args.created_at or utc_now()
    approval = None
    if args.approval_by:
        approval = {"by": args.approval_by, "at": args.approval_at or utc_now()}
    source_host = args.source_host or socket.gethostname().split(".")[0] or "unknown-host"
    source_agent = args.source_agent or os.getenv("CANUTO_AGENT", "manual")
    session_id = args.session_id or os.getenv("CLAUDE_SESSION_ID") or f"manual-{envelope_id}"
    envelope = {
        "schema_version": SCHEMA_VERSION,
        "id": envelope_id,
        "operation": args.operation,
        "target": args.target,
        "tier": args.tier,
        "expected_sha256": args.expected_sha256,
        "content_b64": base64.b64encode(content).decode("ascii"),
        "content_sha256": sha256_bytes(content),
        "source": {
            "host": source_host,
            "agent": source_agent,
            "session_id": session_id,
        },
        "approval": approval,
        "created_at": created_at,
    }
    outbox = args.outbox.expanduser()
    destination = outbox / f"{envelope_id}.json"
    try:
        atomic_create_json(destination, envelope)
    except FileExistsError:
        print(f"outbox already contains id {envelope_id}", file=sys.stderr)
        return 1
    print(json.dumps({"id": envelope_id, "outbox_path": str(destination)}, sort_keys=True))
    return 0


def validate_envelope_filename(final_name: str) -> None:
    if not ENVELOPE_FILENAME_RE.fullmatch(final_name):
        raise RuntimeError("outbox filename is not a valid envelope ID")


def deliver_local(sending: Path, inbox: Path, final_name: str) -> None:
    validate_envelope_filename(final_name)
    inbox.mkdir(parents=True, exist_ok=True)
    destination = inbox / final_name
    try:
        os.link(sending, destination)
    except FileExistsError:
        if destination.read_bytes() != sending.read_bytes():
            raise RuntimeError(f"inbox collision for {final_name}")
    except OSError:
        tmp = inbox / f".{final_name}.delivery-{os.getpid()}-{time.time_ns()}"
        shutil.copyfile(sending, tmp)
        if fsync_enabled():
            with tmp.open("rb") as handle:
                os.fsync(handle.fileno())
        try:
            os.link(tmp, destination)
        except FileExistsError:
            if destination.read_bytes() != sending.read_bytes():
                raise RuntimeError(f"inbox collision for {final_name}")
        finally:
            try:
                tmp.unlink()
            except FileNotFoundError:
                pass


def deliver_remote(
    sending: Path, host: str, remote_inbox: str, final_name: str, connect_timeout: int
) -> None:
    validate_envelope_filename(final_name)
    if host.startswith("-") or not SSH_HOST_RE.fullmatch(host):
        raise RuntimeError("SSH host contains unsupported characters")
    pure_remote = PurePosixPath(remote_inbox)
    if (
        not REMOTE_PATH_RE.fullmatch(remote_inbox)
        or ".." in pure_remote.parts
        or pure_remote.as_posix() != remote_inbox
    ):
        raise RuntimeError("remote inbox must be a normalized absolute POSIX path")
    remote_tmp = f"{remote_inbox}/.{final_name}.delivery-{os.getpid()}-{time.time_ns()}"
    remote_final = f"{remote_inbox}/{final_name}"
    ssh_base = [
        "ssh",
        "-o",
        "BatchMode=yes",
        "-o",
        f"ConnectTimeout={connect_timeout}",
        host,
    ]
    scp_base = [
        "scp",
        "-q",
        "-o",
        "BatchMode=yes",
        "-o",
        f"ConnectTimeout={connect_timeout}",
    ]
    remote_prepare = (
        "import os,sys\n"
        "path=sys.argv[1]\n"
        "os.makedirs(path, mode=0o700, exist_ok=True)\n"
    )
    remote_publish = (
        "import os,sys\n"
        "src,dst=sys.argv[1:3]\n"
        "if os.path.exists(dst):\n"
        "    with open(src,'rb') as source, open(dst,'rb') as existing:\n"
        "        if source.read() != existing.read():\n"
        "            raise FileExistsError('remote inbox collision')\n"
        "    os.unlink(src)\n"
        "else:\n"
        "    os.link(src,dst)\n"
        "    os.unlink(src)\n"
    )
    remote_cleanup = (
        "import os,sys\n"
        "try:\n"
        "    os.unlink(sys.argv[1])\n"
        "except FileNotFoundError:\n"
        "    pass\n"
    )
    subprocess.run(
        [*ssh_base, "python3", "-", remote_inbox],
        input=remote_prepare,
        text=True,
        check=True,
    )
    try:
        subprocess.run([*scp_base, str(sending), f"{host}:{remote_tmp}"], check=True)
        subprocess.run(
            [*ssh_base, "python3", "-", remote_tmp, remote_final],
            input=remote_publish,
            text=True,
            check=True,
        )
    except subprocess.CalledProcessError:
        subprocess.run(
            [*ssh_base, "python3", "-", remote_tmp],
            input=remote_cleanup,
            text=True,
            check=False,
        )
        raise


@contextlib.contextmanager
def outbox_lock(outbox: Path):
    outbox.mkdir(parents=True, exist_ok=True)
    lock_path = outbox / ".flush.lock"
    with lock_path.open("a+", encoding="utf-8") as handle:
        try:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise RuntimeError("another flush process holds the outbox lock") from exc
        try:
            yield
        finally:
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def flush(args: argparse.Namespace) -> int:
    if bool(args.deliver_to) == bool(args.ssh_host):
        print("choose exactly one of --deliver-to or --ssh-host", file=sys.stderr)
        return 2
    if args.ssh_host and not args.remote_inbox:
        print("--ssh-host requires --remote-inbox", file=sys.stderr)
        return 2
    outbox = args.outbox.expanduser()
    outbox.mkdir(parents=True, exist_ok=True)
    sent = 0
    failed = 0
    try:
        with outbox_lock(outbox):
            for source in sorted(outbox.glob("*.json")):
                try:
                    if args.deliver_to:
                        deliver_local(source, args.deliver_to.expanduser(), source.name)
                    else:
                        deliver_remote(
                            source,
                            args.ssh_host,
                            args.remote_inbox,
                            source.name,
                            args.connect_timeout,
                        )
                    source.unlink()
                    sent += 1
                    print(f"DELIVERED {source.name}")
                except (OSError, RuntimeError, subprocess.CalledProcessError) as exc:
                    failed += 1
                    print(f"DELIVERY FAILED {source.name}: {exc}", file=sys.stderr)
    except RuntimeError as exc:
        print(f"FLUSH LOCKED: {exc}", file=sys.stderr)
        return 75
    print(f"SUMMARY delivered={sent} failed={failed} remaining={len(list(outbox.glob('*.json')))}")
    return 1 if failed else 0


def list_outbox(args: argparse.Namespace) -> int:
    outbox = args.outbox.expanduser()
    values = []
    for path in sorted(outbox.glob("*.json")) if outbox.exists() else []:
        try:
            payload = json.loads(path.read_text(encoding="utf-8"))
            values.append(
                {
                    "id": payload.get("id"),
                    "operation": payload.get("operation"),
                    "target": payload.get("target"),
                    "path": str(path),
                }
            )
        except (OSError, json.JSONDecodeError):
            values.append({"id": None, "path": str(path), "invalid": True})
    print(json.dumps(values, ensure_ascii=True, sort_keys=True))
    return 0


def outbox_default() -> Path:
    return Path(os.getenv("CANUTO_VAULT_OUTBOX", "~/.canuto/vault-spool/outbox"))


def add_submit_arguments(parser: argparse.ArgumentParser, operation: str) -> None:
    parser.set_defaults(operation=operation, handler=submit)
    parser.add_argument("--target", required=True)
    parser.add_argument("--content-file", type=Path, required=True)
    parser.add_argument("--tier", choices=["hypothesis", "curated"], default="hypothesis")
    parser.add_argument("--expected-sha256")
    parser.add_argument("--id")
    parser.add_argument("--source-host")
    parser.add_argument("--source-agent")
    parser.add_argument("--session-id")
    parser.add_argument("--approval-by")
    parser.add_argument("--approval-at")
    parser.add_argument("--created-at", help=argparse.SUPPRESS)
    parser.add_argument("--max-content-bytes", type=int, default=DEFAULT_MAX_CONTENT_BYTES)
    parser.add_argument("--outbox", type=Path, default=outbox_default())


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    add_submit_arguments(subparsers.add_parser("create"), "create")
    add_submit_arguments(subparsers.add_parser("replace"), "replace")

    flush_parser = subparsers.add_parser("flush")
    flush_parser.add_argument("--outbox", type=Path, default=outbox_default())
    flush_parser.add_argument("--deliver-to", type=Path)
    flush_parser.add_argument("--ssh-host")
    flush_parser.add_argument("--remote-inbox")
    flush_parser.add_argument("--connect-timeout", type=int, default=10)
    flush_parser.set_defaults(handler=flush)

    list_parser = subparsers.add_parser("list")
    list_parser.add_argument("--outbox", type=Path, default=outbox_default())
    list_parser.set_defaults(handler=list_outbox)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    if getattr(args, "max_content_bytes", 1) <= 0:
        print("--max-content-bytes must be positive", file=sys.stderr)
        return 2
    if getattr(args, "connect_timeout", 1) <= 0:
        print("--connect-timeout must be positive", file=sys.stderr)
        return 2
    return int(args.handler(args))


if __name__ == "__main__":
    raise SystemExit(main())
