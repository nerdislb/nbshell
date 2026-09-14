import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch, Mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'shell/scripts'))
import gaming_minecraft as m


class MinecraftSetup(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.data = Path(self.tmp.name) / 'data'
        self.state = Path(self.tmp.name) / 'state'
        self.state.mkdir()

    def test_registration_has_stable_minecraft_identity(self):
        icon = Path(self.tmp.name) / 'minecraft.svg'
        icon.write_text('<svg/>')
        with patch.object(m, 'ICON', icon), patch.object(m.shutil, 'which', return_value='/bin/tool'), patch.object(m.subprocess, 'run'):
            m.register(self.data)
        entry = (self.data / 'applications/nbshell-minecraft.desktop').read_text()
        self.assertIn('Name=Minecraft\n', entry)
        self.assertIn('Icon=nbshell-minecraft\n', entry)
        self.assertIn('Terminal=false\n', entry)
        self.assertEqual((self.data / 'icons/hicolor/scalable/apps/nbshell-minecraft.svg').read_text(), '<svg/>')

    def test_success_does_not_launch_prism(self):
        output = io.StringIO()
        with patch.object(m, 'installed', return_value=True), patch.object(m.shutil, 'which', return_value='/bin/tool'), patch.object(m, 'register') as register, patch.object(m.subprocess, 'Popen') as launch, patch('sys.stdout', output):
            m.install(self.data, self.state)
        register.assert_called_once_with(self.data)
        launch.assert_not_called()
        self.assertEqual(json.loads(output.getvalue().splitlines()[-1])['phase'], 'done')

    def test_package_failure_never_registers_success(self):
        with patch.object(m, 'installed', return_value=False), patch.object(m.shutil, 'which', return_value='/bin/tool'), patch.object(m.subprocess, 'run', side_effect=[Mock(returncode=0)] * 3 + [Mock(returncode=1)]), patch.object(m, 'register') as register:
            with self.assertRaisesRegex(RuntimeError, 'Package setup failed'):
                m.install(self.data, self.state)
            register.assert_not_called()

    def test_cancel_after_transaction_keeps_packages_and_skips_registration(self):
        calls = []
        def run(args, **kwargs):
            calls.append(args)
            if args[0] == 'pkexec':
                (self.state / 'cancel').write_text('cancel')
            return Mock(returncode=0)
        with patch.object(m, 'installed', return_value=False), patch.object(m.shutil, 'which', return_value='/bin/tool'), patch.object(m.subprocess, 'run', side_effect=run), patch.object(m, 'register') as register:
            with self.assertRaisesRegex(RuntimeError, 'Cancelled'):
                m.install(self.data, self.state)
            register.assert_not_called()
        self.assertEqual(calls[-1], ['pkexec', 'pacman', '-S', '--needed', '--noconfirm', *m.PACKAGES])

    def test_failed_postinstall_verification_does_not_register(self):
        with patch.object(m, 'installed', side_effect=[True, True, True, False]), patch.object(m.shutil, 'which', return_value='/bin/tool'), patch.object(m, 'register') as register:
            with self.assertRaisesRegex(RuntimeError, 'verification failed'):
                m.install(self.data, self.state)
            register.assert_not_called()

    def test_stale_cancel_token_rejected(self):
        (self.state / 'active-job.json').write_text('{"token":"new"}')
        with patch.object(m, 'locations', return_value=(self.data,self.state)), patch.object(sys, 'argv', ['worker', 'cancel', 'minecraft', '--job', 'old']):
            with self.assertRaisesRegex(RuntimeError, 'no longer active'):
                m.main()
        self.assertFalse((self.state / 'cancel').exists())

    def test_missing_icon_preserves_previous_shortcut(self):
        entry = self.data / 'applications/nbshell-minecraft.desktop'
        entry.parent.mkdir(parents=True)
        entry.write_text('previous')
        with patch.object(m, 'ICON', Path(self.tmp.name) / 'absent'), patch.object(m.shutil, 'which', return_value='/bin/tool'):
            with self.assertRaisesRegex(RuntimeError, 'icon is missing'):
                m.register(self.data)
        self.assertEqual(entry.read_text(), 'previous')


if __name__ == '__main__':
    unittest.main()
