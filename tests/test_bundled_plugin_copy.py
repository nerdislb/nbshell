#!/usr/bin/env python3
"""Exercise the exact installer staging helper with a dirty development tree."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('copy_plugin', Path(__file__).resolve().parents[1] / 'shell/scripts/copy-bundled-plugin.py')
copy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(copy)


class BundledCopy(unittest.TestCase):
    def test_caches_are_omitted_without_losing_runtime_or_nested_assets(self):
        with tempfile.TemporaryDirectory() as directory:
            source, dest = Path(directory, 'source'), Path(directory, 'dest')
            keep = ['manifest.json', '.nbshell-managed', 'ui/Panel.qml', 'bin/backend',
                    'resources/target/icon.png', 'docs/example.txt']
            omit = ['target/debug/backend', 'node_modules/dependency/index.js', '.git/config',
                    '.venv/bin/python', 'backend/__pycache__/worker.pyc', '.pytest_cache/log']
            for name in keep + omit:
                path = source / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(name.encode())
            (source / 'bin/backend').chmod(0o755)
            copy.copy_plugin(source, dest)
            for name in keep:
                self.assertEqual((dest / name).read_bytes(), name.encode())
            for name in omit:
                self.assertFalse((dest / name).exists())
            self.assertEqual((dest / 'bin/backend').stat().st_mode & 0o777, 0o755)
            self.assertTrue((source / 'target/debug/backend').exists())

    def test_links_are_not_followed_and_existing_destination_is_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            source, dest = Path(directory, 'source'), Path(directory, 'dest')
            source.mkdir()
            (source / 'link').symlink_to('/does-not-exist')
            copy.copy_plugin(source, dest)
            self.assertTrue((dest / 'link').is_symlink())
            with self.assertRaises(FileExistsError):
                copy.copy_plugin(source, dest)


if __name__ == '__main__':
    unittest.main()
