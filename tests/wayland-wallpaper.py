#!/usr/bin/env python3
"""Exercise dynamic wallpaper UI and player lifecycle in a private Wayland session.

No host configuration, session bus, windows or lock state are touched.
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
    require(os.environ.get('NBSHELL_WALLPAPER_TEST') == '1', 'Missing sandbox marker')
    require(not Path('/run/dbus/system_bus_socket').exists(), 'Host system bus exposed')
    test_home = Path.home()
    config = test_home / '.config/nbshell'
    config.mkdir(parents=True)
    (config / 'themes').symlink_to('/source/themes')
    (config / 'config.json').write_text(json.dumps({
        'schemaVersion': 1, 'theme': args.theme, 'motionProfile': args.motion,
        'idle': False,
        'mode': 'bar', 'leftWidgets': ['clock'], 'centerWidgets': [],
        'rightWidgets': [], 'collapsedWidgets': ['clock'],
    }))
    Path('/run/test').mkdir(mode=0o700)
    os.environ.update(XDG_CONFIG_HOME=str(test_home / '.config'),
                      XDG_CACHE_HOME=str(test_home / '.cache'), XDG_STATE_HOME=str(test_home / '.local/state'),
                      XDG_DATA_HOME=str(test_home / '.local/share'), XDG_RUNTIME_DIR='/run/test',
                      WLR_BACKENDS='headless', WLR_HEADLESS_OUTPUTS='1', WLR_LIBINPUT_NO_DEVICES='1',
                      WLR_RENDER_DRM_DEVICE=args.render_node, QT_QPA_PLATFORM='wayland',
                      QSG_RHI_BACKEND='opengl', QT_QPA_PLATFORMTHEME='',
                      NBSHELL_DISABLE_HOT_RELOAD='1')
    Path('/work/umbriel.toml').write_text('[general]\nxwayland = false\nshow_cheatsheet = false\nautostart = []\n'
                                        f'[output.HEADLESS-1]\nmode = "{args.width}x{args.height}@60"\nscale = 1.0\n')
    shutil.copytree('/source/shell', '/work/shell')
    wallpaper = Path('/work/shell/Bar/Wallpaper.qml')
    text = wallpaper.read_text().replace('import QtQuick', 'import QtQuick\nimport Quickshell.Io', 1)
    text = text.replace('            // Empty desktop gestures', '\n' + """            IpcHandler {
                target: "wallpaperProbe"
                function state(): string { return JSON.stringify({eligible: win.mayPlay, active: video.active, status: video.status, source: win.source, locked: DynamicWallpaper.nativeLocked, error: DynamicWallpaper.error, position: video.item ? video.item.position : -1, details: video.item ? video.item.details : "unloaded"}); }
                function config(key: string, value: string): bool { return Config.set(key, JSON.parse(value)); }
                function windows(present: bool): string {
                    Compositor.workspaces = [{id: 1, output: win.screen.name, is_active: true}];
                    Compositor.windows = present ? [{workspace: 1}] : [];
                    return "set";
                }
            }
""" + '\n            // Empty desktop gestures')
    wallpaper.write_text(text)
    player = Path('/work/shell/Wallpaper/VideoWallpaper.qml')
    player.write_text(player.read_text().replace('id: root', 'id: root\n    property alias position: player.position\n    readonly property string details: [player.playbackState, player.mediaStatus, player.hasVideo, width, height, output.visible, output.contentRect].join(";")', 1))

    picker = Path('/work/shell/Wallpaper/WallpaperPicker.qml')
    text = picker.read_text(); end = text.rfind('}')
    picker.write_text('import Quickshell.Io\n' + text[:end] + """
    IpcHandler {
        target: "wallpaperUi"
        function isOpen(): bool { return root.preferencesOpen; }
        function open(): bool { root.preferencesOpen = true; editor.forceActiveFocus(); return root.preferencesOpen; }
        function focus(): string { return String(root.contentItem.Window.window.activeFocusItem); }
    }
