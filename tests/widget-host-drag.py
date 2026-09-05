#!/usr/bin/env python3
"""Exercise WidgetHost's actual drag objects without loading desktop services."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "shell/Bar/WidgetHost.qml").read_text()
# Keep production properties, DragHandler and DropArea verbatim. Only omit the
# service-backed Loader and decorative preview, which need a running shell.
properties = source[source.index('    property string widgetName:'):source.index('    readonly property bool hasActivityWidget:')]
proxy = source[source.index('    Item {\n        id: dragProxy'):source.index('        Rectangle {\n            anchors.fill: parent')]
drop = source[source.index('    DropArea {'):source.index('\n    Rectangle {\n        z: 999')]
fixture = ('import QtQuick\nItem {\n    id: root\n' + properties.replace('    readonly property var item: loader.item\n', '')
           + '    width: 100; height: 40\n'
           + '    property alias proxy: dragProxy\n    property alias handler: moduleDrag\n    property alias dropArea: reorderDrop\n'
           + proxy + '    }\n' + drop + '\n}\n')
with tempfile.TemporaryDirectory(prefix="nbshell-widget-drag-") as directory:
    path = Path(directory)
    (path / "WidgetHost.qml").write_text(fixture)
    (path / "tst_widgethostdrag.qml").write_text((ROOT / "tests/fixtures/widgethostdrag.qml.in").read_text())
    env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="", QT_QUICK_BACKEND="software")
    env.pop("DISPLAY", None)
    env.pop("WAYLAND_DISPLAY", None)
    result = subprocess.run([os.environ.get("QML_TEST_RUNNER", "/usr/lib/qt6/bin/qmltestrunner"), "-input", directory, "-o", "-,txt"], env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    print(result.stdout, end="")
    # QML runtime warnings must fail this regression, not merely appear in logs.
    raise SystemExit(result.returncode or (1 if "QWARN" in result.stdout or "TypeError:" in result.stdout else 0))
