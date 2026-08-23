#!/usr/bin/env python3
"""Regression tests for vault outbox atomicity and SSH transport quoting."""

from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SUBMIT = ROOT / ".agents" / "vps" / "vault-submit.py"


def load_submit_module():
    spec = importlib.util.spec_from_file_location("canuto_vault_submit", SUBMIT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"could not load {SUBMIT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


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
