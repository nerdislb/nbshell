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
    "rightLabel: \"Toggle screen recording\"",
    "rightLabel: \"Next theme\"",
):
    if snippet not in dashboard:
        raise SystemExit(f"Dashboard secondary action label is missing: {snippet}")
update_panel = (ROOT / "shell/Widgets/UpdatePanel.qml").read_text(encoding="utf-8")
update_widget = (ROOT / "shell/Bar/Widgets/Updates.qml").read_text(encoding="utf-8")
bar = (ROOT / "shell/Bar/Bar.qml").read_text(encoding="utf-8")
if "import qs.Ui" not in update_panel:
    raise SystemExit("Unified update panel no longer imports the PanelSeparator module")
for snippet in (
    'title: qsTr("System packages")',
    'text: qsTr("Packages")',
    'text: qsTr("Install updates")',
    'append(Updates.repo, qsTr("REPOSITORY"))',
    'append(Updates.aur, qsTr("AUR"))',
    'append(Updates.flatpak, qsTr("FLATPAK"))',
    'title: qsTr("nbshell")',
    'title: qsTr("Umbriel stack")',
    "Updates.update()",
    "ShellUpdates.install()",
    "ShellUpdates.installCompositor()",
    "ShellUpdates.compositorBlockedReason",
    'return qsTr("BLOCKED")',
):
    if snippet not in update_panel:
        raise SystemExit(f"Unified update panel contract is incomplete: {snippet}")
if "shown: root.availableKinds > 0" not in update_widget:
    raise SystemExit("Automatic update signal no longer follows all available update kinds")
for snippet in (
    "withUpdateIndicator(Config.collapsedWidgets, true)",
    'withUpdateIndicator(Config.leftWidgets, expandedClockGroup === "left")',
    'withUpdateIndicator(Config.centerWidgets, expandedClockGroup === "center")',
    'withUpdateIndicator(Config.rightWidgets, expandedClockGroup === "right")',
    'widget === "clock"',
):
    if snippet not in bar:
        raise SystemExit(f"Clock-adjacent update signal contract is incomplete: {snippet}")
if dashboard.count("UpdatePanel {") != 1 or "shellUpdatesOpen" in dashboard:
    raise SystemExit("Dashboard regressed to separate system and desktop updater surfaces")
modal_surface = (ROOT / "shell/Widgets/ModalSurface.qml").read_text(encoding="utf-8")
for snippet in (
    "ModalSurface {",
    "blockedItem: dashboardContent",
    "initialFocusItem: updatePanel.initialFocusItem",
):
    if snippet not in dashboard:
        raise SystemExit(f"Dashboard modal update contract is incomplete: {snippet}")
for snippet in (
    "Accessible.role: Accessible.Dialog",
    'property: "enabled"',
    "Keys.onEscapePressed",
    "Keys.onTabPressed",
    "Keys.onBacktabPressed",
    "root.containsFocusItem(next)",
):
    if snippet not in modal_surface:
        raise SystemExit(f"Shared modal contract is incomplete: {snippet}")
for snippet in (
    "popoutTakesKeyboard: true",
    "property var closePopout: null",
    "property Item initialFocusItem: refreshButton",
):
    if snippet not in update_widget + update_panel:
        raise SystemExit(f"Update keyboard/popout contract is incomplete: {snippet}")
plugins_service = (ROOT / "shell/Services/Plugins.qml").read_text(encoding="utf-8")
if '"id": "updates"' in plugins_service:
    raise SystemExit("Automatic update signal is still exposed as a movable module")
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
for snippet in (
    "InteractiveSurface {",
    "accessibleName: modelData.name",
    "defaultAgentButton",
    "brainRow.activate();",
    "transactionRow.activate();",
    "hermesSession.activate();",
    "FocusScroll.contentYForFocus(",
    '["apply", "install", "push", "reject", "cancel"]',
    '"hint": "API bridge"',
):
    if snippet not in agent_center:
        raise SystemExit(f"Agent Center keyboard action contract is incomplete: {snippet}")
