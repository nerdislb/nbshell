#!/usr/bin/env python3
from __future__ import annotations

import os
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))

import player  # noqa: E402
from server import AuthError, Backend, idle_should_exit  # noqa: E402


class IdleWatchTests(unittest.TestCase):
    def test_idle_exit_requires_minutes_and_silence(self):
        now = 1_000.0
        self.assertFalse(idle_should_exit(
            idle_minutes=15, playing=False, client_count=0,
            last_activity=now, now=now))
        self.assertTrue(idle_should_exit(
            idle_minutes=15, playing=False, client_count=0,
            last_activity=now - 15 * 60, now=now))

    def test_idle_exit_skips_playing_and_connected_clients(self):
        now = 1_000.0
        self.assertFalse(idle_should_exit(
            idle_minutes=15, playing=True, client_count=0,
            last_activity=now - 15 * 60, now=now))
        self.assertFalse(idle_should_exit(
            idle_minutes=15, playing=False, client_count=1,
            last_activity=now - 15 * 60, now=now))
        self.assertFalse(idle_should_exit(
            idle_minutes=0, playing=False, client_count=0,
            last_activity=now - 15 * 60, now=now))


class StreamCacheWarmUpTests(unittest.TestCase):
    """Solving YouTube's player JS challenge before the first play."""

    def setUp(self):
        self._runtime = tempfile.TemporaryDirectory()
        self._previous = os.environ.get("XDG_RUNTIME_DIR")
        os.environ["XDG_RUNTIME_DIR"] = self._runtime.name
        self.backend = Backend(Path(self._runtime.name) / "absent.json")

    def tearDown(self):
        if self._previous is None:
            os.environ.pop("XDG_RUNTIME_DIR", None)
        else:
            os.environ["XDG_RUNTIME_DIR"] = self._previous
        self._runtime.cleanup()

    def test_warm_up_is_skipped_when_the_cache_is_already_warm(self):
        with mock.patch.object(player, "yt_dlp_cache_warm", return_value=True), \
             mock.patch.object(self.backend, "_catalog_video_id") as picker:
            self.backend._warm_stream_cache()
        picker.assert_not_called()

    def test_warm_up_uses_a_catalog_video_not_a_hardcoded_one(self):
        with mock.patch.object(player, "yt_dlp_cache_warm", return_value=False), \
             mock.patch.object(self.backend, "_catalog_video_id",
                               return_value="dQw4w9wgkcQ") as picker, \
             mock.patch.object(self.backend.player.resolver, "resolve") as resolve:
            self.backend._warm_stream_cache()
            for _ in range(50):
                if picker.called and resolve.called:
                    break
                time.sleep(0.02)
        picker.assert_called_once_with()
        resolve.assert_called_once_with("dQw4w9wgkcQ")

    def test_state_reports_whether_a_resolve_is_in_flight(self):
        self.assertIs(self.backend.state()["resolving"], False)
        self.backend.player.resolving = True
        self.assertIs(self.backend.state()["resolving"], True)


class LikeAuthTests(unittest.TestCase):
    def setUp(self):
        self._runtime = tempfile.TemporaryDirectory()
        self._previous = os.environ.get("XDG_RUNTIME_DIR")
        os.environ["XDG_RUNTIME_DIR"] = self._runtime.name
        self.backend = Backend(Path(self._runtime.name) / "absent.json")

    def tearDown(self):
        if self._previous is None:
            os.environ.pop("XDG_RUNTIME_DIR", None)
        else:
            os.environ["XDG_RUNTIME_DIR"] = self._previous
        self._runtime.cleanup()

    def test_like_without_session_asks_to_sign_in(self):
        self.backend.signed_in = False
        with self.assertRaises(AuthError) as raised:
            self.backend.like("abcdefghijk", True)
        self.assertEqual(str(raised.exception), "Sign in to like songs")


class PlaybackCommandTests(unittest.TestCase):
    def setUp(self):
        self._runtime = tempfile.TemporaryDirectory()
        self._previous = os.environ.get("XDG_RUNTIME_DIR")
        os.environ["XDG_RUNTIME_DIR"] = self._runtime.name
        self.backend = Backend(Path(self._runtime.name) / "absent.json")
        self.track = lambda vid, name: {
            "type": "track",
            "videoId": vid,
            "name": name,
            "subtitle": "Artist",
        }
        self.backend.player.queue = [
            self.track("aaa", "First"),
            self.track("bbb", "Second"),
            self.track("ccc", "Third"),
        ]
        self.backend.player.index = 1

    def tearDown(self):
        if self._previous is None:
            os.environ.pop("XDG_RUNTIME_DIR", None)
        else:
            os.environ["XDG_RUNTIME_DIR"] = self._previous
        self._runtime.cleanup()

    def test_reorder_queue_moves_items_and_keeps_now_playing_index(self):
        with mock.patch.object(self.backend.player, "apply_eq"):
            result = self.backend.dispatch("reorder_queue", {
                "source_index": 0,
                "destination_index": 2,
            })
        ids = [item["videoId"] for item in result["queue"]]
        self.assertEqual(ids, ["bbb", "ccc", "aaa"])
        self.assertEqual(self.backend.player.index, 0)
        self.assertEqual(self.backend.player.current["videoId"], "bbb")

    def test_set_eq_preset_applies_cliamp_curve(self):
        with mock.patch.object(self.backend.player, "apply_eq") as apply_eq:
            snapshot = self.backend.dispatch("set_eq_preset", {"name": "Rock"})
        self.assertEqual(snapshot["preset"], "Rock")
        self.assertEqual(snapshot["bands"], list(player.EQ_PRESETS["Rock"]))
        apply_eq.assert_called_once()

    def test_restore_eq_reloads_custom_bands(self):
        with mock.patch.object(self.backend.player, "apply_eq"):
            snapshot = self.backend.dispatch("restore_eq", {
                "preset": "Custom",
                "bands": [4, 0, -2],
            })
        self.assertEqual(snapshot["preset"], "Custom")
        self.assertEqual(snapshot["bands"][0], 4.0)
        self.assertEqual(snapshot["bands"][2], -2.0)
        self.assertEqual(len(snapshot["bands"]), 10)


if __name__ == "__main__":
    unittest.main()
