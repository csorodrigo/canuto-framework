"""Shared validation and atomic filesystem primitives for the vault integrator."""

from __future__ import annotations

import base64
import binascii
import contextlib
import datetime as dt
import hashlib
import json
import os
import re
import stat
import tempfile
from pathlib import Path, PurePosixPath
from typing import Any

SCHEMA_VERSION = 1
MAX_ENVELOPE_BYTES = 8 * 1024 * 1024
DEFAULT_MAX_CONTENT_BYTES = 5 * 1024 * 1024
ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$")
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
SLUG_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$")
HYPOTHESIS_AREAS = frozenset(
    {"sessions", "pending", "metrics", "audit", "rework", "handoffs"}
)
CURATED_AREAS = HYPOTHESIS_AREAS | frozenset(
    {"decisions", "instincts", "design", "digests"}
)


class EnvelopeError(ValueError):
    """Envelope is invalid or cannot be safely applied."""


class CommitError(RuntimeError):
    """Git commit failed after a write and the write was rolled back."""


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def canonical_json_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(",", ":")).encode(
        "utf-8"
    )


def fsync_enabled() -> bool:
    return os.getenv("CANUTO_VAULT_TEST_NO_FSYNC") != "1"


def _prepared_temp(path: Path, payload: bytes, mode: int) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.canuto-", dir=path.parent)
    tmp_path = Path(tmp_name)
    try:
        with os.fdopen(fd, "wb", closefd=True) as handle:
            handle.write(payload)
            handle.flush()
            if fsync_enabled():
                os.fsync(handle.fileno())
        os.chmod(tmp_path, stat.S_IMODE(mode))
        return tmp_path
    except Exception:
        with contextlib.suppress(FileNotFoundError):
            tmp_path.unlink()
        raise


def _fsync_directory(path: Path) -> None:
    if not fsync_enabled():
        return
    directory_fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(directory_fd)
    finally:
        os.close(directory_fd)


def atomic_create_bytes(path: Path, payload: bytes, mode: int = 0o644) -> None:
    tmp_path = _prepared_temp(path, payload, mode)
    try:
        try:
            os.link(tmp_path, path)
        except FileExistsError as exc:
            raise EnvelopeError("create target appeared during publication") from exc
        _fsync_directory(path.parent)
    finally:
        with contextlib.suppress(FileNotFoundError):
            tmp_path.unlink()


def atomic_write_bytes(path: Path, payload: bytes, mode: int = 0o644) -> None:
    tmp_path = _prepared_temp(path, payload, mode)
    try:
        os.replace(tmp_path, path)
        _fsync_directory(path.parent)
    finally:
        with contextlib.suppress(FileNotFoundError):
            tmp_path.unlink()


def atomic_write_json(path: Path, value: dict[str, Any]) -> None:
    atomic_write_bytes(
        path,
        json.dumps(value, ensure_ascii=True, indent=2, sort_keys=True).encode("utf-8") + b"\n",
    )


def read_bytes_limited(path: Path, max_bytes: int, label: str) -> bytes:
    with path.open("rb") as handle:
        payload = handle.read(max_bytes + 1)
    if len(payload) > max_bytes:
        raise EnvelopeError(f"{label} exceeds {max_bytes} bytes")
    return payload


def load_json_limited(path: Path) -> dict[str, Any]:
    try:
        payload = read_bytes_limited(path, MAX_ENVELOPE_BYTES, "envelope")
        value = json.loads(payload.decode("utf-8"))
    except EnvelopeError:
        raise
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise EnvelopeError(f"invalid JSON: {exc}") from exc
    if not isinstance(value, dict):
        raise EnvelopeError("envelope root must be an object")
    return value


def require_nonempty_string(value: Any, field: str, max_len: int = 512) -> str:
    if not isinstance(value, str) or not value.strip():
        raise EnvelopeError(f"{field} must be a non-empty string")
    if len(value) > max_len:
        raise EnvelopeError(f"{field} exceeds {max_len} characters")
    if any(ord(ch) < 32 for ch in value):
        raise EnvelopeError(f"{field} contains control characters")
    return value


def parse_iso_timestamp(value: Any, field: str) -> str:
    text = require_nonempty_string(value, field, 64)
    try:
        parsed = dt.datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError as exc:
        raise EnvelopeError(f"{field} must be ISO-8601") from exc
    if parsed.tzinfo is None:
        raise EnvelopeError(f"{field} must include a timezone")
    return text


def parse_target(target: Any, tier: str) -> tuple[str, str, str]:
    target_text = require_nonempty_string(target, "target")
    if "\\" in target_text or target_text.startswith("/"):
        raise EnvelopeError("target must be a relative POSIX path")
    pure = PurePosixPath(target_text)
    if pure.as_posix() != target_text or any(part in {"", ".", ".."} for part in pure.parts):
        raise EnvelopeError("target is not normalized")
    if len(pure.parts) < 4 or pure.parts[0] != "projects":
        raise EnvelopeError("v1 targets must be projects/<slug>/<area>/<note>.md")
    slug = pure.parts[1]
    area = pure.parts[2]
    if not SLUG_RE.fullmatch(slug):
        raise EnvelopeError("project slug is invalid")
    allowed = HYPOTHESIS_AREAS if tier == "hypothesis" else CURATED_AREAS
    if area not in allowed:
        raise EnvelopeError(f"area '{area}' is not allowed for tier '{tier}'")
    for part in pure.parts[3:]:
        if part.startswith("."):
            raise EnvelopeError("hidden target path components are not allowed")
        if any(ord(ch) < 32 for ch in part):
            raise EnvelopeError("target contains control characters")
    if pure.suffix != ".md":
        raise EnvelopeError("v1 only accepts lowercase .md targets")
    return target_text, slug, area


