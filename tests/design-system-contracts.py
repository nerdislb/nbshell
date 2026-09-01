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
    "NumberField",
    "PanelActionButton",
    "PanelSectionHeader",
    "PanelSeparator",
    "PanelSlider",
    "PanelToolTip",
    "TextField",
    "ToggleSwitch",
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
tab_start = dashboard.index('model: ["OVERVIEW", "CALENDAR", "TOOLS"]')
tab_end = dashboard.index("// ── TODAY", tab_start)
tab_contract = dashboard[tab_start:tab_end]
if "ControlButton {" not in tab_contract:
    raise SystemExit("Dashboard tabs no longer use the canonical ControlButton")
for legacy in ("tabHover", "tabTap", "Theme.controlFill("):
    if legacy in tab_contract:
        raise SystemExit(f"Dashboard tab contract regressed to manual state handling: {legacy}")
if "component Action: DashboardAction" not in dashboard:
    raise SystemExit("Dashboard no longer uses the testable DashboardAction component")
dashboard_action = (ROOT / "shell/Menu/DashboardAction.qml").read_text(encoding="utf-8")
for snippet in (
    "InteractiveSurface {",
    "accessibleName: label",
    "onTriggered: if (run) run()",
    "id: rightHint",
    "onRightTriggered: root.triggerSecondary()",
    "function activateFromPointer(position, button)",
    "root.pointerInsideSecondary(position)",
):
    if snippet not in dashboard_action:
        raise SystemExit(f"Dashboard action accessibility contract is incomplete: {snippet}")
for snippet in (
    "rightLabel: \"Install system updates\"",
    "rightLabel: \"Install desktop updates\"",
    "rightLabel: \"Toggle screen recording\"",
    "rightLabel: \"Next theme\"",
):
    if snippet not in dashboard:
        raise SystemExit(f"Dashboard secondary action label is missing: {snippet}")
if "component Action: Rectangle" in dashboard:
    raise SystemExit("Dashboard actions regressed to manual Rectangle controls")
for snippet in (
    "dockedTop: true",
    'model: ["OVERVIEW", "CALENDAR", "TOOLS"]',
    "opacity: box.opacity * 0.45",
):
    if snippet not in dashboard:
        raise SystemExit(f"Dashboard bar-extension contract is incomplete: {snippet}")
for removed in ("// ── MEDIA", "MediaService.player?.trackArtUrl"):
    if removed in dashboard:
        raise SystemExit(f"Dashboard dedicated media page returned: {removed}")

desktop_ipc = (ROOT / "shell/Ipc/DesktopIpc.qml").read_text(encoding="utf-8")
data_ipc = (ROOT / "shell/Ipc/DataIpc.qml").read_text(encoding="utf-8")
if 'const names = ["overview", "calendar", "tools"]' not in desktop_ipc:
    raise SystemExit("Dashboard IPC no longer exposes the three-page navigation")
if '"media": 0' not in desktop_ipc or 'target: "music"' not in data_ipc:
    raise SystemExit("Legacy media entry points no longer route to the overview")

agent_center = (ROOT / "shell/Menu/AgentCenter.qml").read_text(encoding="utf-8")
for snippet in (
    "dockedTop: true",
    'model: ["NOW", "WORK", "SETUP"]',
    "visible: root.page === 1 && (Agents.hermesJobs || []).length > 0",
    "visible: root.page === 2",
    'Line { text: root.page === 0 ? "CURRENT SESSION" : "HERMES"',
    'model: (Agents.hermes.sessions || []).slice(0, 2)',
    "opacity: box.opacity * 0.45",
):
    if snippet not in agent_center:
        raise SystemExit(f"Agent Center bar-extension contract is incomplete: {snippet}")
for removed in (
    '"RESOURCES"', 'Line { text: "IN  "', 'model: Agents.projects',
    'text: "LIVE SESSIONS"', 'text: "MODEL ROUTING"',
    'text: "NEW WORKSPACE"', 'text: "LOCAL MODELS"',
):
    if removed in agent_center:
        raise SystemExit(f"Agent Center overview regained secondary detail: {removed}")

