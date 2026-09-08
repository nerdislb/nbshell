#!/usr/bin/env python3
"""Behavioral coordinator tests: real workers/flock, isolated state, no updates."""
import contextlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'shell/scripts/update-coordinator.py'
spec = importlib.util.spec_from_file_location('coordinator', SCRIPT)
C = importlib.util.module_from_spec(spec)
spec.loader.exec_module(C)


@contextlib.contextmanager
def fake_inhibitor():
    with open(os.devnull) as handle:
        yield handle.fileno()


class CoordinatorTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="update ' fixture ")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.scripts = self.root / 'runtime/scripts'
        self.scripts.mkdir(parents=True)
        shutil.copy2(SCRIPT, self.scripts / SCRIPT.name)
        (self.scripts.parent / 'VERSION').write_text('1.0.0')
        catalog = self.scripts.parent / 'Catalog'
        catalog.mkdir()
        (catalog / 'umbriel-capabilities.json').write_text('{}')
        self.log = self.root / 'steps'
        self.outcomes = self.root / 'outcomes.json'
        self.outcomes.write_text('{}')
        self.env = dict(os.environ, XDG_STATE_HOME=str(self.root / 'state'),
                        TEST_LOG=str(self.log), TEST_OUTCOMES=str(self.outcomes),
                        TEST_FIXTURE=str(self.scripts), TEST_ROOT=str(self.root))
        self.addCleanup(patch.stopall)
        patch.dict(os.environ, self.env).start()
        patch.object(C, 'SCRIPTS', self.scripts).start()
        patch.object(C, 'inhibit_sleep', fake_inhibitor).start()
        patch.object(C, 'check_space').start()
        patch.object(C.shutil, 'which', return_value='/fixture/flatpak').start()
        worker = '''import os,runpy,json,sys,time
from pathlib import Path
assert runpy.run_path(str(Path(__file__).with_name('update-coordinator.py')))['inherited_guard']()
assert (Path(__file__).parent.parent/'Catalog/umbriel-capabilities.json').exists()
step = STEP
with open(os.environ['TEST_LOG'],'a') as output: output.write(step+'\\n')
root=Path(os.environ['TEST_ROOT'])
if (root/'hold').exists():
    (root/'ready').touch()
    while (root/'hold').exists(): time.sleep(.02)
raise SystemExit(json.loads(Path(os.environ['TEST_OUTCOMES']).read_text()).get(step,0))
'''
        for name, step in [('nbshell-update.py', 'shell'), ('umbriel-update.py', 'compositor'),
                           ('package-fixture.py', 'packages'), ('flatpak-fixture.py', 'flatpak')]:
            (self.scripts / name).write_text(worker.replace('STEP', repr(step)))
        (self.scripts / 'updates.sh').write_text('''#!/bin/bash
case "$1" in
_packages) exec python3 "$(dirname "$0")/package-fixture.py" ;;
_flatpak) exec python3 "$(dirname "$0")/flatpak-fixture.py" ;;
esac
''')

    def steps(self):
        return self.log.read_text().splitlines() if self.log.exists() else []

    def test_desktop_partial_retry(self):
        self.outcomes.write_text('{"compositor": 7}')
        self.assertEqual(C.run('desktop', 'stable', True), 1)
        self.assertEqual(C.status()['status'], 'partial')
        self.outcomes.write_text('{}')
        self.assertEqual(C.run('retry'), 0)
        self.assertEqual(self.steps(), ['shell', 'compositor', 'compositor'])
        self.assertEqual(C.status()['channel'], 'stable')
        self.assertTrue(C.status()['yes'])
        self.assertEqual(C.run('retry'), 0)
        self.assertEqual(len(self.steps()), 3)

    def test_runtime_replacement_keeps_snapshot(self):
        shell = self.scripts / 'nbshell-update.py'
        source = shell.read_text()
        source = source.replace("step = 'shell'", "step = 'shell'\n(Path(os.environ['TEST_FIXTURE'])/'umbriel-update.py').write_text('raise SystemExit(91)')")
        shell.write_text(source)
        self.assertEqual(C.run('desktop', yes=True), 0)
        self.assertEqual(self.steps(), ['shell', 'compositor'])
        self.assertIn('91', (self.scripts / 'umbriel-update.py').read_text())

    def test_desktop_failure_stops_dependency(self):
        self.outcomes.write_text('{"shell": 7}')
        self.assertEqual(C.run('desktop'), 1)
        self.assertEqual(self.steps(), ['shell'])
        self.assertEqual(C.status()['steps'][1]['status'], 'pending')

    def test_cancel_is_not_success(self):
        self.outcomes.write_text('{"shell": 125}')
        self.assertEqual(C.run('desktop'), 1)
        self.assertEqual(C.status()['steps'][0]['status'], 'cancelled')
        self.assertEqual(self.steps(), ['shell'])

    def test_system_independent_steps(self):
        self.outcomes.write_text('{"packages": 9}')
        self.assertEqual(C.run('system'), 1)
        self.assertEqual(self.steps(), ['packages', 'flatpak'])
        self.outcomes.write_text('{}')
        self.assertEqual(C.run('retry'), 0)
        self.assertEqual(self.steps(), ['packages', 'flatpak', 'packages'])

    def test_preflight_preserves_previous_recovery(self):
        self.outcomes.write_text('{"shell": 7}')
        C.run('desktop')
        previous = C.load()
        for target in ('inhibit_sleep', 'check_space'):
            with patch.object(C, target, side_effect=OSError('preflight failed')):
                with self.assertRaises(OSError):
                    C.run('system')
            self.assertEqual(C.load(), previous)
        self.assertEqual(self.steps(), ['shell'])

    def test_noninteractive_confirmation_has_clean_exit(self):
        import io
        import runpy
        for name in ('nbshell-update.py', 'umbriel-update.py'):
            helper = runpy.run_path(str(ROOT / 'shell/scripts' / name))
            main = helper['main']
            def no_input(*_args):
                raise EOFError()
            output = io.StringIO()
            with patch.dict(main.__globals__, install=no_input), \
                    patch.object(sys, 'argv', [name, 'install', '--coordinated']), \
                    patch('runpy.run_path', return_value={'inherited_guard': lambda: True}), \
                    contextlib.redirect_stderr(output):
                self.assertEqual(main(), 125)
            self.assertIn('Confirmation requires a terminal', output.getvalue())

    def test_forged_guard_is_rejected(self):
        with patch.dict(os.environ, NBSHELL_UPDATE_LOCK_FD='99999'):
            self.assertFalse(C.inherited_guard())
        for script, args in [('nbshell-update.py', ['install', '--coordinated']),
                             ('umbriel-update.py', ['install', '--coordinated']),
                             ('updates.sh', ['_packages'])]:
            interpreter = 'bash' if script.endswith('.sh') else sys.executable
            result = subprocess.run([interpreter, str(ROOT / 'shell/scripts' / script), *args],
                                    env=self.env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('requires an active update coordinator', result.stderr)

    def start_held(self):
        (self.root / 'hold').touch()
        driver = self.root / 'driver.py'
        driver.write_text('''import os,runpy,contextlib
from pathlib import Path
m=runpy.run_path(SOURCE_PATH)
g=m['run'].__globals__
@contextlib.contextmanager
def inhibitor():
    with open(os.devnull) as f: yield f.fileno()
g['inhibit_sleep']=inhibitor
g['check_space']=lambda step:None
g['SCRIPTS']=Path(os.environ['TEST_FIXTURE'])
raise SystemExit(m['run']('desktop',yes=True))
'''.replace('SOURCE_PATH', repr(str(SCRIPT))))
        proc = subprocess.Popen([sys.executable, str(driver)], env=self.env,
                                stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        self.addCleanup(lambda: proc.stderr.close())
        def cleanup():
            (self.root / 'hold').unlink(missing_ok=True)
            if proc.poll() is None:
                proc.wait(timeout=10)
        self.addCleanup(cleanup)
        deadline = time.monotonic() + 10
        while not (self.root / 'ready').exists():
            if proc.poll() is not None or time.monotonic() > deadline:
                self.fail('Fixture did not start: ' + proc.stderr.read().decode())
            time.sleep(.02)
        return proc

    def test_concurrent_workflows_and_term_keep_lock(self):
        proc = self.start_held()
        self.assertTrue(C.status()['active'])
        self.assertEqual(C.run('system'), 75)
        proc.send_signal(signal.SIGTERM)
        time.sleep(.1)
        self.assertIsNone(proc.poll())
        self.assertEqual(C.run('shell'), 75)
        (self.root / 'hold').unlink()
        self.assertEqual(proc.wait(timeout=10), 1)
        self.assertEqual(self.steps(), ['shell'])
        self.assertEqual(C.status()['status'], 'interrupted')
        self.assertFalse(C.status()['active'])

    def test_killed_worker_waits_for_fd_closing_grandchild(self):
        shell = self.scripts / 'nbshell-update.py'
        # Model sudo's descriptor boundary: this descendant has no guard fds.
        shell.write_text("""import os,subprocess,sys,time
from pathlib import Path
root=Path(os.environ['TEST_ROOT'])
child=subprocess.Popen([sys.executable,'-c',
    \"import os,time; from pathlib import Path; r=Path(os.environ['TEST_ROOT']); (r/'ready').touch(); \\nwhile (r/'hold').exists(): time.sleep(.02)\"],close_fds=True)
(root/'worker-pid').write_text(str(os.getpid()))
child.wait()
""")
        proc = self.start_held()
        os.kill(int((self.root / 'worker-pid').read_text()), signal.SIGKILL)
        time.sleep(.15)
        self.assertIsNone(proc.poll(), 'Coordinator released protection while an installer was alive')
        self.assertEqual(C.run('system'), 75)
        (self.root / 'hold').unlink()
        self.assertEqual(proc.wait(timeout=10), 1)
        self.assertEqual(C.status()['steps'][0]['status'], 'failed')
        self.assertEqual(C.status()['steps'][1]['status'], 'pending')

    def test_exception_cleanup_retains_snapshot_until_child_exits(self):
        sentinel = self.root / 'snapshot-survived'
        children = []
        def failed_wait(command, **_kwargs):
            children.append(subprocess.Popen([sys.executable, '-c',
                'import sys,time; from pathlib import Path; time.sleep(.1); '
                'Path(sys.argv[2]).write_text(str(Path(sys.argv[1]).exists()))',
                command[1], str(sentinel)]))
            raise OSError('Injected process wait failure')
        with patch.object(C.subprocess, 'run', side_effect=failed_wait):
            self.assertEqual(C.run('shell'), 1)
        self.assertEqual(sentinel.read_text(), 'True')
        for child in children:
            child.poll()  # The coordinator already reaped it.

    def test_retry_preserves_compositor_confirmation(self):
        self.outcomes.write_text('{"compositor":7}')
        self.assertEqual(C.run('desktop', compositor_yes=True), 1)
        self.outcomes.write_text('{}')
        self.assertEqual(C.run('retry'), 0)
        self.assertTrue(C.status()['compositorYes'])
        self.assertFalse(C.status()['yes'])

    def test_killed_supervisor_worker_retains_lock(self):
        proc = self.start_held()
        proc.kill()
        proc.wait(timeout=10)
        self.assertEqual(C.run('system'), 75)
        (self.root / 'hold').unlink()
        deadline = time.monotonic() + 10
        while C.status()['active'] and time.monotonic() < deadline:
            time.sleep(.02)
        self.assertEqual(C.status()['status'], 'interrupted')
        self.assertFalse(C.status()['active'])

    def test_space_checks_separate_mounts(self):
        # Exercise the actual function rather than the fixture's preflight mock.
        real = runpy_load()['check_space']
        from collections import namedtuple
        Usage = namedtuple('Usage', 'total used free')
        with patch('shutil.disk_usage', return_value=Usage(10**12, 0, 0)):
            with self.assertRaisesRegex(RuntimeError, 'Not enough free space'):
                real('shell')
        seen = []
        def usage(path):
            seen.append(str(path))
            return Usage(10**12, 0, 10**12)
        for variable in ('XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_BIN_HOME', 'XDG_CACHE_HOME'):
            path = self.root / variable
            path.mkdir()
            os.environ[variable] = str(path)
        with patch('shutil.disk_usage', side_effect=usage):
            real('shell')
            real('packages')
            real('flatpak')
        for variable in ('XDG_CONFIG_HOME', 'XDG_DATA_HOME', 'XDG_BIN_HOME', 'XDG_CACHE_HOME'):
            self.assertIn(os.environ[variable], seen)
        self.assertIn('/usr', seen)
        self.assertIn('/boot', seen)


def runpy_load():
    import runpy
    return runpy.run_path(str(SCRIPT))


if __name__ == '__main__':
    unittest.main()
