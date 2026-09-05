#!/usr/bin/env python3
"""Offline policy/probe tests; synthetic attestations are never release claims."""
import copy
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "shell/scripts"))
import stack_status as stack

FIXTURES = ROOT / "tests/fixtures/stack"
CLI = ROOT / "shell/scripts/stack-status.py"


class PolicyTests(unittest.TestCase):
    def setUp(self):
        self.manifest = stack.load_json(stack.DEFAULT_MANIFEST)
        self.observed = stack.load_json(FIXTURES / "baseline-observed.json")

    def report(self):
        return stack.evaluate(self.manifest, self.observed)

    def component(self, name="qt"):
        return self.report()["components"][name]

    def attest(self):
        self.manifest["testedStacks"] = [{"components": {n: v["value"] for n, v in self.observed["components"].items()}, "evidence": "SYNTHETIC TEST ONLY"}]

    def test_release_identity_and_pins_do_not_drift(self):
        self.assertEqual(self.manifest["nbshellVersion"], (ROOT / "VERSION").read_text().strip())
        setup = (ROOT / "setup-umbriel.sh").read_text()
        for name, var in (("umbriel", "UMBRIEL"), ("portal", "PORTAL")):
            self.assertIn(f'{var}_REVISION="{self.manifest["components"][name]["supported"][0]}"', setup)
        contract = stack.load_json(ROOT / "shell/Catalog/umbriel-capabilities.json")
        self.assertEqual(contract["referenceRevision"], self.manifest["components"]["umbriel"]["supported"][0])

    def test_shipped_manifest_does_not_invent_tested_stack_or_minimum(self):
        self.assertEqual(self.manifest["testedStacks"], [])
        for name in ("qt", "quickshell"):
            self.assertIsNone(self.manifest["components"][name]["minimum"])
        self.assertEqual(self.report()["status"], "compatible-unverified")
        self.assertEqual(self.component("quickshell")["status"], "supported")

    def test_all_states_and_precedence(self):
        self.manifest["components"]["qt"]["supported"] = ["6.11.2"]
        self.assertEqual(self.report()["status"], "supported")
        self.attest()
        self.assertEqual(self.report()["status"], "tested")
        self.observed["components"]["qt"]["dirty"] = True
        self.assertEqual(self.report()["status"], "compatible-unverified")
        self.observed["components"]["portal"]["available"] = False
        self.assertEqual(self.report()["status"], "degraded")
        self.manifest["components"]["qt"]["incompatible"] = ["6.11.2"]
        self.assertEqual(self.report()["status"], "unsupported")
        self.manifest["components"]["qt"]["securityBlocked"] = ["6.11.2"]
        self.assertEqual(self.report()["status"], "security-blocked")

    def test_security_block_cannot_be_evaded_with_build_metadata(self):
        self.manifest["components"]["qt"]["securityBlocked"] = ["6.11.2"]
        self.observed["components"]["qt"].update(value="6.11.2+local", dirty=True, available=False)
        self.assertEqual(self.component()["status"], "security-blocked")

    def test_minimum_uses_semver_not_lexical_order(self):
        self.manifest["components"]["qt"]["minimum"] = "6.9.0"
        self.assertEqual(self.component()["status"], "compatible-unverified")
        self.observed["components"]["qt"]["value"] = "6.8.99"
        self.assertEqual(self.component()["reason"], "below-minimum")
        self.observed["components"]["qt"]["value"] = "6.9.0-rc.1"
        self.assertEqual(self.component()["reason"], "below-minimum")
        self.observed["components"]["qt"]["value"] = "7.0.0"
        self.assertEqual(self.component()["status"], "compatible-unverified")

    def test_semver_prerelease_order(self):
        values = ["1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2", "1.0.0-beta.11", "1.0.0-rc.1", "1.0.0"]
        self.assertEqual(sorted(values, key=stack.version), values)
        self.assertEqual(stack.version("1.0.0+build"), stack.version("1.0.0"))

    def test_malformed_versions_do_not_gain_support_or_leak(self):
        for value in ["v6.11.2", "6.11", "06.11.2", "6.11.2-01", "6.11.2-3-arch!", "secret\nvalue", "$(touch /tmp/forbidden)"]:
            with self.subTest(value=value):
                self.observed["components"]["qt"]["value"] = value
                self.assertIsNone(self.component()["value"])
                self.assertEqual(self.component()["status"], "compatible-unverified")

    def test_revision_prefix_case_and_dirty_do_not_match(self):
        original = self.observed["components"]["umbriel"]["value"]
        for value in (original[:12], original.upper(), original + "-dirty", "a" * 40):
            self.observed["components"]["umbriel"]["value"] = value
            self.assertEqual(self.component("umbriel")["status"], "compatible-unverified")
        self.observed["components"]["umbriel"].update(value=original, dirty=True)
        self.assertEqual(self.component("umbriel")["reason"], "development-build")

    def test_unknown_and_development_fixtures(self):
        for name in ("unknown", "development"):
            self.observed = stack.load_json(FIXTURES / f"{name}-observed.json")
            report = self.report()
            self.assertEqual(report["status"], "compatible-unverified")
            self.assertIsNone(report["testedStack"])
            self.assertEqual(set(report["components"]), set(stack.COMPONENTS))

    def test_platform_identity_and_functional_failure(self):
        self.observed["components"]["platform"]["value"] = "linux:endeavouros"
        self.assertEqual(self.component("platform")["status"], "compatible-unverified")
        self.observed["components"]["platform"]["value"] = "freebsd:freebsd"
        self.assertEqual(self.report()["status"], "unsupported")
        self.observed["components"]["platform"]["value"] = "linux:arch"
        self.observed["components"]["portal"]["health"] = "degraded"
        self.assertEqual(self.report()["status"], "degraded")

    def test_evaluation_is_pure_and_deterministic(self):
        before = copy.deepcopy((self.manifest, self.observed))
        with patch.object(stack, "bounded_probe", side_effect=AssertionError("must not probe")):
            self.assertEqual(self.report(), self.report())
        self.assertEqual(before, (self.manifest, self.observed))

    def test_invalid_manifest_fails_closed(self):
        for update in ({"schemaVersion": True}, {"schemaVersion": 2}, {"manifestVersion": 0}, {"nbshellVersion": "bad"}, {"testedStacks": [{"components": {}}]}, {"components": {}}):
            with self.subTest(update=update), self.assertRaises(ValueError):
                stack.evaluate({**self.manifest, **update}, self.observed)
        self.manifest["components"]["umbriel"]["supported"] = ["e677dbbe"]
        with self.assertRaises(ValueError):
            self.report()

    def test_invalid_observations_fail_closed(self):
        for update in ({"schemaVersion": True}, {"schemaVersion": 2}, {"components": []}, {"components": {"alien": {}}}):
            with self.subTest(update=update), self.assertRaises(ValueError):
                stack.evaluate(self.manifest, {**self.observed, **update})
        for value in ({"available": 1}, {"dirty": "false"}, {"health": "tested"}, {"value": []}, {"value": "x" * 129}, {"command": "whoami"}):
            self.observed["components"]["qt"] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                self.report()

    def test_attestation_requires_every_exact_component(self):
        self.attest()
        self.assertEqual(self.report()["testedStack"], 0)
        self.observed["components"]["qt"]["value"] = "6.11.2+local"
        self.assertIsNone(self.report()["testedStack"])
        self.manifest["testedStacks"][0]["components"].pop("portal")
        with self.assertRaises(ValueError):
            self.report()