keys = (ROOT / "shell/Keys/KeysWindow.qml").read_text(encoding="utf-8")
for snippet in (
    "OverlaySurface {",
    "dockedTop: true",
    "PanelHead {",
    "SectionHeader {",
    "component ShortcutColumn: PanelSurface",
    "opacity: box.opacity * 0.45",
):
    if snippet not in keys:
        raise SystemExit(f"Keyboard shortcuts no longer follows the shared panel language: {snippet}")
for removed in ("DragHandler {", "x: (parent.width - width) / 2", "y: (parent.height - height) / 2"):
    if removed in keys:
        raise SystemExit(f"Keyboard shortcuts regressed to the detached legacy window: {removed}")

umbriel_config = (ROOT / "umbriel/nbshell.toml").read_text(encoding="utf-8")
if "show_cheatsheet = false" not in umbriel_config:
    raise SystemExit("Umbriel startup cheatsheet must remain disabled")
if 'mode = "dwindle"' not in umbriel_config:
    raise SystemExit("Umbriel must start new workspaces in Dwindle, not Scrolling")

modules = (ROOT / "shell/Settings/ModulesMenu.qml").read_text(encoding="utf-8")
for snippet in (
    "dockedTop: true",
    "PanelHead {",
    'title: "Bar modules"',
    "PanelSurface {",
    "SectionHeader {",
    "delegate: PanelRow {",
    "opacity: box.opacity * 0.45",
):
    if snippet not in modules:
        raise SystemExit(f"Modules menu no longer follows the shared panel language: {snippet}")
for removed in ('text: "MODULES"', 'text: "AVAILABLE"'):
    if removed in modules:
        raise SystemExit(f"Modules menu regressed to the legacy split-list header: {removed}")

overlay_surface = (ROOT / "shell/Widgets/OverlaySurface.qml").read_text(encoding="utf-8")
for snippet in ("property bool dockedTop: false", "property real dockOffset:"):
    if snippet not in overlay_surface:
        raise SystemExit(f"OverlaySurface docking contract is incomplete: {snippet}")

settings = (ROOT / "shell/Settings/SettingsMenu.qml").read_text(encoding="utf-8")
for snippet in (
    "PanelHead {",
    "SectionHeader {",
    "PanelRow {",
    "ActionButton {",
    "function groupIcon(name)",
):
    if snippet not in settings:
        raise SystemExit(f"Settings no longer follows the shared panel language: {snippet}")
if settings.count("PanelRow {") < 2:
    raise SystemExit("Settings navigation and values must both use shared PanelRow controls")

volume = (ROOT / "shell/Bar/Widgets/Volume.qml").read_text(encoding="utf-8")
volume_header = volume[:volume.index("popout: Component")]
if "popoutTakesKeyboard: true" not in volume_header:
    raise SystemExit("Audio popout no longer accepts keyboard focus")
if "initialFocusItem: outputVolume" not in volume:
    raise SystemExit("Audio popout no longer identifies its initial keyboard target")
for snippet in (
    'keyboardFocusable: true\n                    accessibleName: "Output volume"',
    'accessibleName: Audio.label(appRow.modelData) + " volume"',
    'accessibleName: Audio.micMuted ? "Unmute microphone" : "Mute microphone"',
):
    if snippet not in volume:
        raise SystemExit(f"Audio popout keyboard control contract is incomplete: {snippet}")
popout = (ROOT / "shell/Widgets/Popout.qml").read_text(encoding="utf-8")
for snippet in (
    "target.forceActiveFocus(reason)",
    "function focusIsInsideContent(item)",
    "function focusIsOnKeyboardControl(item)",
    "cursor === loader.item",
    "item.visible && item.enabled && item.activeFocusOnTab",
    "item.Accessible.focusable",
    "root.focusIsOnKeyboardControl(focused)",
    "focus: root.takesKeyboard",
    "attempts >= 60",
    "function recoverKeyboardFocusAfterPointerEntry()",
    "id: pointerFocusRecovery",
    "function onActiveChanged()",
    "root.recoverKeyboardFocusAfterPointerEntry()",
    "function onActiveFocusItemChanged()",
    "root.focusWindow.activeFocusItem",
    "Keys.onTabPressed",
    "Keys.onBacktabPressed",
    "root.enterKeyboardFocus(Qt.TabFocusReason)",
):
    if snippet not in popout:
        raise SystemExit(f"Keyboard popout initial-focus contract is incomplete: {snippet}")
