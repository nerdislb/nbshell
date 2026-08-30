#!/usr/bin/env python3
"""Validate the bounded Hermarchy theme adaptation shipped by nbshell."""

from __future__ import annotations

import hashlib
import re
import tomllib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
THEME = ROOT / "themes/hermarchy"
WALLPAPERS = ROOT / "wallpapers/hermarchy"
SOURCE_COMMIT = "12f3c5257f87237fa3fd549cf7be3f9fba76f9c8"
EXPECTED_WALLPAPERS = {
    "1.webp": "9743b061787c393ee66f09aed0c495efcba93d20781079729da6fd79b78cca5d",
    "2.webp": "3d9bd57c367d242334c0f59559a37ca91e123f002665bc19c108e11e0426e5be",
    "3.webp": "c57e6d0ff7f8e50056984e1ac3a0edc16427507167dc3a824267f55f4c662a1c",
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def webp_size(path: Path) -> tuple[int, int]:
    data = path.read_bytes()
    assert data[:4] == b"RIFF" and data[8:12] == b"WEBP", f"invalid WebP: {path}"
    chunk = data[12:16]
    if chunk == b"VP8X":
        return (
            1 + int.from_bytes(data[24:27], "little"),
            1 + int.from_bytes(data[27:30], "little"),
        )
    if chunk == b"VP8L":
        assert data[20] == 0x2F, f"invalid VP8L header: {path}"
        bits = int.from_bytes(data[21:25], "little")
        return (1 + (bits & 0x3FFF), 1 + ((bits >> 14) & 0x3FFF))
    if chunk == b"VP8 ":
        assert data[23:26] == b"\x9d\x01\x2a", f"invalid VP8 header: {path}"
        return (
            int.from_bytes(data[26:28], "little") & 0x3FFF,
            int.from_bytes(data[28:30], "little") & 0x3FFF,
        )
    raise AssertionError(f"unsupported WebP chunk {chunk!r}: {path}")


def luminance(color: str) -> float:
    values = [int(color[index:index + 2], 16) / 255 for index in (1, 3, 5)]
    linear = [value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4 for value in values]
    return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2]


def contrast(left: str, right: str) -> float:
    light, dark = sorted((luminance(left), luminance(right)), reverse=True)
    return (light + 0.05) / (dark + 0.05)


def main() -> None:
    assert {path.name for path in THEME.iterdir()} == {"colors.toml", "LICENSE"}
    palette_text = (THEME / "colors.toml").read_text(encoding="utf-8")
    palette = tomllib.loads(palette_text)
    assert palette["mode"] == "dark"
    assert palette["background"] == "#08090A"
    assert palette["foreground"] == "#F1F1EC"
    assert palette["accent"] == "#61D6FF"
    assert palette["selection"] == "#26333A"
    for name, value in palette.items():
        if name == "mode":
            continue
        assert isinstance(value, str) and re.fullmatch(r"#[0-9A-Fa-f]{6}", value), name
    assert contrast(palette["foreground"], palette["background"]) >= 4.5
    assert contrast(palette["accent"], palette["background"]) >= 3.0

    assert "Copyright (c) 2026 Archer Clawbot" in (THEME / "LICENSE").read_text(encoding="utf-8")
    for documentation in (
        ROOT / "themes/ATTRIBUTION.md",
        ROOT / "wallpapers/README.md",
        ROOT / "THIRD_PARTY.md",
    ):
        assert SOURCE_COMMIT in documentation.read_text(encoding="utf-8"), documentation

    assert {path.name for path in WALLPAPERS.iterdir()} == set(EXPECTED_WALLPAPERS)
    for name, expected_hash in EXPECTED_WALLPAPERS.items():
        path = WALLPAPERS / name
        assert sha256(path) == expected_hash, path
        assert webp_size(path) == (1920, 1080), path
        assert path.stat().st_size < 1_000_000, path

    # Keep the adaptation visually useful but structurally quiet: nbshell already
    # has one native Hermes surface, so the Omarchy collector/widget is excluded.
    tracked_names = [path.as_posix() for path in ROOT.rglob("*") if path.is_file()]
    assert not any("hermarchy-agent-state" in name for name in tracked_names)
    assert not (ROOT / "plugins/io.github.archer-clawbot.hermarchy-agent").exists()

    print("Hermarchy theme adaptation: OK")


if __name__ == "__main__":
    main()
