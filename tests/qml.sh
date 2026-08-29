#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="${QML_TEST_RUNNER:-/usr/lib/qt6/bin/qmltestrunner}"

if [[ ! -x $RUNNER ]]; then
    echo "Qt QML test runner is not available; skipping QML tests."
    exit 0
fi

env -u DISPLAY -u WAYLAND_DISPLAY \
    QT_QPA_PLATFORM=offscreen QT_QPA_PLATFORMTHEME= QT_QUICK_BACKEND=software \
    "$RUNNER" -import "$ROOT/tests/imports" -input "$ROOT/tests" -o -,txt
