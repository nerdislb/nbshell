#!/usr/bin/env python3
"""Exercise setup transaction boundaries with no host commands or services."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
MOCK = r'''
import json, os, pathlib, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
scenario = os.environ['SCENARIO']
with open(os.environ['CALL_LOG'], 'a') as out:
    out.write(json.dumps([name, *args]) + '\n')
def executable(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('#!/bin/bash\n' + text + '\n')
    path.chmod(0o755)
if name == 'id':
    print('1000')
elif name == 'dirname':
    print(str(pathlib.Path(args[0]).parent))
elif name == 'basename':
    print(pathlib.Path(args[0]).name)
elif name == 'sudo':
    os.execvp(args[0], args)
elif name == 'pacman':
    if args[0] == '-Qq':
        missing = {'legacy-pkg', 'legacy-aur'}
        if scenario == 'core-failure':
            missing.add('quickshell')
        if scenario == 'missing-bubblewrap':
            missing.add('bubblewrap')
        sys.exit(int(args[1] in missing))
    if args[0] == '-Syu' and 'paru' in args:
        if scenario == 'helper-repair-failure':
            sys.exit(1)
        if scenario != 'helper-still-broken':
            (pathlib.Path(os.environ['HOME']) / 'helper-repaired').touch()
    sys.exit(1 if scenario in {'core-failure', 'legacy-failure'} else 0)
elif name == 'git':
    sys.exit(int(scenario == 'pull-failure'))
elif name in {'paru', 'yay'}:
    if args == ['--version']:
        broken = scenario in {'broken-helper', 'helper-repair-failure', 'helper-still-broken', 'healthy-yay'}
        repaired = (pathlib.Path(os.environ['HOME']) / 'helper-repaired').exists()
        sys.exit(int(name == 'paru' and broken and not repaired))
    sys.exit(int(scenario == 'aur-failure'))
elif name == 'restore.sh':
    sys.stdin.read()
    sys.exit(int(scenario == 'restore-failure'))
elif name == 'systemctl':
    sys.exit(1)  # No service units exist in this fixture.
elif name == 'python3':
    sys.exit(int(scenario == 'no-render'))
elif name == 'setup-umbriel.sh':
    bindir = pathlib.Path(os.environ.get('XDG_BIN_HOME', os.environ['HOME'] + '/.local/bin'))
    for command in ('umbriel', 'start-umbriel'):
        executable(bindir / command, 'exit 0')
elif name == 'install.sh':
    runtime = pathlib.Path(os.environ['HOME']) / '.config/quickshell/nbshell'
    runtime.mkdir(parents=True, exist_ok=True)
    (runtime / 'VERSION').write_text('fixture')
    data = pathlib.Path(os.environ['HOME']) / '.local/share/nbshell'
    for script in ('setup-locker.sh', 'setup-greeter.sh'):
        text = 'echo "[\\"' + script + '\\"]" >> "$CALL_LOG"'
        if script == 'setup-greeter.sh' and scenario in {'no-render', 'greeter-failure'}:
            text += '\necho "No render device available" >&2\nexit 1'
        executable(data / script, text)
'''


class SetupTransactions(unittest.TestCase):
    def run_setup(self, scenario, *options, legacy=False, custom_bin=False, retry=False):
        with tempfile.TemporaryDirectory(prefix='nbshell-setup-test-') as temp:
            base = Path(temp)
            home, repo, bindir = (base / name for name in ('home', 'repo', 'bin'))
            for directory in (home, repo, bindir):
                directory.mkdir()
            shutil.copyfile(ROOT / 'setup.sh', repo / 'setup.sh')
            mock = base / 'mock'
            mock.write_text('#!' + sys.executable + '\n' + MOCK)
            mock.chmod(0o755)
            # An allowlist PATH prevents accidental calls to host package managers,
            # services, network clients, or an already installed compositor.
            commands = ('id', 'dirname', 'basename', 'sudo', 'pacman', 'git',
                        'paru', 'systemctl', 'qs', 'quickshell', 'agreety', 'bwrap',
                        'python3', 'jq', 'curl', 'wl-copy', 'wl-paste',
                        'notify-send', 'xdg-open', 'pactl')
            for command in commands:
                (bindir / command).symlink_to(mock)
            for command in ('mkdir', 'rm'):
                (bindir / command).symlink_to('/usr/bin/' + command)
            if scenario == 'healthy-yay':
                (bindir / 'yay').symlink_to(mock)
            for command in ('install.sh', 'setup-umbriel.sh'):
                (repo / command).symlink_to(mock)
            if legacy:
                dotfiles = home / 'dotfiles'
                (dotfiles / '.git').mkdir(parents=True)
                (dotfiles / 'bin').mkdir()
                (dotfiles / 'bin/restore.sh').symlink_to(mock)
                (dotfiles / 'pkglist.txt').write_text('legacy-pkg\n')
                (dotfiles / 'pkglist-aur.txt').write_text('legacy-aur\n')
                options += ('--with-legacy-dotfiles',)
            log = base / 'calls.jsonl'
            env = {'HOME': str(home), 'PATH': str(bindir), 'LC_ALL': 'C',
                   'SCENARIO': scenario, 'CALL_LOG': str(log),
                   'NBSHELL_LEGACY_DOTFILES_REPO': 'https://example.invalid/dotfiles.git'}
            if custom_bin:
                env['XDG_BIN_HOME'] = str(home / 'custom-bin')
            result = subprocess.run(['/bin/bash', str(repo / 'setup.sh'), '--yes', *options],
                                    env=env, input='', text=True, capture_output=True,
                                    timeout=15)
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            if retry:
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue((home / '.local/state/nbshell/setup/greeter-pending').exists())
                self.assertIn('greeter install', result.stderr)
                env['SCENARIO'] = 'success'
                log.write_text('')
                result = subprocess.run(['/bin/bash', str(repo / 'setup.sh'), '--yes', *options],
                                        env=env, input='', text=True, capture_output=True, timeout=15)
                calls = [json.loads(line) for line in log.read_text().splitlines()]
                self.assertFalse((home / '.local/state/nbshell/setup/greeter-pending').exists())
            return result, calls

    def assert_stopped(self, scenario, message, *, legacy=False):
        result, calls = self.run_setup(scenario, legacy=legacy)
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(message, result.stderr)
        self.assertFalse(any(call[0] in {'install.sh', 'setup-umbriel.sh'} for call in calls), calls)
        return calls

    def test_core_package_failure_stops_before_deployment(self):
        calls = self.assert_stopped('core-failure', 'Package installation failed')
        self.assertTrue(any(call[:2] == ['pacman', '-S'] for call in calls))

    def test_legacy_package_failure_stops_before_restore(self):
        calls = self.assert_stopped('legacy-failure', 'Personal package installation failed', legacy=True)
        self.assertNotIn('restore.sh', [call[0] for call in calls])

    def test_legacy_aur_failure_stops_before_restore(self):
        calls = self.assert_stopped('aur-failure', 'Personal AUR package installation failed', legacy=True)
        self.assertIn('paru', [call[0] for call in calls])
        self.assertNotIn('restore.sh', [call[0] for call in calls])

    def test_dotfiles_pull_failure_stops_before_restore(self):
        calls = self.assert_stopped('pull-failure', 'Dotfiles update failed', legacy=True)
        self.assertNotIn('restore.sh', [call[0] for call in calls])

    def test_dotfiles_restore_failure_stops_before_deployment(self):
        calls = self.assert_stopped('restore-failure', 'Dotfiles restore failed', legacy=True)
        self.assertIn('restore.sh', [call[0] for call in calls])

    def test_no_aur_skips_installed_helper_and_continues_restore(self):
        result, calls = self.run_setup('success', '--no-aur', legacy=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn('paru', [call[0] for call in calls])
        self.assertIn('restore.sh', [call[0] for call in calls])
        self.assertIn('install.sh', [call[0] for call in calls])

    def test_broken_helper_is_reinstalled_and_verified_before_aur(self):
        result, calls = self.run_setup('broken-helper', legacy=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        repair = calls.index(['pacman', '-Syu', 'paru'])
        aur = next(i for i, call in enumerate(calls) if call[:2] == ['paru', '-S'])
        self.assertLess(repair, aur)
        self.assertIn(['paru', '--version'], calls[repair + 1:aur])

    def test_healthy_yay_is_used_when_paru_cannot_start(self):
        result, calls = self.run_setup('healthy-yay', legacy=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn(['pacman', '-Syu', 'paru'], calls)
        self.assertTrue(any(call[:2] == ['yay', '-S'] for call in calls))

    def test_failed_helper_repair_stops_before_restore(self):
        self.assert_stopped('helper-repair-failure', 'AUR helper repair failed', legacy=True)

    def test_successful_package_transaction_is_not_enough_for_broken_helper(self):
        self.assert_stopped('helper-still-broken', 'still cannot run', legacy=True)

    def test_retry_after_greeter_failure_keeps_fresh_install_intent(self):
        result, calls = self.run_setup('greeter-failure', retry=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('setup-greeter.sh', [call[0] for call in calls])

    def test_fresh_console_finds_new_compositor_for_greeter_and_final_check(self):
        for custom_bin in (False, True):
            with self.subTest(custom_bin=custom_bin):
                result, calls = self.run_setup('success', custom_bin=custom_bin)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('setup-greeter.sh', [call[0] for call in calls])
                self.assertIn('All required commands are available.', result.stdout)

    def test_fresh_setup_installs_missing_greeter_sandbox_dependency(self):
        result, calls = self.run_setup('missing-bubblewrap')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        transactions = [call for call in calls if call[:2] == ['pacman', '-S']]
        self.assertTrue(any('bubblewrap' in call for call in transactions), transactions)
        self.assertIn('setup-greeter.sh', [call[0] for call in calls])

    def test_auto_greeter_skips_without_render_device_and_completes_setup(self):
        result, calls = self.run_setup('no-render')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue(any(call[:2] == ['python3', '-c'] for call in calls), calls)
        self.assertNotIn('setup-greeter.sh', [call[0] for call in calls])
        self.assertIn('Orbital skipped', result.stdout)
        self.assertIn('All required commands are available.', result.stdout)

    def test_explicit_greeter_preserves_visible_failure_without_render_device(self):
        result, calls = self.run_setup('no-render', '--with-greeter')
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('setup-greeter.sh', [call[0] for call in calls])
        self.assertIn('No render device available', result.stderr)

    def test_no_greeter_preserves_opt_out_and_avoids_sandbox_install(self):
        result, calls = self.run_setup('missing-bubblewrap', '--no-greeter')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn('setup-greeter.sh', [call[0] for call in calls])
        self.assertFalse(any(call[:2] == ['pacman', '-S'] and 'bubblewrap' in call
                             for call in calls), calls)


if __name__ == '__main__':
    unittest.main(verbosity=2)
