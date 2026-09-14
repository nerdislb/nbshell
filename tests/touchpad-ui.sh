#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR="$(mktemp -d /tmp/nbshell-touchpad-ui.XXXXXX)"
# Keep captures and logs as review artifacts; never change the desktop config.
for dir in Common Commons Widgets Ui Services Touchpad; do ln -s "$ROOT/shell/$dir" "$TEST_DIR/$dir"; done
cp "$ROOT/tests/touchpad-ui.qml" "$TEST_DIR/shell.qml"
env -u WAYLAND_DISPLAY -u DISPLAY QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
    timeout 35s qs -p "$TEST_DIR/shell.qml" > "$TEST_DIR/result.log" 2>&1
cat "$TEST_DIR/result.log"
if rg -q 'FAIL!|QWARN|TypeError|ReferenceError|Error:|is not a type' "$TEST_DIR/result.log"; then exit 1; fi
rg -q 'TOUCHPAD_UI_PASS' "$TEST_DIR/result.log"
printf 'Artifacts: %s\n' "$TEST_DIR"