if '"hint": "agy bridge"' in agent_center:
    raise SystemExit("Agent Center regained the broken Gemini bridge label")

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

system_hub = (ROOT / "shell/Menu/SystemHub.qml").read_text(encoding="utf-8")
system_hub_backend = (ROOT / "shell/scripts/system-hub.py").read_text(encoding="utf-8")
if "if (Array.isArray(command))" not in system_hub or "Quickshell.execDetached(command.map(value => String(value)))" not in system_hub:
    raise SystemExit("System Hub no longer supports argv-safe detached actions")
for unsafe in ('"detached:xdg-open " + link', '"detached:python3 " + str(Path(__file__).resolve())'):
    if unsafe in system_hub_backend:
        raise SystemExit(f"System Hub dynamic action returned to shell-string construction: {unsafe}")
if 'def arch_news_link(value):' not in system_hub_backend or 'host.endswith(".archlinux.org")' not in system_hub_backend:
    raise SystemExit("System Hub Arch News links are no longer origin constrained")
for snippet in (
    "InteractiveSurface {",
    "accessibleName: itemBlock.modelData.label",
    "row.activate();",
    "systemScroll.contentY = FocusScroll.contentYForFocus(",
    'text: "OPEN EXTERNALLY"',
):
    if snippet not in system_hub:
        raise SystemExit(f"System Hub keyboard action contract is incomplete: {snippet}")

notes_window = (ROOT / "shell/Notes/NotesWindow.qml").read_text(encoding="utf-8")
for snippet in (
    "delegate: InteractiveSurface {",
    "accessibleSelected:",
    "noteList.positionViewAtIndex(index, ListView.Contain)",
    "function requestNewNote()",
    "function requestEditNote(note)",
    "function requestDelete()",
    'text: root.confirmDelete ? "CONFIRM DELETE" : "DELETE"',
    "Accessible.role: Accessible.EditableText",
):
    if snippet not in notes_window:
        raise SystemExit(f"Notes keyboard/safety contract is incomplete: {snippet}")

calculator_window = (ROOT / "shell/Calculator/CalculatorWindow.qml").read_text(encoding="utf-8")
for snippet in (
    "function copyResult()",
    "function keyName(action, label)",
    "ControlButton {",
    "accessibleName: root.keyName(modelData.action, modelData.label)",
    "onTriggered: root.activate(modelData.action)",
):
    if snippet not in calculator_window:
        raise SystemExit(f"Calculator keyboard action contract is incomplete: {snippet}")

shopping_window = (ROOT / "shell/Shopping/ShoppingListWindow.qml").read_text(encoding="utf-8")
shopping_service = (ROOT / "shell/Services/ShoppingDraft.qml").read_text(encoding="utf-8")
config = (ROOT / "shell/Common/Config.qml").read_text(encoding="utf-8")
for snippet in (
    "OverlaySurface {",
    "PanelHead {",
    "PanelSurface {",
    "ActionButton {",
    "Accessible.name: \"Shopping list items\"",
    "ShoppingDraft.send(root.targetGroup, root.message)",
    "function onSendFinished(success, message)",
    "height: parent.height - header.height - separator.height - footer.height - parent.spacing * 3",
):
    if snippet not in shopping_window:
        raise SystemExit(f"Shopping-list surface contract is incomplete: {snippet}")
for snippet in (
    "atomicWrites: true",
    "readonly property bool sending: sendProc.running",
    '"--to", String(target)',
    "write(pendingMessage)",
    "sendProc.stdinEnabled = true",
    "onExited: code => Qt.callLater(() => root.finishSend(code))",
):
    if snippet not in shopping_service:
        raise SystemExit(f"Shopping-list service contract is incomplete: {snippet}")
if "Process {" in shopping_window or "sh -c" in shopping_service:
    raise SystemExit("Shopping-list sending escaped its permanent safe-argv service")
if '"--message"' in shopping_service:
    raise SystemExit("Shopping-list draft must travel over stdin, not as a --message argument")
