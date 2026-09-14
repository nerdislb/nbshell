import concurrent.futures
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('fork_updates', Path(__file__).resolve().parents[1] / 'shell/scripts/fork_updates.py')
forks = importlib.util.module_from_spec(spec)
spec.loader.exec_module(forks)


class ForkReviewTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.directory = Path(self.tmp.name)
        self.catalog = self.directory / 'catalog.json'
        self.catalog.write_text(json.dumps({'sources': [{'name': 'Example', 'repository': 'https://github.com/example/app', 'reviewedCommit': 'a' * 40}]}))
        self.state = patch.object(forks, 'STATE', self.directory / 'state')
        self.source = patch.object(forks, 'CATALOG', self.catalog)
        self.state.start(); self.source.start()
        self.addCleanup(self.state.stop); self.addCleanup(self.source.stop)

    def check(self, head='b' * 40):
        def response(repo, suffix):
            if suffix == '/commits/HEAD': return {'sha': head}
            return {'status': 'ahead', 'total_commits': 1, 'commits': [{'commit': {'message': 'Fix navigation\nDetails'}}]}
        with patch.object(forks, 'api', side_effect=response):
            return forks.refresh()['sources'][0]

    def test_decision_survives_same_revision_but_not_new_head(self):
        row = self.check()
        forks.decide(row['id'], row['token'], 'approved')
        self.assertEqual(self.check()['decision'], 'approved')
        self.assertEqual(self.check('c' * 40)['decision'], 'pending')
        self.assertEqual(self.check()['decision'], 'pending')
        self.check('c' * 40)
        with self.assertRaises(ValueError): forks.decide(row['id'], row['token'], 'approved')

    def test_catalog_change_invalidates_cached_result_and_approval(self):
        row = self.check()
        forks.decide(row['id'], row['token'], 'approved')
        data = json.loads(self.catalog.read_text())
        data['sources'][0]['reviewedCommit'] = 'c' * 40
        self.catalog.write_text(json.dumps(data))
        self.assertEqual(forks.snapshot()['sources'][0]['status'], 'unchecked')
        with self.assertRaises(ValueError): forks.decide(row['id'], row['token'], 'approved')

    def test_failure_is_not_current_and_cannot_be_approved(self):
        row = self.check()
        with patch.object(forks, 'api', side_effect=OSError('offline')):
            result = forks.refresh()['sources'][0]
        self.assertEqual(result['status'], 'error')
        self.assertEqual(result['head'], row['head'])
        self.assertTrue(result['stale'])
        with self.assertRaises(ValueError): forks.decide(row['id'], row['token'], 'approved')

    def test_failed_check_preserves_approval_and_allows_revocation(self):
        row = self.check()
        forks.decide(row['id'], row['token'], 'approved')
        with patch.object(forks, 'api', side_effect=OSError('offline')):
            result = forks.refresh()['sources'][0]
        self.assertEqual(result['decision'], 'approved')
        self.assertEqual(result['status'], 'error')
        self.assertEqual(forks.decide(row['id'], row['token'], 'pending')['sources'][0]['decision'], 'pending')

    def test_reference_cannot_be_approved(self):
        data = json.loads(self.catalog.read_text())
        data['sources'][0]['scope'] = 'reference'
        self.catalog.write_text(json.dumps(data))
        row = self.check()
        with self.assertRaises(ValueError): forks.decide(row['id'], row['token'], 'approved')

    def test_concurrent_decisions_do_not_lose_other_sources(self):
        data = json.loads(self.catalog.read_text())
        data['sources'].append({'name': 'Second', 'repository': 'https://github.com/example/second', 'reviewedCommit': 'a' * 40})
        self.catalog.write_text(json.dumps(data))
        self.check()
        rows = forks.snapshot()['sources']
        with concurrent.futures.ThreadPoolExecutor(2) as pool:
            list(pool.map(lambda r: forks.decide(r['id'], r['token'], 'approved'), rows))
        self.assertEqual([r['decision'] for r in forks.snapshot()['sources']], ['approved', 'approved'])

    def test_reset_defer_and_persistence(self):
        row = self.check()
        self.assertEqual(forks.decide(row['id'], row['token'], 'deferred')['sources'][0]['decision'], 'deferred')
        self.assertEqual(forks.decide(row['id'], row['token'], 'pending')['sources'][0]['decision'], 'pending')
        self.assertEqual((forks.STATE / 'decisions.json').stat().st_mode & 0o777, 0o600)

    def test_first_cached_read_creates_watchable_files(self):
        self.assertEqual(forks.snapshot()['sources'][0]['status'], 'unchecked')
        self.assertTrue((forks.STATE / 'snapshot.json').is_file())
        self.assertTrue((forks.STATE / 'decisions.json').is_file())

    def test_missing_notifier_does_not_lose_snapshot(self):
        with patch.object(forks, 'api', side_effect=lambda repo, suffix:
                          {'sha': 'b' * 40} if suffix == '/commits/HEAD' else
                          {'status': 'ahead', 'commits': [], 'total_commits': 1}), \
             patch('subprocess.run', side_effect=FileNotFoundError('notify-send')):
            self.assertEqual(forks.refresh(notify=True)['sources'][0]['status'], 'review')
        self.assertFalse((forks.STATE / 'notified.json').exists())
        self.assertEqual(forks.snapshot()['sources'][0]['head'], 'b' * 40)

    def test_refresh_exclusion(self):
        with forks.lock('refresh.lock'):
            with self.assertRaises(BlockingIOError): forks.refresh()

    def test_corrupt_state_is_not_silently_discarded(self):
        forks.STATE.mkdir()
        (forks.STATE / 'decisions.json').write_text('broken')
        with self.assertRaises(ValueError): forks.snapshot()

    def test_current_means_catalog_baseline_only(self):
        row = self.check('a' * 40)
        self.assertEqual(row['status'], 'current')
        with self.assertRaises(ValueError): forks.decide(row['id'], row['token'], 'approved')


if __name__ == '__main__': unittest.main()
