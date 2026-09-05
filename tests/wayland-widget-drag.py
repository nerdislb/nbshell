#!/usr/bin/env python3
"""Isolated real-Wayland test of production WidgetHost drag input.

Requires Quickshell and Umbriel's tests/harness/clients/pointer_client.cpp
built with virtual-pointer and virtual-keyboard protocol support. Runs only
a temporary headless compositor: no installation or live-session input.
The fixture extracts production drag properties/handlers, not the full bar;
reorder callbacks are recorded rather than persisted to user configuration.
"""
import argparse
import json
import os
from pathlib import Path
import signal
import shutil
import subprocess
import sys
import tempfile
import time


def require(condition, message):
    # Unlike assert, regression checks must also run under python -O.
    if not condition:
        raise RuntimeError(message)

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--compositor', required=True, help='Umbriel executable to test')
parser.add_argument('--pointer-client', required=True, help='Umbriel harness pointer-client executable')
args = parser.parse_args()
binary = str(Path(args.compositor).resolve())
root = Path(__file__).resolve().parents[1]
helper = str(Path(args.pointer_client).resolve())
for executable in [binary, helper, 'qs']:
    if not shutil.which(executable):
        parser.error('Executable not found or not executable: ' + executable)
with tempfile.TemporaryDirectory(prefix='nbmod-') as directory:
    work = Path(directory)
    config = work / 'config.toml'
    config.write_text('[general]\nxwayland = false\nshow_cheatsheet = false\nautostart = []\n')
    source = (root / 'shell/Bar/WidgetHost.qml').read_text()
    properties = source[source.index('    property string widgetName:'):source.index('    readonly property bool hasActivityWidget:')]
    proxy = source[source.index('    Item {\n        id: dragProxy'):source.index('        Rectangle {\n            anchors.fill: parent')]
    drop = source[source.index('    DropArea {'):source.index('\n    Rectangle {\n        z: 999')]
    host = 'import QtQuick\nItem {\n id: root\n' + properties.replace('    readonly property var item: loader.item\n', '') + '\n width: 100; height: 40\n' + proxy + '    }\n' + drop + '\n}\n'
    (work / 'WidgetHost.qml').write_text(host)
    (work / 'panel.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Wayland
PanelWindow {
 implicitWidth: 400; implicitHeight: 80
 anchors.left: true; anchors.top: true
 color: "#222222"
 exclusionMode: ExclusionMode.Ignore
 WlrLayershell.namespace: "nbshell:drag-regression"
 WlrLayershell.layer: WlrLayershell.Overlay
 WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
 WidgetHost {
  x: 10; y: 10; layoutKey: "leftWidgets"; layoutIndex: 0
  MouseArea { anchors.fill: parent; onClicked: console.log("PROBE_CLICK") }
 }
 WidgetHost {
  x: 200; y: 10; layoutKey: "rightWidgets"; layoutIndex: 1
  reorderAction: function(a,b,c,d,e) { console.log("PROBE_MOVE", a,b,c,d,e); }
 }
}
''')
    (work / 'focus.qml').write_text('''import QtQuick
Window {
 visible: true; width: 600; height: 400; title: "nbshell-focus-regression"
 TextInput {
  anchors.fill: parent; focus: true
  onTextChanged: console.log("PROBE_TEXT", JSON.stringify(text))
 }
}
''')
    env = dict(os.environ, XDG_RUNTIME_DIR=directory, WLR_BACKENDS='headless', WLR_LIBINPUT_NO_DEVICES='1', WLR_HEADLESS_OUTPUTS='1', QT_QPA_PLATFORM='wayland', QT_QUICK_BACKEND='software', XKB_DEFAULT_LAYOUT='us')
    for name in ['WAYLAND_DISPLAY', 'DISPLAY', 'DBUS_SESSION_BUS_ADDRESS', 'UMBRIEL_SOCKET', 'WAYLAND_DEBUG', 'XKB_DEFAULT_VARIANT', 'XKB_DEFAULT_OPTIONS']:
        env.pop(name, None)
    processes = []
    handles = []
    def launch(args, log, debug=False):
        handle = open(work / log, 'w')
        handles.append(handle)
        proc = subprocess.Popen(args, env=dict(env, WAYLAND_DEBUG='1') if debug else env, stdout=handle, stderr=subprocess.STDOUT, start_new_session=True)
        processes.append(proc)
        return proc
    def wait_for(test, label):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            for proc in processes:
                require(proc.poll() is None, 'Child exited early: ' + str(proc.args))
            if test():
                return
            time.sleep(.03)
        raise RuntimeError('Timed out: ' + label)
    def run(args):
        return subprocess.run(args, env=env, capture_output=True, text=True, timeout=10, check=True).stdout
    try:
        server = launch([binary, '-c', str(config)], 'server.log')
        wait_for(lambda: (work / 'umbriel-wayland-0.sock').exists() or server.poll() is not None, 'compositor socket')
        if server.poll() is not None:
            raise RuntimeError((work / 'server.log').read_text())
        env['WAYLAND_DISPLAY'] = 'wayland-0'
        env['UMBRIEL_SOCKET'] = str(work / 'umbriel-wayland-0.sock')
        outputs = json.loads(run([binary, 'outputs', '--json']))
        mode = next(m for m in outputs[0]['modes'] if m['current'])
        extent = [str(mode['width']), str(mode['height'])]
        # Establish keyboard capabilities before either Qt client maps. Otherwise
        # removing a transient keyboard can produce unrelated wl_keyboard.leave warnings.
        launch([helper, *extent, 'mod', 'none', 'pause', '300000'], 'keyboard.log', debug=True)
        def keyboard_ready():
            log = (work / 'keyboard.log').read_text()
            marker = log.rfind('.modifiers(')
            return marker >= 0 and '.done(' in log[marker:]
        wait_for(keyboard_ready, 'persistent virtual keyboard roundtrip')
        launch(['qs', '-p', str(work / 'focus.qml')], 'focus.log')
        wait_for(lambda: 'nbshell-focus-regression' in run([binary, 'windows']), 'focused window')
        launch(['qs', '-p', str(work / 'panel.qml')], 'panel.log')
        wait_for(lambda: 'nbshell:drag-regression' in run([binary, 'layers']), 'nonfocusable panel')
        # Confirm an ordinary click arrives, without changing keyboard focus.
        run([helper, *extent, 'move','60','30','pause','80','click','272'])
        wait_for(lambda: 'PROBE_CLICK' in (work / 'panel.log').read_text(), 'normal click')
        def check_focus(text):
            windows = json.loads(run([binary, 'windows', '--json']))
            require(any(w['title'] == 'nbshell-focus-regression' and w['focused'] for w in windows), 'Panel stole compositor keyboard focus')
            run([helper, *extent, 'mod', 'none', 'tap', '30'])
            wait_for(lambda: 'PROBE_TEXT ' + json.dumps(text) in (work / 'focus.log').read_text(), 'exact typing reaches original window: ' + text)

        check_focus('a')
        print('PASS: ordinary click; keyboard focus and typing preserved')
        for index, modifier in enumerate(['none', 'shift', 'logo', 'none', 'shift'], 2):
            before = (work / 'panel.log').read_text().count('PROBE_MOVE')
            run([helper, *extent, 'move','60','30','mod',modifier,'pause','150','press','272','pause','100','move','100','30','pause','100','move','230','30','pause','100','move','270','30','pause','100','release','272','mod','none','pause','200'])
            check_focus('a' * index)
            log = (work / 'panel.log').read_text()
            expected = before + (1 if modifier == 'logo' else 0)
            require(log.count('PROBE_MOVE') == expected,
                    f'{modifier} drag: expected {expected} reorder callbacks, got {log.count("PROBE_MOVE")}')
            require(log.count('PROBE_CLICK') == 1, modifier + ' drag leaked an ordinary click')
            print(f'PASS: {modifier} drag; reorder callbacks={expected}; keyboard focus and typing preserved')
        log = (work / 'panel.log').read_text()
        require('PROBE_MOVE leftWidgets 0 rightWidgets 1 true' in log, 'Unexpected reorder arguments')
        for filename in ['panel.log', 'focus.log']:
            log = (work / filename).read_text()
            require(not any(token in log for token in ['TypeError', 'ReferenceError', 'WARN', 'ERROR', 'Binding loop']), filename + ': QML warnings/errors')
        print('PASS: real unfocused Wayland widget drag regression')
    except Exception as error:
        print('FAIL:', error, file=sys.stderr)
        for filename in ['server.log', 'keyboard.log']:
            if (work / filename).exists():
                print(filename + ' (last 20 lines)\n' + '\n'.join((work / filename).read_text().splitlines()[-20:]), file=sys.stderr)
        raise
    finally:
        for filename in ['panel.log', 'focus.log']:
            if (work / filename).exists():
                print(filename, (work / filename).read_text())
        for proc in reversed(processes):
            if proc.poll() is None:
                try:
                    os.killpg(proc.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
        for proc in reversed(processes):
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
                proc.wait()
        for handle in handles:
            handle.close()
