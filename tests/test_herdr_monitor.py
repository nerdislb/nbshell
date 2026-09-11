"""Herdr wire fixtures: labels, pane identity, backwards compatibility and failure."""
import importlib.util
import json
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("agents", Path(__file__).resolve().parents[1] / "shell/scripts/agents.py")
agents = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agents)


class HerdrMonitorTest(unittest.TestCase):
    def test_snapshot_maps_custom_labels_without_changing_focus_identity(self):
        raw = [{"pane_id": "w2:p7", "tab_id": "w2:t2", "agent": "codex", "agent_status": "working", "focused": True}]
        snapshot = {"result": {"snapshot": {"agents": raw, "tabs": [{"tab_id": "w2:t2", "label": "API <review>"}]}}}
        with patch.object(agents.shutil, "which", return_value="/bin/herdr"), patch.object(agents.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, json.dumps(snapshot))) as run:
            rows = agents.herdr_sessions()
        self.assertEqual(run.call_count, 1)
        self.assertEqual(rows[0]["tab"], "API <review>")
        self.assertEqual(rows[0]["id"], "herdr:w2:p7")
        self.assertEqual(rows[0]["status"], "working")
        self.assertTrue(rows[0]["focused"])

    def test_legacy_list_fallback_keeps_pane_label(self):
        responses = [subprocess.CompletedProcess([], 1, ""), subprocess.CompletedProcess([], 0, json.dumps({"result": {"agents": [{"pane_id": "w1:p3", "agent": "claude"}]}}))]
        with patch.object(agents.shutil, "which", return_value="/bin/herdr"), patch.object(agents.subprocess, "run", side_effect=responses):
            rows = agents.herdr_sessions()
        self.assertEqual(rows[0]["tab"], "w1:p3")
        self.assertEqual(rows[0]["name"], "claude")

    def test_unavailable_is_not_reported_as_successful_empty_monitor(self):
        with patch.object(agents.shutil, "which", return_value="/bin/herdr"), patch.object(agents.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, "")):
            self.assertEqual(agents.herdr_sessions(), [])
            with self.assertRaises(SystemExit):
                agents.herdr_sessions(strict=True)

    def test_empty_snapshot_is_valid(self):
        with patch.object(agents.shutil, "which", return_value="/bin/herdr"), patch.object(agents.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, '{"result":{"snapshot":{"agents":[],"tabs":[]}}}')):
            self.assertEqual(agents.herdr_sessions(strict=True), [])


if __name__ == "__main__":
    unittest.main()
