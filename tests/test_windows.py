"""Behavioral checks for the Windows desktop lifecycle without touching host Docker."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'shell/scripts/windows-vm.sh'
spec = importlib.util.spec_from_file_location('windows', ROOT / 'shell/scripts/windows.py')
windows = importlib.util.module_from_spec(spec)
spec.loader.exec_module(windows)


class WindowsLifecycle(unittest.TestCase):
    def exercise(self, client_exit=0, keep=False):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            (base / 'bin').mkdir()
            client = base / 'bin/xfreerdp3'
            client.write_text('#!/usr/bin/python3\nimport json,os,sys\nfrom pathlib import Path\nPath(os.environ["PROBE"]+"/client.json").write_text(json.dumps({"argv":sys.argv[1:],"stdin":sys.stdin.read()}))\nsys.exit(int(os.environ["CLIENT_EXIT"]))\n')
            client.chmod(0o755)
            probe = '''set -- help
source "$SCRIPT" >/dev/null
migrate_legacy_compose() { return 0; }
read_credential() { if [[ $1 == USERNAME ]]; then echo developer; else echo test-password; fi; }
priv() { echo "$1" >>"$PROBE/actions"; }
gum() { :; }
notify-send() { :; }
nbshell() { printf '%s\\n' '{"outputs":[{"enabled":true,"focused":true,"scale":1.5}]}'; }
launch_windows "$KEEP"
'''
            env = dict(os.environ, HOME=temp, XDG_RUNTIME_DIR=temp, PROBE=temp,
                       SCRIPT=str(SCRIPT), CLIENT_EXIT=str(client_exit),
                       KEEP='--keep-alive' if keep else '', PATH=str(base/'bin')+':'+os.environ['PATH'])
            result = subprocess.run(['bash', '-c', probe], env=env, capture_output=True, text=True)
            data = json.loads((base/'client.json').read_text())
            actions = (base/'actions').read_text().splitlines()
            self.assertNotIn('test-password', result.stdout+result.stderr)
            self.assertNotIn('test-password', ' '.join(data['argv']))
            self.assertEqual(data['argv'], ['/args-from:stdin'])
            private_args = data['stdin'].splitlines()
            self.assertIn('/p:test-password', private_args)
            self.assertIn('/scale:140', private_args)
            self.assertIn('/cert:tofu', private_args)
            return result.returncode, actions

    def test_normal_close_stops(self):
        self.assertEqual(self.exercise(), (0, ['up_wait', 'down']))

    def test_keepalive_keeps_build_running(self):
        self.assertEqual(self.exercise(keep=True), (0, ['up_wait']))

    def test_failed_connection_does_not_stop_guest(self):
        self.assertEqual(self.exercise(client_exit=42), (42, ['up_wait']))

    def test_credentials_refuse_redirected_output(self):
        with patch.object(windows, 'trusted_helper', return_value=True), \
             patch.object(windows, 'COMPOSE') as compose, \
             patch('sys.argv', ['windows.py', 'credentials']), \
             patch('sys.stdout.isatty', return_value=False):
            compose.exists.return_value = True
            with self.assertRaisesRegex(RuntimeError, 'local terminal'):
                windows.main()

    def test_status_does_not_install_or_elevate(self):
        with patch.object(windows, 'COMPOSE') as compose, \
             patch('sys.argv', ['windows.py', 'status']), \
             patch.object(windows, 'run') as run:
            compose.exists.return_value = False
            windows.main()
            run.assert_not_called()

    def test_unknown_flags_rejected_before_side_effects(self):
        with patch('sys.argv', ['windows.py', 'install', '--unattended-evil']), \
             patch.object(windows, 'run') as run:
            with self.assertRaisesRegex(RuntimeError, 'Usage:'):
                windows.main()
            run.assert_not_called()


if __name__ == '__main__':
    unittest.main()
