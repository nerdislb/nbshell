#!/usr/bin/env python3
"""Isolated launcher contract checks; never starts Wine or touches real accounts."""
import fcntl
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

TOOL = Path(__file__).resolve().parents[1] / 'shell/scripts/battlenet.py'


class BattleNetTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.prefix = self.home / 'Faugus/prefix with spaces'
        self.runner = self.home / 'runner with spaces'
        self.state = self.home / '.local/state/nbshell/battlenet'
        self.exe = self.prefix / 'drive_c/Program Files (x86)/Battle.net/Battle.net.exe'
        self.exe.parent.mkdir(parents=True)
        self.exe.touch()
        self.runner.mkdir()
        (self.runner / 'proton').touch()
        umu = self.home / '.local/share/faugus-launcher/umu-run'
        umu.parent.mkdir(parents=True)
        umu.write_text('#!/usr/bin/env python3\nimport json,os,sys\n'
                       'print(json.dumps({"args":sys.argv[1:],"prefix":os.environ["WINEPREFIX"],'
                       '"proton":os.environ["PROTONPATH"],"wayland":os.environ["PROTON_ENABLE_WAYLAND"]}))\n')
        umu.chmod(0o755)
        self.env = {k: v for k, v in os.environ.items() if not k.startswith(('XDG_', 'NBSHELL_BATTLENET_'))}
        self.env.update(HOME=str(self.home), NBSHELL_BATTLENET_PREFIX=str(self.prefix),
                        NBSHELL_BATTLENET_PROTON=str(self.runner))
        self.env.pop('DISPLAY', None)
        self.env.pop('DBUS_SESSION_BUS_ADDRESS', None)

    def run_tool(self, action):
        return subprocess.run(['python3', str(TOOL), action], env=self.env,
                              capture_output=True, text=True, timeout=15)

    def test_launch_preserves_paths_and_renderer_fix(self):
        self.assertEqual(self.run_tool('launch').returncode, 0)
        result = json.loads((self.state / 'launch.log').read_text())
        self.assertEqual(result['args'], [str(self.exe), '--disable-gpu'])
        self.assertEqual(result['prefix'], str(self.prefix))
        self.assertEqual(result['proton'], str(self.runner))
        self.assertEqual(result['wayland'], '0')
        self.assertEqual((self.state / 'launch.log').stat().st_mode & 0o077, 0)

    def test_lock_prevents_second_instance(self):
        self.state.mkdir(parents=True)
        with (self.state / 'launch.lock').open('w') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self.assertNotEqual(self.run_tool('launch').returncode, 0)
            self.assertFalse((self.state / 'launch.log').exists())

    def test_missing_executable_does_not_start_runner(self):
        self.exe.unlink()
        self.assertNotEqual(self.run_tool('launch').returncode, 0)
        self.assertFalse(self.state.exists())

    def test_status_is_read_only(self):
        self.assertEqual(self.run_tool('status').returncode, 0)
        self.assertFalse(self.state.exists())


if __name__ == '__main__':
    unittest.main()
