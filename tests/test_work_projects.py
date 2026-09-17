import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('work_projects', Path(__file__).resolve().parents[1] / 'shell/scripts/work-projects.py')
work = importlib.util.module_from_spec(spec)
spec.loader.exec_module(work)

class Projects(unittest.TestCase):
    def test_real_git_rename_and_untracked(self):
        with tempfile.TemporaryDirectory() as directory:
            def git(*args):
                subprocess.run(['git', '-C', directory, *args], check=True, capture_output=True)
            git('init', '-b', 'main')
            Path(directory, 'old').write_text('a')
            git('add', '.')
            git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-m', 'fixture')
            self.assertEqual(work.inspect(directory)['changed'], 0)
            git('mv', 'old', 'new\nname')
            Path(directory, 'untracked').write_text('b')
            row = work.inspect(directory)
            self.assertEqual(row['branch'], 'main')
            self.assertEqual(row['changed'], 2)
            self.assertEqual(row['conflicts'], 0)
    def test_invalid_and_non_repository(self):
        self.assertIn('error', work.inspect('relative'))
        with tempfile.TemporaryDirectory() as directory:
            self.assertIn('error', work.inspect(directory))
        self.assertEqual(work.snapshot([]), {})

    def test_status_never_executes_clean_process_or_fsmonitor(self):
        for driver in ('clean', 'process'):
            with self.subTest(driver=driver), tempfile.TemporaryDirectory() as directory:
                def git(*args):
                    return subprocess.run(['git', '-C', directory, *args], check=True, capture_output=True)
                root = Path(directory)
                git('init', '-b', 'main')
                (root / 'file').write_text('original\n')
                (root / '.gitattributes').write_text('file filter=probe\n')
                git('add', '.')
                git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-m', 'fixture')
                git('config', 'filter.probe.' + driver, 'touch FILTER_EXECUTED; cat')
                git('config', 'filter.probe.required', 'true')
                git('config', 'core.fsmonitor', 'touch FSMONITOR_EXECUTED')
                # Same size forces Git to compare content rather than stat only.
                (root / 'file').write_text('modified\n')
                os.utime(root / 'file', (1000000000, 1000000000))
                index = (root / '.git/index').read_bytes()
                result = work.inspect(directory)
                self.assertNotIn('error', result)
                self.assertEqual(result['changed'], 1)
                self.assertFalse((root / 'FILTER_EXECUTED').exists())
                self.assertFalse((root / 'FSMONITOR_EXECUTED').exists())
                self.assertEqual(index, (root / '.git/index').read_bytes())

    def test_inherited_git_directory_and_config_cannot_redirect_inspection(self):
        with tempfile.TemporaryDirectory() as directory:
            subprocess.run(['git', '-C', directory, 'init', '-b', 'intended'], check=True, capture_output=True)
            with patch.dict(os.environ, {'GIT_DIR': '/does-not-exist', 'GIT_WORK_TREE': '/does-not-exist',
                                         'GIT_CONFIG_COUNT': '1', 'GIT_CONFIG_KEY_0': 'core.bare',
                                         'GIT_CONFIG_VALUE_0': 'true'}):
                result = work.inspect(directory)
            self.assertNotIn('error', result)
            self.assertEqual(result['root'], directory)

    def test_output_overflow_is_rejected(self):
        with patch.object(work, 'MAX_OUTPUT', 4096):
            with self.assertRaisesRegex(ValueError, 'output limit'):
                work.run_git([sys.executable, '-c', 'import sys; sys.stdout.write("x" * 100000)'], os.environ)
        self.assertFalse(work._children)

    def test_included_filter_config_and_submodule_worktrees_are_not_executed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def git(where, *args):
                return subprocess.run(['git', '-C', str(where), *args], check=True, capture_output=True)
            source, parent = root / 'source', root / 'parent'
            source.mkdir(); parent.mkdir()
            git(source, 'init', '-b', 'main')
            (source / 'file').write_text('original\n')
            (source / '.gitattributes').write_text('file filter=probe\n')
            git(source, 'add', '.')
            git(source, '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-m', 'fixture')
            git(parent, 'init', '-b', 'main')
            git(parent, '-c', 'protocol.file.allow=always', 'submodule', 'add', str(source), 'sub')
            git(parent, '-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', 'commit', '-m', 'fixture')
            sub = parent / 'sub'
            config = root / 'filters.config'
            config.write_text('[filter "probe"]\nclean = "touch FILTER_EXECUTED; cat"\nrequired = true\n')
            git(sub, 'config', 'include.path', str(config))
            (sub / 'file').write_text('modified\n')
            os.utime(sub / 'file', (1000000000, 1000000000))
            self.assertEqual(work.inspect(str(parent))['changed'], 0)
            self.assertEqual(work.inspect(str(sub))['changed'], 1)
            self.assertFalse((sub / 'FILTER_EXECUTED').exists())

    def test_helper_sigterm_cancels_active_and_queued_commands(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary = root / 'git'
            binary.write_text(f'#!{sys.executable}\nimport os,time\nfrom pathlib import Path\n'
                              'with Path(os.environ["TEST_PIDS"]).open("a") as f: f.write(str(os.getpid())+"\\n")\n'
                              'time.sleep(30)\n')
            binary.chmod(0o755)
            paths = [root / str(i) for i in range(12)]
            for path in paths:
                path.mkdir()
            pids = root / 'pids'
            child = subprocess.Popen([sys.executable, str(Path(work.__file__)), json.dumps(list(map(str, paths)))],
                                     env={**os.environ, 'PATH': str(root), 'TEST_PIDS': str(pids)},
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            try:
                for _ in range(100):
                    if pids.exists() and len(pids.read_text().splitlines()) >= 4:
                        break
                    time.sleep(0.02)
                else:
                    self.fail('Fixture did not start its four Git workers')
                child.terminate()
                child.communicate(timeout=3)
                self.assertEqual(child.returncode, 143)
                started = pids.read_text().splitlines()
                self.assertEqual(len(started), 4, 'Queued commands started after cancellation')
                for pid in started:
                    self.assertFalse(Path(f'/proc/{pid}').exists(), 'Git child was not reaped')
            finally:
                if child.poll() is None:
                    child.kill(); child.communicate()

    def test_timeout_kills_descendant_holding_pipe(self):
        with tempfile.TemporaryDirectory() as directory:
            pidfile = Path(directory, 'pid')
            program = ('import subprocess,sys; from pathlib import Path; '
                       'p=subprocess.Popen([sys.executable,"-c","import time; time.sleep(30)"]); '
                       'Path(sys.argv[1]).write_text(str(p.pid))')
            with patch.object(work, 'COMMAND_TIMEOUT', 0.4):
                with self.assertRaises(subprocess.TimeoutExpired):
                    work.run_git([sys.executable, '-c', program, str(pidfile)], os.environ)
            pid = int(pidfile.read_text())
            for _ in range(50):
                try:
                    state = Path(f'/proc/{pid}/stat').read_text().split(') ', 1)[1].split()[0]
                except FileNotFoundError:
                    break
                if state == 'Z':
                    break
                time.sleep(0.02)
            else:
                self.fail('Git descendant survived timeout')
        self.assertFalse(work._children)


if __name__ == '__main__':
    unittest.main()
