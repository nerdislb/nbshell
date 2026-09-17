#!/usr/bin/env python3
"""Measure how much of Omarchy's QML kit nbshell can actually serve.

The adapter layer under ``shell/Commons`` and ``shell/Ui`` is the channel that
lets an upstream Omarchy component run on nbshell. Two things break a port, and
both fail *silently* or late today:

1. a singleton member upstream calls (``Style.bar.iconSlot``, ``Color.popups.text``)
   that the adapter does not provide;
2. a component upstream ships (``Dropdown``, ``PopupCard``) that has no nbshell
   counterpart, which pushes a new surface into hand-built chrome.

This script reports both so the gap is visible before someone builds on it.

Usage:
    tests/ui-kit-coverage.py [--omarchy PATH] [--strict]

Without ``--omarchy`` a few conventional checkout locations are tried. With no
checkout available the script prints that it skipped and exits 0, like the QML
runner does when it is missing. ``--strict`` turns any gap into exit status 1,
which is how the check is meant to run while a surface is being ported.
"""

from __future__ import annotations

import argparse
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
ADAPTER_COMPONENT_DIR = ROOT / "shell/Ui"
ADAPTER_SINGLETON_DIR = ROOT / "shell/Commons"
SINGLETONS = ("Style", "Color", "Border", "Util")
CANDIDATE_CHECKOUTS = (
    pathlib.Path.home() / ".cache/omarchy-research/omarchy",
    pathlib.Path.home() / "projects/omarchy-comparison-20260907",
)


def nested_members(text: str) -> dict[str, set[str]]:
    """Map a ``property QtObject foo: QtObject { ... }`` name to its members."""
    nested: dict[str, set[str]] = {}
    for match in re.finditer(r"property\s+QtObject\s+(\w+)\s*:\s*QtObject\s*\{", text):
        name = match.group(1)
        depth = 1
        index = match.end()
        while index < len(text) and depth:
            if text[index] == "{":
                depth += 1
            elif text[index] == "}":
                depth -= 1
            index += 1
        body = text[match.end():index]
        members = set(re.findall(r"\bproperty\s+(?:\w+(?:<[^>]+>)?\s+)?(\w+)\s*:", body))
        members |= set(re.findall(r"\bfunction\s+(\w+)\s*\(", body))
        nested[name] = members
    return nested


def flat_members(text: str) -> set[str]:
    members = set(re.findall(r"\bproperty\s+(?:\w+(?:<[^>]+>)?\s+)?(\w+)\s*:", text))
    members |= set(re.findall(r"\bfunction\s+(\w+)\s*\(", text))
    return members


def adapter_members(singleton: str) -> tuple[set[str], dict[str, set[str]]]:
    path = ADAPTER_SINGLETON_DIR / f"{singleton}.qml"
    if not path.exists():
        return set(), {}
    text = path.read_text(encoding="utf-8")
    return flat_members(text), nested_members(text)


def used_members(ui_dir: pathlib.Path, singleton: str) -> set[str]:
    # Qt exposes r/g/b/a (and the hsv/hsla families) on every color value, so a
    # dotted access like Color.accent.b is not a missing member.
    color_components = {"r", "g", "b", "a", "hsvHue", "hsvSaturation", "hsvValue",
                        "hsvaHue", "hsvaSaturation", "hsvaValue", "hsvaAlpha",
                        "hslaHue", "hslaSaturation", "hslaLightness", "hslaAlpha"}
    used: set[str] = set()
    for path in sorted(ui_dir.glob("*.qml")):
        text = path.read_text(encoding="utf-8")
        for member in re.findall(rf"\b{singleton}\.([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)", text):
            if member.rpartition(".")[2] in color_components:
                continue
            used.add(member)
    return used


def adapter_component_types() -> set[str]:
    qmldir = ADAPTER_COMPONENT_DIR / "qmldir"
    if not qmldir.exists():
        return set()
    types: set[str] = set()
    for line in qmldir.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("module "):
            continue
        types.add(line.split()[0])
    return types


def upstream_component_types(ui_dir: pathlib.Path) -> set[str]:
    return {path.stem for path in sorted(ui_dir.glob("*.qml"))}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--omarchy", type=pathlib.Path, default=None)
    parser.add_argument("--strict", action="store_true")
    args = parser.parse_args()

    checkout = args.omarchy
    if checkout is None:
        checkout = next((path for path in CANDIDATE_CHECKOUTS if path.is_dir()), None)
    if checkout is None or not (checkout / "shell/Ui").is_dir():
        print("No Omarchy checkout found; UI-kit coverage skipped.")
        return 0

    ui_dir = checkout / "shell/Ui"
    print(f"Omarchy reference: {checkout}")
    print("Run this against the pinned commit before trusting the numbers.")
    print()

    missing_members: list[str] = []
    for singleton in SINGLETONS:
        provided, nested = adapter_members(singleton)
        used = used_members(ui_dir, singleton)
        for member in sorted(used):
            head, _, tail = member.partition(".")
            if head not in provided:
                missing_members.append(f"{singleton}.{member}")
            elif tail and tail not in nested.get(head, set()):
                missing_members.append(f"{singleton}.{member}")

    upstream_types = upstream_component_types(ui_dir)
    provided_types = adapter_component_types()
    missing_types = sorted(upstream_types - provided_types)

    print(f"Singleton members upstream uses but the adapter lacks: {len(missing_members)}")
    for member in missing_members:
        print(f"  - {member}")
    print()
    print(f"Upstream components: {len(upstream_types)}")
    print(f"Adapter components:  {len(provided_types)}")
    print(f"Not ported yet:      {len(missing_types)}")
    for name in missing_types:
        print(f"  - {name}")

    if missing_members or missing_types:
        if args.strict:
            print()
            print("FAIL: a ported surface would need hand-built chrome or a missing member.")
            return 1
        print()
        print("Report only. Use --strict while porting to make this a gate.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
