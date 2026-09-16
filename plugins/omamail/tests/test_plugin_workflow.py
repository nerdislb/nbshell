"""Bundle validation and explicit development installation retain their scope."""
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class PluginWorkflow(unittest.TestCase):
    def app_tests(self, *, managed=False, scripts=None):
        with tempfile.TemporaryDirectory(prefix="omamail-app-test-scope-") as directory:
            root = Path(directory)
            (root / "Makefile").write_bytes((ROOT / "Makefile").read_bytes())
            if managed:
                (root / ".nbshell-managed").write_text("Managed plugin bundle\n")
            if scripts is not None:
                (root / "app/tests").mkdir(parents=True)
                for name, content in scripts.items():
                    (root / "app/tests" / name).write_text(content)
            return subprocess.run(["make", "--no-print-directory", "test-app-js"],
                                  cwd=root, capture_output=True, text=True)

    def test_plugin_bundle_does_not_require_omitted_desktop_app(self):
        result = self.app_tests(managed=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Standalone app is not bundled", result.stdout)

    def test_missing_app_outside_bundle_fails(self):
        result = self.app_tests()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Standalone app tree missing", result.stderr)

    def test_present_app_runs_both_real_node_tests(self):
        result = self.app_tests(scripts={
            "test_theme.js": "console.log('theme-tested')",
            "test_shell_theme.js": "console.log('shell-theme-tested')",
        })
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.splitlines(), ["theme-tested", "shell-theme-tested"])

    def test_missing_or_failing_app_test_never_becomes_a_skip(self):
        for first in [None, "process.exit(7)", "console.log('theme-tested')"]:
            with self.subTest(first=first):
                scripts = {} if first is None else {"test_theme.js": first}
                result = self.app_tests(managed=True, scripts=scripts)
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("not bundled", result.stdout)

    def test_install_delegates_to_plugin_installer(self):
        result = subprocess.run(["make", "--no-print-directory", "-n", "install"], cwd=ROOT,
                                capture_output=True, text=True, check=True)
        self.assertEqual(result.stdout.strip().splitlines(), [
            f'cargo build --locked --release --target-dir "{ROOT}/target" --bin omamail',
            'python3 scripts/backend-runtime.py install-local',
            'bash scripts/link-plugin.sh',
        ])

    def test_install_plugin_does_not_build_or_install_backend(self):
        result = subprocess.run(["make", "--no-print-directory", "-n", "install-plugin"], cwd=ROOT,
                                capture_output=True, text=True, check=True)
        self.assertEqual(result.stdout.strip().splitlines(), [
            'python3 scripts/backend-runtime.py uninstall',
            'bash scripts/link-plugin.sh',
        ])


if __name__ == "__main__":
    unittest.main()