if "focused && focused !== surface && focused !== target" in popout:
    raise SystemExit("Keyboard popout can still abandon initial focus on an internal proxy")
if "if (root.focusIsInsideContent(focused))" in popout:
    raise SystemExit("Keyboard popout can still treat a passive content proxy as a focused control")
level_bar = (ROOT / "shell/Widgets/LevelBar.qml").read_text(encoding="utf-8")
for snippet in (
    "Accessible.ignored: !keyboardFocusable",
    "readonly property int minimumValue: 0",
    "readonly property int maximumValue: maximum",
    "readonly property int stepSize: keyboardStep",
):
    if snippet not in level_bar:
        raise SystemExit(f"LevelBar accessibility contract is incomplete: {snippet}")
sink_start = volume.index("model: Audio.sinks")
sink_contract = volume[sink_start:]
if "PanelRow {" not in sink_contract:
    raise SystemExit("Audio sink rows no longer use the canonical PanelRow")
for legacy in ("id: mouse", "onTapped: Audio.setSink"):
    if legacy in sink_contract:
        raise SystemExit(f"Audio sink rows regressed to manual interaction: {legacy}")

themes = (ROOT / "shell/Bar/Widgets/Themes.qml").read_text(encoding="utf-8")
for snippet in (
    "active: Runtime.themePickerOpen",
    "onClicked: Runtime.themePickerOpen = true",
    "onWheel: delta => ThemeIndex.step",
):
    if snippet not in themes:
        raise SystemExit(f"Theme bar entry no longer routes to the standalone gallery: {snippet}")
if "popout: Component" in themes:
    raise SystemExit("Theme gallery regressed to an optional bar-owned popout")

theme_gallery = (ROOT / "shell/Wallpaper/ThemeGallery.qml").read_text(encoding="utf-8")
for snippet in (
    "MotionSurface {",
    "orientation: ListView.Horizontal",
    "snapMode: ListView.SnapOneItem",
    "highlightRangeMode: ListView.StrictlyEnforceRange",
    "property string query:",
    "model: root.filteredThemes",
    "Accessible.name: \"Search themes\"",
    "highlightMoveVelocity: -1",
    "ThemeIndex.apply(current.name)",
    "enabled: !Theme.reducedMotion",
):
    if snippet not in theme_gallery:
        raise SystemExit(f"Standalone theme gallery contract is incomplete: {snippet}")

shell_root = (ROOT / "shell/shell.qml").read_text(encoding="utf-8")
if "requested: Runtime.themePickerOpen" not in shell_root or "ThemeGallery {}" not in shell_root:
    raise SystemExit("Theme gallery is no longer owned by the permanent shell lifecycle")

wallpaper = (ROOT / "shell/Bar/Wallpaper.qml").read_text(encoding="utf-8")
for snippet in (
    "mask: Region { item: wallpaperInput }",
    "acceptedButtons: Qt.LeftButton",
    "onDoubleTapped: Runtime.wallpaperOpen = true",
    "acceptedButtons: Qt.RightButton",
    "onDoubleTapped: Runtime.themePickerOpen = true",
):
    if snippet not in wallpaper:
        raise SystemExit(f"Wallpaper desktop gesture contract is incomplete: {snippet}")

control = (ROOT / "shell/Bar/Widgets/Control.qml").read_text(encoding="utf-8")
panel_row_source = (ROOT / "shell/Widgets/PanelRow.qml").read_text(encoding="utf-8")
for snippet in (
    "default property alias overlayData: overlay.data",
    "property Item pointerActivationExclusion: null",
    "function activateFromPointer(position)",
):
    if snippet not in panel_row_source:
        raise SystemExit(f"PanelRow overlay interaction contract is incomplete: {snippet}")