if "LazyLoader { active: Runtime.shoppingListOpen; ShoppingListWindow {} }" not in shell_root:
    raise SystemExit("Shopping-list window is no longer lazy-loaded by the shell")
if 'readonly property string targetGroup: Config.shoppingListTarget' not in shopping_window:
    raise SystemExit("Shopping-list target is no longer read from public configuration")
if 'readonly property string shoppingListTarget: String(value("shoppingListTarget", "Einkauf")).trim() || "Einkauf"' not in config:
    raise SystemExit("Shopping-list target configuration contract is missing")

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

phone_panel = (ROOT / "shell/Bar/Widgets/PhonePanel.qml").read_text(encoding="utf-8")
nearby_panel = (ROOT / "shell/Bar/Widgets/NearbyPanel.qml").read_text(encoding="utf-8")
for snippet in (
    "PhonePanel {",
    "NearbyPanel {",
    "sectionSpacing: panel.spacing",
    "active: root.popoutVisible",
    "shown: Kdeconnect.enabled || Phone.available || Nearby.enabled",
):
    if snippet not in kde_connect:
        raise SystemExit(f"KDE Connect subpanel composition contract is incomplete: {snippet}")
for legacy in ('label: "PHONE MIRROR · NBPHONE"', 'label: "NEARBY · LOCALSEND"'):
    if legacy in kde_connect:
        raise SystemExit(f"KDE Connect still owns an extracted subpanel: {legacy}")
for snippet in (
    "readonly property bool available: Phone.available",
    "if (root.active)",
    "Phone.refresh()",
    'label: "PHONE MIRROR · NBPHONE"',
    'label: "PHONE CAMERA · WEBCAM"',
):
    if snippet not in phone_panel:
        raise SystemExit(f"Phone subpanel contract is incomplete: {snippet}")
for snippet in (
    "readonly property bool available: Nearby.enabled",
    "onActiveChanged: Nearby.wanted = root.active",
    "Component.onDestruction",
    'label: "NEARBY · LOCALSEND"',
    "Nearby.sendText",
    "Nearby.sendLastShot",
):
    if snippet not in nearby_panel:
        raise SystemExit(f"Nearby subpanel contract is incomplete: {snippet}")

