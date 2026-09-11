#!/usr/bin/env python3
"""Regression tests for vault outbox atomicity and SSH transport quoting."""

from __future__ import annotations

import base64
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
VPS = ROOT / ".agents" / "vps"
SUBMIT = VPS / "vault-submit.py"


def load_submit_module():
    spec = importlib.util.spec_from_file_location("canuto_vault_submit", SUBMIT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {SUBMIT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def load_engine_module():
    sys.path.insert(0, str(VPS))
    try:
        spec = importlib.util.spec_from_file_location(
            "canuto_vault_integrator_engine", VPS / "vault_integrator_engine.py"
        )
        if spec is None or spec.loader is None:
            raise RuntimeError("could not load vault integrator engine")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module
    finally:
        sys.path.pop(0)


def load_git_module():
    sys.path.insert(0, str(VPS))
    try:
        spec = importlib.util.spec_from_file_location(
            "canuto_vault_integrator_git", VPS / "vault_integrator_git.py"
        )
        if spec is None or spec.loader is None:
            raise RuntimeError("could not load vault integrator Git helpers")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module
    finally:
        sys.path.pop(0)


class VaultTransportTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="canuto-vault-transport-")
        self.root = Path(self.tmp.name)
        self.outbox = self.root / "outbox"
        self.inbox = self.root / "remote-inbox"
        self.content = self.root / "content.md"
        self.content.write_text("# queued\n", encoding="utf-8")
        self.env = os.environ.copy()
        self.env["CANUTO_VAULT_TEST_NO_FSYNC"] = "1"

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def run_submit(self, *args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        merged = self.env.copy()
        if env:
            merged.update(env)
        return subprocess.run(
            [sys.executable, str(SUBMIT), *args],
            text=True,
            capture_output=True,
            timeout=15,
            env=merged,
        )

    def test_atomic_outbox_create_never_replaces_existing_id(self) -> None:
        module = load_submit_module()
        destination = self.outbox / "we-atomic-0001.json"
        module.atomic_create_json(destination, {"value": "first"})
        with self.assertRaises(FileExistsError):
            module.atomic_create_json(destination, {"value": "second"})
        self.assertEqual(
            json.loads(destination.read_text(encoding="utf-8")),
            {"value": "first"},
        )

    def test_remote_flush_survives_shell_style_ssh_argument_joining(self) -> None:
        created = self.run_submit(
            "create",
            "--id",
            "we-remote-0001",
            "--target",
            "projects/demo/sessions/remote.md",
            "--content-file",
            str(self.content),
            "--outbox",
            str(self.outbox),
            "--source-host",
            "dobra",
            "--source-agent",
            "codex",
            "--session-id",
            "transport-test",
        )
        self.assertEqual(created.returncode, 0, created.stderr)

        fake_bin = self.root / "fake-bin"
        fake_bin.mkdir()
        fake_ssh = fake_bin / "ssh"
        fake_ssh.write_text(
            """#!/usr/bin/env bash
set -euo pipefail
while [ "$#" -gt 0 ]; do
  case "$1" in
    -o) shift 2 ;;
    *) host="$1"; shift; break ;;
  esac
done
[ -n "${host:-}" ]
[ "$#" -gt 0 ] || exit 0
joined=""
for arg in "$@"; do
  if [ -n "$joined" ]; then joined="$joined "; fi
  joined="$joined$arg"
done
exec /bin/sh -c "$joined"
""",
            encoding="utf-8",
        )
        fake_scp = fake_bin / "scp"
        fake_scp.write_text(
            """#!/usr/bin/env bash
set -euo pipefail
source_path=""
destination=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -q) shift ;;
    -o) shift 2 ;;
    *)
      if [ -z "$source_path" ]; then source_path="$1"; else destination="$1"; fi
      shift
      ;;
  esac
done
[ -n "$source_path" ] && [ -n "$destination" ]
remote_path="${destination#*:}"
cp "$source_path" "$remote_path"
""",
            encoding="utf-8",
        )
        fake_ssh.chmod(0o755)
        fake_scp.chmod(0o755)

        env = {"PATH": f"{fake_bin}{os.pathsep}{self.env.get('PATH', '')}"}
        flushed = self.run_submit(
            "flush",
            "--outbox",
            str(self.outbox),
            "--ssh-host",
            "papiro",
            "--remote-inbox",
            str(self.inbox),
            env=env,
        )
        self.assertEqual(flushed.returncode, 0, flushed.stderr)
        self.assertIn("delivered=1 failed=0 remaining=0", flushed.stdout)
        delivered = self.inbox / "we-remote-0001.json"
        self.assertTrue(delivered.is_file())
        self.assertEqual(
            json.loads(delivered.read_text(encoding="utf-8"))["id"],
            "we-remote-0001",
        )
        self.assertFalse((self.outbox / "we-remote-0001.json").exists())

    def test_integrator_rejects_oversized_envelope_without_unbounded_read(self) -> None:
        module = load_engine_module()
        vault = self.root / "vault"
        state = self.root / "state"
        inbox = self.root / "inbox"
        vault.mkdir()
        inbox.mkdir()
        for name in (
            "receipts",
            "processed",
            "rejected",
            "collisions",
            "journal",
            "recovery",
            "locks",
        ):
            (state / name).mkdir(parents=True, exist_ok=True)
        envelope_path = inbox / "we-oversized-0001.json"
        receipt_path = None
        for _ in range(2):
            envelope_path.write_bytes(b"x" * (8 * 1024 * 1024 + 1))
            with mock.patch.object(
                Path,
                "read_bytes",
                side_effect=AssertionError("unbounded Path.read_bytes was used"),
            ):
                status, receipt_path = module.apply_one(
                    envelope_path,
                    vault,
                    state,
                    5 * 1024 * 1024,
                    False,
                    False,
                )
            self.assertEqual(status, "rejected")
            self.assertFalse(envelope_path.exists())

        self.assertIsNotNone(receipt_path)
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
        self.assertIn("envelope exceeds", receipt["reason"])

    def test_replace_rejects_oversized_existing_target_without_unbounded_read(self) -> None:
        module = load_engine_module()
        vault = self.root / "vault"
        state = self.root / "state"
        inbox = self.root / "inbox"
        vault.mkdir()
        inbox.mkdir()
        for name in (
            "receipts",
            "processed",
            "rejected",
            "collisions",
            "journal",
            "recovery",
            "locks",
        ):
            (state / name).mkdir(parents=True, exist_ok=True)

        target_rel = "projects/demo/pending/oversized.md"
        target = vault / target_rel
        target.parent.mkdir(parents=True)
        target.write_bytes(b"x" * (5 * 1024 * 1024 + 1))
        content = b"replacement\n"
        envelope = {
            "schema_version": 1,
            "id": "we-target-oversized-0001",
            "operation": "replace",
            "target": target_rel,
            "tier": "hypothesis",
            "expected_sha256": "0" * 64,
            "content_b64": base64.b64encode(content).decode("ascii"),
            "content_sha256": hashlib.sha256(content).hexdigest(),
            "source": {"host": "dobra", "agent": "codex", "session_id": "transport-test"},
            "approval": None,
            "created_at": "2026-08-23T18:00:00Z",
        }
        envelope_path = inbox / "we-target-oversized-0001.json"
        envelope_path.write_text(json.dumps(envelope), encoding="utf-8")

        with mock.patch.object(
            Path,
            "read_bytes",
            side_effect=AssertionError("unbounded Path.read_bytes was used"),
        ):
            status, receipt_path = module.apply_one(
                envelope_path,
                vault,
                state,
                5 * 1024 * 1024,
                False,
                False,
            )

        self.assertEqual(status, "rejected")
        self.assertIsNotNone(receipt_path)
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
        self.assertIn("replace target exceeds", receipt["reason"])
        self.assertEqual(target.stat().st_size, 5 * 1024 * 1024 + 1)

    def test_oversized_outbox_file_is_not_delivered(self) -> None:
        self.outbox.mkdir()
        oversized = self.outbox / "we-outbox-oversized-0001.json"
        oversized.write_bytes(b"x" * (8 * 1024 * 1024 + 1))
        local_inbox = self.root / "local-inbox"
        flushed = self.run_submit(
            "flush",
            "--outbox",
            str(self.outbox),
            "--deliver-to",
            str(local_inbox),
        )
        self.assertEqual(flushed.returncode, 1)
        self.assertIn("outbox envelope exceeds", flushed.stderr)
        self.assertTrue(oversized.exists())
        self.assertFalse((local_inbox / oversized.name).exists())

    def test_symlinked_outbox_entry_is_not_delivered(self) -> None:
        self.outbox.mkdir()
        payload = self.root / "payload.json"
        payload.write_text("{}\n", encoding="utf-8")
        symlink = self.outbox / "we-symlink-outbox-0001.json"
        symlink.symlink_to(payload)
        local_inbox = self.root / "local-inbox"
        flushed = self.run_submit(
            "flush",
            "--outbox",
            str(self.outbox),
            "--deliver-to",
            str(local_inbox),
        )
        self.assertEqual(flushed.returncode, 1)
        self.assertIn("regular file, not a symlink", flushed.stderr)
        self.assertTrue(symlink.is_symlink())
        self.assertFalse((local_inbox / symlink.name).exists())

    def test_receipt_filename_keeps_colon_and_underscore_ids_distinct(self) -> None:
        module = load_git_module()
        colon = module.receipt_filename("we:receipt-0001")
        underscore = module.receipt_filename("we_receipt-0001")
        self.assertNotEqual(colon, underscore)
        self.assertTrue(colon.startswith("%"))
        self.assertEqual(underscore, "we_receipt-0001.json")

    def test_list_outbox_marks_oversized_and_symlink_entries_invalid(self) -> None:
        self.outbox.mkdir()
        oversized = self.outbox / "we-list-oversized-0001.json"
        oversized.write_bytes(b"x" * (8 * 1024 * 1024 + 1))
        payload = self.root / "payload.json"
        payload.write_text("{}\n", encoding="utf-8")
        symlink = self.outbox / "we-list-symlink-0001.json"
        symlink.symlink_to(payload)

        listed = self.run_submit("list", "--outbox", str(self.outbox))

        self.assertEqual(listed.returncode, 0, listed.stderr)
        values = json.loads(listed.stdout)
        self.assertEqual(len(values), 2)
        self.assertTrue(all(value.get("invalid") is True for value in values))

    def test_remote_host_cannot_be_parsed_as_an_ssh_option(self) -> None:
        module = load_submit_module()
        sending = self.root / "we-option-0001.json"
        sending.write_text("{}\n", encoding="utf-8")
        with self.assertRaisesRegex(RuntimeError, "unsupported characters"):
            module.deliver_remote(
                sending,
                "-oProxyCommand",
                "/tmp/canuto-inbox",
                sending.name,
                10,
            )

    def test_invalid_outbox_filename_is_not_delivered(self) -> None:
        self.outbox.mkdir()
        invalid = self.outbox / "bad;touch.json"
        invalid.write_text("{}\n", encoding="utf-8")
        local_inbox = self.root / "local-inbox"
        flushed = self.run_submit(
            "flush",
            "--outbox",
            str(self.outbox),
            "--deliver-to",
            str(local_inbox),
        )
        self.assertEqual(flushed.returncode, 1)
        self.assertIn("not a valid envelope ID", flushed.stderr)
        self.assertTrue(invalid.exists())
        self.assertFalse((local_inbox / invalid.name).exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
