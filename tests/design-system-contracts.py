#!/usr/bin/env python3
"""Keep the isolated QML adapter fixture aligned with production Theme APIs."""

from __future__ import annotations

import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]
REAL_THEME = ROOT / "shell/Common/Theme.qml"
FAKE_THEME = ROOT / "tests/imports/qs/Common/Theme.qml"
ADAPTER_DIRS = (ROOT / "shell/Commons", ROOT / "shell/Ui")


def declared_members(path: pathlib.Path) -> set[str]:
    text = path.read_text(encoding="utf-8")
    properties = re.findall(r"\bproperty\s+(?:\w+(?:<[^>]+>)?\s+)?(\w+)\s*:", text)
    functions = re.findall(r"\bfunction\s+(\w+)\s*\(", text)
    return set(properties) | set(functions)


used_theme_members: set[str] = set()
for directory in ADAPTER_DIRS:
    for path in directory.glob("*.qml"):
        used_theme_members.update(
            re.findall(r"\bTheme\.(\w+)", path.read_text(encoding="utf-8"))
        )

real_members = declared_members(REAL_THEME)
fake_members = declared_members(FAKE_THEME)

missing_real = sorted(used_theme_members - real_members)
missing_fake = sorted(used_theme_members - fake_members)
if missing_real:
    raise SystemExit(f"Adapter references missing production Theme members: {missing_real}")
if missing_fake:
    raise SystemExit(f"Fake Theme is missing adapter members: {missing_fake}")

expected_ui_types = {
    "BorderOverlay",
    "BorderSurface",
    "Button",
    "PanelActionButton",
    "PanelSectionHeader",
    "PanelSeparator",
    "PanelSlider",
    "PanelToolTip",
    "TextField",
}
ui_qmldir = (ROOT / "shell/Ui/qmldir").read_text(encoding="utf-8")
exported_ui_types = {
    line.split()[0]
    for line in ui_qmldir.splitlines()
    if line.strip() and not line.startswith("module ")
}
if exported_ui_types != expected_ui_types:
    raise SystemExit(
        f"qs.Ui export drift: expected {sorted(expected_ui_types)}, "
        f"got {sorted(exported_ui_types)}"
    )

dashboard = (ROOT / "shell/Menu/Dashboard.qml").read_text(encoding="utf-8")
tab_start = dashboard.index('model: ["TODAY", "MEDIA", "TOOLS", "CALENDAR"]')
tab_end = dashboard.index("// ── TODAY", tab_start)
tab_contract = dashboard[tab_start:tab_end]
if "ControlButton {" not in tab_contract:
    raise SystemExit("Dashboard tabs no longer use the canonical ControlButton")
for legacy in ("tabHover", "tabTap", "Theme.controlFill("):
    if legacy in tab_contract:
        raise SystemExit(f"Dashboard tab contract regressed to manual state handling: {legacy}")

volume = (ROOT / "shell/Bar/Widgets/Volume.qml").read_text(encoding="utf-8")
volume_header = volume[:volume.index("popout: Component")]
if "popoutTakesKeyboard: true" not in volume_header:
    raise SystemExit("Audio popout no longer accepts keyboard focus")
sink_start = volume.index("model: Audio.sinks")
sink_contract = volume[sink_start:]
if "PanelRow {" not in sink_contract:
    raise SystemExit("Audio sink rows no longer use the canonical PanelRow")
for legacy in ("id: mouse", "onTapped: Audio.setSink"):
    if legacy in sink_contract:
        raise SystemExit(f"Audio sink rows regressed to manual interaction: {legacy}")

required_accessible_names = {
    ROOT / "plugins/omamail/components/AppMenu.qml": [
        'accessibleName: "More options"',
    ],
    ROOT / "plugins/omamail/components/SearchBar.qml": [
        'accessibleName: "Clear search"',
    ],
    ROOT / "plugins/omamail/components/ComposeView.qml": [
        '"Change sender. Current sender: "',
        '"Hide Cc field"',
        '"Show Cc field"',
    ],
}
for path, snippets in required_accessible_names.items():
    source = path.read_text(encoding="utf-8")
    for snippet in snippets:
        if snippet not in source:
            raise SystemExit(f"Missing explicit accessibility name in {path}: {snippet}")

print(
    "Design-system adapter contracts: OK "
    f"({len(used_theme_members)} Theme members, {len(exported_ui_types)} Ui exports)"
)
