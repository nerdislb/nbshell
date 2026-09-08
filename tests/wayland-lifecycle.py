#!/usr/bin/env python3
"""Measure mapped-layer lifecycle in a private headless Wayland session.

Measures IPC-to-mapped-layer latency (including CLI/polling overhead), not first
frame presentation. Never targets the host session or uses its configuration.
"""
import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import statistics
import subprocess
import sys
import tempfile
import time


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def inside(args):
    require(os.environ.get('NBSHELL_LIFECYCLE_TEST') == '1', 'Missing sandbox marker')
    require(not Path('/run/dbus/system_bus_socket').exists(), 'Host system bus exposed')
    config = Path('/home/test/.config/nbshell')
    config.mkdir(parents=True)
    (config / 'themes').symlink_to('/source/themes')
    (config / 'config.json').write_text(json.dumps({
        'schemaVersion': 1, 'theme': args.theme, 'motionProfile': args.motion,
        'idle': False,
        'mode': 'bar', 'leftWidgets': ['clock'], 'centerWidgets': [],
        'rightWidgets': [], 'collapsedWidgets': ['clock'],
    }))
    Path('/run/test').mkdir(mode=0o700)
    os.environ.update(HOME='/home/test', XDG_CONFIG_HOME='/home/test/.config',
                      XDG_CACHE_HOME='/home/test/.cache', XDG_STATE_HOME='/home/test/.local/state',
                      XDG_DATA_HOME='/home/test/.local/share', XDG_RUNTIME_DIR='/run/test',
                      WLR_BACKENDS='headless', WLR_HEADLESS_OUTPUTS='1', WLR_LIBINPUT_NO_DEVICES='1',
                      WLR_RENDER_DRM_DEVICE=args.render_node, QT_QPA_PLATFORM='wayland',
                      QT_QUICK_BACKEND='software', QT_QPA_PLATFORMTHEME='',
                      NBSHELL_DISABLE_HOT_RELOAD='1')
    Path('/work/umbriel.toml').write_text('[general]\nxwayland = false\nshow_cheatsheet = false\nautostart = []\n'
                                        f'[output.HEADLESS-1]\nmode = "{args.width}x{args.height}@60"\nscale = 1.0\n')
    shutil.copytree('/source/shell', '/work/shell')
    root = Path('/work/shell/shell.qml')
    source = root.read_text(); end = source.rfind('}')
    # Diagnostic IPC lives only in the disposable copy, never production.
    source = source[:end] + '''
    IpcHandler {
        target: "lifecycleProbe"
        function closePanels(): string {
            Runtime.settingsOpen = false;
            Runtime.modulesOpen = false;
            Runtime.closeMenu();
            return "closed";
        }
    }
''' + source[end:]
    root.write_text(source)
    settings = Path('/work/shell/Settings/SettingsMenu.qml')
    source = settings.read_text(); end = source.rfind('}')
    source = 'import Quickshell.Io\n' + source[:end] + '''
    IpcHandler {
        target: "lifecycleSettings"
        enabled: root.visible && !root.embedded
        function headerVisible(): bool {
            return content.mapToItem(viewport, 0, 0).y >= 0;
        }
    }
''' + source[end:]
    settings.write_text(source)
    processes, handles = [], []

    def launch(command, name):
        handle = open('/work/' + name, 'w'); handles.append(handle)
        proc = subprocess.Popen(command, stdout=handle, stderr=subprocess.STDOUT, start_new_session=True)
        processes.append(proc)
        return proc

    def run(command, check=True):
        return subprocess.run(command, capture_output=True, text=True, check=check, timeout=10)

    def wait(probe, label):
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            require(all(proc.poll() is None for proc in processes), 'Process exited: ' + label)
            if probe(): return
            time.sleep(0.01)
        raise RuntimeError('Timed out: ' + label)

    def ipc(*argv):
        return run(['/test-bin/qs', '-p', '/work/shell', 'ipc', 'call', *argv]).stdout.strip()

    def mapped(name):
        layers = json.loads(run(['/test-bin/umbriel', 'layers', '--json']).stdout)
        return [layer for layer in layers if layer['namespace'] == 'nbshell:' + name and layer['mapped']]

    def memory():
        values = dict(line.split(':', 1) for line in Path(f'/proc/{shell.pid}/smaps_rollup').read_text().splitlines() if ':' in line)
        return {'time': time.monotonic(), 'pss_kib': int(values['Pss'].split()[0]),
                'rss_kib': int(values['Rss'].split()[0])}

    try:
        launch(['/test-bin/umbriel', '-c', '/work/umbriel.toml'], 'compositor.log')
        wait(lambda: Path('/run/test/umbriel-wayland-0.sock').exists(), 'compositor')
        os.environ.update(WAYLAND_DISPLAY='wayland-0', UMBRIEL_SOCKET='/run/test/umbriel-wayland-0.sock')
        shell = launch(['/test-bin/qs', '-p', '/work/shell', '--no-color'], 'shell.log')
        wait(lambda: run(['/test-bin/qs', '-p', '/work/shell', 'ipc', 'call', 'state', 'dump'], False).returncode == 0, 'shell IPC')
        time.sleep(2)
        rows, samples = [], [memory()]
        for panel, command in [('settings', ('settings', 'open')), ('modules', ('settings', 'modules'))]:
            for index in range(args.cycles):
                start = time.monotonic()
                ipc(*command)
                wait(lambda: len(mapped(panel)) == 1, panel + ' map')
                elapsed = (time.monotonic() - start) * 1000
                time.sleep(0.15)
                if index == 0:
                    time.sleep(0.6)
                    run(['grim', '/work/' + panel + '.png'])
                    if panel == 'settings':
                        require(ipc('lifecycleSettings', 'headerVisible') == 'true', 'Settings opened with a clipped header')
                ipc('lifecycleProbe', 'closePanels')
                wait(lambda: not mapped(panel), panel + ' unmap')
                rows.append({'panel': panel, 'cycle': index, 'mapped_latency_ms': elapsed})
                if index % 10 == 0: samples.append(memory())
        deadline = time.monotonic() + args.settle_seconds
        while time.monotonic() < deadline:
            samples.append(memory())
            time.sleep(min(1, max(0, deadline - time.monotonic())))
        samples.append(memory())
        summary = {}
        for panel in ('settings', 'modules'):
            values = sorted(row['mapped_latency_ms'] for row in rows if row['panel'] == panel)
            summary[panel] = {'cycles': len(values), 'p50_ms': statistics.median(values),
                              'p95_ms': values[max(0, int(len(values) * .95 + .999) - 1)]}
        result = {'measurement': 'IPC-to-compositor-mapped-layer, includes CLI and polling overhead; software renderer',
                  'theme': args.theme, 'motion': args.motion, 'size': [args.width, args.height],
                  'summary': summary, 'samples': samples, 'cycles': rows}
        Path('/work/result.json').write_text(json.dumps(result, indent=2))
        log = Path('/work/shell.log').read_text()
        require(not any(word in log for word in ('ReferenceError', 'TypeError', 'Binding loop')), 'QML runtime error')
        print(json.dumps(summary, indent=2), flush=True)
    finally:
        for proc in reversed(processes):
            if proc.poll() is None: os.killpg(proc.pid, signal.SIGTERM)
        for proc in reversed(processes):
            try: proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(proc.pid, signal.SIGKILL); proc.wait()
        for handle in handles: handle.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compositor', required=True)
    parser.add_argument('--quickshell', default='/usr/bin/quickshell')
    parser.add_argument('--render-node', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--cycles', type=int, default=100)
    parser.add_argument('--settle-seconds', type=int, default=60)
    parser.add_argument('--theme', default='tokyo-night')
    parser.add_argument('--motion', choices=['standard', 'reduced'], default='standard')
    parser.add_argument('--width', type=int, default=800)
    parser.add_argument('--height', type=int, default=600)
    parser.add_argument('--inside', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    require(1 <= args.cycles <= 1000 and 0 <= args.settle_seconds <= 3600, 'Invalid duration/cycle count')
    if args.inside:
        inside(args); return
    root = Path(__file__).resolve().parents[1]
    for binary in (args.compositor, args.quickshell, 'bwrap', 'dbus-run-session', 'grim'):
        require(shutil.which(binary), 'Missing executable: ' + binary)
    render = Path(args.render_node)
    require(render.parent == Path('/dev/dri') and render.name.startswith('renderD') and render.is_char_device(), 'Choose a DRM render node')
    args.output.mkdir(parents=True, exist_ok=False)
    with tempfile.TemporaryDirectory(prefix='nbshell-lifecycle-') as directory:
        command = ['bwrap', '--unshare-all', '--die-with-parent', '--new-session', '--cap-drop', 'ALL',
                   '--ro-bind', '/usr', '/usr', '--symlink', 'usr/bin', '/bin', '--symlink', 'usr/lib', '/lib',
                   '--symlink', 'usr/lib', '/lib64', '--ro-bind', '/etc', '/etc', '--ro-bind', '/sys', '/sys',
                   '--proc', '/proc', '--dev', '/dev', '--dev-bind', str(render), str(render),
                   '--tmpfs', '/tmp', '--tmpfs', '/run', '--tmpfs', '/home', '--dir', '/var',
                   '--ro-bind', str(root), '/source', '--bind', directory, '/work',
                   '--ro-bind', str(Path(args.quickshell).resolve()), '/test-bin/qs',
                   '--ro-bind', str(Path(args.compositor).resolve()), '/test-bin/umbriel',
                   '--clearenv', '--setenv', 'PATH', '/test-bin:/usr/local/bin:/usr/bin:/bin',
                   '--setenv', 'LANG', 'C.UTF-8', '--setenv', 'NBSHELL_LIFECYCLE_TEST', '1',
                   '--setenv', 'PYTHONDONTWRITEBYTECODE', '1', '--chdir', '/work',
                   '--', 'dbus-run-session', '--', 'python3', '/source/tests/wayland-lifecycle.py', *sys.argv[1:], '--inside']
        try:
            result = subprocess.run(command, timeout=args.cycles * 10 + args.settle_seconds + 90)
            require(result.returncode == 0, 'Isolated lifecycle run failed; inspect output logs')
        finally:
            for path in Path(directory).iterdir():
                if path.is_file() and path.suffix in ('.log', '.json', '.png'):
                    shutil.copyfile(path, args.output / path.name)


if __name__ == '__main__': main()
