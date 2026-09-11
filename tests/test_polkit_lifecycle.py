"""Guard permanent activation and fallback without touching desktop services."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('polkit_agent', Path(__file__).resolve().parents[1] / 'shell/scripts/polkit-trial.py')
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)

class Lifecycle(unittest.TestCase):
    def test_runtime_integrity_and_regression_gate(self):
        with tempfile.TemporaryDirectory() as directory:
            runtime = Path(directory)
            binary = runtime / 'quickshell'
            binary.write_bytes(b'test runtime')
            record = {'queueRegressionPassed': True, 'sha256': hashlib.sha256(binary.read_bytes()).hexdigest()}
            (runtime / 'build.json').write_text(json.dumps(record))
            with patch.object(agent, 'RUNTIME', runtime), patch.object(agent, 'BINARY', binary):
                agent.verify_runtime()
                binary.write_bytes(b'changed')
                with self.assertRaises(RuntimeError): agent.verify_runtime()
                record['queueRegressionPassed'] = False
                (runtime / 'build.json').write_text(json.dumps(record))
                with self.assertRaises(RuntimeError): agent.verify_runtime()

    def test_unexpected_clean_exit_is_failure(self):
        with patch.object(agent, 'verify_runtime'), patch.object(agent, 'run', return_value=subprocess.CompletedProcess([], 0)):
            with self.assertRaises(RuntimeError): agent.serve()

    def test_logout_does_not_start_fallback(self):
        with patch.object(agent, 'active', return_value=False), patch.object(agent, 'run') as run:
            agent.fallback()
            run.assert_not_called()

    def test_active_session_fallback(self):
        with patch.object(agent, 'active', return_value=True), patch.object(agent, 'run') as run:
            agent.fallback()
            run.assert_called_once_with(['systemctl', '--user', 'start', agent.FALLBACK], check=True)

    def test_pending_trial_request_blocks_promotion(self):
        with patch.object(agent, 'verify_runtime'), patch.object(agent, 'active', side_effect=lambda unit: unit == agent.UNIT), patch.object(agent, 'registration', return_value={'active': True}), patch.object(agent, 'run') as run:
            with self.assertRaises(RuntimeError): agent.keep()
            run.assert_not_called()

    def test_failed_registration_restores_previous_agent(self):
        with patch.object(agent, 'verify_runtime'), patch.object(agent, 'active', return_value=False), patch.object(agent, 'run'), patch.object(agent, 'wait_registered', side_effect=RuntimeError('registration failed')), patch.object(agent, 'restore') as restore:
            with self.assertRaises(RuntimeError): agent.keep()
            restore.assert_called_once()

    def test_restore_reports_still_enabled_native(self):
        with patch.object(agent, 'run', return_value=subprocess.CompletedProcess([], 0)), patch.object(agent, 'active', return_value=True):
            with self.assertRaisesRegex(RuntimeError, 'could not be disabled'): agent.restore()

if __name__ == '__main__':
    unittest.main()
