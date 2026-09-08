#!/usr/bin/env python3
"""Native AT-SPI regression for the production Settings and Modules panels.

Requires bubblewrap, pyatspi, wtype, Umbriel, its built pointer-client, and a
Quickshell build containing the AT-SPI export fix. Never installs or targets
the live desktop. All config mutations occur inside a disposable namespace.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def rect_contains(outer, inner):
    x, y, width, height = inner
    left, top, span, depth = outer
    return (width > 0 and height > 0 and span > 0 and depth > 0
            and x >= left and y >= top
            and x + width <= left + span and y + height <= top + depth)


def speech_sequence_present(lines, expected):
    remaining = iter(lines)
    return all(any(f"SPEECH OUTPUT: '{text}'" in line for line in remaining)
               for text in expected)


def inside(args):
    require(os.environ.get('NBSHELL_FOCUS_TEST') == '1', 'Missing sandbox marker')
    require(not Path('/run/dbus/system_bus_socket').exists(), 'Host bus exposed')
    home = Path('/home/test')
    config = home / '.config/nbshell'
    config.mkdir(parents=True)
    (config / 'themes').symlink_to('/source/themes')
    (config / 'config.json').write_text(json.dumps({
        'schemaVersion': 1, 'theme': args.theme, 'motionProfile': args.motion,
        'mode': 'bar', 'leftWidgets': ['workspaces', 'clock'],
        'centerWidgets': [], 'rightWidgets': [], 'collapsedWidgets': ['clock'],
    }))
    runtime = Path('/run/test')
    runtime.mkdir(mode=0o700)
    os.environ.update(HOME=str(home), XDG_CONFIG_HOME=str(home / '.config'),
                      XDG_CACHE_HOME=str(home / '.cache'), XDG_STATE_HOME=str(home / '.local/state'),
                      XDG_DATA_HOME=str(home / '.local/share'), XDG_RUNTIME_DIR=str(runtime),
                      WLR_BACKENDS='headless', WLR_HEADLESS_OUTPUTS='1', WLR_LIBINPUT_NO_DEVICES='1',
                      WLR_RENDER_DRM_DEVICE=args.render_node, QT_QPA_PLATFORM='wayland',
                      QT_QUICK_BACKEND='software', QT_QPA_PLATFORMTHEME='',
                      QT_LINUX_ACCESSIBILITY_ALWAYS_ON='1', NBSHELL_DISABLE_HOT_RELOAD='1')
    compositor_config = Path('/work/umbriel.toml')
    compositor_config.write_text('[general]\nxwayland = false\nshow_cheatsheet = false\nautostart = []\n'
                                f'[output.HEADLESS-1]\nmode = "{args.width}x{args.height}@60"\nscale = 1.0\n')
    processes, handles = [], []

    def launch(command, log, env=None):
        handle = open('/work/' + log, 'w')
        handles.append(handle)
        proc = subprocess.Popen(command, stdout=handle, stderr=subprocess.STDOUT,
                                start_new_session=True, env=env)
        processes.append(proc)
        return proc

    def run(command, check=True):
        return subprocess.run(command, capture_output=True, text=True, check=check, timeout=20)

    def wait(probe, label):
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            require(all(p.poll() is None for p in processes), 'Process exited: ' + label)
            if probe():
                return
            time.sleep(0.1)
        raise RuntimeError('Timed out: ' + label)

    def ipc(*arguments):
        return run(['/test-bin/qs', '-p', '/work/shell', 'ipc', 'call', *arguments]).stdout.strip()

    def state():
        return json.loads(ipc('state', 'dump'))

    def layers():
        return json.loads(run(['/test-bin/umbriel', 'layers', '--json']).stdout)

    def capture(name):
        if args.screenshots:
            run(['grim', '/work/' + name + '.png'])

    def key(name, shift=False, spoken=None):
        offset = Path('/work/orca-debug.log').stat().st_size if args.orca_log else 0
        run(['wtype', *(['-M', 'shift'] if shift else []), '-k', name,
             *(['-m', 'shift'] if shift else [])])
        if args.orca_log and spoken:
            wait(lambda: f"SPEECH OUTPUT: '{spoken}'" in
                 Path('/work/orca-debug.log').read_bytes()[offset:].decode('utf-8'),
                 'Orca speech: ' + spoken)
        time.sleep(0.15)

    def flatten(node, path=()):
        yield node, path
        for index, child in enumerate(probe.iter_children(node)):
            yield from flatten(child, (*path, index))

    def focused():
        app = exported()
        require(app is not None, 'Quickshell is not exported to AT-SPI')
        matches = [(node, path) for node, path in flatten(app) if 'focused' in probe.node_states(node)]
        require(len(matches) == 1, f'Expected one focused accessible node, got {len(matches)}')
        node, path = matches[0]
        require(bool(probe.safe_text(node, 'name')), 'Focused node has no accessible name')
        require('focusable' in probe.node_states(node), 'Focused node is not focusable')
        return node, path

    def exported():
        context = probe.GLib.MainContext.default()
        while context.pending():
            context.iteration(False)
        return probe.find_application(probe.desktop_applications(), probe.DEFAULT_APP_PATTERN, shell.pid)

    def focus_name():
        return probe.safe_text(focused()[0], 'name')

    def focus_visible(surface):
        import pyatspi
        node, _ = focused()
        x, y, width, height = node.queryComponent().getExtents(pyatspi.DESKTOP_COORDS)
        require(rect_contains((0, 0, args.width, args.height), (x, y, width, height)),
                f'Focused row outside output: {(x, y, width, height)}')
        geometry = json.loads(ipc('focusProbe' + surface, 'geometry'))
        require(geometry['activeFocus'], 'Geometry probe is not the focused row')
        require(geometry['clips'], 'No clipping viewport was measured')
        row = geometry['row']
        for clip in geometry['clips']:
            require(rect_contains(clip, row), f'Focused row clipped: row={row}, viewport={clip}')

    def open_panel(surface):
        ipc('settings', 'modules' if surface == 'modules' else 'open')
        wait(lambda: state()[surface], surface + ' open')
        time.sleep(0.6)
        require(sum(x['namespace'] == 'nbshell:' + surface and x['mapped'] for x in layers()) == 1,
                surface + ' layer is missing or duplicated')
        focused()

    def frame_count():
        app = probe.find_application(probe.desktop_applications(), probe.DEFAULT_APP_PATTERN, shell.pid)
        require(app is not None, 'Missing AT-SPI application')
        return sum(probe.role_name(n) == 'frame' for n, _ in flatten(app))

    def close_panel(surface):
        before = frame_count()
        key('Escape')
        wait(lambda: not state()[surface] and not any(x['namespace'] == 'nbshell:' + surface for x in layers()),
             surface + ' close')
        time.sleep(0.2)
        require(frame_count() == before - 1, 'Closed panel retained an AT-SPI frame')

    try:
        # Read-only geometry IPC is added only to a disposable shell copy.
        # AT-SPI does not export the actual QML clipping ancestors.
        shutil.copytree('/source/shell', '/work/shell')
        for surface, filename, expression in (
            ('settings', 'SettingsMenu.qml',
             'root.pane === 0 ? groupRows.itemAt(root.group) : settingRows.itemAt(root.selected)'),
            ('modules', 'ModulesMenu.qml',
             'root.inCatalog ? catalogRows.itemAt(root.catalogIndex) : '
             '(groupRows.itemAt(root.groupIndex) ? groupRows.itemAt(root.groupIndex).rowAt(root.itemIndex) : null)'),
        ):
            path = Path('/work/shell/Settings') / filename
            text = path.read_text()
            end = text.rfind('}')
            require(end >= 0, 'Missing panel root')
            handler = '''
    IpcHandler {
        target: "focusProbeSURFACE"
        enabled: ENABLED
        function geometry(): string {
            const item = (EXPRESSION) || closeButton;
            function rect(node) {
                const origin = node.mapToItem(null, 0, 0);
                return [origin.x, origin.y, node.width, node.height];
            }
            const clips = [];
            for (let ancestor = item.parent; ancestor; ancestor = ancestor.parent) {
                if (ancestor.clip) clips.push(rect(ancestor));
            }
            return JSON.stringify({activeFocus: item.activeFocus, row: rect(item), clips: clips});
        }
    }
'''.replace('SURFACE', surface).replace('EXPRESSION', expression).replace(
                'ENABLED', 'root.visible && !root.embedded' if surface == 'settings' else 'root.visible')
            path.write_text('import Quickshell.Io\n' + text[:end] + handler + text[end:])
        launch(['/test-bin/umbriel', '-c', str(compositor_config)], 'compositor.log')
        wait(lambda: (runtime / 'umbriel-wayland-0.sock').exists(), 'compositor IPC')
        os.environ.update(WAYLAND_DISPLAY='wayland-0', UMBRIEL_SOCKET=str(runtime / 'umbriel-wayland-0.sock'))
        outputs = json.loads(run(['/test-bin/umbriel', 'outputs', '--json']).stdout)
        mode = next(m for m in outputs[0]['modes'] if m['current'])
        require((mode['width'], mode['height']) == (args.width, args.height), 'Wrong output geometry')
        os.environ['WAYLAND_DEBUG'] = '1'
        launch(['/pointer-client', str(args.width), str(args.height), 'mod', 'none', 'pause', '300000'], 'keyboard.log')
        del os.environ['WAYLAND_DEBUG']
        def keyboard_ready():
            log = Path('/work/keyboard.log').read_text()
            marker = log.rfind('.modifiers(')
            return marker >= 0 and '.done(' in log[marker:]
        wait(keyboard_ready, 'persistent keyboard')
        shell = launch(['/test-bin/qs', '-p', '/work/shell', '--no-color'], 'shell.log')
        wait(lambda: run(['/test-bin/qs', '-p', '/work/shell', 'ipc', 'call', 'state', 'dump'], False).returncode == 0,
             'shell IPC')
        spec = importlib.util.spec_from_file_location('atspi_probe', '/source/tests/accessibility/atspi_probe.py')
        if spec is None or spec.loader is None:
            raise RuntimeError('Cannot load the native AT-SPI probe')
        probe = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(probe)
        wait(lambda: exported() is not None, 'native AT-SPI application')
        orca = None
        if args.orca_log:
            # Flush diagnostics only; leave real Orca focus/speech processing unchanged.
            prefs = home / '.local/share/orca'
            prefs.mkdir(parents=True, exist_ok=True)
            (prefs / 'orca-customizations.py').write_text(
                'from orca import debug\ndebug.debugFile.reconfigure(line_buffering=True)\n')
            receiver = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
            receiver.bind('/run/test/orca-ready.sock')
            receiver.setblocking(False)
            handles.append(receiver)
            orca = launch(['orca', '--speech-system', 'speechdispatcherfactory',
                           '--debug', '--debug-file', '/work/orca-debug.log'], 'orca.log',
                          {**os.environ, 'XDG_SESSION_TYPE': 'wayland', 'GDK_BACKEND': 'wayland',
                           'NOTIFY_SOCKET': '/run/test/orca-ready.sock',
                           'SPEECHD_ADDRESS': 'unix_socket:/run/test/no-speech.sock',
                           'SPEECHD_CMD': '/nonexistent-speech-dispatcher'})

            def orca_ready():
                try:
                    return b'READY=1' in receiver.recv(4096)
                except BlockingIOError:
                    return False
            wait(orca_ready, 'Orca native readiness notification')
        time.sleep(0.8)
        open_panel('settings')
        require(focus_name() == 'Edge', 'Settings initial focus')
        focus_visible('settings')
        capture('settings-initial')
        key('Tab', spoken='BAR')
        require(focus_name() == 'BAR', 'Settings Tab did not switch to categories')
        focus_visible('settings')
        key('Down', spoken='MODULES')
        require(focus_name() == 'MODULES', 'Category Down did not move focus')
        key('Up', spoken='BAR')
        key('Tab', shift=True, spoken='Edge')
        require(focus_name() == 'Edge', 'Settings Shift+Tab did not return to options')
        key('Down', spoken='Shape')
        require(focus_name() == 'Shape', 'Settings Down did not move focus')
        key('Return', spoken='◂  island  ▸')
        require(json.loads(ipc('config', 'get', 'mode')) == 'island', 'Return did not activate exactly once')
        key('space', spoken='◂  pill  ▸')
        require(json.loads(ipc('config', 'get', 'mode')) == 'pill', 'Space did not activate exactly once')
        key('Right')
        require(json.loads(ipc('config', 'get', 'mode')) == 'bar', 'Right action changed')
        action = focused()[0].queryAction()
        require(action.doAction(0), 'AT-SPI activation rejected')
        time.sleep(0.2)
        require(json.loads(ipc('config', 'get', 'mode')) == 'island', 'AT-SPI did not activate exactly once')
        require(focus_name() == 'Shape', 'AT-SPI activation lost focus')
        key('Left')
        require(json.loads(ipc('config', 'get', 'mode')) == 'bar', 'Left action changed')
        import pyatspi
        x, y, width, height = focused()[0].queryComponent().getExtents(pyatspi.DESKTOP_COORDS)
        run(['/pointer-client', str(args.width), str(args.height), 'move',
             str(x + width // 2), str(y + height // 2), 'click', '272'])
        time.sleep(0.2)
        require(json.loads(ipc('config', 'get', 'mode')) == 'island', 'Pointer did not activate exactly once')
        require(focus_name() == 'Shape', 'Pointer activation lost focus')
        key('Left')
        for _ in range(20):
            key('Down')
            focus_visible('settings')
        capture('settings-scrolled')
        close_panel('settings')
        print('PASS: Settings initial focus, panes, arrows, activation, scroll and Escape', flush=True)

        open_panel('modules')
        require(focus_name() == 'Workspaces', 'Modules initial focus')
        focus_visible('modules')
        capture('modules-initial')
        left_path = focused()[1]
        key('Tab')
        require(focused()[1] != left_path, 'Modules Tab did not reach catalog')
        focus_visible('modules')
        key('Down')
        focused()
        key('Tab', shift=True)
        require(focused()[1] == left_path, 'Modules Shift+Tab did not return to layout')
        key('Down')
        require(focus_name() == 'Clock', 'Modules Down did not move focus')
        key('Left')
        require(json.loads(ipc('config', 'get', 'leftWidgets')) == ['clock', 'workspaces'], 'Reorder failed')
        require(focus_name() == 'Clock', 'Focus lost on delegate recreation')
        key('Right', shift=True)
        require(json.loads(ipc('config', 'get', 'centerWidgets')) == ['clock'], 'Shift+Right move failed')
        require(focus_name() == 'Clock', 'Focus lost on cross-group move')
        key('Left', shift=True)
        require(json.loads(ipc('config', 'get', 'leftWidgets')) == ['workspaces', 'clock'], 'Shift+Left move failed')
        key('Delete')
        require(json.loads(ipc('config', 'get', 'leftWidgets')) == ['workspaces'], 'Delete failed')
        require(focus_name() == 'Workspaces', 'Focus lost after removing current module')
        key('Delete', spoken='Close')
        require(focus_name() == 'Close', 'Empty group did not use a named focus fallback')
        capture('modules-empty')
        key('Tab')
        require(focus_name() != 'Close', 'Cannot leave empty group with Tab')
        key('Up')
        require(focus_name() == 'Workspaces', 'Catalog navigation changed')
        key('Return')
        require(json.loads(ipc('config', 'get', 'leftWidgets')) == ['workspaces'], 'Catalog activation failed')
        focused()
        for _ in range(40):
            key('Down')
            focus_visible('modules')
        capture('modules-scrolled')
        close_panel('modules')
        open_panel('modules')
        focused()
        close_panel('modules')
        print('PASS: Modules pane focus, reorder/delete, empty fallback, scrolling and reopen', flush=True)
        log = Path('/work/shell.log').read_text()
        require(not any(s in log for s in ['ReferenceError', 'TypeError', 'Binding loop']), 'QML runtime error')
        if orca is not None:
            # Graceful exit flushes Orca's buffered debug file. No fake speech backend.
            orca.send_signal(signal.SIGTERM)
            orca.wait(timeout=10)
            require(orca.returncode == 0, 'Orca did not shut down cleanly')
            speech = [line for line in Path('/work/orca-debug.log').read_text().splitlines()
                      if 'SPEECH OUTPUT:' in line]
            require(speech_sequence_present(speech, [
                'Edge', 'BAR', 'MODULES', 'BAR', 'Edge', 'Shape',
                '◂  bar  ▸', '◂  island  ▸', '◂  pill  ▸',
                'Workspaces', 'Clock', 'Close', 'Workspaces',
            ]), 'Orca focus/value speech sequence is missing or out of order')
            print('PASS: real Orca focus-to-speech-text generation; audio and physical input unverified', flush=True)
    finally:
        for proc in reversed(processes):
            if proc.poll() is None:
                os.killpg(proc.pid, signal.SIGTERM)
        for proc in reversed(processes):
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL)
                proc.wait()
        for handle in handles:
            handle.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--quickshell', required=True)
    parser.add_argument('--compositor', required=True)
    parser.add_argument('--pointer-client', required=True)
    parser.add_argument('--render-node', required=True)
    parser.add_argument('--theme', default='tokyo-night')
    parser.add_argument('--motion', choices=['standard', 'reduced'], default='standard')
    parser.add_argument('--width', type=int, default=800)
    parser.add_argument('--height', type=int, default=600)
    parser.add_argument('--screenshots', type=Path, help='Export synthetic screenshots to a new directory')
    parser.add_argument('--orca-log', type=Path, help='Run real Orca and export its synthetic debug log; no audio')
    parser.add_argument('--inside', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.inside:
        inside(args)
        return
    root = Path(__file__).resolve().parents[1]
    for binary in [args.quickshell, args.compositor, args.pointer_client, 'bwrap', 'dbus-run-session', 'wtype']:
        require(shutil.which(binary), 'Missing executable: ' + binary)
    if args.screenshots:
        require(shutil.which('grim'), 'Missing executable: grim')
        args.screenshots.mkdir(parents=True, exist_ok=False)
    if args.orca_log:
        require(shutil.which('orca'), 'Missing executable: orca')
        require(not args.orca_log.exists(), 'Orca output file already exists')
        args.orca_log.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='nbshell-focus-') as directory:
        command = ['bwrap', '--unshare-all', '--die-with-parent', '--new-session',
                   '--ro-bind', '/usr', '/usr', '--symlink', 'usr/bin', '/bin',
                   '--symlink', 'usr/lib', '/lib', '--symlink', 'usr/lib', '/lib64',
                   '--ro-bind', '/etc', '/etc', '--ro-bind', '/sys', '/sys', '--proc', '/proc',
                   '--dev', '/dev', '--dev-bind', str(Path(args.render_node).parent), '/dev/dri',
                   '--tmpfs', '/tmp', '--tmpfs', '/run', '--tmpfs', '/home', '--dir', '/var',
                   '--ro-bind', str(root), '/source', '--bind', directory, '/work',
                   '--ro-bind', str(Path(args.quickshell).resolve()), '/test-bin/qs',
                   '--ro-bind', str(Path(args.compositor).resolve()), '/test-bin/umbriel',
                   '--ro-bind', str(Path(args.pointer_client).resolve()), '/pointer-client',
                   '--clearenv', '--setenv', 'PATH', '/test-bin:/usr/local/bin:/usr/bin:/bin',
                   '--setenv', 'LANG', 'C.UTF-8', '--setenv', 'NBSHELL_FOCUS_TEST', '1',
                   '--setenv', 'PYTHONDONTWRITEBYTECODE', '1', '--chdir', '/work',
                   '--', 'dbus-run-session', '--', 'python3', '/source/tests/wayland-panel-focus.py',
                   *sys.argv[1:], '--inside']
        result = subprocess.run(command, timeout=180)
        if args.orca_log and (Path(directory) / 'orca-debug.log').exists():
            shutil.copyfile(Path(directory) / 'orca-debug.log', args.orca_log)
        if args.screenshots:
            for image in Path(directory).glob('*.png'):
                shutil.copyfile(image, args.screenshots / image.name)
        if result.returncode:
            for name in ['shell.log', 'compositor.log', 'orca.log']:
                path = Path(directory) / name
                if path.exists():
                    print(name + '\n' + path.read_text()[-12000:])
        require(result.returncode == 0, f'Isolated focus regression failed: {result.returncode}')


if __name__ == '__main__':
    main()
