#!/usr/bin/env python3
"""Offline recovery/documentation contracts; never use the live user manager."""
from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
DOC = ROOT / "docs/recovery-matrix.md"
RUNNER = ROOT / "shell/scripts/config-migrations.py"
RECOVER = ROOT / "bin/nbshell-install-recover"
SPEC = importlib.util.spec_from_file_location(
    "install_tree", ROOT / "shell/scripts/install-tree-transaction.py"
)
assert SPEC and SPEC.loader
TREE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(TREE)


class RecoveryContracts(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="nbshell-recovery-contract-")
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.bin = self.home / "bin"
        self.bin.mkdir()
        # Deliberately no qs/quickshell, network tools, sudo, or real systemctl.
        for name in ("bash", "dirname", "basename", "stat", "find", "rmdir",
                     "rm", "cp", "mv", "mkdir"):
            source = shutil.which(name)
            if source is None:
                self.fail(f"missing test prerequisite: {name}")
            (self.bin / name).symlink_to(source)
        (self.bin / "python3").symlink_to(sys.executable)
        (self.bin / "nbshell").symlink_to(ROOT / "bin/nbshell")
        self.env = {
            "HOME": str(self.home), "PATH": str(self.bin), "LC_ALL": "C",
            "XDG_CONFIG_HOME": str(self.home / "config"),
            "XDG_STATE_HOME": str(self.home / "state"),
            "XDG_DATA_HOME": str(self.home / "data"),
            "XDG_CACHE_HOME": str(self.home / "cache"),
            "XDG_BIN_HOME": str(self.bin),
            "XDG_RUNTIME_DIR": str(self.home / "run"),
            "NBSHELL_MIGRATION_TESTING": "1",
        }
        self.config_home = Path(self.env["XDG_CONFIG_HOME"])
        self.config = self.config_home / "nbshell/config.json"
        self.config.parent.mkdir(parents=True)
        self.config.write_text('{"theme": "fixture", "custom": {"keep": true}}\n')
        self.state = Path(self.env["XDG_STATE_HOME"]) / "nbshell"
        self.runtime = self.config_home / "quickshell/nbshell"
        (self.runtime / "scripts").mkdir(parents=True)
        shutil.copy2(RUNNER, self.runtime / "scripts/config-migrations.py")
        self.calls = self.home / "service-calls"
        self.env["CONTRACT_SERVICE_CALLS"] = str(self.calls)
        stub = self.bin / "systemctl"
        stub.write_text('#!/usr/bin/env bash\nprintf "%s\\n" "$*" >> "$CONTRACT_SERVICE_CALLS"\nexit 0\n')
        stub.chmod(0o755)

    def run_command(self, command, *, env=None):
        result = subprocess.run(
            command, env=self.env | (env or {}), cwd=ROOT,
            text=True, capture_output=True, timeout=20,
        )
        return result

    def migrate(self, *args, env=None):
        return self.run_command([sys.executable, str(RUNNER), *args], env=env)

    def snapshot(self):
        return {str(p.relative_to(self.home)): p.read_bytes()
                for p in self.home.rglob("*") if p.is_file() and not p.is_symlink()}

    def doc_block(self, name):
        match = re.search(
            rf"<!-- recovery-contract: {re.escape(name)} -->\n```bash\n(.*?)\n```\n<!-- /recovery-contract -->",
            DOC.read_text(), re.S,
        )
        if match is None:
            self.fail(f"missing documented contract: {name}")
        return match.group(1)

    def test_documented_tty_commands_are_read_only_without_quickshell(self):
        checkout = self.home / "projects/nbshell/shell/scripts"
        checkout.mkdir(parents=True)
        shutil.copy2(RUNNER, checkout / "config-migrations.py")
        before = self.snapshot()
        for name in ("tty-diagnostics", "migration-cli"):
            result = self.run_command([str(self.bin / "bash"), "-c", self.doc_block(name)])
            self.assertEqual(result.returncode, 0, result.stderr)
            rows = [json.loads(line) for line in result.stdout.splitlines()]
            self.assertEqual(len(rows), 2)
            self.assertEqual(rows[0]["migrations"][0]["status"], "pending")
            self.assertTrue(rows[1]["dryRun"])
            self.assertTrue(rows[1]["wouldMutateConfig"])
        self.assertEqual(self.snapshot(), before)
        self.assertFalse(self.calls.exists())

    def test_corrupted_new_config_does_not_destroy_migration_backup(self):
        original = self.config.read_bytes()
        result = self.migrate("apply", "--json")
        self.assertEqual(result.returncode, 0, result.stderr)
        ledger = self.state / "config-migrations.json"
        saved_ledger = ledger.read_bytes()
        backup = Path(json.loads(result.stdout)["migrations"][0]["backup"])
        self.config.write_bytes(b'{"schemaVersion": 1, damaged')
        damaged = self.config.read_bytes()
        for args in (("status", "--json"), ("apply", "--json")):
            result = self.migrate(*args)
            self.assertEqual(result.returncode, 1)
            self.assertIn("not valid UTF-8 JSON", json.loads(result.stdout)["error"])
            self.assertEqual(self.config.read_bytes(), damaged)
            self.assertEqual(backup.read_bytes(), original)
            self.assertEqual(ledger.read_bytes(), saved_ledger)

    def transaction(self):
        tx = self.config_home / ".nbshell-install-rollback.v2.contract"
        tx.mkdir()
        rollback = self.runtime.parent / ".nbshell-rollback.contract"
        stage = self.runtime.parent / ".nbshell-stage.contract"
        (self.runtime / "shell.qml").write_text("original runtime\n")
        identity = self.runtime.stat()
        (tx / "original-runtime-present").touch()
        (tx / "original-runtime-identity").write_text(f"{identity.st_dev}:{identity.st_ino}\n")
        (tx / "paths").write_bytes(b"")
        # No unit manifest: inactive file recovery must work without systemd.
        rollback.mkdir()
        (rollback / "shell.qml").write_text("replacement runtime\n")
        stage.mkdir()
        return tx, rollback, stage

    def recover(self, tx, rollback, stage, mode="inactive"):
        return self.run_command([
            str(self.bin / "bash"), str(RECOVER), str(self.runtime), str(rollback),
            mode, str(tx), str(self.bin / "nbshell"), str(stage),
        ])

    def test_pre_exchange_interruption_keeps_original_runtime(self):
        tx, rollback, stage = self.transaction()
        result = self.recover(tx, rollback, stage)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.runtime / "shell.qml").read_text(), "original runtime\n")
        self.assertFalse(tx.exists())
        self.assertFalse(rollback.exists())
        self.assertFalse(stage.exists())
        self.assertFalse(self.calls.exists())

    def test_post_exchange_interruption_restores_original_without_quickshell(self):
        tx, rollback, stage = self.transaction()
        exchanged = self.run_command([str(self.bin / "mv"), "--exchange", "-T",
                                      str(self.runtime), str(rollback)])
        self.assertEqual(exchanged.returncode, 0, exchanged.stderr)
        result = self.recover(tx, rollback, stage)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.runtime / "shell.qml").read_text(), "original runtime\n")
        self.assertFalse((self.runtime / "nbshell").exists())
        self.assertFalse(tx.exists())
        self.assertFalse(rollback.exists())
        self.assertFalse(self.calls.exists())

    def test_committed_inactive_transaction_cleans_without_reverting(self):
        tx, rollback, stage = self.transaction()
        (tx / "committed").touch()
        (self.runtime / "shell.qml").write_text("committed runtime\n")
        result = self.recover(tx, rollback, stage)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.runtime / "shell.qml").read_text(), "committed runtime\n")
        self.assertFalse(tx.exists())
        self.assertFalse(rollback.exists())
        self.assertFalse(stage.exists())

    def test_missing_recorded_backup_preserves_transaction_and_current_file(self):
        tx, rollback, stage = self.transaction()
        original = self.config.read_bytes()
        (tx / "paths").write_bytes(b"present\0config.json\0" + os.fsencode(self.config) + b"\0")
        result = self.recover(tx, rollback, stage)
        self.assertEqual(result.returncode, 1)
        self.assertIn("recovery was incomplete", result.stderr)
        self.assertTrue(tx.exists())
        self.assertTrue(rollback.exists())
        self.assertEqual(self.config.read_bytes(), original)

    def test_invalid_mode_is_rejected_before_mutation(self):
        tx, rollback, stage = self.transaction()
        before = self.snapshot()
        result = self.recover(tx, rollback, stage, mode="whole-system")
        self.assertEqual(result.returncode, 2)
        self.assertIn("Unknown recovery mode", result.stderr)
        self.assertEqual(self.snapshot(), before)
        self.assertTrue(stage.is_dir())

    def test_inactive_mode_still_restores_recorded_unit_activity(self):
        tx, rollback, stage = self.transaction()
        unit = "nbshell.service"
        path = self.config_home / "systemd/user" / unit
        (tx / "units").write_bytes(
            b"\0".join(os.fsencode(v) for v in (unit, "static", "1", "", str(path))) + b"\0"
        )
        result = self.recover(tx, rollback, stage)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("--user start nbshell.service", self.calls.read_text())

    def test_overlay_failure_restores_symlink_and_removes_new_file(self):
        prefix = self.home / "prefix"
        prefix.mkdir()
        (prefix / "a-existing").symlink_to("original-target")
        untouched = prefix / "user-owned"
        untouched.write_text("keep\n")
        stage = self.home / "destdir"
        payload = stage / prefix.relative_to("/")
        payload.mkdir(parents=True)
        (payload / "a-existing").write_text("new regular file\n")
        (payload / "new/directory").mkdir(parents=True)
        (payload / "new/directory/b-new").write_text("new leaf\n")
        with self.assertRaisesRegex(RuntimeError, "injected"):
            TREE.install_tree(stage, prefix, fail_after=2)
        self.assertTrue((prefix / "a-existing").is_symlink())
        self.assertEqual(os.readlink(prefix / "a-existing"), "original-target")
        self.assertFalse((prefix / "new").exists())
        self.assertEqual(untouched.read_text(), "keep\n")
        self.assertFalse(list(prefix.glob(".nbshell-umbriel-rollback-*")))


if __name__ == "__main__":
    unittest.main(verbosity=2)
