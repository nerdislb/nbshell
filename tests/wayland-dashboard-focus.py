#!/usr/bin/env python3
"""Native AT-SPI regression for Dashboard navigation and update states.

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

    def key(name, shift=False):
        run(['wtype', *(['-M', 'shift'] if shift else []), '-k', name,
             *(['-m', 'shift'] if shift else [])])
        time.sleep(0.15)

    def flatten(node, path=()):
        yield node, path
        for index, child in enumerate(probe.iter_children(node)):
            yield from flatten(child, (*path, index))

    def focused():
        app = exported()
        require(app is not None, 'Quickshell is not exported to AT-SPI')
        # The existing modal Dialog FocusScope also reports activeFocus;
        # verify the unique focused leaf control, not that ancestor.
        matches = [(node, path) for node, path in flatten(app)
                   if 'focused' in probe.node_states(node) and probe.role_name(node) != 'dialog']
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

    try:
        # Read-only geometry IPC is added only to a disposable shell copy.
        # AT-SPI does not export the actual QML clipping ancestors.
        shutil.copytree('/source/shell', '/work/shell')
        state_path = Path('/work/shell/Ipc/SystemIpc.qml')
        state_path.write_text(state_path.read_text().replace('"popouts": Runtime.popoutCount,',
            '"dashboard": Runtime.dashboardOpen, "popouts": Runtime.popoutCount,'))
        path = Path('/work/shell/Menu/Dashboard.qml')
        text = path.read_text()
        end = text.rfind('}')
        handler = """
    IpcHandler {
        target: "dashboardProbe"
        function snapshot(): string {
            function rect(item) {
                const p = item.mapToItem(null, 0, 0);
                return [p.x, p.y, item.width, item.height];
            }
            return JSON.stringify({page: root.page, modal: root.updatesOpen,
                summary: ShellUpdates.summary, current: ShellUpdates.allCurrent,
                state: updatePanel.compositorState(), detail: updatePanel.compositorDetail(),
                viewport: rect(toolsScroll), tiles: Array.from(toolsFlow.children).map(item => ({
                    label: item.label, focus: item.activeFocus, rect: rect(item)}))});
        }
        function fixture(kind: string): void {
            Updates.checking = false; Updates.lastCheck = new Date(); Updates.error = "";
            Updates.repo = []; Updates.aur = []; Updates.flatpak = [];
            ShellUpdates.ready = true; ShellUpdates.checking = false;
            ShellUpdates.error = ""; ShellUpdates.updateAvailable = false;
            ShellUpdates.compositorReady = true; ShellUpdates.compositorChecking = false;
            ShellUpdates.compositorInstalled = true; ShellUpdates.compositorError = "";
            ShellUpdates.compositorUpdateAvailable = false; ShellUpdates.compositorInstallable = false;
            ShellUpdates.compositorBlockedReason = kind === "blocked"
                ? "Local development branch fix/pointer-focus-modifiers: 1 local and 37 upstream-only commits. Automatic updates are paused to preserve your local work." : "";
            if (kind === "error") ShellUpdates.compositorError = "Remote check failed";
            if (kind === "pending") ShellUpdates.compositorReady = false;
            if (kind === "loading") ShellUpdates.compositorChecking = true;
            if (kind === "system-error") Updates.error = "System check failed";
        }
    }
