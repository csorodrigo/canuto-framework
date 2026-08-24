"""Envelope application and publication engine for the Canuto vault integrator."""

from __future__ import annotations

import contextlib
import stat
import subprocess
import sys
from pathlib import Path
from typing import Any, Iterable

from vault_integrator_common import (
    SCHEMA_VERSION,
    ID_RE,
    EnvelopeError,
    atomic_create_bytes,
    atomic_write_bytes,
    atomic_write_json,
    canonical_json_bytes,
    load_json_limited,
    read_bytes_limited,
    resolve_target,
    sha256_bytes,
    utc_now,
    validate_envelope,
)
from vault_integrator_git import (
    CommitError,
    archive_envelope,
    base_receipt,
    commit_target,
    git_head,
    receipt_filename,
    rollback_target,
    run_git,
)


def apply_one(
    envelope_path: Path,
    vault: Path,
    state: Path,
    max_content_bytes: int,
    commit: bool,
    push_requested: bool,
) -> tuple[str, Path | None]:
    raw: dict[str, Any] | None = None
    envelope_id = f"invalid-{sha256_bytes(envelope_path.name.encode())[:16]}"
    envelope_hash = sha256_bytes(envelope_path.name.encode())
    receipt_path: Path | None = None
    journal_path: Path | None = None
    journal: dict[str, Any] | None = None
    mutation_applied = False
    target: Path | None = None
    previous: bytes | None = None
    previous_mode = 0o644

    try:
        raw = load_json_limited(envelope_path)
        if isinstance(raw.get("id"), str) and ID_RE.fullmatch(raw["id"]):
            envelope_id = raw["id"]
        envelope_hash = sha256_bytes(canonical_json_bytes(raw))
        receipt_path = state / "receipts" / receipt_filename(envelope_id)
        journal_path = state / "journal" / receipt_filename(envelope_id)

        if receipt_path.exists():
            prior = load_json_limited(receipt_path)
            if prior.get("envelope_sha256") == envelope_hash and prior.get("status") == "applied":
                with contextlib.suppress(FileNotFoundError):
                    journal_path.unlink()
                try:
                    archive_envelope(envelope_path, state / "processed", envelope_hash)
                except OSError as exc:
                    print(
                        f"DUPLICATE {envelope_id}: applied; archive retry needed: {exc}",
                        file=sys.stderr,
                    )
                else:
                    print(f"DUPLICATE {envelope_id}: already applied")
                return "duplicate", receipt_path
            collision = base_receipt(
                envelope_id,
                envelope_hash,
                envelope_path,
                "rejected",
                "id collision: an existing receipt has a different envelope hash or terminal state",
            )
            collision_path = state / "collisions" / f"{receipt_filename(envelope_id)[:-5]}-{envelope_hash[:12]}.json"
            atomic_write_json(collision_path, collision)
            archive_envelope(envelope_path, state / "rejected", envelope_hash)
            print(f"REJECTED {envelope_id}: id collision", file=sys.stderr)
            return "rejected", collision_path

        if journal_path.exists():
            try:
                prior_journal = load_json_limited(journal_path)
                same_envelope = prior_journal.get("envelope_sha256") == envelope_hash
            except EnvelopeError:
                same_envelope = False
            reason = (
                "interrupted prior transaction requires recovery review"
                if same_envelope
                else "journal collision: id was reserved by another envelope"
            )
            recovery = base_receipt(
                envelope_id,
                envelope_hash,
                envelope_path,
                "rejected",
                reason,
            )
            recovery["recovery_required"] = True
            recovery_path = state / "recovery" / f"{receipt_filename(envelope_id)[:-5]}-{envelope_hash[:12]}.json"
            atomic_write_json(recovery_path, recovery)
            archive_envelope(envelope_path, state / "recovery", envelope_hash)
            print(f"RECOVERY REQUIRED {envelope_id}: {reason}", file=sys.stderr)
            return "rejected", recovery_path

        normalized, content = validate_envelope(raw, max_content_bytes)
        target = resolve_target(vault, normalized["target"])
        target_rel = normalized["target"]
        before_sha: str | None = None

        if normalized["operation"] == "create":
            if target.exists() or target.is_symlink():
                raise EnvelopeError("create target already exists")
        else:
            if not target.exists() or not target.is_file() or target.is_symlink():
                raise EnvelopeError("replace target must be an existing regular file")
            previous = read_bytes_limited(target, max_content_bytes, "replace target")
            previous_mode = stat.S_IMODE(target.stat().st_mode)
            before_sha = sha256_bytes(previous)
            if before_sha != normalized["expected_sha256"]:
                raise EnvelopeError(
                    f"compare-and-swap failed: expected {normalized['expected_sha256']}, found {before_sha}"
                )

        journal = {
            "schema_version": SCHEMA_VERSION,
            "id": envelope_id,
            "envelope_sha256": envelope_hash,
            "state": "prepared",
            "operation": normalized["operation"],
            "target": target_rel,
            "expected_sha256": normalized["expected_sha256"],
            "content_sha256": normalized["content_sha256"],
            "prepared_at": utc_now(),
        }
        atomic_write_json(journal_path, journal)

        head_before = git_head(vault) if commit else None
        if normalized["operation"] == "create":
            atomic_create_bytes(target, content, previous_mode)
        else:
            assert previous is not None
            current_immediately_before_publish = read_bytes_limited(
                target, max_content_bytes, "replace target"
            )
            if sha256_bytes(current_immediately_before_publish) != normalized["expected_sha256"]:
                raise EnvelopeError("compare-and-swap precondition changed before publication")
            atomic_write_bytes(target, content, previous_mode)
        mutation_applied = True

        commit_sha: str | None = None
        if commit:
            try:
                commit_sha = commit_target(vault, target_rel, envelope_id)
            except CommitError:
                rollback_target(target, previous, previous_mode)
                mutation_applied = False
                with contextlib.suppress(Exception):
                    run_git(vault, ["reset", "-q", "--", target_rel], check=False)
                raise

        journal.update(
            {
                "state": "applied-awaiting-receipt",
                "commit_sha": commit_sha,
                "updated_at": utc_now(),
            }
        )
        atomic_write_json(journal_path, journal)

        receipt = base_receipt(envelope_id, envelope_hash, envelope_path, "applied")
        receipt.update(
            {
                "operation": normalized["operation"],
                "target": target_rel,
                "tier": normalized["tier"],
                "project_slug": normalized["project_slug"],
                "area": normalized["area"],
                "source": normalized["source"],
                "approval": normalized["approval"],
                "before_sha256": before_sha,
                "after_sha256": sha256_bytes(content),
                "git": {
                    "head_before": head_before,
                    "commit_sha": commit_sha,
                },
                "publish": {
                    "status": "pending" if push_requested and commit_sha else "not_requested",
                    "recorded_at": utc_now(),
                },
            }
        )
        assert receipt_path is not None
        atomic_write_json(receipt_path, receipt)
        with contextlib.suppress(FileNotFoundError):
            journal_path.unlink()
        try:
            archive_envelope(envelope_path, state / "processed", envelope_hash)
        except OSError as exc:
            # Receipt is the idempotency root. Leaving the inbox copy is safe:
            # the next run recognizes it as a duplicate and retries archival.
            print(f"APPLIED {envelope_id}: archive deferred: {exc}", file=sys.stderr)
        else:
            print(f"APPLIED {envelope_id}: {target_rel}")
        return "applied", receipt_path

    except (EnvelopeError, CommitError) as exc:
        if journal_path is not None and not mutation_applied:
            with contextlib.suppress(FileNotFoundError):
                journal_path.unlink()
        if receipt_path is None:
            receipt_path = state / "receipts" / receipt_filename(envelope_id)
        receipt = base_receipt(envelope_id, envelope_hash, envelope_path, "rejected", str(exc))
        if raw:
            for key in ("operation", "target", "tier", "source"):
                if key in raw:
                    receipt[key] = raw[key]
        if not receipt_path.exists():
            atomic_write_json(receipt_path, receipt)
        archive_envelope(envelope_path, state / "rejected", envelope_hash)
        print(f"REJECTED {envelope_id}: {exc}", file=sys.stderr)
        return "rejected", receipt_path

    except OSError as exc:
        if mutation_applied and journal_path is not None:
            if journal is not None:
                journal.update(
                    {
                        "state": "recovery-required",
                        "reason": str(exc),
                        "updated_at": utc_now(),
                    }
                )
                with contextlib.suppress(OSError):
                    atomic_write_json(journal_path, journal)
            with contextlib.suppress(OSError):
                archive_envelope(envelope_path, state / "recovery", envelope_hash)
            print(
                f"RECOVERY REQUIRED {envelope_id}: mutation may be applied but receipt was not finalized: {exc}",
                file=sys.stderr,
            )
            return "rejected", journal_path

        if journal_path is not None:
            with contextlib.suppress(FileNotFoundError):
                journal_path.unlink()
        if receipt_path is None:
            receipt_path = state / "receipts" / receipt_filename(envelope_id)
        receipt = base_receipt(envelope_id, envelope_hash, envelope_path, "rejected", str(exc))
        with contextlib.suppress(OSError):
            if not receipt_path.exists():
                atomic_write_json(receipt_path, receipt)
        with contextlib.suppress(OSError):
            archive_envelope(envelope_path, state / "rejected", envelope_hash)
        print(f"REJECTED {envelope_id}: {exc}", file=sys.stderr)
        return "rejected", receipt_path