for snippet in (
    "readonly property Item initialFocusItem: wifiRepeater.count > 0",
    "readonly property Item focusTarget: wifiRow",
    "id: vpnRepeater",
    "id: btRepeater",
    "id: wifiRow",
    "id: vpnRow",
    "id: btRow",
    "accessibleName: entry.modelData.name",
    "accessibleName: vpnRow.modelData.name",
    "accessibleName: Bt.label(btRow.modelData)",
    "pointerActivationExclusion: removeButton",
):
    if snippet not in control:
        raise SystemExit(f"Control Center row migration contract is incomplete: {snippet}")
for legacy in ("id: wifiMouse", "id: vpnMouse", "id: btMouse"):
    if legacy in control:
        raise SystemExit(f"Control Center rows regressed to manual interaction: {legacy}")

kde_connect = (ROOT / "shell/Bar/Widgets/KdeConnect.qml").read_text(encoding="utf-8")
for snippet in (
    "popoutTakesKeyboard: true",
    "readonly property Item initialFocusItem: deviceRepeater.count > 0",
    "function revealItem(item)",
    "id: devRow",
    "pointerActivationExclusion: pairButton",
    "accessibleName: devRow.modelData.name",
    'accessibleName: "Remote commands"',
    "id: commandRow",
    "accessibleName: commandRow.modelData.name",
    "scroll.revealItem(commandRow)",
):
    if snippet not in kde_connect:
        raise SystemExit(f"KDE Connect row migration contract is incomplete: {snippet}")
for legacy in ("id: unpairHover", "id: cmdRowMouse", "id: cmdHover"):
    if legacy in kde_connect:
        raise SystemExit(f"KDE Connect rows regressed to manual interaction: {legacy}")

notification_card = (ROOT / "shell/Notifications/NotificationCard.qml").read_text(encoding="utf-8")
notification_center = (ROOT / "shell/Notifications/NotificationCenter.qml").read_text(encoding="utf-8")
notification_bar = (ROOT / "shell/Bar/Widgets/Notifications.qml").read_text(encoding="utf-8")
for snippet in (
    "Accessible.role: showActions ? Accessible.ListItem : Accessible.Button",
    "Accessible.onPressAction: if (!showActions) root.opened()",
    "signal focusEntered()",
    "onActiveFocusChanged: if (activeFocus) focusEntered()",
    "onActiveFocusChanged: if (activeFocus) root.focusEntered()",
    "Keys.onReturnPressed",
    "Keys.onDeletePressed",
    "TapHandler { onTapped: root.removed() }",
):
    if snippet not in notification_card:
        raise SystemExit(f"NotificationCard accessibility contract is incomplete: {snippet}")
if "removeRequested()" in notification_card:
    raise SystemExit("NotificationCard hover dismiss calls a missing signal")
for snippet in (
    "function openSelected()",
    "notificationCards.itemAt(root.selected)",
    "FocusScroll.contentYForFocus",
    "root.openSelected()",
    "else handled = false",
    "onShownChanged: {",
    "onFocusEntered: root.selected = index",
):
    if snippet not in notification_center:
        raise SystemExit(f"Notification Center keyboard contract is incomplete: {snippet}")
if "shown.length - 2" in notification_center:
    raise SystemExit("Notification Center double-clamps selection after deletion")
for snippet in (
    "popoutTakesKeyboard: true",
    "readonly property Item initialFocusItem: notificationsTab",
    "component HeaderAction: ActionButton",
    "accessibleSelected: active",
    "function revealItem(item)",
    "onFocusEntered: historyView.revealItem(historyCard)",
):
    if snippet not in notification_bar:
        raise SystemExit(f"Notification bar popout keyboard contract is incomplete: {snippet}")

