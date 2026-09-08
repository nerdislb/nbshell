#!/usr/bin/env python3
"""Black-box tests for the nbshell/Umbriel capability contract."""

from __future__ import annotations

import argparse
from contextlib import contextmanager
import copy
import json
import os
from pathlib import Path
import shutil
import socket
import threading
import time
import subprocess
import sys
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "shell/scripts/umbriel-contract.py"
FIXTURES = ROOT / "tests/fixtures/umbriel-contract"


def verify_reference_binary(binary: Path) -> None:
    for arguments, fixture in ((["--help"], "help.txt"), (["msg", "--help"], "msg-help.txt")):
        result = subprocess.run(
            [str(binary), *arguments], text=True, capture_output=True, check=False, timeout=5,
        )
        if result.returncode != 0:
            raise SystemExit(f"Umbriel fixture probe failed: {result.stderr.strip()}")
        expected = (FIXTURES / fixture).read_text(encoding="utf-8")
        if result.stdout != expected:
            raise SystemExit(f"Umbriel fixture drift: {fixture} does not match {binary}")

    metadata = json.loads((FIXTURES / "fixture.json").read_text(encoding="utf-8"))
    version = subprocess.run(
        [str(binary), "--version"], text=True, capture_output=True, check=True, timeout=5,
    ).stdout
    if metadata["sourceRevision"][:12] not in version:
        raise SystemExit("Umbriel binary revision does not match fixture provenance")


def verify_reference_source(source: Path) -> None:
    metadata = json.loads((FIXTURES / "fixture.json").read_text(encoding="utf-8"))
    revision = subprocess.run(
        ["git", "-C", str(source), "rev-parse", "HEAD"],
        text=True, capture_output=True, check=True, timeout=5,
    ).stdout.strip()
    if revision != metadata["sourceRevision"]:
        raise SystemExit("Umbriel source revision does not match fixture provenance")
    dirty = subprocess.run(
        ["git", "-C", str(source), "status", "--porcelain", "--untracked-files=no"],
        text=True, capture_output=True, check=True, timeout=5,
    ).stdout
    if dirty:
        raise SystemExit("Umbriel source has tracked changes; contract verification is not reproducible")


