#!/usr/bin/env python3
"""No downloads, credentials, provider calls, real config writes or service changes."""
import importlib.util
import hashlib
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('setup', Path(__file__).resolve().parents[1] / 'shell/scripts/openclaw-setup.py')
setup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(setup)


class SetupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        env = patch.dict(os.environ, {'HOME': str(self.home), 'PATH': '/usr/bin'}, clear=True)
        env.start()
        self.addCleanup(env.stop)
        slot = patch.object(setup, 'check_gateway_slot')
        slot.start()
        self.addCleanup(slot.stop)

    def test_existing_config_is_never_reconfigured(self):
        config = self.home / '.openclaw/openclaw.json'
        config.parent.mkdir()
        original = b'{"userSetting":"keep"}'
        config.write_bytes(original)
        os.environ['OPENAI_TOKEN'] = 'test-only-never-forward'
        with patch.object(setup, 'executable', return_value='/existing/openclaw'), patch.object(setup, 'run') as run:
            setup.install()
        self.assertEqual(config.read_bytes(), original)
        self.assertEqual([c.args for c in run.call_args_list], [('/existing/openclaw', 'config', 'validate'), ('/existing/openclaw', 'dashboard')])
        for call in run.call_args_list:
            self.assertNotIn('OPENAI_TOKEN', call.kwargs['env'])

    def test_custom_state_stops_without_writes(self):
        os.environ['OPENCLAW_STATE_DIR'] = '/custom/state'
        with self.assertRaisesRegex(RuntimeError, 'custom installation'):
            setup.install()
        self.assertEqual(list(self.home.iterdir()), [])

    def test_orphaned_credentials_are_not_adopted(self):
        state = self.home / '.openclaw'
        state.mkdir()
        existing = state / '.env'
        existing.write_text('test-only-do-not-load')
        with patch.object(setup, 'executable', return_value=None), patch.object(setup, 'run') as run:
            with self.assertRaisesRegex(RuntimeError, 'Existing OpenClaw state'):
                setup.install()
            run.assert_not_called()
        self.assertEqual(existing.read_text(), 'test-only-do-not-load')

    def test_fresh_setup_requires_interactive_consent(self):
        with patch.object(setup, 'executable', return_value=None), patch.object(setup.sys.stdin, 'isatty', return_value=False), patch.object(setup, 'run') as run:
            with self.assertRaisesRegex(RuntimeError, 'terminal'):
                setup.install()
            run.assert_not_called()

    def test_inherited_api_keys_are_not_offered(self):
        os.environ.update(OPENAI_API_KEY='test-only', ANTHROPIC_API_KEY='test-only', OPENAI_BASE_URL='https://invalid.example', PATH='/usr/bin')
        os.environ.update(OPENAI_TOKEN='test-only', CODEX_HOME='/other/agent', NODE_OPTIONS='--inspect')
        env = setup.environment()
        self.assertEqual(set(env), {'HOME', 'PATH', 'npm_config_cache', 'npm_config_userconfig'})
        self.assertTrue(env['npm_config_cache'].startswith(str(self.home / '.local/share/openclaw')))

    def test_partial_setup_is_not_reported_as_ready(self):
        self.write_auth('oauth')
        state = setup.locations()[2]
        state.mkdir(parents=True)
        (state / 'pending-setup').touch()
        with patch.object(setup, 'executable', return_value='/existing/openclaw'), patch.object(setup, 'run') as run:
            with self.assertRaisesRegex(RuntimeError, 'incomplete'):
                setup.install()
            run.assert_not_called()

    def test_fresh_install_ignores_foreign_cli_and_uses_verified_private_installer(self):
        calls = []
        private = self.home / '.local/share/openclaw/bin/openclaw'
        def run(*args, **kwargs):
            calls.append(args)
            if args[0] == 'curl':
                Path(args[args.index('--output') + 1]).write_bytes(b'reviewed-fixture')
            elif args[0] == 'bash':
                private.parent.mkdir(parents=True)
                private.write_text('# fixture, not executable code\n')
                private.chmod(0o755)
            elif len(args) > 1 and args[1] == 'onboard':
                self.write_auth('oauth')
        with patch.object(setup, 'executable', return_value='/foreign/openclaw'), \
             patch.object(setup.sys.stdin, 'isatty', return_value=True), \
             patch.object(setup.os, 'geteuid', return_value=1000), \
             patch.object(setup.platform, 'system', return_value='Linux'), \
             patch.object(setup.platform, 'libc_ver', return_value=('glibc', 'test')), \
             patch.object(setup.shutil, 'which', return_value='/fixture/tool'), \
             patch.object(setup.subprocess, 'run'), \
             patch.object(setup, 'INSTALLER_SHA256', hashlib.sha256(b'reviewed-fixture').hexdigest()), \
             patch.object(setup, 'run', side_effect=run):
            setup.install()
        self.assertTrue(any(c[0] == 'bash' and '--no-onboard' in c for c in calls))
        self.assertTrue(any(c[:2] == (str(private), 'onboard') for c in calls))
        self.assertFalse(any(c[0] == '/foreign/openclaw' for c in calls))
        self.assertFalse((setup.locations()[2] / 'pending-setup').exists())
        self.assertIn('Exec=nbshell openclaw open', (self.home / '.local/share/applications/nbshell-openclaw.desktop').read_text())

    def write_auth(self, mode):
        p = self.home / '.openclaw/openclaw.json'
        p.parent.mkdir(exist_ok=True)
        p.write_text(json.dumps({'auth': {'profiles': {'test': {'provider': 'openai', 'mode': mode}}}}))

    def test_subscription_setup_flags_and_service_order(self):
        calls = []
        def run(*args, **kwargs):
            calls.append(args)
            if args[1] == 'onboard':
                self.write_auth('oauth')
        with patch.object(setup, 'run', side_effect=run):
            setup.fresh_setup('/fake/openclaw', {})
        self.assertIn('openai-device-code', calls[0])
        self.assertIn('--no-install-daemon', calls[0])
        self.assertIn('loopback', calls[0])
        self.assertNotIn('--accept-risk', calls[0])
        self.assertIn(('/fake/openclaw', 'models', 'fallbacks', 'clear'), calls)
        self.assertLess(calls.index(('/fake/openclaw', 'config', 'validate')), calls.index(('/fake/openclaw', 'gateway', 'install', '--runtime', 'node')))
        self.assertEqual(calls[-1], ('/fake/openclaw', 'gateway', 'health'))

    def test_api_auth_does_not_start_service(self):
        calls = []
        def run(*args, **kwargs):
            calls.append(args)
            self.write_auth('api_key')
        with patch.object(setup, 'run', side_effect=run):
            with self.assertRaisesRegex(RuntimeError, 'subscription OAuth'):
                setup.fresh_setup('/fake/openclaw', {})
        self.assertEqual(len(calls), 1)


if __name__ == '__main__':
    unittest.main()