required_accessible_names = {
    ROOT / "shell/Ui/PanelSlider.qml": [
        'property string accessibleName: ""',
        'property string accessibleDescription: ""',
        'Accessible.role: Accessible.Slider',
        'Accessible.focusable: enabled',
        'Accessible.onIncreaseAction: root.commitStep(1)',
        'Accessible.onDecreaseAction: root.commitStep(-1)',
        'activeFocusOnTab: false',
    ],
    ROOT / "shell/Ui/TextField.qml": [
        'property string accessibleName: ""',
        'property string accessibleDescription: ""',
        'Accessible.name: accessibleName.length > 0 ? accessibleName : placeholderText',
        'Accessible.description: accessibleDescription',
        'Accessible.passwordEdit: password',
    ],
    ROOT / "plugins/omamail/components/AppMenu.qml": [
        'accessibleName: "More options"',
    ],
    ROOT / "plugins/omamail/components/SearchBar.qml": [
        'accessibleName: "Search mail"',
        'accessibleName: "Clear search"',
    ],
    ROOT / "plugins/omamail/components/ComposeView.qml": [
        '"Change sender. Current sender: "',
        '"Hide Cc field"',
        '"Show Cc field"',
        'accessibleName: "To"',
        'accessibleName: "Cc"',
        'accessibleName: "Subject"',
    ],
    ROOT / "plugins/omamail/components/SetupPage.qml": [
        'accessibleName: "Google OAuth client ID"',
        'accessibleName: "Google OAuth client secret"',
    ],
    ROOT / "plugins/omamail/components/ImapSetupPage.qml": [
        'accessibleName: "Email address"',
        'accessibleName: "Mailbox password"',
        'accessibleName: "IMAP server"',
        'accessibleName: "IMAP port"',
        'accessibleName: "SMTP server"',
        'accessibleName: "SMTP port"',
        'accessibleName: "Username"',
    ],
    ROOT / "plugins/ytmusic/Panel.qml": [
        'accessibleName: "Playlist name"',
        'accessibleName: "Stop when idle"',
        'accessibleName: "Seek"',
        'accessibleName: "Volume " + Api.volumeCaption(sourceValue)',
        'step: 10',
    ],
}
for path, snippets in required_accessible_names.items():
    source = path.read_text(encoding="utf-8")
    for snippet in snippets:
        if snippet not in source:
            raise SystemExit(f"Missing explicit accessibility name in {path}: {snippet}")

design_doc = (ROOT / "DESIGN.md").read_text(encoding="utf-8")
agent_guide = (ROOT / "AGENTS.md").read_text(encoding="utf-8")
plugin_docs = (ROOT / "docs/plugin-development.md").read_text(encoding="utf-8")
for snippet in (
    "qs.Common` and `qs.Widgets` are the native nbshell API",
    "nbshell plugin new io.github.user.example --kind panel",
    "nbshell plugin design-check . --strict",
    "`nbshell ui-gallery` is the living reference",
):
    if snippet not in design_doc:
        raise SystemExit(f"Stable design contract is incomplete: {snippet}")
for snippet in ("Read the repository-root `DESIGN.md`", "Add a real component to `nbshell ui-gallery`"):
    if snippet not in agent_guide:
        raise SystemExit(f"Agent design guidance is incomplete: {snippet}")
for snippet in ("## Start from the scaffold", "### Design check", "nbshell-design: allow-hardcoded-color"):
    if snippet not in plugin_docs:
        raise SystemExit(f"Plugin authoring guide is incomplete: {snippet}")

ui_gallery = (ROOT / "shell/Settings/UiGallery.qml").read_text(encoding="utf-8")
for snippet in (
    'text: "Plugin design contract"',
    'text: "NATIVE  qs.Common + qs.Widgets"',
    'Theme.motionEffectsDefault',
    'text: "SCAFFOLD  nbshell plugin new <id> --kind <kind>"',
    "Keys.priority: Keys.AfterItem",
    "event.key === Qt.Key_PageDown",
    "event.key === Qt.Key_End",
    "viewport.contentY = maximum",
):
    if snippet not in ui_gallery:
        raise SystemExit(f"UI Gallery no longer exposes the plugin design contract: {snippet}")

print(
    "Design-system adapter contracts: OK "
    f"({len(used_theme_members)} Theme members, {len(exported_ui_types)} Ui exports)"
)
