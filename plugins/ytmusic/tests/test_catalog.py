#!/usr/bin/env python3
from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "backend"))

from catalog import (  # noqa: E402
    context_item,
    duration_ms,
    map_items,
    thumbnail_url,
    track_item,
)


class CatalogTests(unittest.TestCase):
    def test_duration_parses_clock_and_seconds(self):
        self.assertEqual(duration_ms({"duration": "3:45"}), 225000)
        self.assertEqual(duration_ms({"duration": "1:02:03"}), 3723000)
        self.assertEqual(duration_ms({"duration_seconds": 90}), 90000)
        self.assertEqual(duration_ms({}), 0)

    def test_track_item_normalizes_song(self):
        item = track_item({
            "title": "Under the Bridge",
            "videoId": "GLvqBAudoEg",
            "artists": [{"name": "Red Hot Chili Peppers", "id": "UC123"}],
            "album": {"name": "Blood Sugar Sex Magik", "id": "MPREb_album"},
            "duration": "4:24",
            "thumbnails": [{"url": "https://img/small.jpg", "width": 60},
                           {"url": "https://img/large.jpg", "width": 544}],
            "likeStatus": "LIKE",
        })
        self.assertIsNotNone(item)
        self.assertEqual(item["type"], "track")
        self.assertEqual(item["kind"], "item")
        self.assertEqual(item["uri"], "ytm:track:GLvqBAudoEg")
        self.assertEqual(item["subtitle"], "Red Hot Chili Peppers")
        self.assertEqual(item["album"], "Blood Sugar Sex Magik")
        self.assertTrue(item["liked"])
        self.assertEqual(item["imageUrl"], "https://img/large.jpg")
        self.assertEqual(item["durationMs"], 264000)
        self.assertEqual(item["albumItem"]["type"], "album")

    def test_context_item_playlist(self):
        item = context_item({
            "title": "Liked Music",
            "playlistId": "LM",
            "count": 12,
        }, "playlist")
        self.assertEqual(item["type"], "playlist")
        self.assertEqual(item["kind"], "context")
        self.assertIn("12 songs", item["subtitle"])

    def test_map_items_skips_junk(self):
        rows = map_items([
            None,
            {"title": "Nope"},
            {"title": "Song", "videoId": "abcdefghijk"},
        ])
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["videoId"], "abcdefghijk")

    def test_thumbnail_prefers_wide_image(self):
        url = thumbnail_url({
            "thumbnails": [
                {"url": "a", "width": 60},
                {"url": "b", "width": 226},
            ]
        })
        self.assertEqual(url, "b")


if __name__ == "__main__":
    unittest.main()
