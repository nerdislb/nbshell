import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('save_media', Path(__file__).resolve().parents[1] / 'integrations/omawhatsapp/save-media.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class SaveMediaTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / 'source.pdf'
        self.source.write_bytes(b'%PDF-1.7\noriginal\x00bytes')

    def save(self, result):
        with patch.object(module, 'downloads_directory', return_value=self.root), patch.object(module.subprocess, 'run', return_value=result) as dialog:
            value = module.save({'path': str(self.source), 'filename': '../../Report $() <test>.pdf'})
        self.assertIn('--confirm-overwrite', dialog.call_args.args[0])
        self.assertIn('--filename=' + str(self.root / 'Report $() <test>.pdf'), dialog.call_args.args[0])
        return value

    def test_save_preserves_bytes_and_spaces_without_touching_original(self):
        target = self.root / ' saved report.pdf '
        self.assertTrue(self.save(subprocess.CompletedProcess([], 0, str(target) + '\n'))['saved'])
        self.assertEqual(target.read_bytes(), self.source.read_bytes())
        self.assertEqual(target.stat().st_mode & 0o777, 0o600)

    def test_cancel_creates_nothing(self):
        self.assertTrue(self.save(subprocess.CompletedProcess([], 1, ''))['cancelled'])
        self.assertEqual(list(self.root.iterdir()), [self.source])

    def test_confirmed_overwrite(self):
        target = self.root / 'existing.pdf'
        target.write_bytes(b'old')
        self.save(subprocess.CompletedProcess([], 0, str(target) + '\n'))
        self.assertEqual(target.read_bytes(), self.source.read_bytes())

    def test_failed_copy_preserves_existing_file_and_cleans_temporary(self):
        target = self.root / 'existing.pdf'
        target.write_bytes(b'old')
        with self.source.open('rb') as stream, patch.object(module.os, 'read', side_effect=OSError('Disk error')):
            with self.assertRaises(OSError):
                module.copy_atomic(stream.fileno(), target)
        self.assertEqual(target.read_bytes(), b'old')
        self.assertEqual(list(self.root.glob('.whatsapp-save-*')), [])

    def test_rejects_source_overwrite_and_symlinks(self):
        target = self.root / 'link'
        target.symlink_to(self.source)
        with self.source.open('rb') as stream:
            for destination in [self.source, target]:
                with self.assertRaises(ValueError):
                    module.copy_atomic(stream.fileno(), destination)
        with self.assertRaises(OSError):
            module.save({'path': str(target)})

    def test_rejects_non_regular_source_before_dialog(self):
        fifo = self.root / 'fifo'
        os.mkfifo(fifo)
        with patch.object(module.subprocess, 'run') as dialog:
            with self.assertRaises(ValueError):
                module.save({'path': str(fifo)})
            dialog.assert_not_called()

    def test_dialog_failure_is_not_silent_cancellation(self):
        with self.assertRaisesRegex(ValueError, 'dialog'):
            self.save(subprocess.CompletedProcess([], 255, ''))

    def test_filename_is_basename_and_strips_controls(self):
        self.assertEqual(module.suggested_name('C:\\unsafe\\invoice\n.pdf', self.source), 'invoice.pdf')
        self.assertEqual(module.suggested_name('..', self.source), 'attachment')


if __name__ == '__main__':
    unittest.main()
