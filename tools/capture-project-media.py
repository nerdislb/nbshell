#!/usr/bin/env python3
"""Capture real nbshell UI with isolated synthetic data for project documentation.

Requires bubblewrap, wtype, Umbriel, and Quickshell. Never installs or targets
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


def inside(args):
    require(os.environ.get('NBSHELL_FOCUS_TEST') == '1', 'Missing sandbox marker')
    require(not Path('/run/dbus/system_bus_socket').exists(), 'Host bus exposed')
    home = Path('/home/user')
    config = home / '.config/nbshell'
    config.mkdir(parents=True)
    (config / 'themes').symlink_to('/source/themes')
    (config / 'config.json').write_text(json.dumps({
        'schemaVersion': 1, 'theme': args.theme, 'motionProfile': args.motion,
        'workDesktop': True, 'bongoActive': False, 'meterStyle': 'line',
        'wallpaperOverride': '/source/wallpapers/' + args.theme + '/1.webp',
        'wallpaperByTheme': {args.theme: '/source/wallpapers/' + args.theme + '/1.webp'},
        'mode': 'bar', 'leftWidgets': ['workspaces'],
        'centerWidgets': ['clock'], 'rightWidgets': [], 'collapsedWidgets': ['clock'],
    }))
    data = home / '.local/share/nbshell'
    data.mkdir(parents=True)
    (data / 'wallpapers').symlink_to('/source/wallpapers')
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

    try:
        shutil.copytree('/source/shell', '/work/shell')
        services=Path('/work/shell/Services')
        for name, method in [('Agents.qml','refreshSessions'), ('AiUsage.qml','refresh')]:
            path=services/name
            path.write_text(path.read_text().replace('function '+method+'() {','function '+method+'() { return;'))
        path=services/'WorkState.qml'
        text=path.read_text().replace('onTriggered: if (!deviceProc.running) deviceProc.running = true','onTriggered: {}')
        text=text.replace('function refreshGit() {','function refreshGit() { return;')
        path.write_text(text)
        (services/'SysInfo.qml').write_text('pragma Singleton\nimport QtQuick\nimport Quickshell\nSingleton { property int cpuPercent: 24; property int memPercent: 38; property real memUsedGb: 6.1; property real memTotalGb: 16; property bool detailWanted: false; property bool withGpu: false; property var detail: ({}); property bool hasDetail: false; function refreshDetail() {} }\n')
        # No host NetworkManager or UPower bus is mounted. Replace the displayed
        # offline summary with a labelled fixture; the real services stay absent.
        path=services/'Net.qml'; text=path.read_text(); begin=text.index('    readonly property string summary:'); end=text.index('\n    readonly property bool online:',begin)
        text=text[:begin]+'    readonly property string summary: "Demo network (synthetic)"\n'+text[end:];path.write_text(text)
        path=services/'PowerService.qml';text=path.read_text().replace('readonly property bool available: device !== null && device.isLaptopBattery','readonly property bool available: false');path.write_text(text)
        path=Path('/work/shell/shell.qml')
        text=path.read_text()
        injection="""
    Timer {
        interval: 500; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            Agents.monitorError = "";
            Agents.sessions = [{backend: "herdr", id: "demo-herdr", title: "Review keyboard navigation", status: "waiting", project: "/home/user/projects/shell-ui", progress: "Ready for feedback", updatedAt: 2}];
            Agents.openclaw = {online: true, items: [
                {backend: "openclaw", id: "demo-docs", title: "Refresh project documentation", status: "working", project: "/home/user/projects/nbshell", progress: "2/3 steps · Verify examples and links", updatedAt: 3},
                {backend: "openclaw", id: "demo-tests", title: "Check responsive layouts", status: "working", project: "/home/user/projects/shell-ui", progress: "Dark and light theme checks", updatedAt: 2},
                {backend: "openclaw", id: "demo-1", title: "Polish the compact activity grid", status: "idle", updatedAt: 1},
                {backend: "openclaw", id: "demo-2", title: "Improve the theme preview", status: "idle", updatedAt: 1},
                {backend: "openclaw", id: "demo-3", title: "Update the getting-started guide", status: "idle", updatedAt: 1},
                {backend: "openclaw", id: "demo-4", title: "Review optional integrations", status: "idle", updatedAt: 1}
            ]};
            WorkState.device = {host: "demo-workstation · synthetic", disk: "DISK /  320 GiB free / 512 GiB", uptime: "2d 4h"};
            WorkState.projects = {
                "/home/user/projects/nbshell": {root: "/home/user/projects/nbshell", branch: "main", changed: 3, conflicts: 0},
                "/home/user/projects/shell-ui": {root: "/home/user/projects/shell-ui", branch: "feature/keyboard", changed: 0, conflicts: 0}
            };
            const days = (values) => values.map((tokens,i) => ({date: "2026-09-"+String(i+8).padStart(2,"0"),tokens}));
            AiUsage.localStats = {codex: {recentDays: days([2100,9000,6400,11000,3800,15000,7200])}, claude: {recentDays: days([4300,2500,12000,8100,5300,2600,6400])}};
            AiUsage.list = [
                {name: "OpenAI Codex · demo", limits: [{label: "Weekly",percent: 42}]},
                {name: "Claude Code · demo", limits: [{label: "5 hour",percent: 28},{label: "7 day",percent: 61}]}
            ];
        }
    }
