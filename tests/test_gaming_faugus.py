import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch, Mock

SCRIPTS = Path(__file__).resolve().parents[1] / 'shell/scripts'
sys.path.insert(0, str(SCRIPTS))
import gaming_faugus as gaming


class GamingTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.env = patch.dict(os.environ, {
            'HOME': str(self.root), 'XDG_DATA_HOME': str(self.root / 'data'),
            'XDG_CONFIG_HOME': str(self.root / 'config'), 'XDG_STATE_HOME': str(self.root / 'state'),
            'NBSHELL_GAMING_PREFIX': str(self.root / 'prefix with spaces'),
            'NBSHELL_GAMING_PROTON': str(self.root / 'proton'),
        })
        self.env.start()
        self.paths = gaming.locations('battlenet')
        self.paths['state'].mkdir(parents=True)

    def tearDown(self):
        self.env.stop()
        self.tmp.cleanup()

    def test_private_environment_removes_wayland(self):
        with patch.dict(os.environ, WAYLAND_DISPLAY='wayland-0'):
            env = gaming.environment(self.paths, Mock(env={'DISPLAY': ':97', 'XAUTHORITY': '/tmp/auth'}))
        self.assertNotIn('WAYLAND_DISPLAY', env)
        self.assertEqual(env['DISPLAY'], ':97')
        self.assertEqual(env['WINEPREFIX'], str(self.paths['prefix']))
        self.assertEqual(env['PROTON_ENABLE_WAYLAND'], '0')

    def test_cancel_does_not_remove_prefix(self):
        self.paths['prefix'].mkdir()
        save = self.paths['prefix'] / 'savegame'
        save.write_text('keep')
        (self.paths['state'] / 'cancel').touch()
        with self.assertRaisesRegex(RuntimeError, 'Cancelled'):
            gaming.stopped(self.paths)
        self.assertEqual(save.read_text(), 'keep')

    def archive(self, name, link=False):
        archive = self.root / 'payload.tar.gz'
        with tarfile.open(archive, 'w:gz') as bundle:
            item = tarfile.TarInfo(name)
            if link:
                item.type = tarfile.SYMTYPE
                item.linkname = '/tmp/escape'
                bundle.addfile(item)
            else:
                item.size = 4
                bundle.addfile(item, io.BytesIO(b'test'))
        return archive

    def test_archive_traversal_rejected(self):
        for name in ('../escape', '/tmp/escape', 'gog/../../escape'):
            with self.subTest(name=name), self.assertRaisesRegex(RuntimeError, 'Unsafe'):
                gaming.extract_gog(self.archive(name), self.root / 'extract')

    def test_archive_symlink_rejected(self):
        with self.assertRaisesRegex(RuntimeError, 'Unsafe'):
            gaming.extract_gog(self.archive('gog/link', True), self.root / 'extract')

    def test_archive_regular_file_extracts(self):
        result = gaming.extract_gog(self.archive('gog/GalaxySetup.exe'), self.root / 'extract')
        self.assertEqual(result.read_bytes(), b'test')

    def test_register_preserves_other_games_and_is_idempotent(self):
        target = self.paths['data'] / 'faugus-launcher/games.json'
        target.parent.mkdir(parents=True)
        existing = {'gameid': 'mine', 'prefix': '/other/game', 'title': 'Other', 'custom': {'keep': True}}
        target.write_text(json.dumps([existing]))
        with patch.object(gaming, 'faugus_running', return_value=False):
            gaming.register_faugus('battlenet', self.paths)
            gaming.register_faugus('battlenet', self.paths)
        games = json.loads(target.read_text())
        self.assertEqual(games[0], existing)
        self.assertEqual(len(games), 2)
        self.assertEqual(games[1]['game_arguments'], '--disable-gpu')
        self.assertTrue((self.paths['state'] / 'faugus-games.before.json').exists())

    def test_register_refuses_running_faugus(self):
        with patch.object(gaming, 'faugus_running', return_value=True), self.assertRaisesRegex(RuntimeError, 'Close Faugus'):
            gaming.register_faugus('battlenet', self.paths)
        self.assertFalse((self.paths['data'] / 'faugus-launcher/games.json').exists())

    def test_duplicate_title_does_not_overwrite(self):
        target = self.paths['data'] / 'faugus-launcher/games.json'
        target.parent.mkdir(parents=True)
        content = '[{"title":"Battle.net","prefix":"/other/prefix"}]'
        target.write_text(content)
        with patch.object(gaming, 'faugus_running', return_value=False), self.assertRaisesRegex(RuntimeError, 'different Faugus'):
            gaming.register_faugus('battlenet', self.paths)
        self.assertEqual(target.read_text(), content)

    def test_unowned_directory_rejected_before_wine(self):
        self.paths['prefix'].mkdir()
        with patch.object(gaming, 'prerequisites', return_value='/fake/Xvfb'), patch.object(gaming, 'faugus_running', return_value=False), patch.object(gaming, 'prefix_running', return_value=False), self.assertRaisesRegex(RuntimeError, 'not owned'):
            gaming.install('battlenet', self.paths)

    def test_registration_failure_does_not_rerun_installer(self):
        marker = self.paths['prefix'] / '.nbshell-install-owner'
        self.paths['prefix'].mkdir()
        marker.write_text('battlenet\n')
        def installed(*_):
            self.paths['exe'].parent.mkdir(parents=True)
            self.paths['exe'].write_bytes(b'MZ')
        with patch.object(gaming, 'prerequisites', return_value='/fake/Xvfb'), patch.object(gaming, 'faugus_running', return_value=False), patch.object(gaming, 'prefix_running', return_value=False), patch.object(gaming, 'PrivateDisplay'), patch.object(gaming, 'download'), patch.object(gaming, 'run_installer', side_effect=installed) as installer, patch.object(gaming, 'run_checked'), patch.object(gaming, 'register', side_effect=RuntimeError('icon failure')):
            for _ in range(2):
                with self.assertRaisesRegex(RuntimeError, 'icon failure'):
                    gaming.install('battlenet', self.paths)
            self.assertEqual(installer.call_count, 1)
        self.assertFalse(marker.exists())

    def test_stale_cancel_token_cannot_cancel_new_job(self):
        (self.paths['state'] / 'active-job.json').write_text('{"token":"new-job"}')
        with patch.object(sys, 'argv', ['gaming', 'cancel', 'battlenet', '--job', 'old-job']), self.assertRaisesRegex(RuntimeError, 'no longer active'):
            gaming.main()
        self.assertFalse((self.paths['state'] / 'cancel').exists())

    def test_matching_cancel_token_requests_cancel(self):
        (self.paths['state'] / 'active-job.json').write_text('{"token":"current-job"}')
        with patch.object(sys, 'argv', ['gaming', 'cancel', 'battlenet', '--job', 'current-job']):
            self.assertEqual(gaming.main(), 0)
        self.assertTrue((self.paths['state'] / 'cancel').exists())

    def test_remove_keeps_prefix_and_config(self):
        self.paths['prefix'].mkdir()
        save = self.paths['prefix'] / 'game.sav'
        save.write_text('keep')
        entry = self.paths['data'] / 'applications/nbshell-battlenet.desktop'
        entry.parent.mkdir(parents=True)
        entry.write_text('[Desktop Entry]')
        with patch.object(sys, 'argv', ['gaming', 'remove', 'battlenet']):
            self.assertEqual(gaming.main(), 0)
        self.assertFalse(entry.exists())
        self.assertEqual(save.read_text(), 'keep')


if __name__ == '__main__':
    unittest.main()
