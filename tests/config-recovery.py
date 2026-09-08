#!/usr/bin/env python3
"""Recovery transaction and ordered migration behavior in private fixtures."""
import base64
import copy
import json
import os
from pathlib import Path
import runpy
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = patch.dict(os.environ, {"XDG_CONFIG_HOME": str(self.root / "config"),
                                          "XDG_STATE_HOME": str(self.root / "state")})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.m = runpy.run_path(str(ROOT / "shell/scripts/config-migrations.py"))
        self.r = runpy.run_path(str(ROOT / "shell/scripts/config-repair.py"))
        self.config, self.ledger, self.state = self.m["paths_from_environment"]()
        self.config.parent.mkdir(parents=True)
        self.config.write_bytes(b'{broken configuration\xff')
        self.candidate = self.root / "candidate.json"
        self.candidate.write_text(json.dumps({"theme": "custom", "unknown": {"keep": [1, True]}}))

    def test_preview_does_not_replace_and_apply_retains_originals(self):
        original = self.config.read_bytes()
        self.ledger.parent.mkdir(parents=True)
        self.ledger.write_bytes(b'broken history')
        preview = self.r["preview"](self.candidate)
        self.assertEqual(self.config.read_bytes(), original)
        self.assertEqual(self.ledger.read_bytes(), b'broken history')
        self.r["apply"](preview["token"])
        self.assertTrue(self.m["read_status"](self.config, self.ledger)["ok"])
        self.assertEqual(json.loads(self.config.read_bytes())["unknown"], {"keep": [1, True]})
        backup = json.loads(Path(preview["backup"]).read_bytes())
        self.assertEqual(base64.b64decode(backup["beforeConfig"]), original)
        self.assertEqual(base64.b64decode(backup["beforeLedger"]), b'broken history')
        self.assertEqual(Path(preview["backup"]).stat().st_mode & 0o777, 0o600)
        self.assertTrue(self.r["apply"](preview["token"])["ok"])

    def test_changed_config_or_history_rejects_reviewed_candidate(self):
        for target in [self.config, self.ledger]:
            with self.subTest(target=target):
                preview = self.r["preview"](self.candidate)
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(b'changed after preview')
                before = self.config.read_bytes()
                with self.assertRaisesRegex(RuntimeError, "changed after preview"):
                    self.r["apply"](preview["token"])
                self.assertEqual(self.config.read_bytes(), before)
                self.assertFalse((self.state / "repair-pending.json").exists())

    def test_candidate_snapshot_and_damaged_record(self):
        preview = self.r["preview"](self.candidate)
        self.candidate.write_text('{bad later')
        self.r["apply"](preview["token"])
        self.assertEqual(json.loads(self.config.read_bytes())["theme"], "custom")
        Path(preview["backup"]).write_bytes(b'bad record')
        with self.assertRaisesRegex(RuntimeError, "damaged"):
            self.r["apply"](preview["token"])

    def test_invalid_candidates_never_replace(self):
        before = self.config.read_bytes()
        for raw in ['[]', '{bad', '{"schemaVersion":99}', '{"schemaVersion":true}', '{"a":NaN}', '{"a":1e999}']:
            with self.subTest(raw=raw):
                self.candidate.write_text(raw)
                with self.assertRaises((RuntimeError, ValueError)):
                    self.r["preview"](self.candidate)
                self.assertEqual(self.config.read_bytes(), before)
                self.assertFalse(self.ledger.exists())

    def test_interrupted_repair_blocks_writers_and_resumes(self):
        preview = self.r["preview"](self.candidate)
        helpers = self.r["apply"].__globals__["M"]
        original_write = helpers["atomic_write"]
        def interrupted(path, raw):
            original_write(path, raw)
            if path == self.config:
                raise OSError("simulated lost process after config replacement")
        with patch.dict(helpers, {"atomic_write": interrupted}):
            with self.assertRaises(OSError):
                self.r["apply"](preview["token"])
        self.assertTrue((self.state / "repair-pending.json").exists())
        with self.assertRaisesRegex(RuntimeError, "interrupted"):
            self.m["apply_migrations"](self.config, self.ledger, self.state, False)
        writer = runpy.run_path(str(ROOT / "shell/scripts/config-write.py"))
        with self.assertRaisesRegex(RuntimeError, "interrupted"):
            writer["update_config"](lambda data: data)
        with self.assertRaisesRegex(RuntimeError, "interrupted"):
            self.r["preview"](self.candidate)
        self.r["apply"](preview["token"])
        self.assertFalse((self.state / "repair-pending.json").exists())
        self.assertTrue(self.m["read_status"](self.config, self.ledger)["ok"])

    def test_missing_config_with_history_explicitly_restored(self):
        self.config.unlink()
        self.ledger.parent.mkdir(parents=True)
        self.ledger.write_bytes(b'old history')
        preview = self.r["preview"](self.candidate)
        self.r["apply"](preview["token"])
        self.assertTrue(self.config.exists())

    def test_start_failure_launches_recovery_not_main_shell(self):
        scripts = self.root / "config/quickshell/nbshell/scripts"
        scripts.mkdir(parents=True)
        (scripts / "config-migrations.py").write_text('raise SystemExit(1)\n')
        bindir = self.root / "bin"
        bindir.mkdir()
        fake = bindir / "qs"
        fake.write_text('#!/bin/sh\ncase "$*" in *"ipc call"*) exit 1;; esac\nprintf "%s\\n" "$@"\n')
        fake.chmod(0o755)
        with patch.dict(os.environ, {"PATH": str(bindir) + ":" + os.environ["PATH"]}):
            result = subprocess.run([str(ROOT / "bin/nbshell"), "start"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("recovery.qml", result.stdout)
        self.assertEqual(self.config.read_bytes(), b'{broken configuration\xff')


class OrderedMigrationTests(RecoveryTests):
    # Only run this class's tests, not the recovery suite twice.
    def setUp(self):
        super().setUp()
        self.config.write_text('{"kept":{"private":[1,2]}}')
        self.g = self.m["apply_migrations"].__globals__
        def step2(config):
            config["schemaVersion"] = 2
            config["second"] = True
            return config
        def step3(config):
            if not config.get("second"):
                raise RuntimeError("out of order")
            config["schemaVersion"] = 3
            config["third"] = True
            return config
        self.g["SCHEMA_VERSION"] = 3
        self.g["MIGRATIONS"] += ({"id": "0002-fixture", "checksum": "fixture2", "source": 1, "target": 2, "transform": step2},
                                 {"id": "0003-fixture", "checksum": "fixture3", "source": 2, "target": 3, "transform": step3})

    def test_ordered_steps_have_individual_backups_and_are_idempotent(self):
        result = self.m["apply_migrations"](self.config, self.ledger, self.state, False)
        self.assertTrue(result["ok"])
        self.assertEqual(len(result["migrations"]), 3)
        for index, entry in enumerate(result["migrations"]):
            before = json.loads(Path(entry["backup"]).read_bytes())
            self.assertEqual(before.get("schemaVersion"), index or None)
            self.assertEqual(before["kept"], {"private": [1, 2]})
        before = self.config.read_bytes(), self.ledger.read_bytes()
        self.m["apply_migrations"](self.config, self.ledger, self.state, False)
        self.assertEqual(before, (self.config.read_bytes(), self.ledger.read_bytes()))

    def test_second_step_interrupt_resumes_without_reapplying_first(self):
        original_write = self.g["atomic_write"]
        def interrupt(path, raw):
            original_write(path, raw)
            if path == self.config and json.loads(raw).get("schemaVersion") == 2:
                raise OSError("interrupted second step")
        with patch.dict(self.g, {"atomic_write": interrupt}):
            with self.assertRaises(OSError):
                self.m["apply_migrations"](self.config, self.ledger, self.state, False)
        ledger = json.loads(self.ledger.read_bytes())
        first = copy.deepcopy(ledger["migrations"]["0001-config-schema-v1"])
        self.assertEqual(ledger["migrations"]["0002-fixture"]["status"], "pending")
        result = self.m["apply_migrations"](self.config, self.ledger, self.state, False)
        self.assertTrue(result["ok"])
        self.assertEqual(json.loads(self.ledger.read_bytes())["migrations"]["0001-config-schema-v1"], first)
        self.assertTrue(result["migrations"][1]["recoveredAfterInterruption"])

    def test_pending_target_version_does_not_hide_external_edits(self):
        original_write = self.g["atomic_write"]
        def interrupt(path, raw):
            original_write(path, raw)
            if path == self.config:
                raise OSError("interrupt")
        with patch.dict(self.g, {"atomic_write": interrupt}):
            with self.assertRaises(OSError):
                self.m["apply_migrations"](self.config, self.ledger, self.state, False)
        edited = json.loads(self.config.read_bytes())
        edited["external"] = True
        self.config.write_text(json.dumps(edited))
        with self.assertRaisesRegex(RuntimeError, "changed after backup"):
            self.m["apply_migrations"](self.config, self.ledger, self.state, False)
        self.assertEqual(json.loads(self.config.read_bytes()), edited)

    def test_bad_registry_order_and_unknown_history_fail_closed(self):
        steps = self.g["MIGRATIONS"]
        self.g["MIGRATIONS"] = steps[::-1]
        with self.assertRaisesRegex(RuntimeError, "registry order"):
            self.m["apply_migrations"](self.config, self.ledger, self.state, False)
        self.assertFalse(self.ledger.exists())
        self.g["MIGRATIONS"] = steps
        status = self.m["apply_migrations"](self.config, self.ledger, self.state, True)
        self.assertEqual(len(status["migrations"]), 3)
        self.assertFalse(self.ledger.exists())


if __name__ == "__main__":
    suite = unittest.TestSuite()
    for cls in (RecoveryTests, OrderedMigrationTests):
        suite.addTests(cls(name) for name in cls.__dict__ if name.startswith("test_"))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    raise SystemExit(not result.wasSuccessful())