""" + text[end:])

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

    try:
        launch(['/test-bin/umbriel', '-c', '/work/umbriel.toml'], 'compositor.log')
        wait(lambda: Path('/run/test/umbriel-wayland-0.sock').exists(), 'compositor')
        os.environ.update(WAYLAND_DISPLAY='wayland-0', UMBRIEL_SOCKET='/run/test/umbriel-wayland-0.sock')
        shell = launch(['/test-bin/qs', '-p', '/work/shell', '--no-color'], 'shell.log')
        wait(lambda: run(['/test-bin/qs', '-p', '/work/shell', 'ipc', 'call', 'state', 'dump'], False).returncode == 0, 'shell IPC')
        ipc('wallpaper', 'pick')
        time.sleep(1)
        run(['wtype', '-s', '200', '-k', 'd', '-s', '200'])
        require(ipc('wallpaperUi', 'isOpen') == 'true', 'Keyboard did not open dynamic settings')
        ipc('wallpaperProbe', 'config', 'dynamicWallpaper', json.dumps({'daytimeEnabled':True}))
        time.sleep(1)
        run(['grim', '/work/wallpaper-settings.png'])
        print(ipc('wallpaperProbe', 'state'), flush=True)
        for _ in range(12): run(['wtype', '-s', '200', '-k', 'Tab', '-s', '100'])
        run(['grim', '/work/wallpaper-focus.png'])
        run(['wtype', '-s', '200', '-k', 'Escape', '-s', '100'])
        run(['wtype', '-s', '200', '-k', 'Escape', '-s', '100'])
        ipc('wallpaperProbe', 'config', 'motionProfile', '"standard"')
        run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i', 'testsrc2=size=320x180:rate=24', '-t', '2', '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '/work/loop.mp4'])
        ipc('wallpaperProbe', 'config', 'dynamicWallpaper', json.dumps({'videoEnabled':True,'video':'/work/loop.mp4'}))
        ipc('wallpaperProbe', 'windows', 'false')
        time.sleep(3)
        playback = json.loads(ipc('wallpaperProbe', 'state'))
        print('PLAYBACK', playback, flush=True)
        require(playback['active'] and playback['status'] == 1, 'Video did not load')
        run(['grim', '/work/wallpaper-loop.png'])
        time.sleep(0.7)
        later = json.loads(ipc('wallpaperProbe', 'state'))
        require(later['position'] != playback['position'], 'Video position did not advance')
        run(['grim', '/work/wallpaper-loop-next.png'])
        Path('/run/test/nbshell-lock-ready').touch()
        time.sleep(1)
        locked = json.loads(ipc('wallpaperProbe', 'state'))
        require(locked['locked'] and not locked['active'], 'Native lock did not unload video')
        Path('/run/test/nbshell-lock-ready').unlink()
        time.sleep(2)
        require(json.loads(ipc('wallpaperProbe', 'state'))['active'], 'Unlock did not resume')
        Path('/run/test/nbshell-lock-ready').touch()
        time.sleep(1)
        require(not json.loads(ipc('wallpaperProbe', 'state'))['active'], 'Second lock did not unload')
        Path('/run/test/nbshell-lock-ready').unlink()
        time.sleep(2)
        require(json.loads(ipc('wallpaperProbe', 'state'))['active'], 'Second unlock did not resume')
        ipc('wallpaperProbe', 'windows', 'true')
        time.sleep(1)
        require(not json.loads(ipc('wallpaperProbe', 'state'))['active'], 'Window did not unload video')
        ipc('wallpaperProbe', 'windows', 'false')
        ipc('wallpaperProbe', 'config', 'dynamicWallpaper', json.dumps({'videoEnabled':True,'video':'/missing.mp4'}))
        time.sleep(2)
        broken = json.loads(ipc('wallpaperProbe', 'state'))
        require(not broken['active'] and 'Video unavailable' in broken['error'], 'Broken video did not fall back')
        print('PASS: keyboard UI, video load, two native lock cycles, workspace pause, missing video fallback', flush=True)
        return

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
    parser.add_argument('--compositor', required=True)
    parser.add_argument('--quickshell', default='/usr/bin/quickshell')
    parser.add_argument('--render-node', required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--theme', default='tokyo-night')
    parser.add_argument('--motion', choices=['standard', 'reduced'], default='standard')
    parser.add_argument('--width', type=int, default=800)
    parser.add_argument('--height', type=int, default=600)
    parser.add_argument('--inside', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.inside:
        inside(args); return
    root = Path(__file__).resolve().parents[1]
    for binary in (args.compositor, args.quickshell, 'bwrap', 'dbus-run-session', 'grim', 'wtype', 'ffmpeg'):
        require(shutil.which(binary), 'Missing executable: ' + binary)
    render = Path(args.render_node)
    require(render.parent == Path('/dev/dri') and render.name.startswith('renderD') and render.is_char_device(), 'Choose a DRM render node')
    args.output.mkdir(parents=True, exist_ok=False)
    with tempfile.TemporaryDirectory(prefix='nbshell-wallpaper-') as directory:
        command = ['bwrap', '--unshare-all', '--die-with-parent', '--new-session', '--cap-drop', 'ALL',
                   '--ro-bind', '/usr', '/usr', '--symlink', 'usr/bin', '/bin', '--symlink', 'usr/lib', '/lib',
                   '--symlink', 'usr/lib', '/lib64', '--ro-bind', '/etc', '/etc', '--ro-bind', '/sys', '/sys',
                   '--proc', '/proc', '--dev', '/dev', '--dev-bind', str(render), str(render),
                   '--tmpfs', '/tmp', '--tmpfs', '/run', '--tmpfs', '/home', '--dir', '/var',
                   '--ro-bind', str(root), '/source', '--bind', directory, '/work',
                   '--ro-bind', str(Path(args.quickshell).resolve()), '/test-bin/qs',
                   '--ro-bind', str(Path(args.compositor).resolve()), '/test-bin/umbriel',
                   '--clearenv', '--setenv', 'PATH', '/test-bin:/usr/local/bin:/usr/bin:/bin',
                   '--setenv', 'HOME', str(Path.home()), '--setenv', 'LANG', 'C.UTF-8', '--setenv', 'NBSHELL_WALLPAPER_TEST', '1',
                   '--setenv', 'PYTHONDONTWRITEBYTECODE', '1', '--chdir', '/work',
                   '--', 'dbus-run-session', '--', 'python3', '/source/tests/wayland-wallpaper.py', *sys.argv[1:], '--inside']
        try:
            result = subprocess.run(command, timeout=90)
            require(result.returncode == 0, 'Isolated wallpaper run failed; inspect output logs')
        finally:
            for path in Path(directory).iterdir():
                if path.is_file() and path.suffix in ('.log', '.json', '.png'):
                    shutil.copyfile(path, args.output / path.name)


if __name__ == '__main__': main()