notification_card = (ROOT / "shell/Notifications/NotificationCard.qml").read_text(encoding="utf-8")
notification_center = (ROOT / "shell/Notifications/NotificationCenter.qml").read_text(encoding="utf-8")
notification_bar = (ROOT / "shell/Bar/Widgets/Notifications.qml").read_text(encoding="utf-8")
for snippet in (
    "Accessible.role: showActions ? Accessible.ListItem : Accessible.AlertMessage",
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

compositor = (ROOT / "shell/Services/Compositor.qml").read_text(encoding="utf-8")
if "readonly property var focusedScreen: Quickshell.screens.find(" not in compositor:
    raise SystemExit("Overlay surfaces no longer share the compositor-focused output")
for relative in (
    "shell/Launcher/Launcher.qml",
    "shell/Menu/Menu.qml",
    "shell/Power/PowerMenu.qml",
    "shell/Capture/CaptureMenu.qml",
    "shell/Notifications/NotificationCenter.qml",
    "shell/Settings/SettingsWindow.qml",
    "shell/Wallpaper/WallpaperPicker.qml",
):
    source = (ROOT / relative).read_text(encoding="utf-8")
    if "screen: Compositor.focusedScreen" not in source:
        raise SystemExit(f"Overlay does not follow the focused output: {relative}")

notify = (ROOT / "shell/Services/Notify.qml").read_text(encoding="utf-8")
for snippet in (
    "readonly property int lowPopupDuration: 5000",
    'readonly property int normalPopupDuration: Config.value("notifyTimeout", 8000)',
    "function popupDuration(entry)",
    "function setPopupHovered(key, hovered)",
    "root.consumePopupLifetime(entry.key, interval)",
    "const snapshot = root.popups.slice()",
    'app === "nbshell-action"',
    '"expireTimeout": notification.expireTimeout ?? 0',
    'readonly property int maxPopupCount: Config.value("notifyMaxPopups", 5)',
    'function release(entry, reason)',
    '.slice(0, Math.max(1, root.maxPopupCount))',
    'const keepHistory = showPopup || !root.isEphemeral(notification)',
    'return transient || app === "nbshell-action";',
    'notification.id + ":" + (++root.keySerial)',
):
    if snippet not in notify:
        raise SystemExit(f"Omarchy-compatible notification timing contract is incomplete: {snippet}")
if notify.count("root.consumePopupLifetime(entry.key, interval)") != 1:
    raise SystemExit("Notification lifetime must be consumed once by the service-owned clock")
if 'return transient || app === "notify-send"' in notify:
    raise SystemExit("Non-transient notify-send notifications must remain in history during DND")

popups = (ROOT / "shell/Notifications/Popups.qml").read_text(encoding="utf-8")
notification_toast = (ROOT / "shell/Notifications/NotificationToast.qml").read_text(encoding="utf-8")
for snippet in (
    "NotificationToast {",
    "entry: modelData",
    "onRemoved: Notify.dismissPopup(modelData.key)",
):
    if snippet not in popups:
        raise SystemExit(f"Notification popup host contract is incomplete: {snippet}")
for snippet in (
    "Notify.setPopupHovered(root.entry.key, hovered)",
    "Component.onDestruction",
    "PanelSurface {",
    "Accessible.role: Accessible.AlertMessage",
    "Accessible.onPressAction: root.activate()",
):
    if snippet not in notification_toast:
        raise SystemExit(f"Notification toast contract is incomplete: {snippet}")
if "consumePopupLifetime" in notification_toast or "Timer {" in notification_toast:
    raise SystemExit("Per-output notification toasts must not own the shared lifetime clock")

menu_view = (ROOT / "shell/Widgets/MenuView.qml").read_text(encoding="utf-8")
tray = (ROOT / "shell/Bar/Widgets/Tray.qml").read_text(encoding="utf-8")
for snippet in (
    "Accessible.role: Accessible.MenuItem",
    "Keys.onRightPressed",
    "Keys.onLeftPressed",
    "readonly property Item initialFocusItem",
):
    if snippet not in menu_view:
        raise SystemExit(f"Tray submenu keyboard contract is incomplete: {snippet}")
if "takesKeyboard: true" not in tray or "initialFocusItem: menu.initialFocusItem" not in tray:
    raise SystemExit("Tray menu no longer transfers keyboard focus into the DBus menu")

cell = (ROOT / "shell/Widgets/Cell.qml").read_text(encoding="utf-8")
for snippet in (
    "Accessible.role: root.clickable ? Accessible.Button : Accessible.StaticText",
    "Accessible.onPressAction: root.activatePrimary()",
    "function activatePrimary()",
    "Keys.onSpacePressed",
    "root.activatePrimary();",
):
    if snippet not in cell:
        raise SystemExit(f"Bar cells no longer share pointer, keyboard, and accessibility activation: {snippet}")

segments = (ROOT / "shell/Widgets/Segments.qml").read_text(encoding="utf-8")
for snippet in (
    "InteractiveSurface {",
    "accessibleRole: Accessible.RadioButton",
    "Keys.onLeftPressed",
    "Keys.onRightPressed",
    "elide: Text.ElideRight",
):
    if snippet not in segments:
        raise SystemExit(f"Segmented controls lost keyboard or adaptive behavior: {snippet}")

power_menu = (ROOT / "shell/Power/PowerMenu.qml").read_text(encoding="utf-8")
notification_center = (ROOT / "shell/Notifications/NotificationCenter.qml").read_text(encoding="utf-8")
if "property int confirmIndex: -1" not in power_menu or "Enter again confirms" not in power_menu:
    raise SystemExit("Destructive session actions no longer require confirmation")
if "function requestClear()" not in notification_center or "Ctrl+c twice clears" not in notification_center:
    raise SystemExit("Notification-center clear no longer shares a guarded confirmation path")

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
