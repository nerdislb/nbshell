#!/usr/bin/env python3
"""Offline doctor fixtures: no session, services or credentials are mutated."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("doctor", ROOT / "shell/scripts/doctor.py")
assert spec is not None and spec.loader is not None
doctor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(doctor)
SECRET = "private-host /home/private-user token=VERY_SECRET window-title"


def compositor(socket=True, required=True):
    return {"schemaVersion": 1, "runtime": {"socketAvailable": socket, "binary": SECRET,
            "version": SECRET, "socket": SECRET}, "capabilities": [
            {"required": True, "available": required, "id": SECRET},
            {"required": False, "available": False, "id": SECRET}], "errors": [SECRET]}


class DoctorTests(unittest.TestCase):
    def fixture(self, command, timeout=3):
        self.assertGreater(timeout, 0)
        self.assertLessEqual(timeout, 20)
        if command[0] == "busctl":
            self.assertIn("--auto-start=no", command)
            self.assertIn("get-property", command)
            text = "u 3"
        elif command[0] == "systemctl":
            self.assertIn("show", command)
            self.assertIn(command[-1], doctor.UNITS)
            text = "active"
        elif Path(command[1]).name == "umbriel-contract.py":
            self.assertEqual(command[2:], ["status", "--json"])
            text = json.dumps(compositor())
        elif Path(command[1]).name == "stack-status.py":
            text = json.dumps({"schemaVersion": 999, "status": "supported", "secret": SECRET})
        else:
            self.fail("Unexpected command")
        return "ok", text

    def test_projection_and_determinism(self):
        with patch.object(doctor, "probe", side_effect=self.fixture):
            first = doctor.collect()
            self.assertEqual(first, doctor.collect())
        self.assertNotIn(SECRET, json.dumps(first))
        self.assertEqual(first["runtime"]["health"], "healthy")
        self.assertEqual(first["runtime"]["portal"]["health"], "healthy")
        self.assertFalse(first["runtime"]["portal"]["consentCaptureTested"])
        self.assertEqual(first["support"]["status"], "unknown")
        self.assertFalse(doctor.healthy(first))

    def test_offline_and_missing_optional_tools(self):
        def offline(command, timeout=3):
            if command[0] == "busctl":
                return "missing-tool", ""
            return self.fixture(command, timeout)
        with patch.object(doctor, "probe", side_effect=offline):
            data = doctor.collect()
        self.assertEqual(data["runtime"]["health"], "healthy")
        self.assertEqual(data["runtime"]["portal"]["health"], "unknown")
        self.assertNotIn(SECRET, json.dumps(data))
        with patch.object(doctor, "json_probe", return_value=("ok", compositor(socket=False))):
            self.assertEqual(doctor.compositor_status()["health"], "unhealthy")

    def test_failures_are_redacted(self):
        for error in (FileNotFoundError(SECRET), PermissionError(SECRET),
                      subprocess.TimeoutExpired([SECRET], 3, output=SECRET, stderr=SECRET)):
            with self.subTest(error=type(error)), patch.object(doctor.subprocess, "Popen", side_effect=error):
                data = doctor.collect()
                self.assertEqual(data["runtime"]["health"], "unknown")
                self.assertNotIn(SECRET, json.dumps(data))
        for text in (SECRET, "[]", "null", '{"schemaVersion":1}', "{" * 2000):
            with patch.object(doctor, "probe", return_value=("ok", text)):
                self.assertEqual(doctor.collect()["runtime"]["health"], "unknown")
                self.assertNotIn(SECRET, json.dumps(doctor.collect()))

    def test_nonzero_ignored_and_states_allowlisted(self):
        with patch.object(doctor, "probe", return_value=("failed", "")):
            self.assertEqual(doctor.service_status(doctor.UNITS[0])["state"], "unknown")
        with patch.object(doctor, "probe", return_value=("ok", SECRET)):
            self.assertEqual(doctor.service_status(doctor.UNITS[0])["state"], "unknown")
        with patch.object(doctor, "probe", return_value=("ok", "failed")):
            self.assertEqual(doctor.service_status(doctor.UNITS[0])["state"], "failed")

    def test_portal_does_not_accept_arbitrary_or_zero_properties(self):
        for text in ("u 0", "u 4294967296", "u 1\n" + SECRET, 's "1"', SECRET):
            with patch.object(doctor, "probe", return_value=("ok", text)):
                self.assertNotEqual(doctor.portal_status()["health"], "healthy")
                self.assertNotIn(SECRET, json.dumps(doctor.portal_status()))

    def test_contract_validation(self):
        for value in ({}, {"schemaVersion": 1, "capabilities": []},
                      {"schemaVersion": 1, "capabilities": [{"required": "yes", "available": True}]}):
            with patch.object(doctor, "json_probe", return_value=("ok", value)):
                self.assertEqual(doctor.compositor_status()["health"], "unknown")
        with patch.object(doctor, "json_probe", return_value=("ok", compositor(required=False))):
            self.assertEqual(doctor.compositor_status()["health"], "unhealthy")

    def test_real_subprocess_bounds(self):
        python = doctor.sys.executable
        self.assertEqual(doctor.probe([python, "-c", "print('ok')"]), ("ok", "ok"))
        self.assertEqual(doctor.probe([python, "-c", "import sys; print('private'); sys.exit(1)"]), ("failed", ""))
        self.assertEqual(doctor.probe([python, "-c", "print('x'*100000)"]), ("invalid", ""))
        self.assertEqual(doctor.probe([python, "-c", "import time; time.sleep(10)"], .05), ("timeout", ""))
        self.assertEqual(doctor.probe([python, "-c", "import os,time; os.fork(); time.sleep(10)"], .05), ("timeout", ""))
        self.assertEqual(doctor.probe([python, "-c", "import sys; print('private',file=sys.stderr); print('safe')"]), ("ok", "safe"))

    def test_stack_evaluator_projection(self):
        values = {"nbshell": "0.1.0-beta.10", "quickshell": "0.3.1", "qt": "6.11.2",
                  "umbriel": "a" * 40, "portal": "b" * 40, "platform": "linux:arch"}
        data = {"schemaVersion": 1, "status": "supported", "components": {
            name: {"value": value, "status": "supported", "reason": "documented-baseline",
                   "dirty": False, "available": True, "path": SECRET}
            for name, value in values.items()}}
        self.assertEqual(doctor.sanitize_stack("ok", data)["status"], "supported")
        self.assertNotIn(SECRET, json.dumps(doctor.sanitize_stack("ok", data)))
        data["components"]["qt"]["value"] = "6.11.2+private-host"
        self.assertIsNone(doctor.sanitize_stack("ok", data)["components"]["qt"]["value"])
        for state in ("compatible-unverified", "degraded", "unsupported", "security-blocked", "tested"):
            for item in data["components"].values():
                item["status"] = state
            data["status"] = state
            self.assertEqual(doctor.sanitize_stack("ok", data)["status"], state)
        data["status"] = "supported"
        self.assertEqual(doctor.sanitize_stack("ok", data)["status"], "unknown")
        data["components"]["qt"]["status"] = [SECRET]
        self.assertEqual(doctor.sanitize_stack("ok", data)["status"], "unknown")

    def test_check_success_and_optional_units(self):
        with patch.object(doctor, "probe", side_effect=self.fixture):
            data = doctor.collect()
        for support in ("tested", "supported"):
            data["support"]["status"] = support
            self.assertTrue(doctor.healthy(data))
            with patch.object(doctor, "collect", return_value=data), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(doctor.main(["--json", "--check"]), 0)
        def optional_failed(command, timeout=3):
            if command[0] == "systemctl" and command[-1] != "nbshell.service":
                return "ok", "failed"
            return self.fixture(command, timeout)
        with patch.object(doctor, "probe", side_effect=optional_failed):
            self.assertEqual(doctor.collect()["runtime"]["health"], "healthy")
        def shell_failed(command, timeout=3):
            if command[0] == "systemctl" and command[-1] == "nbshell.service":
                return "ok", "failed"
            return self.fixture(command, timeout)
        with patch.object(doctor, "probe", side_effect=shell_failed):
            self.assertEqual(doctor.collect()["runtime"]["health"], "unhealthy")

    def test_cli_default_and_check(self):
        with patch.object(doctor, "probe", side_effect=self.fixture):
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                self.assertEqual(doctor.main(["--json"]), 0)
            self.assertEqual(json.loads(output.getvalue())["schemaVersion"], 1)
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(doctor.main(["--check", "--json"]), 1)
                self.assertEqual(doctor.main([]), 0)


if __name__ == "__main__":
    unittest.main()
