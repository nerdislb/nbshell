#!/usr/bin/env bash
set -euo pipefail

assert_not_grep() {
    local status
    if grep "$@"; then
        printf 'Unexpected grep match: %s\n' "$*" >&2
        return 1
    else
        status=$?
        if [ "$status" -ne 1 ]; then
            printf 'grep failed with status %s: %s\n' "$status" "$*" >&2
            return "$status"
        fi
    fi
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

grep -Fq 'motionProfile' "$ROOT/shell/Common/Config.qml"
grep -Fq 'readonly property bool reducedMotion' "$ROOT/shell/Common/Theme.qml"
grep -Fq 'readonly property int motionEnter' "$ROOT/shell/Common/Theme.qml"
grep -Fq 'readonly property int motionExit' "$ROOT/shell/Common/Theme.qml"
grep -Fq '"values": ["reduced", "standard", "expressive"]' "$ROOT/shell/Settings/SettingsMenu.qml"
grep -Fq 'box.dismiss(() => Runtime.launcherOpen = false)' "$ROOT/shell/Launcher/Launcher.qml"
grep -Fq 'frame.dismiss(() => Runtime.storeOpen = false)' "$ROOT/shell/Store/StoreWindow.qml"
grep -Fq 'highlightMoveDuration: Theme.motionMove' "$ROOT/shell/Wallpaper/WallpaperPicker.qml"
assert_not_grep -Fq 'Canvas {' "$ROOT/shell/Widgets/MotionSurface.qml"
grep -Fq 'Behavior on visualOffsetY' "$ROOT/shell/Widgets/MotionSurface.qml"
grep -Fq 'surface.enter();' "$ROOT/shell/Widgets/Popout.qml"
grep -Fq 'surface.dismiss(root.finalizeClose)' "$ROOT/shell/Widgets/Popout.qml"
grep -Fq 'previous.closeImmediately();' "$ROOT/shell/Widgets/Popout.qml"
grep -Fq 'function show(component, keyboard, delayOverride)' "$ROOT/shell/Widgets/Popout.qml"
grep -Fq 'const replacingContent = visible && loader.sourceComponent !== contentComponent;' "$ROOT/shell/Widgets/Popout.qml"
grep -Fq 'id: popupLoader' "$ROOT/shell/Widgets/Cell.qml"
grep -Fq 'popupLoader.item.show(root.popout, root.popoutTakesKeyboard, -1);' "$ROOT/shell/Widgets/Cell.qml"
grep -Fq 'popupLoader.item.show(root.preview, false, 700);' "$ROOT/shell/Widgets/Cell.qml"
assert_not_grep -Fq 'id: previewLoader' "$ROOT/shell/Widgets/Cell.qml"
assert_not_grep -Fq 'id: popoutLoader' "$ROOT/shell/Widgets/Cell.qml"
grep -Fq 'surface.cancelTransition();' "$ROOT/shell/Widgets/Popout.qml"
grep -Fq 'function cancelTransition()' "$ROOT/shell/Widgets/MotionSurface.qml"
assert_not_grep -Fq 'previous.close(() =>' "$ROOT/shell/Widgets/Popout.qml"
grep -Fq 'root.close()' "$ROOT/shell/Widgets/Popout.qml"
grep -Fq 'Runtime.claimPopout(Runtime.popoutToken, root.popupOutput)' "$ROOT/shell/Widgets/Cell.qml"
grep -Fq 'root.externalPopoutEligible && root.popout !== null' "$ROOT/shell/Widgets/Cell.qml"
grep -Fq 'externalPopoutEligible: win.expandedWidgetNames.indexOf(modelData) < 0' "$ROOT/shell/Bar/Bar.qml"
grep -Fq 'Runtime.requestPopout("volume", Compositor.focusedOutput)' "$ROOT/shell/Ipc/DeviceIpc.qml"
grep -Fq 'Runtime.requestPopout("control", Compositor.focusedOutput)' "$ROOT/shell/Ipc/DesktopIpc.qml"
assert_not_grep -Fq 'function onAudioPanelOpenChanged()' "$ROOT/shell/Bar/Widgets/Volume.qml"
assert_not_grep -Fq 'function onControlOpenChanged()' "$ROOT/shell/Bar/Widgets/Control.qml"
grep -Fq 'autoEnter: false' "$ROOT/shell/Widgets/Popout.qml"
grep -Fq 'readonly property int collapseIndex: visibleWidgets.indexOf("sep")' "$ROOT/shell/Bar/Bar.qml"
grep -Fq 'Config.set("rightSectionExpanded", !Config.rightSectionExpanded)' "$ROOT/shell/Bar/Bar.qml"
grep -Fq 'width: visible && Config.rightSectionExpanded ? rightSectionRow.implicitWidth : 0' "$ROOT/shell/Bar/Bar.qml"
grep -Fq 'Behavior on width' "$ROOT/shell/Bar/Bar.qml"
grep -Fq 'readonly property bool rightSectionExpanded' "$ROOT/shell/Common/Config.qml"
grep -Fq 'readonly property int motionSpatialDefault' "$ROOT/shell/Common/Theme.qml"
grep -Fq 'readonly property int motionEffectsDefault' "$ROOT/shell/Common/Theme.qml"
grep -Fq 'requested: Runtime.notificationCenterOpen' "$ROOT/shell/shell.qml"
grep -Fq 'requested: Runtime.settingsOpen' "$ROOT/shell/shell.qml"
grep -Fq 'requested: Runtime.powerOpen' "$ROOT/shell/shell.qml"
grep -Fq 'property bool mounted: false' "$ROOT/shell/Widgets/MotionLoader.qml"
grep -Fq 'item.requestClose(() => root.finishClose(closeGeneration))' "$ROOT/shell/Widgets/MotionLoader.qml"
grep -Fq 'Runtime.closeLauncher()' "$ROOT/shell/Ipc/DesktopIpc.qml"
grep -Fq 'Runtime.closeMenu()' "$ROOT/shell/Ipc/DesktopIpc.qml"
grep -Fq 'Component.onCompleted: Runtime.launcherController = root' "$ROOT/shell/Launcher/Launcher.qml"
grep -Fq 'Component.onCompleted: Runtime.menuController = root' "$ROOT/shell/Menu/Menu.qml"

python3 - "$ROOT/shell" <<'PY'
import pathlib, re, sys
root = pathlib.Path(sys.argv[1])
qml = list(root.rglob("*.qml"))
hardcoded = []
for path in qml:
    # The standalone session-lock runtime deliberately does not import the
    # reloadable desktop Theme singleton while it owns ext-session-lock.
    if path.relative_to(root).parts[0] == "lock":
        continue
    for number in re.findall(r"\bduration:\s*(\d+)", path.read_text(encoding="utf-8")):
        hardcoded.append((path.relative_to(root).as_posix(), number))
assert not hardcoded, f"hard-coded motion durations remain: {hardcoded}"
for relative in (
    "Ui/Button.qml", "Widgets/IconText.qml",
    "Bar/Widgets/AiFill.qml", "Bar/Widgets/Workspaces.qml",
):
    text = (root / relative).read_text(encoding="utf-8")
    assert (
        "loops: Animation.Infinite" not in text
        or re.search(r"!\s*(?:Common\.)?Theme\.reducedMotion", text)
    ), relative
PY

grep -Fq 'import qs.Common as Common' "$ROOT/shell/Ui/Button.qml"
grep -Fq 'duration: Common.Theme.motionLoopFast' "$ROOT/shell/Ui/Button.qml"

grep -Fq '"nbshell-motion.toml"' "$ROOT/umbriel/nbshell.toml"
grep -Fq 'function onMotionProfileChanged()' "$ROOT/shell/Services/ThemeExport.qml"
grep -Fq 'return "# Managed by nbshell motion settings.\n[animation]\nenabled = false\n"' "$ROOT/shell/Services/ThemeExport.qml"

python3 - "$ROOT/umbriel/nbshell-motion.toml" <<'PY'
import sys, tomllib
with open(sys.argv[1], "rb") as handle:
    config = tomllib.load(handle)
motion = config["animation"]
assert motion["enabled"] is True
assert motion["duration_ms"] == 240
assert motion["beziers"]["nbshell_enter"] == [0.215, 0.61, 0.355, 1.00]
assert motion["windows_in"] == {
    "enabled": True, "duration_ms": 300, "curve": "nbshell_enter",
    "style": "popin", "scale": 0.94,
}
assert motion["windows_out"] == {
    "enabled": True, "duration_ms": 120, "curve": "linear", "style": "fade",
}
assert motion["windows_move"]["curve"] == "snappy"
assert motion["workspaces"]["duration_ms"] == 240
assert motion["overview"]["duration_ms"] == 260
assert motion["border"]["enabled"] is True
assert motion["layers"]["enabled"] is False
PY

if command -v umbriel >/dev/null; then
    stage="$(mktemp -d)"
    trap 'rm -rf "$stage"' EXIT
    cp "$ROOT/umbriel/"*.toml "$stage/"
    : >"$stage/nbshell-outputs.toml"
    umbriel validate -c "$stage/nbshell.toml" >/dev/null
fi

echo "Motion profiles and lifecycle: OK"
