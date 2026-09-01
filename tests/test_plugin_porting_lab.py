#!/usr/bin/env python3

import importlib.util
import json
import pathlib
import sys
import unittest
from unittest import mock

ROOT = pathlib.Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "shell/scripts/plugin-porting-lab.py"
spec = importlib.util.spec_from_file_location("plugin_porting_lab", SCRIPT)
assert spec is not None and spec.loader is not None
lab = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = lab
spec.loader.exec_module(lab)


class SourceResolutionTests(unittest.TestCase):
    def test_github_repository(self):
        source = lab.parse_github_url("https://github.com/example/weather")
        self.assertEqual((source.owner, source.repo, source.ref, source.prefix), ("example", "weather", "", ""))

    def test_github_subtree(self):
        source = lab.parse_github_url("https://github.com/example/plugins/tree/main/weather")
        self.assertEqual((source.ref, source.prefix), ("main", "weather"))

    def test_rejects_http_and_blob_urls(self):
        with self.assertRaisesRegex(lab.AnalysisError, "public HTTPS GitHub"):
            lab.parse_github_url("http://github.com/example/weather")
        with self.assertRaisesRegex(lab.AnalysisError, "repository URL"):
            lab.parse_github_url("https://github.com/example/weather/blob/main/Main.qml")

    @mock.patch.object(lab, "fetch_json")
    def test_marketplace_plugin_resolves_to_pinned_repo_path(self, fetch_json):
        fetch_json.return_value = {
            "plugins": [{
                "id": "example.weather",
                "name": "Weather",
                "repo": "https://github.com/example/plugins",
                "manifestPath": "weather/manifest.json",
                "upstreamObservedCommit": "abc123",
            }]
        }
        source = lab.resolve_source("https://omarchyplugins.com/plugin.html?id=example.weather")
        self.assertEqual((source.owner, source.repo, source.ref, source.prefix), ("example", "plugins", "abc123", "weather"))
        self.assertEqual(source.marketplace["name"], "Weather")


class StaticAnalysisTests(unittest.TestCase):
    def analyze(self, files, marketplace=None):
        source = lab.GitHubSource("example", "plugin", marketplace=marketplace)
        info = {
            "ref": "main",
            "prefix": "",
            "default_branch": "main",
            "repository_description": "",
            "truncated_tree": False,
            "candidate_count": len(files),
            "analyzed_count": len(files),
            "analyzed_bytes": sum(len(value) for value in files.values()),
        }
        return lab.analyze_files(source, files, info)

    def test_native_v2_source_gets_direct_port_verdict(self):
        report = self.analyze({
            "manifest.json": json.dumps({
                "schemaVersion": 2,
                "name": "Weather",
                "license": "MIT",
                "kinds": ["panel"],
            }),
            "Panel.qml": "import QtQuick\nimport qs.Common\nimport qs.Widgets\nFocusScope {}",
            "LICENSE": "MIT License",
        })
        self.assertEqual(report["verdict"]["recommendation"], "native-port")
        self.assertEqual(report["verdict"]["confidence"], "high")
        self.assertIn("nbshell-manifest-v2", {item["rule_id"] for item in report["findings"]})

    def test_omarchy_hyprland_backend_requires_rebuild_of_integration(self):
        report = self.analyze({
            "manifest.json": json.dumps({"name": "Portboard", "license": "MIT"}),
            "Panel.qml": "import qs.Commons\nimport qs.Ui\nimport qs.Services\nProcess { command: [\"hyprctl\", \"clients\"] }",
            "backend.py": "import urllib.request\nprint('status')",
            "LICENSE": "MIT",
        })
        ids = {item["rule_id"] for item in report["findings"]}
        self.assertIn("hyprland-api", ids)
        self.assertIn("omarchy-shell-api", ids)
        self.assertEqual(report["verdict"]["recommendation"], "backend-reuse")
        self.assertIn("Omarchy and compositor integration", report["replace"])

    def test_dangerous_install_is_never_recommended_as_portable(self):
        report = self.analyze({
            "manifest.json": json.dumps({"name": "Unsafe", "license": "MIT"}),
            "install.sh": "sudo pacman -S example\ncurl https://example.invalid/install | sh",
            "Main.qml": "import qs.Ui\nItem {}",
        })
        self.assertEqual(report["verdict"]["recommendation"], "not-recommended")
        self.assertLess(report["verdict"]["compatibility"], 50)
        self.assertIn("privileged-install", {item["rule_id"] for item in report["findings"]})

    def test_existing_capability_is_preferred_over_duplicate_port(self):
        report = self.analyze({
            "manifest.json": json.dumps({"name": "Notification Center", "license": "MIT"}),
            "Panel.qml": "import qs.Ui\nItem {}",
            "LICENSE": "MIT",
        })
        self.assertEqual(report["verdict"]["recommendation"], "compare-existing")
        self.assertIn("Notifications & Clipboard", report["existing_capabilities"])

    def test_missing_manifest_forces_low_confidence(self):
        report = self.analyze({"README.md": "A small plugin idea."})
        self.assertEqual(report["verdict"]["confidence"], "low")
        self.assertIn("manifest-missing", {item["rule_id"] for item in report["findings"]})


if __name__ == "__main__":
    unittest.main()