def pending_receipts(state: Path) -> list[Path]:
    paths: list[Path] = []
    for path in sorted((state / "receipts").glob("*.json")):
        try:
            receipt = load_json_limited(path)
        except EnvelopeError:
            continue
        publish = receipt.get("publish")
        if receipt.get("status") == "applied" and isinstance(publish, dict) and publish.get(
            "status"
        ) in {"pending", "failed"}:
            paths.append(path)
    return paths


def update_publish_receipts(paths: Iterable[Path], status: str, detail: str | None = None) -> None:
    for path in paths:
        try:
            receipt = load_json_limited(path)
        except EnvelopeError:
            continue
        publish = receipt.setdefault("publish", {})
        publish["status"] = status
        publish["recorded_at"] = utc_now()
        if detail:
            publish["detail"] = detail[-2000:]
        else:
            publish.pop("detail", None)
        atomic_write_json(path, receipt)


def _commit_reachable(vault: Path, commit_sha: str) -> bool:
    try:
        result = run_git(vault, ["merge-base", "--is-ancestor", commit_sha, "HEAD"], check=False)
    except OSError:
        return False
    return result.returncode == 0


def publish(vault: Path, state: Path) -> bool:
    paths = pending_receipts(state)
    if not paths:
        print("PUBLISH: no pending receipts")
        return True
    reachable: list[Path] = []
    unreachable: list[Path] = []
    for path in paths:
        try:
            receipt = load_json_limited(path)
            commit_sha = receipt.get("git", {}).get("commit_sha")
        except (EnvelopeError, AttributeError):
            commit_sha = None
        if isinstance(commit_sha, str) and commit_sha and _commit_reachable(vault, commit_sha):
            reachable.append(path)
        else:
            unreachable.append(path)
    if unreachable:
        update_publish_receipts(
            unreachable,
            "failed",
            "receipt commit is absent or not reachable from the current HEAD",
        )
    if not reachable:
        print("PUBLISH FAILED: no pending receipt commit is reachable from HEAD", file=sys.stderr)
        return False
    try:
        result = run_git(vault, ["push", "--porcelain", "origin", "HEAD"])
    except (OSError, subprocess.CalledProcessError) as exc:
        detail = getattr(exc, "stderr", "") or str(exc)
        update_publish_receipts(reachable, "failed", detail.strip())
        print(f"PUBLISH FAILED: {detail.strip()}", file=sys.stderr)
        return False
    update_publish_receipts(reachable, "pushed", result.stdout.strip())
    print(f"PUSHED {len(reachable)} receipt(s)")
    return not unreachable
