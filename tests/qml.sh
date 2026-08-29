#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${QML_TEST_RUNNER:-/usr/lib/qt6/bin/qmltestrunner}"

if [[ ! -x $RUNNER ]]; then
    echo "Qt QML test runner is not available; skipping QML tests."
    exit 0
fi

python3 "$ROOT/tests/design-system-contracts.py"

imports="$(mktemp -d)"
trap 'rm -rf -- "$imports"' EXIT
mkdir -p "$imports/qs"
ln -s "$ROOT/tests/imports/qs/Common" "$imports/qs/Common"
ln -s "$ROOT/shell/Commons" "$imports/qs/Commons"
ln -s "$ROOT/shell/Ui" "$imports/qs/Ui"

qmllint_bin="${QMLLINT_BIN:-/usr/lib/qt6/bin/qmllint}"
if [[ -x $qmllint_bin ]]; then
    "$qmllint_bin" -I "$imports" \
        "$ROOT/tests/tst_accessibleprimitives.qml" \
        "$ROOT/tests/tst_uicompat.qml"
fi

env -u DISPLAY -u WAYLAND_DISPLAY \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= QT_QUICK_BACKEND=software \
    "$RUNNER" -import "$imports" -input "$ROOT/tests" -o -,txt
