#!/usr/bin/env python3
"""Validate readable text roles on every shipped light-theme surface stack."""

from __future__ import annotations

from pathlib import Path
import tomllib


ROOT = Path(__file__).resolve().parent.parent
MINIMUM_CONTRAST = 4.5
TEXT_ROLES = ("foreground", "dark_foreground", "muted")
SURFACE_ROLES = ("background", "dark_background", "darker_background", "lighter_background")
SEMANTIC_SURFACES = {
    "panelSurface": lambda theme: rgb(theme["background"]),
    "panelSurfaceRaised": lambda theme: rgb(theme["lighter_background"]),
    "controlFill": lambda theme: mix(
        rgb(theme["background"]), rgb(theme["lighter_background"]), 0.72
    ),
    "readOnlyTextFieldFill": lambda theme: mix(
        rgb(theme["background"]), rgb(theme["lighter_background"]), 0.42
    ),
}


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


def mix(
    first: tuple[int, int, int], second: tuple[int, int, int], amount: float
) -> tuple[int, int, int]:
    """Match Theme.mix() channel interpolation for opaque theme colors."""
    return (
        round(first[0] * (1 - amount) + second[0] * amount),
        round(first[1] * (1 - amount) + second[1] * amount),
        round(first[2] * (1 - amount) + second[2] * amount),
    )


def main() -> int:
    failures: list[str] = []
    theme_qml = (ROOT / "shell/Common/Theme.qml").read_text()
    for contract in (
        "panelSurfaceRaised: isLight ? bgLight : alpha(bgLight, 0.72)",
        "return isLight ? mix(bg, bgLight, 0.72) : alpha(bgLight, 0.72)",
        "return isLight ? mix(bg, bgLight, 0.42) : alpha(bgLight, 0.42)",
    ):
        if contract not in theme_qml:
            failures.append(f"Theme.qml no longer guarantees opaque light surfaces: {contract}")
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
            for surface_role, make_surface in SEMANTIC_SURFACES.items():
                ratio = contrast(foreground, make_surface(theme))
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
        f"{len(TEXT_ROLES)} text roles, "
        f"{len(SURFACE_ROLES) + len(SEMANTIC_SURFACES)} surfaces)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
