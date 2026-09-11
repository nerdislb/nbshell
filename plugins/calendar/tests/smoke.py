#!/usr/bin/env python3
"""Load the actual panel and stdin backend in an isolated offscreen Quickshell."""
import os
from pathlib import Path
import shutil
import subprocess

from harness import ROOT as root, sandbox

with sandbox() as (work, env):
    shutil.copytree(root/'plugins/calendar', work/'Calendar', ignore=shutil.ignore_patterns('tests', '__pycache__'))
    shutil.copytree(work/'imports/qs/Common', work/'Common')
    shutil.copytree(work/'imports/qs/Widgets', work/'Widgets')
    (work/'shell.qml').write_text('''import QtQuick
    import Quickshell
    import "Calendar"
    ShellRoot {
        Panel { id: panel; Component.onCompleted: open("{}") }
        Timer {
            interval: 1200; running: true
            onTriggered: {
                const service = panel.children.find(child => child.loadedAt !== undefined);
                if (!service || service.busy || service.error || !service.loadedAt || service.accounts.length !== 0)
                    console.error("CALENDAR_SMOKE_FAILED");
                else console.info("CALENDAR_SMOKE_PASSED");
                panel.close();
                Qt.quit();
            }
        }
    }
    ''')
    result = subprocess.run(['quickshell','-p',str(work/'shell.qml')],env=env,capture_output=True,text=True,timeout=10)
    output = result.stdout + result.stderr
    print(output)
    assert result.returncode == 0 and 'CALENDAR_SMOKE_PASSED' in output and 'CALENDAR_SMOKE_FAILED' not in output, output
    print('Actual Panel / Service / stdin backend smoke test passed (empty isolated account store).')
