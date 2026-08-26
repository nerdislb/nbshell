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

echo "Motion profiles and lifecycle: OK"
