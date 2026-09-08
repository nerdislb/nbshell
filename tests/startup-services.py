#!/usr/bin/env python3
"""Real QML cursor-demand contract, isolated from host settings and processes."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class CursorDemandTests(unittest.TestCase):
    def exercise(self, fail_first):
        with tempfile.TemporaryDirectory(prefix='nbshell-startup-') as directory:
            root = Path(directory)
            for name in ['Common', 'Services', 'scripts', 'config/nbshell', 'state', 'runtime']:
                (root / name).mkdir(parents=True)
            (root / 'runtime').chmod(0o700)
            shutil.copy2(ROOT / 'shell/Common/Config.qml', root / 'Common/Config.qml')
            shutil.copy2(ROOT / 'shell/Services/Cursor.qml', root / 'Services/Cursor.qml')
            (root / 'Common/qmldir').write_text('singleton Config 1.0 Config.qml\n')
            (root / 'Services/qmldir').write_text('singleton Cursor 1.0 Cursor.qml\n')
            (root / 'config/nbshell/config.json').write_text(json.dumps({'schemaVersion': 1, 'cursorTheme': 'FixtureCursor', 'cursorSize': 28}))
            (root / 'scripts/cursors.sh').write_text('''#!/bin/bash
printf '%s\\n' "$1" >> "$XDG_STATE_HOME/actions"
if [ "$1" = list ]; then
    if [ "$FAIL_FIRST" = 1 ] && [ ! -f "$XDG_STATE_HOME/attempted" ]; then
        touch "$XDG_STATE_HOME/attempted"
        printf 'invalid-json\\n'
        exit 1
    fi
    printf '["FixtureCursor", "SecondCursor"]\\n'
fi
''')
            (root / 'shell.qml').write_text('''import QtQuick
import Quickshell
import qs.Common
import qs.Services
ShellRoot {
    Component.onCompleted: { void Cursor.theme; }
    Timer { interval: 600; running: true; onTriggered: {
        console.log("CURSOR_IDLE " + JSON.stringify({loaded: Cursor.themesLoaded, themes: Cursor.themes}));
        Cursor.ensureThemes(); Cursor.ensureThemes();
    } }
    Timer { interval: 1100; running: true; onTriggered: Cursor.ensureThemes() }
    Timer { interval: 1700; running: true; onTriggered: {
        Cursor.ensureThemes();
        console.log("CURSOR_RESULT " + JSON.stringify({loaded: Cursor.themesLoaded, themes: Cursor.themes, theme: Cursor.theme, size: Cursor.size}));
        Qt.quit();
    } }
}
''')
            env = dict(os.environ, HOME=str(root), XDG_CONFIG_HOME=str(root / 'config'),
                       XDG_STATE_HOME=str(root / 'state'), XDG_CACHE_HOME=str(root / 'cache'),
                       XDG_DATA_HOME=str(root / 'data'), XDG_RUNTIME_DIR=str(root / 'runtime'),
                       QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', FAIL_FIRST='1' if fail_first else '0')
            qs = shutil.which('qs') or shutil.which('quickshell')
            self.assertIsNotNone(qs, 'Quickshell is required for the real QML contract')
            run = subprocess.run([qs, '-p', str(root), '--no-color'], env=env, capture_output=True, text=True, timeout=10)
            log = run.stdout + run.stderr
            self.assertEqual(run.returncode, 0, log)
            self.assertNotRegex(log, r'ReferenceError|TypeError|Binding loop')
            idle = json.loads(re.search(r'CURSOR_IDLE (.+)', log).group(1))
            result = json.loads(re.search(r'CURSOR_RESULT (.+)', log).group(1))
            self.assertEqual(idle, {'loaded': False, 'themes': []})
            self.assertEqual(result, {'loaded': True, 'themes': ['FixtureCursor', 'SecondCursor'], 'theme': 'FixtureCursor', 'size': 28})
            actions = (root / 'state/actions').read_text().splitlines()
            self.assertEqual(actions, ['apply', 'list', 'list'] if fail_first else ['apply', 'list'])

    def test_apply_at_login_but_enumerate_once_on_demand(self):
        self.exercise(False)

    def test_failed_enumeration_retries_on_next_demand(self):
        self.exercise(True)


if __name__ == '__main__':
    unittest.main()
