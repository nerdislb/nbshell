#!/usr/bin/env python3
"""Exercise the real Quickshell clipboard writer without reading the desktop clipboard."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[1]
qs = shutil.which('quickshell') or shutil.which('qs')
if not qs:
    print('Clipboard runtime: SKIP (Quickshell unavailable)')
    raise SystemExit(0)
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    (root / 'Common').mkdir(); (root / 'Services').mkdir()
    (root / 'scripts').symlink_to(ROOT / 'shell/scripts', target_is_directory=True)
    (root / 'Common/qmldir').write_text('singleton Config 1.0 Config.qml\n')
    (root / 'Common/Config.qml').write_text('pragma Singleton\nimport Quickshell\nSingleton { function value(key, fallback) { return key === "clipboard" ? false : fallback; } }\n')
    (root / 'Services/qmldir').write_text('singleton Clipboard 1.0 Clipboard.qml\n')
    shutil.copy(ROOT / 'shell/Services/Clipboard.qml', root / 'Services/Clipboard.qml')
    (root / 'shell.qml').write_text('''import QtQuick
import Quickshell
import qs.Services
ShellRoot {
    Component.onCompleted: {
        Clipboard.add("first");
        Clipboard.add("second");
        Clipboard.remove("first");
        Clipboard.add("Grüße ✦");
    }
    Timer { interval: 1500; running: true; onTriggered: Qt.quit() }
}
''')
    (root / 'runtime').mkdir(mode=0o700)
    env = dict(os.environ, XDG_RUNTIME_DIR=str(root / 'runtime'), QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='',
               QT_QUICK_BACKEND='software', XDG_STATE_HOME=str(root / 'state'))
    try:
        result = subprocess.run([qs, '-p', str(root)], env=env, capture_output=True, text=True, timeout=8)
    except subprocess.TimeoutExpired as error:
        print('Clipboard runtime timed out; partial Quickshell output:', flush=True)
        for output in (error.stdout, error.stderr):
            if output:
                print(output.decode(errors='replace') if isinstance(output, bytes) else output, flush=True)
        raise
    assert result.returncode == 0, result.stdout + result.stderr
    saved = root / 'state/nbshell/clipboard.json'
    assert saved.exists(), result.stdout + result.stderr
    assert json.loads(saved.read_text()) == ['Grüße ✦', 'second'], result.stdout + result.stderr
    assert 'ERROR' not in result.stdout + result.stderr, result.stdout + result.stderr
print('Real Quickshell clipboard write/coalescing: OK')