"""
        path.write_text(text[:end] + handler + text[end:])
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
        time.sleep(0.8)
        def snapshot():
            return json.loads(ipc('dashboardProbe', 'snapshot'))

        def tile_focus(label):
            require(focus_name() == label, f'Expected {label}, got {focus_name()}')
            data = snapshot()
            rows = [row for row in data['tiles'] if row['focus']]
            require(len(rows) == 1 and rows[0]['label'] == label, 'Qt and AT-SPI focus differ')
            require(rect_contains(data['viewport'], rows[0]['rect']), 'Focused tile clipped')
            return rows[0]

        ipc('dashboard', 'view', 'tools')
        wait(lambda: state()['dashboard'], 'Dashboard open')
        time.sleep(0.6)
        tile_focus('Tasks')
        require(sum(x['namespace'] == 'nbshell:dashboard' and x['mapped'] for x in layers()) == 1,
                'Missing or duplicate dashboard layer')
        data = snapshot()
        columns = sum(row['rect'][1] == data['tiles'][0]['rect'][1] for row in data['tiles'])
        key('Right'); tile_focus('Notes')
        key('Down'); tile_focus(data['tiles'][columns + 1]['label'])
        key('Up'); tile_focus('Notes')
        key('Left'); tile_focus('Tasks')
        capture('dashboard-tools')
        # Traverse to the final row and assert actual viewport containment.
        for _ in range(14):
            key('Down')
            tile_focus(focus_name())
        capture('dashboard-scrolled')
        key('1')
        require(snapshot()['page'] == 0, 'Page 1 shortcut failed')
        key('2')
        require(snapshot()['page'] == 1, 'Page 2 shortcut failed')
        key('3'); tile_focus('Tasks')
        # Tab follows reading order and exposes the separate secondary button.
        for _ in range(4): key('Tab')
        tile_focus('Capture')
        key('Tab'); require(focus_name() == 'Toggle screen recording', 'Secondary Tab focus')
        key('Tab', shift=True); tile_focus('Capture')
        key('Tab'); key('Right'); tile_focus('Theme')
        key('Tab'); require(focus_name() == 'Next theme', 'Theme secondary focus')
        key('Tab', shift=True); tile_focus('Theme')
        # Secondary activation uses only the disposable configuration.
        key('Tab'); key('Return')
        require(json.loads(ipc('config', 'get', 'theme')) != args.theme, 'Secondary Enter did not act')
        ipc('config', 'set', 'theme', args.theme)
        key('3')
        # Same-page shortcuts leave focus alone; switch away/back to select first tile.
        key('1'); key('3'); tile_focus('Tasks')
        for _ in range(3): key('Tab')
        tile_focus('Updates')
        ipc('dashboardProbe', 'fixture', 'blocked')
        key('Return')
        require(snapshot()['modal'], 'Enter did not open update dialog')
        require(focus_name() == 'Check again', 'Dialog initial focus')
        key('1'); require(snapshot()['page'] == 2, 'Modal leaked page shortcut')
        key('Down'); require(snapshot()['modal'], 'Modal leaked arrow')
        key('Tab'); require(focus_name() == 'Close', 'Dialog Tab focus')
        key('Tab', shift=True); require(focus_name() == 'Check again', 'Dialog Shift+Tab focus')
        for kind in ['blocked', 'error', 'pending', 'loading', 'system-error', 'current']:
            ipc('dashboardProbe', 'fixture', kind)
            data = snapshot()
            require(data['current'] == (kind == 'current'), 'False all-current: ' + kind)
            if kind == 'blocked':
                require(data['state'] == 'PAUSED', 'Development branch shown as error/current')
                require('preserve your local work' in data['detail'], 'Missing preservation explanation')
            capture('updates-' + kind)
        key('Escape'); tile_focus('Updates')
        require(not snapshot()['modal'] and state()['dashboard'], 'Dialog Escape closed dashboard')
        key('space'); require(snapshot()['modal'], 'Space did not reopen dialog')
        key('Escape'); tile_focus('Updates')
        key('Escape')
        wait(lambda: not state()['dashboard'], 'Dashboard Escape')
        ipc('dashboard', 'view', 'tools')
        time.sleep(0.6)
        tile_focus('Tasks')
        key('Escape')
        log = Path('/work/shell.log').read_text()
        require(not any(s in log for s in ['ReferenceError', 'TypeError', 'Binding loop']), 'QML runtime error')
        print('PASS: Dashboard real focus, spatial arrows/reflow, scroll, Tab/secondary activation, pages, modal and update states', flush=True)
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
                   '--', 'dbus-run-session', '--', 'python3', '/source/tests/wayland-dashboard-focus.py',
                   *sys.argv[1:], '--inside']
        result = subprocess.run(command, timeout=180)
        if args.screenshots:
            for image in Path(directory).glob('*.png'):
                shutil.copyfile(image, args.screenshots / image.name)
            for name in ['shell.log', 'compositor.log']:
                shutil.copyfile(Path(directory) / name, args.screenshots / name)
        if result.returncode:
            for name in ['shell.log', 'compositor.log']:
                path = Path(directory) / name
                if path.exists():
                    print(name + '\n' + path.read_text()[-12000:])
        require(result.returncode == 0, f'Isolated focus regression failed: {result.returncode}')


if __name__ == '__main__':
    main()
