#!/usr/bin/env python3
"""Black-box tests for the nbshell shell-config migration contract."""

from __future__ import annotations

import json
import os
import pathlib
import shutil
import subprocess
import tempfile
import time
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
RUNNER = ROOT / "shell/scripts/config-migrations.py"
CLI = ROOT / "bin/nbshell"
FIXTURES = ROOT / "tests/fixtures/config-migrations"
MIGRATION_ID = "0001-config-schema-v1"


class ConfigMigrationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temporary.name)
        self.config_home = self.root / "config"
        self.state_home = self.root / "state"
        self.config = self.config_home / "nbshell/config.json"
        self.ledger = self.state_home / "nbshell/config-migrations.json"
        self.config.parent.mkdir(parents=True)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def install_fixture(self, name: str) -> bytes:
        source = (FIXTURES / name).read_bytes()
        self.config.write_bytes(source)
        return source

    def run_runner(
        self, *arguments: str, extra_env: dict[str, str] | None = None
    ) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        environment.update(
            {
                "XDG_CONFIG_HOME": str(self.config_home),
                "XDG_STATE_HOME": str(self.state_home),
                "NBSHELL_MIGRATION_TESTING": "1",
            }
        )
        if extra_env:
            environment.update(extra_env)
        return subprocess.run(
            [str(RUNNER), *arguments],
            check=False,
            capture_output=True,
            text=True,
            env=environment,
        )

    def read_ledger(self) -> dict:
        return json.loads(self.ledger.read_text(encoding="utf-8"))

    def migration_entry(self) -> dict:
        return self.read_ledger()["migrations"][MIGRATION_ID]

    def test_fresh_missing_config_creates_schema_v1_without_backup(self) -> None:
        result = self.run_runner("apply", "--json")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.config.read_text()), {"schemaVersion": 1})
        self.assertTrue(self.migration_entry()["fresh"])
        self.assertFalse((self.state_home / "nbshell/migration-backups").exists())

    def test_status_reports_missing_config_as_pending_baseline(self) -> None:
        result = self.run_runner("status", "--json")
        self.assertEqual(result.returncode, 1, result.stderr)
        status = json.loads(result.stdout)
        self.assertFalse(status["ok"])
        self.assertIsNone(status["schemaVersion"])
        self.assertEqual(status["migrations"][0]["status"], "pending")
        self.assertTrue(status["migrations"][0]["baseline"])
        self.assertFalse(self.config.exists())
        self.assertFalse(self.ledger.exists())

    def test_current_config_without_ledger_records_baseline(self) -> None:
        original = self.install_fixture("current-v1.json")
        result = self.run_runner("apply", "--json")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.config.read_bytes(), original)
        self.assertEqual(self.migration_entry()["status"], "applied")
        self.assertTrue(self.migration_entry()["baseline"])
        self.assertFalse((self.state_home / "nbshell/migration-backups").exists())

    def test_supported_legacy_fixture_is_migrated_with_backup(self) -> None:
        original = self.install_fixture("legacy-v0.json")
        result = self.run_runner("apply", "--json")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(self.config.read_text())["schemaVersion"], 1)
        entry = self.migration_entry()
        self.assertEqual(entry["status"], "applied")
        self.assertEqual(pathlib.Path(entry["backup"]).read_bytes(), original)

    def test_already_current_config_and_applied_ledger_are_no_op(self) -> None:
        self.install_fixture("current-v1.json")
        self.assertEqual(self.run_runner("apply").returncode, 0)
        config_before = self.config.read_bytes()
        ledger_before = self.ledger.read_bytes()
        result = self.run_runner("apply", "--json")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.config.read_bytes(), config_before)
        self.assertEqual(self.ledger.read_bytes(), ledger_before)

    def test_applied_ledger_does_not_hide_a_downgraded_config(self) -> None:
        self.install_fixture("current-v1.json")
        first = self.run_runner("apply")
        self.assertEqual(first.returncode, 0, first.stderr)
        self.install_fixture("legacy-v0.json")

        result = self.run_runner("apply")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("recorded as applied", result.stderr)
        self.assertNotIn("schemaVersion", json.loads(self.config.read_text()))

    def test_running_legacy_migration_twice_is_idempotent(self) -> None:
        self.install_fixture("legacy-v0.json")
        self.assertEqual(self.run_runner("apply").returncode, 0)
        config_before = self.config.read_bytes()
        ledger_before = self.ledger.read_bytes()
        self.assertEqual(self.run_runner("apply").returncode, 0)
        self.assertEqual(self.config.read_bytes(), config_before)
        self.assertEqual(self.ledger.read_bytes(), ledger_before)
        self.assertEqual(len(list((self.state_home / "nbshell/migration-backups").iterdir())), 1)

    def test_unknown_fields_are_preserved(self) -> None:
        value = {
            "theme": "custom",
            "futureOption": {"nested": [1, "two", {"three": True}]},
            "pluginDefinedValue": None,
        }
        self.config.write_text(json.dumps(value), encoding="utf-8")
        result = self.run_runner("apply")
        self.assertEqual(result.returncode, 0, result.stderr)
        migrated = json.loads(self.config.read_text(encoding="utf-8"))
        self.assertEqual(migrated["futureOption"], value["futureOption"])
        self.assertIsNone(migrated["pluginDefinedValue"])
        self.assertEqual(migrated["schemaVersion"], 1)

    def test_invalid_json_fails_without_writes(self) -> None:
        original = self.install_fixture("invalid-json.txt")
        result = self.run_runner("apply", "--json")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not valid UTF-8 JSON", json.loads(result.stdout)["error"])
        self.assertEqual(self.config.read_bytes(), original)
        self.assertFalse(self.ledger.exists())
        self.assertFalse((self.state_home / "nbshell/migration-backups").exists())

    def test_filesystem_errors_stay_machine_readable(self) -> None:
        self.config.mkdir(parents=True)
        result = self.run_runner("status", "--json")
        self.assertNotEqual(result.returncode, 0)
        payload = json.loads(result.stdout)
        self.assertFalse(payload["ok"])
        self.assertEqual(result.stderr, "")

    def test_controlled_migration_failure_is_failed_not_applied(self) -> None:
        original = self.install_fixture("legacy-v0.json")
        result = self.run_runner(
            "apply", extra_env={"NBSHELL_MIGRATION_TEST_FAIL": MIGRATION_ID}
        )
        self.assertNotEqual(result.returncode, 0)
        entry = self.migration_entry()
        self.assertEqual(entry["status"], "failed")
        self.assertNotIn("completedAt", entry)
        self.assertEqual(self.config.read_bytes(), original)
        self.assertEqual(pathlib.Path(entry["backup"]).read_bytes(), original)
        retry = self.run_runner("apply")
        self.assertNotEqual(retry.returncode, 0)
        self.assertIn("previously failed", retry.stderr)

    def test_interrupt_after_backup_leaves_original_and_resumes(self) -> None:
        original = self.install_fixture("legacy-v0.json")
        result = self.run_runner(
            "apply", extra_env={"NBSHELL_MIGRATION_TEST_INTERRUPT": "after-backup"}
        )
        self.assertEqual(result.returncode, 97)
        self.assertEqual(self.config.read_bytes(), original)
        entry = self.migration_entry()
        self.assertEqual(entry["status"], "pending")
        backup = pathlib.Path(entry["backup"])
        self.assertEqual(backup.read_bytes(), original)
        resumed = self.run_runner("apply")
        self.assertEqual(resumed.returncode, 0, resumed.stderr)
        self.assertEqual(self.migration_entry()["status"], "applied")
        self.assertEqual(backup.read_bytes(), original)

    def test_interrupt_after_replace_recovers_pending_ledger(self) -> None:
        original = self.install_fixture("legacy-v0.json")
        result = self.run_runner(
            "apply", extra_env={"NBSHELL_MIGRATION_TEST_INTERRUPT": "after-replace"}
        )
        self.assertEqual(result.returncode, 98)
        self.assertEqual(json.loads(self.config.read_text())["schemaVersion"], 1)
        entry = self.migration_entry()
        self.assertEqual(entry["status"], "pending")
        self.assertEqual(pathlib.Path(entry["backup"]).read_bytes(), original)

        resumed = self.run_runner("apply")
        self.assertEqual(resumed.returncode, 0, resumed.stderr)
        entry = self.migration_entry()
        self.assertEqual(entry["status"], "applied")
        self.assertTrue(entry["recoveredAfterInterruption"])

    def test_pending_migration_rejects_a_damaged_backup(self) -> None:
        self.install_fixture("legacy-v0.json")
        result = self.run_runner(
            "apply", extra_env={"NBSHELL_MIGRATION_TEST_INTERRUPT": "after-replace"}
        )
        self.assertEqual(result.returncode, 98)
        entry = self.migration_entry()
        pathlib.Path(entry["backup"]).write_text("damaged\n", encoding="utf-8")

        resumed = self.run_runner("apply")
        self.assertNotEqual(resumed.returncode, 0)
        self.assertIn("backup is damaged", resumed.stderr)
        self.assertEqual(self.migration_entry()["status"], "pending")

    def test_missing_ledger_is_created_and_corrupt_ledger_is_rejected(self) -> None:
        self.install_fixture("legacy-v0.json")
        self.assertFalse(self.ledger.exists())
        dry_run = self.run_runner("apply", "--dry-run", "--json")
        self.assertEqual(dry_run.returncode, 0, dry_run.stderr)
        self.assertFalse(self.ledger.exists())
        self.ledger.parent.mkdir(parents=True, exist_ok=True)
        self.ledger.write_text('{"ledgerVersion": 1, "domain": "wrong"}\n', encoding="utf-8")
        original = self.config.read_bytes()
        result = self.run_runner("apply", "--json")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("unexpected domain", json.loads(result.stdout)["error"])
        self.assertEqual(self.config.read_bytes(), original)

    def test_parallel_starts_serialize_and_apply_once(self) -> None:
        self.install_fixture("legacy-v0.json")
        ready = self.root / "lock-ready"
        environment = os.environ.copy()
        environment.update(
            {
                "XDG_CONFIG_HOME": str(self.config_home),
                "XDG_STATE_HOME": str(self.state_home),
                "NBSHELL_MIGRATION_TESTING": "1",
                "NBSHELL_MIGRATION_TEST_READY_FILE": str(ready),
                "NBSHELL_MIGRATION_TEST_HOLD_LOCK": "0.5",
            }
        )
        first = subprocess.Popen(
            [str(RUNNER), "apply"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            env=environment,
        )
        deadline = time.monotonic() + 3
        while not ready.exists() and time.monotonic() < deadline:
            time.sleep(0.01)
        self.assertTrue(ready.exists(), "first runner did not acquire the lock")
        started = time.monotonic()
        second = self.run_runner("apply")
        elapsed = time.monotonic() - started
        first_stdout, first_stderr = first.communicate(timeout=3)
        self.assertEqual(first.returncode, 0, first_stderr or first_stdout)
        self.assertEqual(second.returncode, 0, second.stderr)
        self.assertGreater(elapsed, 0.2)
        self.assertEqual(self.migration_entry()["status"], "applied")
        self.assertEqual(len(list((self.state_home / "nbshell/migration-backups").iterdir())), 1)

    def test_cli_refuses_live_mutating_apply_with_options_before_action(self) -> None:
        self.install_fixture("legacy-v0.json")
        runtime_scripts = self.config_home / "quickshell/nbshell/scripts"
        runtime_scripts.mkdir(parents=True)
        shutil.copy2(RUNNER, runtime_scripts / RUNNER.name)
        fake_bin = self.root / "bin"
        fake_bin.mkdir()
        fake_qs = fake_bin / "qs"
        fake_qs.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        fake_qs.chmod(0o755)
        environment = os.environ.copy()
        environment.update(
            {
                "HOME": str(self.root / "home"),
                "XDG_CONFIG_HOME": str(self.config_home),
                "XDG_STATE_HOME": str(self.state_home),
                "PATH": f"{fake_bin}:{environment['PATH']}",
            }
        )

        result = subprocess.run(
            [str(CLI), "migrate", "--json", "apply"],
            check=False,
            capture_output=True,
            text=True,
            env=environment,
        )

        self.assertNotEqual(result.returncode, 0)
        self.assertIn("stop nbshell", result.stderr)
        self.assertNotIn("schemaVersion", json.loads(self.config.read_text()))
        self.assertFalse(self.ledger.exists())


if __name__ == "__main__":
    unittest.main()
