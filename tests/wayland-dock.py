#!/usr/bin/env python3
"""Exercise the real dock on an isolated headless Umbriel, never the live desktop.

Requires qs, grim, wtype and a built Umbriel harness pointer-client.
Keeps evidence under --evidence; configuration and state are temporary.
"""
import argparse
import json
import os
from pathlib import Path
import signal
import shutil
import subprocess
import tempfile
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--compositor', default='/usr/local/bin/umbriel')
parser.add_argument('--pointer-client', required=True)
parser.add_argument('--theme', default='nbdark')
parser.add_argument('--motion', default='standard')
parser.add_argument('--width', type=int, default=1280)
parser.add_argument('--height', type=int, default=720)
parser.add_argument('--evidence', required=True)
a = parser.parse_args()
root = Path(__file__).resolve().parents[1]
evidence = Path(a.evidence).resolve()
evidence.mkdir(parents=True, exist_ok=True)
processes, handles = [], []


def require(value, message):
    if not value:
        raise RuntimeError(message)


with tempfile.TemporaryDirectory(prefix='nb-dock-') as directory:
    work = Path(directory)
    for d in ['runtime', 'config/nbshell', 'state', 'data/applications', 'shell']:
        (work / d).mkdir(parents=True, exist_ok=True)
    (work / 'runtime').chmod(0o700)
    for path in (root / 'shell').iterdir():
        if path.is_dir():
            if path.name == 'Dock':
                shutil.copytree(path, work / 'shell' / path.name)
            else:
                (work / 'shell' / path.name).symlink_to(path)
    # Read-only probe in the disposable copy; no test API in the installed dock.
    dock_path = work / 'shell/Dock/DockWindow.qml'
    dock_text = dock_path.read_text()
    end = dock_text.rfind('}')
    probe = '''
    IpcHandler {
        target: "dockProbe"
        function closeLabels(): string {
            return JSON.stringify(menu.visible ? menuColumn.children.filter(c => c.visible
                && (c.title === "Close" || c.title === "Close all windows")).map(c => c.title) : []);
        }
    }
'''
    dock_path.write_text('import Quickshell.Io\n' + dock_text[:end] + probe + dock_text[end:])
    (work / 'config/nbshell/themes').symlink_to(root / 'themes')
    (work / 'config/nbshell/config.json').write_text(json.dumps({
        'schemaVersion': 1, 'theme': a.theme, 'motionProfile': a.motion,
        'dockEnabled': True, 'dockPins': ['org.test.Pinned'],
    }))
    (work / 'data/applications/org.test.Pinned.desktop').write_text(
        '[Desktop Entry]\nType=Application\nName=Pinned fixture\nExec=/bin/true\nIcon=utilities-terminal\n')
    (work / 'data/applications/org.nbshell.DockFixture.desktop').write_text(
        '[Desktop Entry]\nType=Application\nName=Running fixture\nExec=/bin/true\nIcon=utilities-terminal\n')
    (work / 'umbriel.toml').write_text(
        '[general]\nxwayland = false\nshow_cheatsheet = false\nautostart = []\n'
        f'[output.HEADLESS-1]\nmode = "{a.width}x{a.height}@60"\nscale = 1.0\n')
    (work / 'shell/shell.qml').write_text('''//@ pragma AppId org.nbshell.DockFixture
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Dock
import qs.Settings
ShellRoot {
 id: fixture
 property int clicks: 0
 LazyLoader { active: Config.dockEnabled; Dock {} }
 LazyLoader { id: settings; active: Runtime.settingsOpen; SettingsWindow {} }
 FloatingWindow {
  id: windowA
  visible: true; title: "Dock fixture A"
  color: "#454545"
  MouseArea { anchors.fill: parent; onClicked: fixture.clicks++ }
 }
 FloatingWindow { id: windowB; visible: true; title: "Dock fixture B"; color: "#555555" }
 IpcHandler {
  target: "probe"
  function state(): string { return JSON.stringify({surfaces: DockService.surfaces, clicks: fixture.clicks, pins: DockService.pins, iconSize: Theme.controlHeight + Theme.spaceXl, spacing: Theme.spaceXs, padding: Theme.spaceSm, groups: DockService.groups.map(g => ({key:g.key,count:g.windows.length}))}); }
  function reveal(): void { DockService.revealRequested(Quickshell.screens[0].name); }
  function hide(): void { DockService.hideRequested(); }
  function enabled(value: bool): void { Config.set("dockEnabled", value); }
  function edge(value: string): void { Config.set("edge", value); }
  function settingsOpen(): void { Runtime.settingsOpen = true; }
  function resetWindows(both: bool): void {
   windowA.visible = false; windowB.visible = false;
   Qt.callLater(() => { windowA.visible = true; windowB.visible = both; });
  }
  function resetSizes(): void { Config.set("dockScale", 100); Config.set("dockIconScale", 100); }
  function sizes(): string { return JSON.stringify({scale: DockService.dockScale, icons: DockService.dockIconScale, savedScale: Config.dockScale, savedIcons: Config.dockIconScale, open: Runtime.settingsOpen, preview: DockService.previewActive}); }
  function slider(label: string): string {
   function find(node) {
    if (!node) return null;
    if (node.visible && node.accessibleName === label) {
     const p = node.mapToItem(null, 0, 0);
     return {x:p.x, y:p.y, width:node.width, height:node.height, focused:node.activeFocus};
    }
    for (const child of node.children ?? []) { const found = find(child); if (found) return found; }
    return null;
   }
   return JSON.stringify(find(settings.item?.contentItem));
  }
 }
}
''')
    env = dict(os.environ, XDG_RUNTIME_DIR=str(work / 'runtime'),
               XDG_CONFIG_HOME=str(work / 'config'), XDG_STATE_HOME=str(work / 'state'),
               XDG_DATA_HOME=str(work / 'data'), WLR_BACKENDS='headless',
               WLR_HEADLESS_OUTPUTS='1', WLR_LIBINPUT_NO_DEVICES='1',
               QT_QPA_PLATFORM='wayland', QT_QUICK_BACKEND='software', QT_QPA_PLATFORMTHEME='')
    for key in ['WAYLAND_DISPLAY', 'DISPLAY', 'UMBRIEL_SOCKET', 'DBUS_SESSION_BUS_ADDRESS']:
        env.pop(key, None)

    def launch(command, log):
        handle = (evidence / log).open('w')
        handles.append(handle)
        proc = subprocess.Popen(command, env=env, stdout=handle, stderr=handle, start_new_session=True)
        processes.append(proc)
        return proc

    def run(command):
        return subprocess.run(command, env=env, capture_output=True, text=True, check=True, timeout=15).stdout

    def ipc(*args):
        return run(['qs', '-p', str(work / 'shell'), 'ipc', 'call', 'probe', *args]).strip()

    def state():
        return json.loads(ipc('state'))

    def close_labels():
        return json.loads(run(['qs', '-p', str(work / 'shell'), 'ipc', 'call', 'dockProbe', 'closeLabels']))

    def surface():
        return state()['surfaces'].get('HEADLESS-1', {})

    def wait(probe, label):
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            try:
                if probe():
                    return
            except (subprocess.CalledProcessError, KeyError):
                pass
            time.sleep(.1)
        raise RuntimeError('Timed out: ' + label)

    def pointer(*commands):
        return run([a.pointer_client, str(a.width), str(a.height), *map(str, commands)])

    def capture(name):
        run(['grim', str(evidence / (name + '.png'))])

    try:
        server = launch([a.compositor, '-c', str(work / 'umbriel.toml')], 'compositor.log')
        wait(lambda: (work / 'runtime/umbriel-wayland-0.sock').exists(), 'compositor')
        env.update(WAYLAND_DISPLAY='wayland-0', UMBRIEL_SOCKET=str(work / 'runtime/umbriel-wayland-0.sock'))
        launch([a.pointer_client, str(a.width), str(a.height), 'mod', 'none', 'pause', '300000'], 'keyboard.log')
        shell = launch(['qs', '-p', str(work / 'shell')], 'shell.log')
        wait(lambda: bool(surface()), 'dock loaded')
        wait(lambda: any(g['count'] == 2 for g in state()['groups']), 'real grouped windows')
        require(not surface()['shown'], 'Dock must start hidden')
        capture('hidden')
        pointer('move', a.width // 2, a.height - 1, 'pause', 450)
        wait(lambda: surface()['shown'], 'edge reveal')
        capture('revealed')
        metrics = state()
        dock_width = (len(metrics['groups']) + 1) * metrics['iconSize'] + len(metrics['groups']) * metrics['spacing'] + 2 * metrics['padding']
        app_x = round(a.width / 2 + dock_width / 2 - metrics['padding'] - metrics['iconSize'] / 2)
        app_y = round(a.height - 2 * metrics['padding'] - metrics['iconSize'] / 2)
        pointer('move', app_x, app_y, 'click', 273, 'pause', 300)
        wait(lambda: surface()['menu'], 'pointer context menu')
        run(['wtype', '-k', 'Escape'])
        wait(lambda: not surface()['shown'], 'pointer-menu Escape')
        pointer('move', a.width // 2, a.height // 2, 'pause', 1100)
        wait(lambda: not surface()['shown'], 'leave hide')
        # The hidden dock window spans this area; the real client must get the click.
        rows = json.loads(run([a.compositor, 'windows', '--json']))
        row = next(w for w in rows if w['title'] == 'Dock fixture A')
        pointer('move', row['x'] + row['w'] // 2, row['y'] + row['h'] - 30, 'click', 272)
        wait(lambda: state()['clicks'] == 1, 'hidden input passthrough')
        ipc('reveal')
        wait(lambda: surface()['shown'] and surface()['keyboard'], 'keyboard reveal')
        run(['wtype', '-k', 'Tab'])  # pinned fixture
        run(['wtype', '-k', 'Tab'])  # running group
        run(['wtype', '-k', 'Menu'])
        wait(lambda: surface()['menu'], 'window chooser')
        capture('chooser')
        run(['wtype', '-k', 'Tab', '-k', 'Tab', '-k', 'Return'])
        wait(lambda: 'org.nbshell.DockFixture' in state()['pins'], 'pin from keyboard menu')
        run(['wtype', '-k', 'Escape'])
        wait(lambda: not surface()['shown'] and not surface()['keyboard'], 'Escape dismiss/focus release')
        # A fullscreen client must suppress the hotspot and dock on its output.
        run([a.compositor, 'msg', 'window-focus:' + str(row['id'])])
        run([a.compositor, 'msg', 'window-toggle-fullscreen'])
        wait(lambda: surface()['blocked'], 'fullscreen suppression')
        pointer('move', a.width // 2, a.height - 1, 'pause', 450)
        require(not surface()['shown'], 'Fullscreen edge must remain hidden')
        run([a.compositor, 'msg', 'window-toggle-fullscreen'])
        wait(lambda: not surface()['blocked'], 'fullscreen exit')
        pointer('move', a.width // 2, a.height // 2)
        ipc('enabled', 'false')
        wait(lambda: not state()['surfaces'], 'disable destroys surfaces')
        layers = json.loads(run([a.compositor, 'layers', '--json']))
        require(not any(w['namespace'] == 'nbshell:dock' for w in layers), 'Disabled dock leaves layer surface')
        ipc('enabled', 'true')
        wait(lambda: bool(surface()) and not surface()['shown'], 're-enable hidden')
        ipc('edge', 'bottom')
        wait(lambda: surface()['edge'] == 'top', 'bottom-bar collision policy')
        time.sleep(.25)  # Wait for the layer-shell re-anchor commit before motion.
        pointer('move', a.width // 2, 1, 'pause', 450)
        wait(lambda: surface()['shown'], 'top edge reveal')
        capture('top-edge')
        # Pin data must survive the feature switch; settings are persisted through Config.
        wait(lambda: json.loads((work / 'config/nbshell/config.json').read_text()).get('dockEnabled') is True, 'saved config')
        require(json.loads((work / 'config/nbshell/config.json').read_text())['dockPins'] == ['org.test.Pinned', 'org.nbshell.DockFixture'], 'Pins lost')
        # Exercise the real settings controls, including live, unsaved drag state.
        ipc('edge', 'top')
        pointer('move', a.width // 2, a.height // 2)
        ipc('settingsOpen')
        time.sleep(.4)
        run(['wtype', '-k', 'Down', '-k', 'Right'])
        wait(lambda: surface()['preview'] and surface()['shown'], 'settings preview')
        require(not surface()['keyboard'], 'Preview must not steal keyboard focus')
        capture('settings-sizes')
        original = surface()

        def sizes():
            return json.loads(ipc('sizes'))

        def drag(label, fraction, key, saved_key):
            rect = json.loads(ipc('slider', label))
            require(rect is not None, 'Slider missing: ' + label)
            y = round(rect['y'] + rect['height'] / 2)
            x = round(rect['x'] + rect['width'] * fraction)
            before = sizes()[saved_key]
            handle = (evidence / ('drag-' + key + '.log')).open('w')
            handles.append(handle)
            proc = subprocess.Popen([a.pointer_client, str(a.width), str(a.height),
                'move', str(x), str(y), 'press', '272', 'pause', '1200',
                'move', str(x + 2), str(y), 'pause', '1200', 'release', '272'],
                env=env, stdout=handle, stderr=handle, start_new_session=True)
            processes.append(proc)
            wait(lambda: sizes()[key] != before, label + ' live drag')
            require(sizes()[saved_key] == before, 'Drag must not persist before release')
            require(json.loads(ipc('slider', label))['focused'], 'Dragged slider not focused')
            capture('drag-' + key)
            proc.wait(timeout=10)
            wait(lambda: sizes()[saved_key] == sizes()[key], label + ' commit')

        drag('Dock size', .65, 'scale', 'savedScale')
        require(surface()['height'] > original['height'], 'Dock slider did not resize frame')
        require(surface()['iconSize'] == original['iconSize'], 'Dock slider changed icon size')
        run(['wtype', '-k', 'Down'])  # focus/scroll next slider into view
        drag('Icon size', .9, 'icons', 'savedIcons')
        require(surface()['iconSize'] > original['iconSize'], 'Icon slider did not resize icons')
        before_key = sizes()['savedIcons']
        run(['wtype', '-k', 'Left'])
        wait(lambda: sizes()['savedIcons'] == before_key - 5, 'keyboard slider step')
        capture('settings-large')
        run(['wtype', '-k', 'Escape'])
        wait(lambda: not sizes()['open'] and not surface()['preview'] and not surface()['shown'], 'preview ends with settings')
        pointer('move', a.width // 2, a.height - 1, 'pause', 450)
        wait(lambda: surface()['shown'], 'resized dock auto-hide reveal')
        pointer('move', a.width // 2, a.height // 2, 'pause', 1000)
        wait(lambda: not surface()['shown'], 'resized dock auto-hide leave')
        ipc('enabled', 'false')
        ipc('settingsOpen')
        time.sleep(.4)
        run(['wtype', '-k', 'Down', '-k', 'Right', '-k', 'Down'])
        drag('Dock size', .2, 'scale', 'savedScale')
        require(not state()['surfaces'] and not sizes()['preview'], 'Sizing enabled a disabled dock')
        run(['wtype', '-k', 'Escape'])
        wait(lambda: not sizes()['open'], 'disabled dock settings close')
        saved = json.loads((work / 'config/nbshell/config.json').read_text())
        require(saved['dockScale'] == sizes()['savedScale'] and saved['dockIconScale'] == sizes()['savedIcons'], 'Sizes not persisted')
        # Normal close requests through the actual context menu, never process kills.
        ipc('resetSizes')
        ipc('enabled', 'true')
        wait(lambda: bool(surface()), 'close-test dock enabled')
        ipc('resetWindows', 'false')
        wait(lambda: any(g['count'] == 1 for g in state()['groups']), 'single-window fixture')
        for count, label in [(1, 'Close'), (2, 'Close all windows')]:
            if count == 2:
                ipc('resetWindows', 'true')
                wait(lambda: any(g['count'] == 2 for g in state()['groups']), 'multi-window fixture')
            ipc('reveal')
            time.sleep(.3)  # Commit the new layer keyboard grab before injecting keys.
            run(['wtype', '-k', 'Tab', '-k', 'Tab', '-k', 'Menu'])
            wait(lambda: surface()['menu'], 'close context menu')
            require(close_labels() == [label], 'Incorrect close action')
            for _ in range(count + 1):
                run(['wtype', '-k', 'Tab'])
            run(['wtype', '-k', 'Tab'])  # close, after windows, pin and new instance
            time.sleep(.3)
            capture('close-' + str(count))
            run(['wtype', '-k', 'Return'])
            wait(lambda: all(g['count'] == 0 for g in state()['groups']), 'requested windows closed')
            require(not surface()['menu'] and not surface()['keyboard'], 'Close retained menu/focus')
            require('org.nbshell.DockFixture' in state()['pins'], 'Close removed pin')
        ipc('reveal')
        time.sleep(.3)
        run(['wtype', '-k', 'Tab', '-k', 'Tab', '-k', 'Menu'])
        wait(lambda: surface()['menu'], 'non-running pin menu')
        require(not close_labels(), 'Non-running pin offers close')
        run(['wtype', '-k', 'Escape'])
        log = (evidence / 'shell.log').read_text()
        require('ERROR' not in log and 'WARN' not in log, 'Unexpected QML warning: ' + log)
        print('PASS: dock/size regressions; context-menu close single/all, focus release, pin preservation, no close for non-running pin')
    finally:
        for proc in reversed(processes):
            if proc.poll() is None:
                os.killpg(proc.pid, signal.SIGTERM)
                proc.wait(timeout=10)
        for handle in handles:
            handle.close()
