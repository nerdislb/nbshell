#!/usr/bin/env python3
"""Check that isolated previews expose only the selected GPU's device nodes."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('greeter_check', ROOT / 'shell/scripts/greeter-check.py')
CHECK = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECK)


class Devices(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.addCleanup(self.folder.cleanup)
        root = Path(self.folder.name)
        self.sys = root / 'sys'
        self.proc = root / 'proc'
        self.dev = root / 'dev'
        self.render = self.dev / 'dri/renderD129'
        self.pci = root / '0000:08:00.0'
        self.pci.mkdir()
        (self.pci / 'driver').symlink_to(root / 'drivers/nvidia')
        node = self.sys / self.render.name
        node.mkdir(parents=True)
        (node / 'device').symlink_to(self.pci)
        info = self.proc / self.pci.name
        info.mkdir(parents=True)
        self.info = info / 'information'
        self.info.write_text('Device Minor: \t 3\n')

    def devices(self):
        return CHECK.graphics_devices(self.render, self.sys, self.proc, self.dev)

    def test_non_nvidia_and_platform_renderers_need_no_extra_devices(self):
        for vendor in (None, '0x8086', '0x1002'):
            with self.subTest(vendor=vendor):
                if vendor:
                    (self.pci / 'vendor').write_text(vendor)
                self.assertEqual(self.devices(), [self.render])

    def test_nvidia_minor_is_mapped_by_pci_not_render_node_index(self):
        (self.pci / 'vendor').write_text('0x10de\n')
        allowed = [self.dev / 'nvidiactl', self.dev / 'nvidia3']
        with patch.object(Path, 'is_char_device', lambda path: path in allowed):
            self.assertEqual(self.devices(), [self.render, *allowed])

    def test_nouveau_needs_no_proprietary_device_nodes(self):
        (self.pci / 'vendor').write_text('0x10de')
        (self.pci / 'driver').unlink()
        (self.pci / 'driver').symlink_to(self.pci.parent / 'drivers/nouveau')
        self.info.unlink()
        self.assertEqual(self.devices(), [self.render])

    def test_missing_device_blocks_preview(self):
        (self.pci / 'vendor').write_text('0x10de')
        with patch.object(Path, 'is_char_device', return_value=False):
            with self.assertRaisesRegex(RuntimeError, 'Missing NVIDIA'):
                self.devices()

    def test_unknown_minor_does_not_expose_other_gpus(self):
        (self.pci / 'vendor').write_text('0x10de')
        self.info.write_text('Device Minor: ../../input/event0\n')
        with self.assertRaisesRegex(RuntimeError, 'Cannot identify'):
            self.devices()

    def test_missing_nvidia_information_fails_closed(self):
        (self.pci / 'vendor').write_text('0x10de')
        self.info.unlink()
        with self.assertRaises(FileNotFoundError):
            self.devices()


if __name__ == '__main__':
    unittest.main()