class InputAndProbeTests(unittest.TestCase):
    def test_json_size_duplicate_and_nonfinite_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "input.json"
            for text in ('{"a":1,"a":2}', '{"a":NaN}', ' ' * (stack.LIMIT + 1)):
                path.write_text(text)
                with self.assertRaises(ValueError):
                    stack.load_json(path)

    def test_nonregular_input_rejected_without_blocking(self):
        import os
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "pipe"
            os.mkfifo(path)
            with self.assertRaises(ValueError):
                stack.load_json(path)

    def test_cli_offline_deterministic(self):
        command = [sys.executable, str(CLI), "--json", "--observed", str(FIXTURES / "development-observed.json")]
        first = subprocess.run(command, capture_output=True, text=True, check=True)
        second = subprocess.run(command, capture_output=True, text=True, check=True)
        self.assertEqual(first.stdout, second.stdout)
        self.assertEqual(json.loads(first.stdout)["status"], "compatible-unverified")
        self.assertEqual(first.stderr, "")

    def test_cli_error_is_sanitized_json(self):
        proc = subprocess.run([sys.executable, str(CLI), "--json", "--observed", "/secret-private-missing-file"], capture_output=True, text=True)
        self.assertEqual(proc.returncode, 2)
        self.assertEqual(json.loads(proc.stdout)["error"]["code"], "stack-input-invalid")
        self.assertNotIn("secret-private", proc.stdout + proc.stderr)

    def test_probe_success_failure_timeout_and_overflow(self):
        for script, expected in [("print('1.2.3')", "ok"), ("raise SystemExit(3)", "failed"), ("import time; time.sleep(20)", "timeout"), ("print('x'*10000)", "overflow")]:
            with self.subTest(expected=expected):
                text, state = stack.bounded_probe([sys.executable, "-c", script], timeout=0.2, limit=100)
                self.assertEqual(state, expected)
                self.assertEqual(text, "1.2.3" if expected == "ok" else None)
        self.assertEqual(stack.bounded_probe(["/definitely/not/a/binary"]), (None, "missing"))

    def test_probe_does_not_dump_environment_or_stderr(self):
        with patch.dict("os.environ", {"NBSHELL_TEST_SECRET": "do-not-leak"}):
            text, state = stack.bounded_probe([sys.executable, "-c", "import os,sys; print(os.environ.get('NBSHELL_TEST_SECRET', 'absent')); print('private', file=sys.stderr)"])
        self.assertEqual((text, state), ("absent", "ok"))

    def test_descendant_holding_pipe_is_bounded(self):
        text, outcome = stack.bounded_probe([sys.executable, "-c", "import os,time; pid=os.fork(); time.sleep(20) if pid == 0 else None"], timeout=0.2)
        self.assertEqual((text, outcome), (None, "timeout"))

    def test_probe_only_known_version_commands_and_no_portal_start(self):
        replies = [("Quickshell 0.3.1 (revision , distributed by Arch Linux)", "ok"), ("6.11.2", "ok"), ("umbriel 0.1.0 (9b6472f5e408)", "ok")]
        with patch.object(stack, "bounded_probe", side_effect=replies) as probe:
            observed = stack.probe_stack()
        self.assertEqual([c.args[0] for c in probe.call_args_list], [["quickshell", "--version"], ["/usr/lib/qt6/bin/qtpaths", "--qt-version"], ["umbriel", "--version"]])
        self.assertIsNone(observed["components"]["portal"]["value"])
        self.assertIsNone(observed["components"]["umbriel"]["value"])
        self.assertEqual(observed["components"]["qt"]["value"], "6.11.2")

    def test_missing_probe_tool_is_not_missing_qt(self):
        with patch.object(stack, "bounded_probe", return_value=(None, "missing")):
            components = stack.probe_stack()["components"]
        self.assertIsNone(components["qt"]["available"])
        self.assertFalse(components["quickshell"]["available"])
        self.assertFalse(components["umbriel"]["available"])


if __name__ == "__main__":
    unittest.main()
