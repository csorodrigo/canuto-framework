#!/usr/bin/env python3
"""Serialize and apply reviewable writes to a Canuto Obsidian vault.

The integrator is intentionally narrow: v1 accepts only project-scoped Markdown
creates/replacements, validates content hashes and compare-and-swap preconditions,
and records immutable receipts outside the vault. It never deletes, moves, or
merges notes.
"""

from __future__ import annotations

import argparse
import contextlib
import fcntl
import json
import os
import sys
import time
from pathlib import Path

from vault_integrator_common import DEFAULT_MAX_CONTENT_BYTES, fsync_enabled, utc_now
from vault_integrator_engine import apply_one, pending_receipts, publish
from vault_integrator_git import CommitError, ensure_git_ready

EX_TEMPFAIL = 75

@contextlib.contextmanager
def integrator_lock(state: Path):
    locks = state / "locks"
    locks.mkdir(parents=True, exist_ok=True)
    lock_path = locks / "integrator.lock"
    with lock_path.open("a+", encoding="utf-8") as handle:
        try:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as exc:
            raise TimeoutError("another vault integrator holds the mutation lock") from exc
        handle.seek(0)
        handle.truncate()
        handle.write(json.dumps({"pid": os.getpid(), "acquired_at": utc_now()}) + "\n")
        handle.flush()
        if fsync_enabled():
            os.fsync(handle.fileno())
        hold = float(os.getenv("CANUTO_INTEGRATOR_HOLD_LOCK_SECONDS", "0") or "0")
        if hold > 0:
            time.sleep(hold)
        try:
            yield
        finally:
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def process(args: argparse.Namespace) -> int:
    if args.push and not args.commit:
        print("--push requires --commit", file=sys.stderr)
        return 2
    vault = args.vault.expanduser().resolve()
    if not vault.is_dir():
        print(f"vault does not exist: {vault}", file=sys.stderr)
        return 2
    inbox = args.inbox.expanduser().resolve()
    state = args.state.expanduser().resolve()
    for directory in (
        inbox,
        state / "receipts",
        state / "processed",
        state / "rejected",
        state / "collisions",
        state / "journal",
        state / "recovery",
        state / "locks",
    ):
        directory.mkdir(parents=True, exist_ok=True)
    try:
        with integrator_lock(state):
            if args.commit:
                try:
                    ensure_git_ready(vault, args.branch)
                except CommitError as exc:
                    print(f"GIT PREFLIGHT FAILED: {exc}", file=sys.stderr)
                    return 1
            counts = {"applied": 0, "duplicate": 0, "rejected": 0}
            receipt_paths: list[Path] = []
            for envelope_path in sorted(inbox.glob("*.json")):
                status, receipt_path = apply_one(
                    envelope_path,
                    vault,
                    state,
                    args.max_content_bytes,
                    args.commit,
                    args.push,
                )
                counts[status] += 1
                if receipt_path:
                    receipt_paths.append(receipt_path)
            push_ok = True
            if args.push:
                push_ok = publish(vault, state)
            print(
                "SUMMARY "
                + " ".join(f"{key}={value}" for key, value in counts.items())
                + f" push={'ok' if push_ok else 'failed'}"
            )
            return 1 if counts["rejected"] or not push_ok else 0
    except TimeoutError as exc:
        print(f"LOCKED: {exc}", file=sys.stderr)
        return EX_TEMPFAIL


def status(args: argparse.Namespace) -> int:
    inbox = args.inbox.expanduser()
    state = args.state.expanduser()
    result = {
        "inbox": len(list(inbox.glob("*.json"))) if inbox.exists() else 0,
        "receipts": len(list((state / "receipts").glob("*.json"))) if state.exists() else 0,
        "processed": len(list((state / "processed").glob("*.json"))) if state.exists() else 0,
        "rejected": len(list((state / "rejected").glob("*.json"))) if state.exists() else 0,
        "pending_publish": len(pending_receipts(state)) if state.exists() else 0,
    }
    print(json.dumps(result, sort_keys=True))
    return 0


def publish_command(args: argparse.Namespace) -> int:
    vault = args.vault.expanduser().resolve()
    state = args.state.expanduser().resolve()
    try:
        with integrator_lock(state):
            try:
                ensure_git_ready(vault, args.branch)
            except CommitError as exc:
                print(f"GIT PREFLIGHT FAILED: {exc}", file=sys.stderr)
                return 1
            return 0 if publish(vault, state) else 1
    except TimeoutError as exc:
        print(f"LOCKED: {exc}", file=sys.stderr)
        return EX_TEMPFAIL


def default_path(env_name: str, fallback: str) -> Path:
    return Path(os.getenv(env_name, fallback))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    common = argparse.ArgumentParser(add_help=False)
    common.add_argument(
        "--vault",
        type=Path,
        default=default_path("CANUTO_VAULT_DIR", "~/.canuto/vault"),
    )
    common.add_argument(
        "--state",
        type=Path,
        default=default_path(
            "CANUTO_VAULT_INTEGRATOR_STATE", "~/.canuto/vault-integrator"
        ),
    )
    common.add_argument(
        "--branch",
        default=os.getenv("CANUTO_VAULT_BRANCH", "main"),
        help="canonical publication branch (default: main)",
    )

    process_parser = subparsers.add_parser("process", parents=[common])
    process_parser.add_argument(
        "--inbox",
        type=Path,
        default=default_path("CANUTO_VAULT_INBOX", "~/.canuto/vault-spool/inbox"),
    )
    process_parser.add_argument("--commit", action="store_true")
    process_parser.add_argument("--push", action="store_true")
    process_parser.add_argument(
        "--max-content-bytes", type=int, default=DEFAULT_MAX_CONTENT_BYTES
    )
    process_parser.set_defaults(handler=process)

    status_parser = subparsers.add_parser("status")
    status_parser.add_argument(
        "--inbox",
        type=Path,
        default=default_path("CANUTO_VAULT_INBOX", "~/.canuto/vault-spool/inbox"),
    )
    status_parser.add_argument(
        "--state",
        type=Path,
        default=default_path(
            "CANUTO_VAULT_INTEGRATOR_STATE", "~/.canuto/vault-integrator"
        ),
    )
    status_parser.set_defaults(handler=status)

    publish_parser = subparsers.add_parser("publish", parents=[common])
    publish_parser.set_defaults(handler=publish_command)
    return parser


def main() -> int:
    args = build_parser().parse_args()
    if getattr(args, "max_content_bytes", 1) <= 0:
        print("--max-content-bytes must be positive", file=sys.stderr)
        return 2
    return int(args.handler(args))


if __name__ == "__main__":
    raise SystemExit(main())
