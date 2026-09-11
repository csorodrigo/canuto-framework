#!/usr/bin/env python3
"""Behavioral tests for the Canuto vault single-publisher foundation."""

from __future__ import annotations

import base64
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INTEGRATOR = ROOT / ".agents" / "vps" / "vault-integrator.py"
SUBMIT = ROOT / ".agents" / "vps" / "vault-submit.py"
FIXED_AT = "2026-08-23T18:00:00Z"
os.environ["CANUTO_VAULT_TEST_NO_FSYNC"] = "1"


def digest(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


class VaultIntegratorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="canuto-vault-integrator-")
        self.root = Path(self.tmp.name)
        self.vault = self.root / "vault"
        self.inbox = self.root / "inbox"
        self.outbox = self.root / "outbox"
        self.state = self.root / "state"
        self.vault.mkdir()
        self.inbox.mkdir()
        self.outbox.mkdir()
        # Most tests exercise filesystem serialization only. Git is initialized
        # explicitly by the two commit-path tests to keep the suite fast.


    def tearDown(self) -> None:
        self.tmp.cleanup()

    def init_git(self) -> None:
        subprocess.run(["git", "init", "-q", "-b", "main", str(self.vault)], check=True)
        (self.vault / ".gitignore").write_text(".obsidian/workspace*\n", encoding="utf-8")
        subprocess.run(["git", "-C", str(self.vault), "add", ".gitignore"], check=True)
        subprocess.run(
            [
                "git", "-C", str(self.vault),
                "-c", "user.name=test", "-c", "user.email=test@example.invalid",
                "commit", "-q", "-m", "initial",
            ],
            check=True,
        )

    def enqueue(
        self,
        operation: str,
        envelope_id: str,
        target: str,
        content: bytes,
        *,
        expected: str | None = None,
        tier: str = "hypothesis",
        approval_by: str | None = None,
    ) -> None:
        envelope = {
            "schema_version": 1,
            "id": envelope_id,
            "operation": operation,
            "target": target,
            "tier": tier,
            "expected_sha256": expected,
            "content_b64": base64.b64encode(content).decode("ascii"),
            "content_sha256": digest(content),
            "source": {"host": "dobra", "agent": "codex", "session_id": "session-test"},
            "approval": ({"by": approval_by, "at": FIXED_AT} if approval_by else None),
            "created_at": FIXED_AT,
        }
        self.write_direct_envelope(envelope)

    def run_integrator(
        self,
        *extra: str,
        env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        command = [
            sys.executable,
            str(INTEGRATOR),
            "process",
            "--vault",
            str(self.vault),
            "--inbox",
            str(self.inbox),
            "--state",
            str(self.state),
            *extra,
        ]
        merged_env = os.environ.copy()
        if env:
            merged_env.update(env)
        return subprocess.run(command, text=True, capture_output=True, env=merged_env)

    def receipt(self, envelope_id: str) -> dict:
        name = envelope_id.replace(":", "_") + ".json"
        return json.loads((self.state / "receipts" / name).read_text(encoding="utf-8"))

    def write_direct_envelope(self, envelope: dict) -> None:
        self.inbox.mkdir(parents=True, exist_ok=True)
        (self.inbox / f"{envelope['id']}.json").write_text(
            json.dumps(envelope, sort_keys=True), encoding="utf-8"
        )

    def valid_direct_envelope(self, envelope_id: str, target: str, content: bytes) -> dict:
        return {
            "schema_version": 1,
            "id": envelope_id,
            "operation": "create",
            "target": target,
            "tier": "hypothesis",
            "expected_sha256": None,
            "content_b64": base64.b64encode(content).decode("ascii"),
            "content_sha256": digest(content),
            "source": {"host": "dobra", "agent": "codex", "session_id": "s1"},
            "approval": None,
            "created_at": FIXED_AT,
        }

    def test_create_is_applied_and_receipted(self) -> None:
        envelope_id = "we-create-0001"
        target = "projects/demo/sessions/2026-08-23.md"
        payload = b"# Session\n\nApplied safely.\n"
        self.enqueue("create", envelope_id, target, payload)
        result = self.run_integrator()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.vault / target).read_bytes(), payload)
        receipt = self.receipt(envelope_id)
        self.assertEqual(receipt["status"], "applied")
        self.assertEqual(receipt["after_sha256"], digest(payload))
        self.assertEqual(receipt["publish"]["status"], "not_requested")

    def test_same_envelope_id_and_hash_is_idempotent(self) -> None:
        envelope_id = "we-duplicate-0001"
        target = "projects/demo/audit/event.md"
        payload = b"event\n"
        self.enqueue("create", envelope_id, target, payload)
        first = self.run_integrator()
        self.assertEqual(first.returncode, 0, first.stderr)
        processed = next((self.state / "processed").glob(f"{envelope_id}-*.json"))
        shutil.copyfile(processed, self.inbox / f"{envelope_id}.json")
        second = self.run_integrator()
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertIn("DUPLICATE", second.stdout)
        self.assertEqual((self.vault / target).read_bytes(), payload)

    def test_replace_uses_compare_and_swap(self) -> None:
        target = "projects/demo/pending/task.md"
        path = self.vault / target
        path.parent.mkdir(parents=True)
        path.write_bytes(b"old\n")
        self.enqueue(
            "replace",
            "we-replace-0001",
            target,
            b"new\n",
            expected=digest(b"old\n"),
        )
        result = self.run_integrator()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(path.read_bytes(), b"new\n")
        self.assertEqual(self.receipt("we-replace-0001")["before_sha256"], digest(b"old\n"))

    def test_stale_compare_and_swap_is_rejected_without_mutation(self) -> None:
        target = "projects/demo/pending/task.md"
        path = self.vault / target
        path.parent.mkdir(parents=True)
        path.write_bytes(b"current\n")
        self.enqueue(
            "replace",
            "we-stale-0001",
            target,
            b"new\n",
            expected="0" * 64,
        )
        result = self.run_integrator()
        self.assertEqual(result.returncode, 1)
        self.assertEqual(path.read_bytes(), b"current\n")
        self.assertIn("compare-and-swap failed", self.receipt("we-stale-0001")["reason"])

    def test_path_escape_is_rejected(self) -> None:
        envelope = self.valid_direct_envelope(
            "we-traversal-0001", "projects/demo/sessions/../../escape.md", b"bad\n"
        )
        self.write_direct_envelope(envelope)
        result = self.run_integrator()
        self.assertEqual(result.returncode, 1)
        self.assertFalse((self.root / "escape.md").exists())
        self.assertEqual(self.receipt("we-traversal-0001")["status"], "rejected")

    def test_curated_write_without_approval_is_rejected(self) -> None:
        envelope = self.valid_direct_envelope(
            "we-curated-0001", "projects/demo/decisions/d-1.md", b"decision\n"
        )
        envelope["tier"] = "curated"
        self.write_direct_envelope(envelope)
        result = self.run_integrator()
        self.assertEqual(result.returncode, 1)
        self.assertIn("require approval", self.receipt("we-curated-0001")["reason"])

    def test_content_hash_mismatch_is_rejected(self) -> None:
        envelope = self.valid_direct_envelope(
            "we-hashbad-0001", "projects/demo/sessions/hash.md", b"content\n"
        )
        envelope["content_sha256"] = "f" * 64
        self.write_direct_envelope(envelope)
        result = self.run_integrator()
        self.assertEqual(result.returncode, 1)
        self.assertFalse((self.vault / envelope["target"]).exists())

    def test_git_commit_contains_only_declared_target(self) -> None:
        self.init_git()
        target = "projects/demo/metrics/m.md"
        self.enqueue("create", "we-commit-0001", target, b"metric\n")
        result = self.run_integrator("--commit")
        self.assertEqual(result.returncode, 0, result.stderr)
        changed = subprocess.run(
            ["git", "-C", str(self.vault), "show", "--pretty=format:", "--name-only", "HEAD"],
            check=True,
            text=True,
            capture_output=True,
        ).stdout.splitlines()
        self.assertEqual([line for line in changed if line], [target])
        self.assertEqual(
            subprocess.run(
                ["git", "-C", str(self.vault), "status", "--porcelain"],
                check=True, text=True, capture_output=True,
            ).stdout,
            "",
        )

    def test_dirty_git_worktree_blocks_integrator_before_mutation(self) -> None:
        self.init_git()
        (self.vault / "unrelated.txt").write_text("foreign writer\n", encoding="utf-8")
        target = "projects/demo/sessions/blocked.md"
        self.enqueue("create", "we-dirty-0001", target, b"must not apply\n")
        result = self.run_integrator("--commit")
        self.assertEqual(result.returncode, 1)
        self.assertIn("working tree is not clean", result.stderr)
        self.assertFalse((self.vault / target).exists())
        self.assertTrue((self.inbox / "we-dirty-0001.json").exists())

    def test_commit_failure_rolls_back_file(self) -> None:
        self.init_git()
        target = "projects/demo/sessions/rollback.md"
        self.enqueue("create", "we-rollback-0001", target, b"must rollback\n")
        result = self.run_integrator(
            "--commit", env={"CANUTO_INTEGRATOR_TEST_FAIL_COMMIT": "1"}
        )
        self.assertEqual(result.returncode, 1)
        self.assertFalse((self.vault / target).exists())
        self.assertIn("commit failure injected", self.receipt("we-rollback-0001")["reason"])

    def test_submit_tool_keeps_outbox_until_explicit_flush(self) -> None:
        content_file = self.root / "submit-content.md"
        content_file.write_text("# queued\n", encoding="utf-8")
        envelope_id = "we-submit-0001"
        submit = subprocess.run(
            [
                sys.executable, str(SUBMIT), "create",
                "--id", envelope_id,
                "--target", "projects/demo/sessions/submitted.md",
                "--content-file", str(content_file),
                "--outbox", str(self.outbox),
                "--source-host", "dobra",
                "--source-agent", "codex",
                "--session-id", "s-submit",
                "--created-at", FIXED_AT,
            ],
            text=True, capture_output=True, timeout=10,
        )
        self.assertEqual(submit.returncode, 0, submit.stderr)
        self.assertTrue((self.outbox / f"{envelope_id}.json").exists())
        self.assertFalse((self.inbox / f"{envelope_id}.json").exists())
        flush = subprocess.run(
            [
                sys.executable, str(SUBMIT), "flush",
                "--outbox", str(self.outbox),
                "--deliver-to", str(self.inbox),
            ],
            text=True, capture_output=True, timeout=10,
        )
        self.assertEqual(flush.returncode, 0, flush.stderr)
        self.assertFalse((self.outbox / f"{envelope_id}.json").exists())
        self.assertTrue((self.inbox / f"{envelope_id}.json").exists())

    def test_curated_write_with_approval_is_applied(self) -> None:
        target = "projects/demo/decisions/d-approved.md"
        self.enqueue(
            "create",
            "we-curated-approved-0001",
            target,
            b"# Approved decision\n",
            tier="curated",
            approval_by="rodrigo",
        )
        result = self.run_integrator()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.vault / target).exists())
        self.assertEqual(
            self.receipt("we-curated-approved-0001")["approval"]["by"], "rodrigo"
        )

    def test_existing_create_target_is_never_overwritten(self) -> None:
        target = "projects/demo/sessions/existing.md"
        path = self.vault / target
        path.parent.mkdir(parents=True)
        path.write_bytes(b"original\n")
        self.enqueue("create", "we-existing-0001", target, b"replacement\n")
        result = self.run_integrator()
        self.assertEqual(result.returncode, 1)
        self.assertEqual(path.read_bytes(), b"original\n")

    def test_same_id_with_different_envelope_is_collision(self) -> None:
        first_target = "projects/demo/sessions/first.md"
        second_target = "projects/demo/sessions/second.md"
        envelope_id = "we-collision-0001"
        self.enqueue("create", envelope_id, first_target, b"first\n")
        self.assertEqual(self.run_integrator().returncode, 0)
        self.enqueue("create", envelope_id, second_target, b"second\n")
        result = self.run_integrator()
        self.assertEqual(result.returncode, 1)
        self.assertFalse((self.vault / second_target).exists())
        self.assertTrue(list((self.state / "collisions").glob("*.json")))

    def test_symlink_path_component_is_rejected(self) -> None:
        external = self.root / "external"
        external.mkdir()
        (self.vault / "projects").symlink_to(external, target_is_directory=True)
        target = "projects/demo/sessions/symlink.md"
        self.enqueue("create", "we-symlink-0001", target, b"escape\n")
        result = self.run_integrator()
        self.assertEqual(result.returncode, 1)
        self.assertFalse((external / "demo" / "sessions" / "symlink.md").exists())

    def test_push_without_commit_fails_before_mutation(self) -> None:
        target = "projects/demo/sessions/no-push.md"
        self.enqueue("create", "we-push-guard-0001", target, b"not applied\n")
        result = self.run_integrator("--push")
        self.assertEqual(result.returncode, 2)
        self.assertFalse((self.vault / target).exists())
        self.assertTrue((self.inbox / "we-push-guard-0001.json").exists())

    def test_existing_journal_forces_manual_recovery(self) -> None:
        envelope = self.valid_direct_envelope(
            "we-recovery-0001", "projects/demo/sessions/recovery.md", b"payload\n"
        )
        self.write_direct_envelope(envelope)
        envelope_hash = digest(
            json.dumps(
                envelope, ensure_ascii=True, sort_keys=True, separators=(",", ":")
            ).encode("utf-8")
        )
        journal_dir = self.state / "journal"
        journal_dir.mkdir(parents=True)
        (journal_dir / "we-recovery-0001.json").write_text(
            json.dumps(
                {
                    "schema_version": 1,
                    "id": envelope["id"],
                    "envelope_sha256": envelope_hash,
                    "state": "prepared",
                }
            ),
            encoding="utf-8",
        )
        result = self.run_integrator()
        self.assertEqual(result.returncode, 1)
        self.assertIn("RECOVERY REQUIRED", result.stderr)
        self.assertFalse((self.vault / envelope["target"]).exists())
        self.assertTrue(list((self.state / "recovery").glob("*.json")))

    def test_second_integrator_fails_closed_on_lock(self) -> None:
        target = "projects/demo/sessions/concurrent.md"
        self.enqueue("create", "we-lock-0001", target, b"serialized\n")
        command = [
            sys.executable,
            str(INTEGRATOR),
            "process",
            "--vault",
            str(self.vault),
            "--inbox",
            str(self.inbox),
            "--state",
            str(self.state),
        ]
        env = os.environ.copy()
        env["CANUTO_INTEGRATOR_HOLD_LOCK_SECONDS"] = "1.5"
        first = subprocess.Popen(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
        lock_path = self.state / "locks" / "integrator.lock"
        deadline = time.time() + 5
        lock_owned = False
        while time.time() < deadline:
            try:
                owner = json.loads(lock_path.read_text(encoding="utf-8"))
                if owner.get("pid") == first.pid:
                    lock_owned = True
                    break
            except (FileNotFoundError, json.JSONDecodeError, OSError):
                pass
            time.sleep(0.02)
        self.assertTrue(lock_owned, "first integrator never published lock ownership")
        second = subprocess.run(command, text=True, capture_output=True, timeout=5)
        stdout, stderr = first.communicate(timeout=5)
        self.assertEqual(first.returncode, 0, stderr)
        self.assertEqual(second.returncode, 75)
        self.assertIn("LOCKED", second.stderr)
        self.assertEqual((self.vault / target).read_bytes(), b"serialized\n")


if __name__ == "__main__":
    unittest.main(verbosity=2)