class UmbrielCapabilityContractTests(unittest.TestCase):
    def test_fixture_provenance_matches_contract_reference(self) -> None:
        metadata = json.loads((FIXTURES / "fixture.json").read_text(encoding="utf-8"))
        contract = json.loads((ROOT / "shell/Catalog/umbriel-capabilities.json").read_text(encoding="utf-8"))
        self.assertEqual(metadata["sourceRevision"], contract["referenceRevision"])
        self.assertEqual(metadata["binary"], "build-nbshell-contract/umbriel")

    def setUp(self) -> None:
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.binary = self.root / "umbriel"
        self.log = self.root / "actions.jsonl"
        self.binary.write_text(textwrap.dedent(f"""\
            #!/usr/bin/env python3
            import os
            from pathlib import Path
            import sys

            fixtures = Path(os.environ["NBSHELL_UMBRIEL_FIXTURES"])
            args = sys.argv[1:]
            if args == ["--help"]:
                print((fixtures / "help.txt").read_text(), end="")
                raise SystemExit(0)
            if args == ["msg", "--help"]:
                name = os.environ.get("NBSHELL_UMBRIEL_MSG_HELP", "msg-help.txt")
                print((fixtures / name).read_text(), end="")
                raise SystemExit(0)
            if args == ["--version"]:
                print(os.environ.get("NBSHELL_UMBRIEL_VERSION", "umbriel 0.1.0 (e677dbbe2728)"))
                raise SystemExit(0)
            if len(args) == 2 and args[0] == "msg":
                with Path(os.environ["NBSHELL_UMBRIEL_ACTION_LOG"]).open("a") as handle:
                    handle.write(args[1] + "\\n")
                if os.environ.get("NBSHELL_UMBRIEL_FAIL_ACTION") == args[1]:
                    print("rejected by fixture", file=sys.stderr)
                    raise SystemExit(1)
                print("ok")
                raise SystemExit(0)
            print("unexpected fixture invocation: " + repr(args), file=sys.stderr)
            raise SystemExit(2)
        """), encoding="utf-8")
        self.binary.chmod(0o755)
        self.environment = os.environ.copy()
        self.environment.update({
            "NBSHELL_UMBRIEL_FIXTURES": str(FIXTURES),
            "NBSHELL_UMBRIEL_ACTION_LOG": str(self.log),
            "XDG_RUNTIME_DIR": str(self.root / "runtime"),
            "WAYLAND_DISPLAY": "fixture-0",
        })
        self.environment.pop("UMBRIEL_SOCKET", None)

    def tearDown(self) -> None:
        self.temporary.cleanup()

    def run_contract(self, *arguments: str, check: bool = True) -> subprocess.CompletedProcess[str]:
        result = subprocess.run(
            [str(RUNNER), *arguments, "--binary", str(self.binary), "--json"],
            env=self.environment, text=True, capture_output=True, check=False,
        )
        if check and result.returncode != 0:
            self.fail(f"contract failed ({result.returncode}): {result.stdout!r} {result.stderr!r}")
        return result

    @contextmanager
    def wire_server(self, transform=lambda name, event, value: value):
        path = self.root / "wire.sock"
        self.environment["UMBRIEL_SOCKET"] = str(path)
        stopped = threading.Event()
        requests = []
        failures = []
        windows = [{"id": "window-1", "workspace": "out:1", "app_id": "fixture",
                    "title": "PRIVATE-TITLE", "active": True, "floating": False,
                    "focused": True, "urgent": False, "xwayland": False,
                    "x": -10, "y": 0, "w": 400, "h": 300}]
        workspaces = [{"id": "out:1", "name": "PRIVATE-WORKSPACE", "index": 1,
                       "output": "out", "active": True, "focused": True, "layout": "scrolling"}]
        snapshots = {"windows": windows, "workspaces": workspaces}
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(str(path)); server.listen(); server.settimeout(0.05)

        def serve():
            while not stopped.is_set():
                try:
                    connection, _ = server.accept()
                except socket.timeout:
                    continue
                with connection:
                    connection.settimeout(1)
                    data = b""
                    while b"\n" not in data:
                        chunk = connection.recv(4096)
                        if not chunk:
                            break  # Discovery's connect-only readiness probe.
                        data += chunk
                    if not data:
                        continue
                    request = json.loads(data)
                    requests.append(request)
                    event = request["cmd"] == "subscribe"
                    # Intentionally reverse initial event order and fragment frames.
                    names = ["workspaces", "windows"] if event else [request["cmd"]]
                    for name in names:
                        reply = ({"event": name, "data": snapshots[name]} if event else {"ok": snapshots[name]})
                        reply = transform(name, event, copy.deepcopy(reply))
                        if callable(reply):
                            reply(connection, stopped)
                            return
                        if reply is None:
                            stopped.wait(4)
                            return
                        wire = reply if isinstance(reply, bytes) else json.dumps(reply).encode() + b"\n"
                        try:
                            connection.sendall(wire[:7]); connection.sendall(wire[7:])
                        except (BrokenPipeError, ConnectionResetError):
                            break

        def guarded():
            try:
                serve()
            except Exception as error:
                failures.append(error)
        thread = threading.Thread(target=guarded, daemon=True); thread.start()
        try:
            yield requests
        finally:
            stopped.set(); thread.join(2); server.close()
            self.assertFalse(thread.is_alive(), "Fixture server did not stop")
            self.assertEqual(failures, [])

    def test_wire_verifies_queries_and_reordered_fragmented_snapshots_privately(self):
        with self.wire_server() as requests:
            result = self.run_contract("verify-wire")
        value = json.loads(result.stdout)
        self.assertEqual(value["protocol"]["status"], "verified")
        self.assertEqual(len(value["protocol"]["checked"]), 4)
        self.assertNotIn("PRIVATE", result.stdout + result.stderr)
        self.assertEqual([r["cmd"] for r in requests], ["windows", "workspaces", "subscribe"])

    def test_plain_discovery_does_not_read_state(self):
        with self.wire_server() as requests:
            value = json.loads(self.run_contract("status").stdout)
        self.assertEqual(requests, [])
        self.assertEqual(value["protocol"]["status"], "not-checked")

    def test_valid_wire_does_not_override_revision_policy(self):
        self.environment["NBSHELL_UMBRIEL_VERSION"] = "umbriel 99.0 (deadbeefdead)"
        with self.wire_server():
            result = self.run_contract("verify-wire", check=False)
        value = json.loads(result.stdout)
        self.assertEqual(result.returncode, 1)
        self.assertFalse(value["compatible"])
        self.assertEqual(value["protocol"]["status"], "verified")

    def test_wire_rejects_bad_query_and_event_field_types(self):
        for event in (False, True):
            for name, field, bad in (("windows", "focused", "false"),
                                     ("workspaces", "index", True),
                                     ("windows", "x", None)):
                with self.subTest(event=event, name=name, field=field):
                    def transform(current, is_event, reply):
                        if current == name and is_event == event:
                            reply["data" if event else "ok"][0][field] = bad
                        return reply
                    with self.wire_server(transform):
                        result = self.run_contract("verify-wire", check=False)
                    (self.root / "wire.sock").unlink()
                    value = json.loads(result.stdout)
                    self.assertEqual(result.returncode, 1)
                    self.assertEqual(value["protocol"]["error"]["code"], "wire-schema-invalid")
                    self.assertNotIn("PRIVATE", result.stdout + result.stderr)

    def test_wire_accepts_empty_snapshots_and_additive_fields(self):
        for empty in (False, True):
            def transform(name, event, reply):
                key = "data" if event else "ok"
                if empty:
                    reply[key] = []
                else:
                    reply[key][0]["future_field"] = {"something": True}
                return reply
            with self.wire_server(transform):
                self.run_contract("verify-wire")
            (self.root / "wire.sock").unlink()

    def test_wire_rejects_error_malformed_truncated_and_oversized_frames(self):
        for reply, code in (({"err": "PRIVATE-SERVER-ERROR"}, "wire-reply-invalid"),
                            (b"not json\n", "wire-json-invalid"),
                            (b'{"ok": []}', "wire-truncated"),
                            (b"x" * (4 * 1024 * 1024 + 1), "wire-frame-too-large")):
            with self.subTest(code=code):
                with self.wire_server(lambda *_: reply):
                    result = self.run_contract("verify-wire", check=False)
                (self.root / "wire.sock").unlink()
                value = json.loads(result.stdout)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(value["protocol"]["error"]["code"], code)
                self.assertNotIn("PRIVATE", result.stdout + result.stderr)

    def test_wire_deadline_and_missing_initial_event_are_failures(self):
        with self.wire_server(lambda *_: None):
            result = self.run_contract("verify-wire", check=False)
        self.assertEqual(json.loads(result.stdout)["protocol"]["error"]["code"], "wire-timeout")
        (self.root / "wire.sock").unlink()
        def omit_event(name, event, reply):
            if event:
                return {"event": "windows", "data": []}
            return reply
        with self.wire_server(omit_event):
            result = self.run_contract("verify-wire", check=False)
        self.assertEqual(json.loads(result.stdout)["protocol"]["error"]["code"], "wire-truncated")
        self.assertEqual(result.returncode, 1)

    def test_wire_slow_trickle_cannot_extend_total_deadline(self):
        def trickle(connection, stopped):
            while not stopped.wait(0.05):
                try:
                    connection.sendall(b" ")
                except (BrokenPipeError, ConnectionResetError):
                    return
        started = time.monotonic()
        with self.wire_server(lambda *_: trickle):
            result = self.run_contract("verify-wire", check=False)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(json.loads(result.stdout)["protocol"]["error"]["code"], "wire-timeout")
        self.assertLess(time.monotonic() - started, 6)

    def test_wire_offline_is_failure_even_when_executable_is_compatible(self):
        result = self.run_contract("verify-wire", check=False)
        value = json.loads(result.stdout)
        self.assertTrue(value["compatible"])
        self.assertEqual(result.returncode, 1)
        self.assertEqual(value["protocol"]["error"]["code"], "wire-unavailable")

    def test_reference_fixture_discovers_every_required_capability(self) -> None:
        result = self.run_contract("check")
        value = json.loads(result.stdout)
        self.assertTrue(value["compatible"])
        self.assertEqual(value["status"], "offline")
        self.assertEqual(value["missingRequired"], [])
        self.assertEqual(value["runtime"]["version"], "umbriel 0.1.0 (e677dbbe2728)")
        self.assertFalse(value["runtime"]["socketAvailable"])
        self.assertIn("ipc-unavailable", {error["code"] for error in value["errors"]})

    def test_missing_required_action_is_structured_and_fails_check(self) -> None:
        self.environment["NBSHELL_UMBRIEL_MSG_HELP"] = "msg-help-missing-window-focus.txt"
        result = self.run_contract("check", check=False)
        value = json.loads(result.stdout)
        self.assertEqual(result.returncode, 1)
        self.assertFalse(value["compatible"])
        self.assertEqual(value["status"], "incompatible")
        self.assertIn("window.focus", value["missingRequired"])
        self.assertEqual(value["errors"][0]["code"], "missing-required-capability")

    def test_revision_mismatch_is_incompatible(self) -> None:
        self.environment["NBSHELL_UMBRIEL_VERSION"] = "umbriel 99.0 (deadbeefdead)"
        result = self.run_contract("check", check=False)
        value = json.loads(result.stdout)
        self.assertEqual(result.returncode, 1)
        self.assertFalse(value["compatible"])
        self.assertFalse(value["runtime"]["revisionMatchesReference"])
        self.assertIn("revision-mismatch", {error["code"] for error in value["errors"]})

    def test_stable_action_maps_to_one_fixed_umbriel_action(self) -> None:
        value = json.loads(self.run_contract("action", "workspace.layout.set", "dwindle").stdout)
        self.assertTrue(value["ok"])
        self.assertEqual(value["capability"], "workspace.layout.set")
        self.assertEqual(value["effectiveCapability"], "workspace.layout.set")
        self.assertFalse(value["fallbackUsed"])
        self.assertEqual(self.log.read_text(encoding="utf-8"), "workspace-set-layout:dwindle\n")

    def test_declared_action_fallback_is_executed_and_reported(self) -> None:
        self.environment["NBSHELL_UMBRIEL_MSG_HELP"] = "msg-help-missing-window-focus-warp.txt"
        value = json.loads(self.run_contract("action", "window.focus-warp", "window-7").stdout)
        self.assertEqual(value["capability"], "window.focus-warp")
        self.assertEqual(value["effectiveCapability"], "window.focus")
        self.assertTrue(value["fallbackUsed"])
        self.assertEqual(self.log.read_text(encoding="utf-8"), "window-focus:window-7\n")

    def test_no_argument_action_maps_without_separator(self) -> None:
        self.run_contract("action", "config.reload")
        self.assertEqual(self.log.read_text(encoding="utf-8"), "config-reload\n")

    def test_workspace_name_with_spaces_is_preserved(self) -> None:
        self.run_contract("action", "workspace.focus", "Web Apps")
        self.assertEqual(self.log.read_text(encoding="utf-8"), "workspace-switch:Web Apps\n")

    def test_missing_action_is_not_invoked(self) -> None:
        self.environment["NBSHELL_UMBRIEL_MSG_HELP"] = "msg-help-missing-window-focus.txt"
        result = self.run_contract("action", "window.focus", "7", check=False)
        value = json.loads(result.stdout)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(value["error"]["code"], "unsupported-action")
        self.assertFalse(self.log.exists())

    def test_unknown_action_does_not_reach_umbriel(self) -> None:
        result = self.run_contract("action", "process.spawn", "sh", check=False)
        value = json.loads(result.stdout)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(value["error"]["code"], "unknown-action")
        self.assertFalse(self.log.exists())

    def test_invalid_layout_does_not_reach_umbriel(self) -> None:
        result = self.run_contract("action", "workspace.layout.set", "grid", check=False)
        value = json.loads(result.stdout)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(value["error"]["code"], "invalid-argument")
        self.assertFalse(self.log.exists())

    def test_control_characters_are_rejected(self) -> None:
        result = self.run_contract("action", "window.focus", "id\nsecond-action", check=False)
        value = json.loads(result.stdout)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(value["error"]["code"], "invalid-argument")
        self.assertFalse(self.log.exists())

    def test_fraction_below_umbriel_minimum_is_rejected(self) -> None:
        result = self.run_contract("action", "window.width.set", "0.05", check=False)
        value = json.loads(result.stdout)
        self.assertEqual(result.returncode, 2)
        self.assertEqual(value["error"]["code"], "invalid-argument")
        self.assertFalse(self.log.exists())

    def test_action_failure_is_not_reported_as_success(self) -> None:
        self.environment["NBSHELL_UMBRIEL_FAIL_ACTION"] = "window-close:abc"
        result = self.run_contract("action", "window.close", "abc", check=False)
        value = json.loads(result.stdout)
        self.assertEqual(result.returncode, 1)
        self.assertFalse(value["ok"])
        self.assertEqual(value["error"]["code"], "action-failed")
        self.assertEqual(value["error"]["capability"], "window.close")

    def test_missing_binary_is_reported_without_traceback(self) -> None:
        missing = self.root / "missing"
        result = subprocess.run(
            [str(RUNNER), "status", "--binary", str(missing), "--json"],
            env=self.environment, text=True, capture_output=True, check=False,
        )
        value = json.loads(result.stdout)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(value["status"], "unavailable")
        self.assertEqual(value["errors"][0]["code"], "binary-not-found")
        self.assertNotIn("Traceback", result.stderr)

    def test_public_cli_exposes_discovery_and_preserves_plain_status(self) -> None:
        config_home = self.root / "config"
        runtime = config_home / "quickshell/nbshell"
        (runtime / "scripts").mkdir(parents=True)
        (runtime / "Catalog").mkdir()
        shutil.copy2(RUNNER, runtime / "scripts/umbriel-contract.py")
        shutil.copy2(
            ROOT / "shell/Catalog/umbriel-capabilities.json",
            runtime / "Catalog/umbriel-capabilities.json",
        )
        environment = dict(self.environment)
        environment["XDG_CONFIG_HOME"] = str(config_home)
        environment["NBSHELL_UMBRIEL_BINARY"] = str(self.binary)
        status = subprocess.run(
            [str(ROOT / "bin/nbshell"), "compositor", "status"],
            env=environment, text=True, capture_output=True, check=False,
        )
        self.assertEqual(status.returncode, 0, status.stderr)
        self.assertEqual(status.stdout, "umbriel\n")
        discovery = subprocess.run(
            [str(ROOT / "bin/nbshell"), "compositor", "capabilities", "--json"],
            env=environment, text=True, capture_output=True, check=False,
        )
        self.assertEqual(discovery.returncode, 0, discovery.stderr)
        self.assertTrue(json.loads(discovery.stdout)["compatible"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=Path)
    parser.add_argument("--source", type=Path)
    options = parser.parse_args()
    if options.source is not None:
        verify_reference_source(options.source.resolve())
    if options.binary is not None:
        verify_reference_binary(options.binary.resolve())
    unittest.main(argv=[sys.argv[0]])