def validate_envelope(
    envelope: dict[str, Any], max_content_bytes: int
) -> tuple[dict[str, Any], bytes]:
    required = {
        "schema_version",
        "id",
        "operation",
        "target",
        "tier",
        "expected_sha256",
        "content_b64",
        "content_sha256",
        "source",
        "approval",
        "created_at",
    }
    missing = sorted(required - envelope.keys())
    if missing:
        raise EnvelopeError(f"missing required fields: {', '.join(missing)}")
    unknown = sorted(envelope.keys() - required)
    if unknown:
        raise EnvelopeError(f"unknown fields: {', '.join(unknown)}")
    if envelope.get("schema_version") != SCHEMA_VERSION:
        raise EnvelopeError(f"schema_version must be {SCHEMA_VERSION}")

    envelope_id = require_nonempty_string(envelope.get("id"), "id", 128)
    if not ID_RE.fullmatch(envelope_id):
        raise EnvelopeError("id has an invalid format")

    operation = envelope.get("operation")
    if operation not in {"create", "replace"}:
        raise EnvelopeError("operation must be create or replace")
    tier = envelope.get("tier")
    if tier not in {"hypothesis", "curated"}:
        raise EnvelopeError("tier must be hypothesis or curated")

    target, slug, area = parse_target(envelope.get("target"), tier)
    expected_sha = envelope.get("expected_sha256")
    if operation == "create":
        if expected_sha not in {None, ""}:
            raise EnvelopeError("create must not include expected_sha256")
        expected_sha = None
    else:
        if not isinstance(expected_sha, str) or not SHA256_RE.fullmatch(expected_sha):
            raise EnvelopeError("replace requires a lowercase SHA-256 expected_sha256")

    content_sha = envelope.get("content_sha256")
    if not isinstance(content_sha, str) or not SHA256_RE.fullmatch(content_sha):
        raise EnvelopeError("content_sha256 must be a lowercase SHA-256")
    content_b64 = envelope.get("content_b64")
    if not isinstance(content_b64, str) or not content_b64:
        raise EnvelopeError("content_b64 must be a non-empty base64 string")
    try:
        content = base64.b64decode(content_b64.encode("ascii"), validate=True)
    except (UnicodeEncodeError, binascii.Error) as exc:
        raise EnvelopeError("content_b64 is invalid") from exc
    if len(content) > max_content_bytes:
        raise EnvelopeError(f"content exceeds {max_content_bytes} bytes")
    if sha256_bytes(content) != content_sha:
        raise EnvelopeError("content_sha256 does not match content_b64")

    source = envelope.get("source")
    if not isinstance(source, dict):
        raise EnvelopeError("source must be an object")
    source_fields = {"host", "agent", "session_id"}
    unknown_source = sorted(source.keys() - source_fields)
    if unknown_source:
        raise EnvelopeError(f"unknown source fields: {', '.join(unknown_source)}")
    normalized_source = {
        "host": require_nonempty_string(source.get("host"), "source.host", 128),
        "agent": require_nonempty_string(source.get("agent"), "source.agent", 128),
        "session_id": require_nonempty_string(
            source.get("session_id"), "source.session_id", 256
        ),
    }

    created_at = parse_iso_timestamp(envelope.get("created_at"), "created_at")

    approval = envelope.get("approval")
    normalized_approval: dict[str, str] | None = None
    if approval is not None:
        if not isinstance(approval, dict):
            raise EnvelopeError("approval must be an object or null")
        approval_fields = {"by", "at"}
        unknown_approval = sorted(approval.keys() - approval_fields)
        if unknown_approval:
            raise EnvelopeError(f"unknown approval fields: {', '.join(unknown_approval)}")
        normalized_approval = {
            "by": require_nonempty_string(approval.get("by"), "approval.by", 256),
            "at": parse_iso_timestamp(approval.get("at"), "approval.at"),
        }
    if tier == "curated" and normalized_approval is None:
        raise EnvelopeError("curated writes require approval.by and approval.at")

    normalized = {
        "schema_version": SCHEMA_VERSION,
        "id": envelope_id,
        "operation": operation,
        "target": target,
        "tier": tier,
        "expected_sha256": expected_sha,
        "content_sha256": content_sha,
        "source": normalized_source,
        "created_at": created_at,
        "approval": normalized_approval,
        "project_slug": slug,
        "area": area,
    }
    return normalized, content


def resolve_target(vault: Path, relative_target: str) -> Path:
    vault_resolved = vault.resolve(strict=True)
    unresolved = vault_resolved / relative_target
    cursor = vault_resolved
    for part in PurePosixPath(relative_target).parts:
        cursor = cursor / part
        if cursor.is_symlink():
            raise EnvelopeError("symlink target components are not allowed")
    candidate = unresolved.resolve(strict=False)
    try:
        candidate.relative_to(vault_resolved)
    except ValueError as exc:
        raise EnvelopeError("target resolves outside the vault") from exc
    return candidate
