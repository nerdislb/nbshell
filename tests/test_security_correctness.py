#!/usr/bin/env python3
"""Regression tests for the first architecture-audit fix package."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class SecurityCorrectnessTests(unittest.TestCase):
    def test_qml_process_arguments_do_not_interpolate_local_values(self):
        kdeconnect = (ROOT / "shell/Services/Kdeconnect.qml").read_text(encoding="utf-8")
        capture = (ROOT / "shell/Services/CaptureService.qml").read_text(encoding="utf-8")
        nearby = (ROOT / "shell/Services/Nearby.qml").read_text(encoding="utf-8")
        theme_export = (ROOT / "shell/Services/ThemeExport.qml").read_text(encoding="utf-8")

        self.assertIn(
            'Quickshell.execDetached(["kdeconnect-sms", "--device", String(id)])',
            kdeconnect,
        )
        self.assertNotIn('nohup kdeconnect-sms', kdeconnect)
        self.assertEqual(
            capture.count('Quickshell.execDetached(["mkdir", "-p",'),
            3,
        )
        self.assertNotIn('"mkdir -p " + JSON.stringify(', capture)
        self.assertIn(
            'lastShot.command = ["python3", root.script, "latest-image", root.shotDir]',
            nearby,
        )
        self.assertNotIn('"ls -1t \'" + root.shotDir', nearby)
        self.assertIn('[ -x \\"$1\\" ] && exec \\"$1\\" \\"$2\\" \\"$3\\" || true', theme_export)
        self.assertIn('"nbshell-theme-hook", root.hookPath, Config.theme,', theme_export)
        self.assertNotIn('"[ -x " + root.hookPath', theme_export)

    def test_latest_image_handles_shell_metacharacters(self):
        with tempfile.TemporaryDirectory(prefix="nbshell latest '$- ") as tmp:
            directory = Path(tmp)
            older = directory / "older image.png"
            latest = directory / "latest '$HOME image.JPG"
            ignored = directory / "newest.txt"
            older.write_bytes(b"older")
            latest.write_bytes(b"latest")
            ignored.write_bytes(b"ignored")
            os.utime(older, ns=(1_000_000_000, 1_000_000_000))
            os.utime(latest, ns=(2_000_000_000, 2_000_000_000))
            os.utime(ignored, ns=(3_000_000_000, 3_000_000_000))

            env = os.environ.copy()
            env["XDG_STATE_HOME"] = str(directory / "state")
            result = subprocess.run(
                ["python3", str(ROOT / "shell/scripts/nearby.py"), "latest-image", str(directory)],
                check=True,
                capture_output=True,
                text=True,
                env=env,
            )
            self.assertEqual(result.stdout.rstrip("\n"), str(latest))

    def test_headset_charging_contract(self):
        with tempfile.TemporaryDirectory() as tmp:
            bindir = Path(tmp)
            helper = bindir / "headsetcontrol"
            helper.write_text(
                "#!/bin/sh\n"
                "printf '%s\\n' '{\"devices\":[{\"status\":\"success\","
                "\"product\":\"Test Headset\",\"battery\":{"
                "\"status\":\"BATTERY_CHARGING\",\"level\":73}}]}'\n",
                encoding="utf-8",
            )
            helper.chmod(0o755)
            env = os.environ.copy()
            env["PATH"] = str(bindir) + os.pathsep + env["PATH"]
            result = subprocess.run(
                ["bash", str(ROOT / "plugins/headset/headset.sh")],
                check=True,
                capture_output=True,
                text=True,
                env=env,
            )
            payload = json.loads(result.stdout)
            self.assertEqual(payload["level"], 73)
            self.assertIs(payload["charging"], True)
            self.assertNotIn("laedt", payload)

            widget = (ROOT / "plugins/headset/BarWidget.qml").read_text(encoding="utf-8")
            self.assertIn("data.charging === true", widget)

    def test_plugin_loading_state_is_english(self):
        host = (ROOT / "shell/Extensions/PluginHost.qml").read_text(encoding="utf-8")
        self.assertIn(
            'Plugins.reportLoadState(modelData.id, modelData.kind, "loading", modelData.source)',
            host,
        )
        self.assertNotIn('modelData.kind, "laedt",', host)


if __name__ == "__main__":
    unittest.main()
