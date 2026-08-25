#!/usr/bin/env python3
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))

import play_history  # noqa: E402


class PlayHistoryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "play-history.json"

    def tearDown(self):
        self.tmp.cleanup()

    def test_remember_puts_latest_first_and_dedupes(self):
        first = {"videoId": "aaa", "name": "One"}
        second = {"videoId": "bbb", "name": "Two"}
        rows = play_history.remember(first, [], self.path)
        rows = play_history.remember(second, rows, self.path)
        rows = play_history.remember({"videoId": "aaa", "name": "One again"}, rows, self.path)
        self.assertEqual([play_history.video_id(row) for row in rows], ["aaa", "bbb"])
        self.assertTrue(rows[0]["externalUrl"].endswith("aaa"))

    def test_merge_keeps_local_ahead_of_remote(self):
        local = [{"videoId": "aaa", "name": "Local"}]
        remote = [{"videoId": "bbb", "name": "Remote"}, {"videoId": "aaa", "name": "Old"}]
        merged = play_history.merge(local, remote)
        self.assertEqual([play_history.video_id(row) for row in merged], ["aaa", "bbb"])
        self.assertEqual(merged[0]["name"], "Local")


if __name__ == "__main__":
    unittest.main()
