#!/usr/bin/env python3
"""Exercise privileged publishing with private fixture roots, never host /etc."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('policy', ROOT / 'shell/scripts/brave-theme-policy.py')
policy = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(policy)
HEALTH_SPEC = importlib.util.spec_from_file_location('health', ROOT / 'shell/scripts/brave-theme-health.py')
health = importlib.util.module_from_spec(HEALTH_SPEC)
HEALTH_SPEC.loader.exec_module(health)


class PolicyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.leaf = self.root / 'etc/brave/policies/managed/nbshell-color.json'

    def publish(self, color='#A0b1C2'):
        policy.publish(color, str(self.root))

    def test_health_metadata_and_legacy_repair(self):
        check = lambda: health.status(self.leaf, owner=os.geteuid(), root=self.root)
        self.assertEqual(check(), 'absent')
        self.publish()
        self.assertEqual(check(), 'secure')
        self.assertEqual(health.status(self.leaf, owner=os.geteuid() + 1, root=self.root), 'insecure')
        self.leaf.chmod(0o666)
        self.assertEqual(check(), 'insecure')
        self.publish()
        self.assertEqual(check(), 'secure')
        self.leaf.unlink(); self.leaf.symlink_to(self.root / 'missing')
        self.assertEqual(check(), 'insecure')
        self.publish(); self.leaf.parent.chmod(0o777)
        self.assertEqual(check(), 'insecure')

    def test_exact_key_mode_and_atomic_replacement(self):
        self.publish()
        sibling = self.leaf.with_name('admin.json')
        sibling.write_text('{"unrelated":true}')
        old = self.leaf.open('r+')
        self.addCleanup(old.close)
        self.publish('#ffffff')
        old.seek(0); old.write('arbitrary policy'); old.flush()
        self.assertEqual(json.loads(self.leaf.read_text()), {'BrowserThemeColor': '#ffffff'})
        self.assertEqual(self.leaf.stat().st_mode & 0o777, 0o644)
        self.assertEqual(self.leaf.stat().st_uid, os.geteuid())
        self.assertEqual(sibling.read_text(), '{"unrelated":true}')
        self.assertEqual(list(self.leaf.parent.glob('.nbshell-*')), [])

    def test_invalid_input_never_creates_tree(self):
        for value in ('', '#123', '#123456\n', '#123456"}', '--help', '/tmp/out', '#GGGGGG'):
            with self.assertRaises(ValueError): self.publish(value)
        self.assertFalse((self.root / 'etc').exists())

    def test_symlink_leaf_is_replaced_without_following(self):
        self.publish()
        target = self.root / 'unrelated'
        target.write_text('preserved')
        self.leaf.unlink(); self.leaf.symlink_to(target)
        self.publish()
        self.assertFalse(self.leaf.is_symlink())
        self.assertEqual(target.read_text(), 'preserved')

    def test_symlink_parent_is_rejected(self):
        target = self.root / 'target'; target.mkdir()
        (self.root / 'etc').symlink_to(target)
        with self.assertRaises(OSError): self.publish()
        self.assertEqual(list(target.iterdir()), [])

    def test_writable_parent_is_rejected(self):
        self.publish(); self.leaf.parent.chmod(0o777)
        with self.assertRaises(PermissionError): self.publish()

    def test_foreign_parent_is_rejected(self):
        with patch.object(policy.os, 'geteuid', return_value=os.geteuid() + 1):
            with self.assertRaises(PermissionError): self.publish()

    def test_failed_replace_preserves_old_file_and_cleans_temp(self):
        self.publish()
        with patch.object(policy.os, 'replace', side_effect=OSError('failure')):
            with self.assertRaises(OSError): self.publish('#ffffff')
        self.assertEqual(json.loads(self.leaf.read_text()), {'BrowserThemeColor': '#A0b1C2'})
        self.assertEqual(list(self.leaf.parent.glob('.nbshell-*')), [])

    def test_cli_has_no_path_or_extra_argument_capability(self):
        for argv in ([], ['#123456', '/tmp/path'], ['--root', '/tmp']):
            with self.assertRaises(ValueError): policy.main(argv)
        with patch.object(policy.os, 'geteuid', return_value=1000):
            with self.assertRaises(PermissionError): policy.main(['#123456'])

    def test_action_authorizes_only_fixed_executable(self):
        action = ET.parse(ROOT / 'shell/scripts/org.nbshell.brave-theme.policy').getroot().find('action')
        self.assertEqual(action.find('annotate').text, '/usr/lib/nbshell/brave-theme-policy')
        self.assertEqual({node.tag: node.text for node in action.find('defaults')},
                         {'allow_any': 'no', 'allow_inactive': 'no', 'allow_active': 'yes'})


if __name__ == '__main__': unittest.main()
