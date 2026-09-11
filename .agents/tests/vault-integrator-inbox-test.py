#!/usr/bin/env python3
"""Adversarial tests for special-file entries at the integrator inbox boundary."""

from __future__ import annotations

import base64
import hashlib
import importlib.util
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
VPS = ROOT / ".agents" / "vps"


def load_module(name: str, path: Path):
    sys.path.insert(0, str(VPS))
    try:
        spec = importlib.util.spec_from_file_location(name, path)
        if spec is None or spec.loader is None:
            raise RuntimeError(f"could not load {path}")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module
    finally:
        sys.path.pop(0)


class VaultInboxBoundaryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="canuto-vault-inbox-")
        self.root = Path(self.tmp.name)
        self.vault = self.root / "vault"
        self.state = self.root / "state"
        self.inbox = self.root / "inbox"
        self.vault.mkdir()
        self.inbox.mkdir()
        for name in (
            "receipts",
            "processed",
            "rejected",
            "collisions",
            "journal",
            "recovery",
            "locks",
        ):
            (self.state / name).mkdir(parents=True, exist_ok=True)
        os.environ["CANUTO_VAULT_TEST_NO_FSYNC"] = "1"

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def engine(self):
        return load_module(
            "canuto_vault_integrator_engine_inbox_test",
            VPS / "vault_integrator_engine.py",
        )

    def git_helpers(self):
        return load_module(
            "canuto_vault_integrator_git_inbox_test",
            VPS / "vault_integrator_git.py",
        )

    def test_symlinked_inbox_entry_is_rejected_without_following_target(self) -> None:
        module = self.engine()
        content = b"must not apply\n"
        target_rel = "projects/demo/sessions/symlink-inbox.md"
        external = self.root / "external-envelope.json"
        external.write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "id": "we-symlink-inbox-0001",
                    "operation": "create",
                    "target": target_rel,
                    "tier": "hypothesis",
                    "expected_sha256": None,
                    "content_b64": base64.b64encode(content).decode("ascii"),
                    "content_sha256": hashlib.sha256(content).hexdigest(),
                    "source": {
                        "host": "dobra",
                        "agent": "codex",
                        "session_id": "inbox-test",
                    },
                    "approval": None,
                    "created_at": "2026-08-23T18:00:00Z",
                }
            ),
            encoding="utf-8",
        )
        envelope_path = self.inbox / "we-symlink-inbox-0001.json"
        envelope_path.symlink_to(external)

        status, receipt_path = module.apply_one(
            envelope_path,
            self.vault,
            self.state,
            5 * 1024 * 1024,
            False,
            False,
        )

        self.assertEqual(status, "rejected")
        self.assertIsNotNone(receipt_path)
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
        self.assertIn("regular file", receipt["reason"])
        self.assertTrue(external.is_file())
        self.assertFalse((self.vault / target_rel).exists())
        self.assertFalse(envelope_path.exists())
        self.assertTrue(any(path.is_symlink() for path in (self.state / "rejected").iterdir()))

    @unittest.skipUnless(hasattr(os, "mkfifo"), "POSIX FIFO support required")
    def test_fifo_inbox_entry_is_rejected_without_blocking(self) -> None:
        module = self.engine()
        envelope_path = self.inbox / "we-fifo-inbox-0001.json"
        os.mkfifo(envelope_path)

        status, receipt_path = module.apply_one(
            envelope_path,
            self.vault,
            self.state,
            5 * 1024 * 1024,
            False,
            False,
        )

        self.assertEqual(status, "rejected")
        self.assertIsNotNone(receipt_path)
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
        self.assertIn("regular file", receipt["reason"])
        self.assertFalse(envelope_path.exists())

    @unittest.skipUnless(hasattr(os, "mkfifo"), "POSIX FIFO support required")
    def test_repeated_special_archive_never_opens_fifo_for_comparison(self) -> None:
        module = self.git_helpers()
        source = self.root / "we-fifo-archive-0001.json"
        destination_dir = self.root / "archive"
        os.mkfifo(source)

        with mock.patch.object(
            module,
            "files_equal",
            side_effect=AssertionError("special files must not be opened for comparison"),
        ):
            first = module.archive_envelope(source, destination_dir, "a" * 64)
            os.mkfifo(source)
            second = module.archive_envelope(source, destination_dir, "a" * 64)

        self.assertNotEqual(first, second)
        self.assertTrue(first.exists())
        self.assertTrue(second.exists())
        self.assertFalse(source.exists())


if __name__ == "__main__":
    unittest.main(verbosity=2)
