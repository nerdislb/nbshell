#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

grep -Fq 'motionProfile' "$ROOT/shell/Common/Config.qml"
grep -Fq 'readonly property bool reducedMotion' "$ROOT/shell/Common/Theme.qml"
grep -Fq 'readonly property int motionEnter' "$ROOT/shell/Common/Theme.qml"
grep -Fq 'readonly property int motionExit' "$ROOT/shell/Common/Theme.qml"
grep -Fq '"values": ["reduced", "standard", "expressive"]' "$ROOT/shell/Settings/SettingsMenu.qml"
grep -Fq 'box.dismiss(() => Runtime.launcherOpen = false)' "$ROOT/shell/Launcher/Launcher.qml"
grep -Fq 'frame.dismiss(() => Runtime.storeOpen = false)' "$ROOT/shell/Store/StoreWindow.qml"
grep -Fq 'highlightMoveDuration: Theme.motionMove' "$ROOT/shell/Wallpaper/WallpaperPicker.qml"
! grep -Fq 'Canvas {' "$ROOT/shell/Widgets/MotionSurface.qml"
grep -Fq 'Behavior on visualOffsetY' "$ROOT/shell/Widgets/MotionSurface.qml"
grep -Fq 'surface.enter();' "$ROOT/shell/Widgets/Popout.qml"
grep -Fq 'readonly property int collapseIndex: Config.rightWidgets.indexOf("sep")' "$ROOT/shell/Bar/Bar.qml"
grep -Fq 'Config.set("rightSectionExpanded", !Config.rightSectionExpanded)' "$ROOT/shell/Bar/Bar.qml"
grep -Fq 'width: visible && Config.rightSectionExpanded ? rightSectionRow.implicitWidth : 0' "$ROOT/shell/Bar/Bar.qml"
grep -Fq 'Behavior on width' "$ROOT/shell/Bar/Bar.qml"
grep -Fq 'readonly property bool rightSectionExpanded' "$ROOT/shell/Common/Config.qml"

echo "Motion profiles and lifecycle: OK"
