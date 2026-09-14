"""The update preflight must leave active legacy workers and unrelated jobs alone."""
import importlib.util
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('upgrade', ROOT/'plugins/omamail/scripts/check-upgrade.py')
upgrade = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(upgrade)


class MailUpgrade(unittest.TestCase):
    def test_exact_active_worker_blocks_until_it_finishes(self):
        with tempfile.TemporaryDirectory() as name:
            script = Path(name)/'agent-job.py'
            script.write_text('import time; time.sleep(30)')
            child = subprocess.Popen([sys.executable, str(script), 'run', 'synthetic-job'])
            try:
                self.assertIn(str(child.pid), list(upgrade.active_workers(script)))
                self.assertEqual(list(upgrade.active_workers(Path(name)/'other/agent-job.py')), [])
                probe = subprocess.run([sys.executable, str(ROOT/'plugins/omamail/scripts/check-upgrade.py'), str(script)], capture_output=True)
                self.assertNotEqual(probe.returncode, 0)
                self.assertIsNone(child.poll())
            finally:
                child.terminate(); child.wait(timeout=5)
            self.assertEqual(list(upgrade.active_workers(script)), [])


if __name__ == '__main__': unittest.main()
