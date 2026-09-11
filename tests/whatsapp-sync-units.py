#!/usr/bin/env python3
"""Exercise installer service selection without systemd or real account state."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'shell/scripts/omawhatsapp.sh').read_text()
FUNCTION = SOURCE[SOURCE.index('sync_accounts() {'):SOURCE.index('setup() (')]


class SyncUnits(unittest.TestCase):
    def run_plan(self, accounts):
        with tempfile.TemporaryDirectory(prefix='nbshell-sync-test-') as temporary:
            work = Path(temporary)
            mock = work / 'systemctl'
            mock.write_text('#!/usr/bin/python3\nimport json,os,sys\nwith open(os.environ["SYNC_CALLS"], "a") as f: f.write(json.dumps(sys.argv[1:])+"\\n")\n')
            mock.chmod(0o755)
            calls = work / 'calls'
            env = dict(os.environ, PATH=str(work)+':'+os.environ['PATH'], SYNC_CALLS=str(calls))
            result = subprocess.run(['bash', '-eu', '-c', FUNCTION+'\nsync_accounts "$1"', 'test', json.dumps({'ok': True, 'accounts': accounts})], env=env, capture_output=True, text=True)
            actual = [json.loads(line)[1:] for line in calls.read_text().splitlines()] if calls.exists() else []
            return result.returncode, actual

    @staticmethod
    def row(name, unit, online=True):
        return {'account': name, 'unit': unit, 'online': online}

    def test_legacy_primary_uses_base_and_stops_wrong_template(self):
        code, calls = self.run_plan([self.row('primary', 'wacli-sync.service')])
        self.assertEqual(code, 0)
        self.assertEqual(calls, [['disable', '--now', 'wacli-sync@primary.service'], ['enable', 'wacli-sync.service'], ['restart', 'wacli-sync.service']])

    def test_real_named_primary_uses_template(self):
        code, calls = self.run_plan([self.row('primary', 'wacli-sync@primary.service')])
        self.assertEqual(code, 0)
        self.assertEqual(calls, [['disable', '--now', 'wacli-sync.service'], ['enable', 'wacli-sync@primary.service'], ['restart', 'wacli-sync@primary.service']])

    def test_mixed_legacy_and_named_preserves_both(self):
        code, calls = self.run_plan([self.row('primary', 'wacli-sync.service'), self.row('work', 'wacli-sync@work.service')])
        self.assertEqual(code, 0)
        self.assertNotIn(['disable', '--now', 'wacli-sync.service'], calls)
        self.assertIn(['restart', 'wacli-sync.service'], calls)
        self.assertIn(['restart', 'wacli-sync@work.service'], calls)

    def test_offline_remains_disabled(self):
        code, calls = self.run_plan([self.row('primary', 'wacli-sync.service', False)])
        self.assertEqual(code, 0)
        self.assertEqual(calls[-1], ['disable', '--now', 'wacli-sync.service'])
        self.assertFalse(any('restart' in call for call in calls))

    def test_old_unnamed_legacy_stays_supported(self):
        code, calls = self.run_plan([self.row('', 'wacli-sync.service')])
        self.assertEqual(code, 0)
        self.assertEqual(calls, [['enable', 'wacli-sync.service'], ['restart', 'wacli-sync.service']])

    def test_invalid_entire_plan_changes_nothing(self):
        bad_rows = [self.row('primary', 'nbshell.service'), self.row('bad/name', 'wacli-sync.service'), {'account': 'primary', 'online': True}, self.row('primary', 'wacli-sync.service', 'false')]
        for bad in bad_rows:
            with self.subTest(bad=bad):
                code, calls = self.run_plan([self.row('work', 'wacli-sync@work.service'), bad])
                self.assertNotEqual(code, 0)
                self.assertEqual(calls, [])

    def test_duplicate_unit_changes_nothing(self):
        code, calls = self.run_plan([self.row('primary', 'wacli-sync.service'), self.row('', 'wacli-sync.service')])
        self.assertNotEqual(code, 0)
        self.assertEqual(calls, [])


if __name__ == '__main__':
    unittest.main()
