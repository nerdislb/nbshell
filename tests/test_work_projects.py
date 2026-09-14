import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest

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
