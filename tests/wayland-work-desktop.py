#!/usr/bin/env python3
"""Isolated Wayland regression for desktop work-card layout and lifecycle.

Requires bubblewrap, wtype, Umbriel, its built pointer-client, and Quickshell. Never installs or targets
the live desktop. All config mutations occur inside a disposable namespace.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import signal
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


def inside(args):
    require(os.environ.get('NBSHELL_FOCUS_TEST') == '1', 'Missing sandbox marker')
    require(not Path('/run/dbus/system_bus_socket').exists(), 'Host bus exposed')
    home = Path('/home/test')
    config = home / '.config/nbshell'
    config.mkdir(parents=True)
    (config / 'themes').symlink_to('/source/themes')
    (config / 'config.json').write_text(json.dumps({
        'schemaVersion': 1, 'theme': args.theme, 'motionProfile': args.motion,
        'workDesktop': True, 'mode': 'bar', 'leftWidgets': ['workspaces', 'clock'],
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

    def capture(name):
        if args.screenshots:
            run(['grim', '/work/' + name + '.png'])

    def key(name, shift=False):
        run(['wtype', *(['-M', 'shift'] if shift else []), '-k', name,
             *(['-m', 'shift'] if shift else [])])
        time.sleep(0.15)


    try:
        shutil.copytree('/source/shell', '/work/shell')
        agent_path = Path('/work/shell/Services/Agents.qml')
        agent_path.write_text(agent_path.read_text().replace('function refreshSessions() {', 'function refreshSessions() { return;'))
        path = Path('/work/shell/Menu/WorkDesktop.qml')
        source = path.read_text().replace('import Quickshell.Wayland', 'import Quickshell.Io\nimport Quickshell.Wayland')
        handler = """
            IpcHandler {
                target: "workProbe"
                function snapshot(): string {
                    function rect(item) {
                        if (!item) return [];
                        const p = item.mapToItem(null, 0, 0);
                        return [p.x, p.y, item.width, item.height];
                    }
                    const f = win.contentItem.Window.window.activeFocusItem;
                    return JSON.stringify({columns: grid.columns, viewport: rect(desk),
                        first: rect(header.children[0]),
                        focus: f ? f.Accessible.name : "", rect: rect(f), scroll: desk.contentY});
                }
                function fixture(empty: bool): void {
                    Agents.sessions = [];
                    Agents.monitorError = empty ? "Herdr unavailable (fixture)" : "";
                    Agents.openclaw = {online: true, items: empty ? [] : Array.from({length: 18}, (_, i) => ({
                        backend: "openclaw", id: "fixture-" + i, title: "Synthetic session " + i + " — long project description for narrow layouts",
                        status: i === 0 ? "working" : "idle", updatedAt: 100 - i,
                        progress: i === 0 ? "Step 1: a deliberately long progress summary that wraps without covering other controls" : ""
                    }))};
                    AiUsage.list = [{name: "Synthetic provider", limits: [{label: "Weekly", percent: 92}]}];
                }
            }
"""
        source=source.replace('            Flickable {', handler + '\n            Flickable {', 1)
        path.write_text(source)
        launch(['/test-bin/umbriel', '-c', str(compositor_config)], 'compositor.log')
        wait(lambda: (runtime / 'umbriel-wayland-0.sock').exists(), 'compositor IPC')
        os.environ.update(WAYLAND_DISPLAY='wayland-0', UMBRIEL_SOCKET=str(runtime / 'umbriel-wayland-0.sock'))
        launch(['/pointer-client', str(args.width), str(args.height), 'mod', 'none', 'pause', '300000'], 'keyboard.log')
        launch(['/test-bin/qs', '-p', '/work/shell', '--no-color'], 'shell.log')
        wait(lambda: run(['/test-bin/qs', '-p', '/work/shell', 'ipc', 'call', 'work', 'status'], False).returncode == 0, 'shell IPC')
        time.sleep(1)
        ipc('workProbe', 'fixture', 'true')
        time.sleep(0.4)
        capture('work-empty')
        ipc('workProbe', 'fixture', 'false')
        time.sleep(0.4)
        capture('work-sessions')
        def snapshot(): return json.loads(ipc('workProbe', 'snapshot'))
        data=snapshot()
        require(data['columns'] == (1 if args.width < 900 else 2), 'Unexpected responsive layout')
        x,y,w,h=data['first']
        run(['/pointer-client', str(args.width), str(args.height), 'move', str(int(x+w/2)), str(int(y+h/2)), 'click', '272'])
        time.sleep(0.2)
        require('sessions' not in json.loads(ipc('work','status'))['modules'], 'Pointer module toggle failed')
        key('Return')
        require('sessions' in json.loads(ipc('work','status'))['modules'], 'Keyboard module toggle failed')
        for _ in range(6): key('Tab')
        data=snapshot()
        require(data['focus'].startswith('Synthetic session'), 'Tab did not reach session card: '+str(data))
        require(rect_contains(data['viewport'],data['rect']), 'Focused session clipped')
        for _ in range(11): key('Tab')
        require(snapshot()['focus'].startswith('Show all'), 'Missing expand control')
        key('Return')
        key('Tab', True)
        data=snapshot()
        require(data['focus'].startswith('Synthetic session 17'), 'Expanded list traversal failed: '+str(data))
        require(rect_contains(data['viewport'],data['rect']), 'Expanded focused session clipped: '+str(data))
        capture('work-keyboard-scroll')
        key('Tab'); key('Tab')
        data=snapshot()
        require(data['focus'] == '● SESSIONS', 'Tab did not cycle back to toolbar')
        require(rect_contains(data['viewport'],data['rect']), 'Toolbar focus did not scroll back into view: '+str(data))
        key('Escape')
        require(not json.loads(ipc('work','status'))['enabled'], 'Escape did not hide desktop')
        require(not json.loads(ipc('work','status'))['sessions'], 'Disabled desktop kept session demand')
        ipc('dashboard','view','work'); time.sleep(0.3)
        require(json.loads(ipc('work','status'))['sessions'], 'Dashboard failed to acquire shared demand')
        ipc('dashboard','close'); time.sleep(0.3)
        require(not json.loads(ipc('work','status'))['sessions'], 'Dashboard failed to release shared demand')
        ipc('work','on'); ipc('work','module','sessions','off'); ipc('work','module','git','off'); time.sleep(0.3)
        require(not json.loads(ipc('work','status'))['sessions'], 'Disabled modules kept session demand')
        log=Path('/work/shell.log').read_text()
        require(not any(s in log for s in ['ReferenceError', 'TypeError', 'Binding loop', 'is not a type']), 'QML runtime error')
        print('PASS: work desktop empty/long data, responsive layout, pointer and keyboard toggles, scroll focus, Escape, shared demand', flush=True)
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
                   '--', 'dbus-run-session', '--', 'python3', '/source/tests/wayland-work-desktop.py',
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
