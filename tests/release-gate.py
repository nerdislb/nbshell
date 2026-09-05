#!/usr/bin/env python3
"""Release-gate argument and fail-closed prerequisite contracts."""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
GATE = ROOT / "tests/release-gate.sh"


class ReleaseGateTests(unittest.TestCase):
    def run_gate(self, *args, **overrides):
        return subprocess.run(
            ["bash", str(GATE), *args], env={**os.environ, **overrides},
            capture_output=True, text=True, timeout=10,
        )

    def test_help_does_not_run_suite(self):
        result = self.run_gate("--help")
        self.assertEqual(result.returncode, 0)
        self.assertIn("live Umbriel acceptance", result.stdout)
        self.assertNotIn("==> shell syntax", result.stdout)

    def test_unknown_argument_fails(self):
        result = self.run_gate("--skip-qml")
        self.assertEqual(result.returncode, 2)

    def test_missing_qml_runner_fails_before_suite(self):
        result = self.run_gate(
            "--check-tools", QML_TEST_RUNNER="/nonexistent/nbshell-test-runner",
        )
        self.assertEqual(result.returncode, 1)
        self.assertIn("Required Qt gate tool missing", result.stderr)
        self.assertNotIn("==> shell syntax", result.stdout)

    def test_rejects_extra_arguments(self):
        self.assertEqual(self.run_gate("--check-tools", "extra").returncode, 2)


if __name__ == "__main__":
    unittest.main()
