#!/usr/bin/env python3
"""Validate readable text roles on every shipped light-theme surface."""

from __future__ import annotations

from pathlib import Path
import tomllib


ROOT = Path(__file__).resolve().parent.parent
MINIMUM_CONTRAST = 4.5
TEXT_ROLES = ("foreground", "dark_foreground", "muted")
SURFACE_ROLES = ("background", "dark_background", "darker_background", "lighter_background")


def rgb(value: str) -> tuple[int, int, int]:
    value = value.removeprefix("#")
    if len(value) != 6:
        raise ValueError(f"expected #RRGGBB, got {value!r}")
    return int(value[0:2], 16), int(value[2:4], 16), int(value[4:6], 16)


def linear(channel: int) -> float:
    encoded = channel / 255
    return encoded / 12.92 if encoded <= 0.04045 else ((encoded + 0.055) / 1.055) ** 2.4


def luminance(color: tuple[int, int, int]) -> float:
    red, green, blue = (linear(channel) for channel in color)
    return 0.2126 * red + 0.7152 * green + 0.0722 * blue


def contrast(foreground: tuple[int, int, int], background: tuple[int, int, int]) -> float:
    lighter, darker = sorted((luminance(foreground), luminance(background)), reverse=True)
    return (lighter + 0.05) / (darker + 0.05)


def main() -> int:
    failures: list[str] = []
    light_themes = 0
    for path in sorted((ROOT / "themes").glob("*/colors.toml")):
        with path.open("rb") as handle:
            theme = tomllib.load(handle)
        if theme.get("mode") != "light":
            continue
        light_themes += 1
        for role in TEXT_ROLES:
            foreground = rgb(theme[role])
            for surface_role in SURFACE_ROLES:
                ratio = contrast(foreground, rgb(theme[surface_role]))
                if ratio + 1e-9 < MINIMUM_CONTRAST:
                    failures.append(
                        f"{path.parent.name}: {role} on {surface_role} is {ratio:.2f}:1"
                    )
    if not light_themes:
        failures.append("no light themes were found")
    if failures:
        raise SystemExit("Light-theme contrast failures:\n  " + "\n  ".join(failures))
    print(
        f"Light theme contrast: OK ({light_themes} themes, "
        f"{len(TEXT_ROLES)} text roles, {len(SURFACE_ROLES)} surfaces)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
