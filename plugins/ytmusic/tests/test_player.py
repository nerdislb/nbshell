#!/usr/bin/env python3
from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))

from player import (  # noqa: E402
    EQ_PRESETS,
    QueuePlayer,
    eq_filter_chain,
    loadfile_command,
    looks_like_stream_title,
    media_artist,
    media_title,
    mpris_title,
    mpv_command_line,
    mpv_env,
    quality_format,
    resolve_timeout,
    yt_dlp_cache_warm,
)


class PlayerTests(unittest.TestCase):
    def test_quality_format(self):
        self.assertIn("96", quality_format(96))
        self.assertIn("160", quality_format(160))
        self.assertIn("320", quality_format(320))

    def test_mpv_command_stays_headless(self):
        command = mpv_command_line("/usr/bin/mpv", Path("/tmp/mpv.sock"), "/lib/mpris.so")
        joined = " ".join(command)
        self.assertIn("--vo=null", command)
        self.assertIn("--no-config", command)
        self.assertIn("--load-scripts=no", command)
        self.assertIn("--keep-open=no", command)
        self.assertIn("--clipboard-backends-clr", command)
        self.assertIn("--audio-client-name=omarchy-ytmusic", command)
        self.assertIn("--script=/lib/mpris.so", command)
        self.assertNotIn("--really-quiet", command)
        self.assertIn("pipewire", joined)
        # Spaces in the Pulse/MPRIS client name make mpv-mpris hang on D-Bus.
        self.assertTrue(all(" " not in arg.split("=", 1)[-1]
                            for arg in command if arg.startswith("--audio-client-name=")))

    def test_media_title_prefers_track_name(self):
        self.assertEqual(media_title({"name": "Splashing Around"}), "Splashing Around")
        self.assertEqual(media_title({}), "YouTube Music")
        self.assertEqual(
            media_artist({"subtitle": "Baby Sleep Music", "artists": [{"name": "Other"}]}),
            "Baby Sleep Music",
        )
        self.assertEqual(media_artist({"artists": [{"name": "A"}, {"name": "B"}]}), "A, B")

    def test_loadfile_sets_force_media_title(self):
        command = loadfile_command(
            "https://example.test/stream",
            {"name": "Splashing Around", "subtitle": "Baby Sleep Music"},
        )
        self.assertEqual(command[0], "loadfile")
        self.assertEqual(command[2], "replace")
        self.assertEqual(
            command[4]["force-media-title"],
            "Baby Sleep Music - Splashing Around",
        )
        self.assertEqual(
            mpris_title({"name": "Splashing Around", "subtitle": "Baby Sleep Music"}),
            "Baby Sleep Music - Splashing Around",
        )

    def test_stream_titles_are_rejected(self):
        self.assertTrue(looks_like_stream_title("webm&ns=abc&rqh=1"))
        self.assertTrue(looks_like_stream_title("https://rr1---sn.googlevideo.com/videoplayback?x=1"))
        self.assertFalse(looks_like_stream_title("Skip to my lou"))

    def test_mpv_env_drops_wayland(self):
        env = mpv_env({
            "WAYLAND_DISPLAY": "wayland-1",
            "DISPLAY": ":0",
            "XDG_RUNTIME_DIR": "/run/user/1000",
            "HOME": "/home/user",
        })
        self.assertNotIn("WAYLAND_DISPLAY", env)
        self.assertNotIn("DISPLAY", env)
        self.assertEqual(env["XDG_RUNTIME_DIR"], "/run/user/1000")

    def test_cold_cache_gets_a_bigger_resolve_budget(self):
        # A cold player-JS solve is what made the first play after an install
        # report "Playback failed", so it must not share the warm budget.
        self.assertGreater(resolve_timeout(False), resolve_timeout(True))
        self.assertEqual(resolve_timeout(True), 40)

    def test_yt_dlp_cache_warm_detects_a_solved_challenge(self):
        with tempfile.TemporaryDirectory() as tmp:
            cache = Path(tmp) / "youtube-sigfuncs"
            self.assertFalse(yt_dlp_cache_warm(cache))     # missing
            cache.mkdir()
            self.assertFalse(yt_dlp_cache_warm(cache))     # present but empty
            (cache / "abc-main-1.json").write_text("{}", encoding="utf-8")
            self.assertTrue(yt_dlp_cache_warm(cache))


class QueueAndEqTests(unittest.TestCase):
    def test_eq_filter_chain_keeps_a_stable_lavfi_graph(self):
        chain = eq_filter_chain([8, 0, 0, 0, 0, 0, 0, 0, 0, 0])
        self.assertTrue(chain.startswith("lavfi=["))
        self.assertIn("equalizer=f=70:t=o:w=1:g=8.0", chain)
        self.assertIn("equalizer=f=16000:t=o:w=1:g=0.0", chain)
        self.assertEqual(chain.count("equalizer="), 10)
        flat = eq_filter_chain([0] * 10)
        self.assertEqual(flat.count("equalizer="), 10)
        self.assertIn("g=0.0", flat)

    def test_eq_presets_match_cliamp_count(self):
        self.assertEqual(len(next(iter(EQ_PRESETS.values()))), 10)
        self.assertIn("Rock", EQ_PRESETS)

    def test_restore_eq_named_preset_and_custom_bands(self):
        from unittest import mock
        with tempfile.TemporaryDirectory() as tmp:
            qp = QueuePlayer(Path(tmp))
            with mock.patch.object(qp, "apply_eq"):
                qp.restore_eq("Rock")
            self.assertEqual(qp.eq_preset, "Rock")
            self.assertEqual(qp.eq_bands, list(EQ_PRESETS["Rock"]))
            with mock.patch.object(qp, "apply_eq"):
                qp.restore_eq("Custom", [3, -1])
            self.assertEqual(qp.eq_preset, "Custom")
            self.assertEqual(qp.eq_bands[0], 3.0)
            self.assertEqual(qp.eq_bands[1], -1.0)
            self.assertEqual(len(qp.eq_bands), 10)


if __name__ == "__main__":
    unittest.main()