"""
        end=text.rfind('}');path.write_text(text[:end]+injection+text[end:])
        launch(['/test-bin/umbriel','-c',str(compositor_config)],'compositor.log')
        wait(lambda: (runtime/'umbriel-wayland-0.sock').exists(),'compositor IPC')
        os.environ.update(WAYLAND_DISPLAY='wayland-0',UMBRIEL_SOCKET=str(runtime/'umbriel-wayland-0.sock'))
        launch(['/test-bin/qs','-p','/work/shell','--no-color'],'shell.log')
        wait(lambda: run(['/test-bin/qs','-p','/work/shell','ipc','call','work','status'],False).returncode==0,'shell IPC')
        time.sleep(2)
        ipc('wallpaper', 'set', '/source/wallpapers/' + args.theme + '/1.webp')
        time.sleep(1)
        capture('work-desk')
        ipc('work','off');time.sleep(0.5)
        ipc('menu','open');time.sleep(0.8);capture('menu');ipc('menu','close')
        ipc('store','open');time.sleep(2)
        ipc('wallpaper', 'set', '/source/wallpapers/' + args.theme + '/1.webp')
        time.sleep(0.5);capture('library');ipc('store','close')
        log=Path('/work/shell.log').read_text()
        require(not any(s in log for s in ['ReferenceError','TypeError','Binding loop','is not a type']), 'QML runtime error in capture')
        print('PASS: isolated project media captured; all account/project/machine data is synthetic',flush=True)
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
    parser.add_argument('--render-node', required=True)
    parser.add_argument('--theme', default='nbdark')
    parser.add_argument('--motion', choices=['standard', 'reduced'], default='standard')
    parser.add_argument('--width', type=int, default=1920)
    parser.add_argument('--height', type=int, default=1080)
    parser.add_argument('--screenshots', type=Path, help='Export synthetic screenshots to a new directory')
    parser.add_argument('--inside', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.inside:
        inside(args)
        return
    root = Path(__file__).resolve().parents[1]
    for binary in [args.quickshell, args.compositor, 'bwrap', 'dbus-run-session', 'wtype']:
        require(shutil.which(binary), 'Missing executable: ' + binary)
    if args.screenshots:
        require(shutil.which('grim'), 'Missing executable: grim')
        args.screenshots.mkdir(parents=True, exist_ok=False)
    with tempfile.TemporaryDirectory(prefix='nbshell-media-') as directory:
        command = ['bwrap', '--unshare-all', '--die-with-parent', '--new-session',
                   '--ro-bind', '/usr', '/usr', '--symlink', 'usr/bin', '/bin',
                   '--symlink', 'usr/lib', '/lib', '--symlink', 'usr/lib', '/lib64',
                   '--ro-bind', '/etc', '/etc', '--ro-bind', '/sys', '/sys', '--proc', '/proc',
                   '--dev', '/dev', '--dev-bind', str(Path(args.render_node).parent), '/dev/dri',
                   '--tmpfs', '/tmp', '--tmpfs', '/run', '--tmpfs', '/home', '--dir', '/var',
                   '--ro-bind', str(root), '/source', '--bind', directory, '/work',
                   '--ro-bind', str(Path(args.quickshell).resolve()), '/test-bin/qs',
                   '--ro-bind', str(Path(args.compositor).resolve()), '/test-bin/umbriel',
                   '--clearenv', '--setenv', 'PATH', '/test-bin:/usr/local/bin:/usr/bin:/bin',
                   '--setenv', 'LANG', 'C.UTF-8', '--setenv', 'NBSHELL_FOCUS_TEST', '1',
                   '--setenv', 'PYTHONDONTWRITEBYTECODE', '1', '--chdir', '/work',
                   '--', 'dbus-run-session', '--', 'python3', '/source/tools/capture-project-media.py',
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
        require(result.returncode == 0, f'Isolated media capture failed: {result.returncode}')


if __name__ == '__main__':
    main()
