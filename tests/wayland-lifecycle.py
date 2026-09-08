#!/usr/bin/env python3
"""Measure mapped-layer lifecycle in a private headless Wayland session.

Measures IPC-to-mapped-layer latency (including CLI/polling overhead), not first
frame presentation. Never targets the host session or uses its configuration.
"""
import argparse
import json
import os
import re
import runpy
from collections import Counter
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
    config = Path('/home/user/.config/nbshell')
    config.mkdir(parents=True)
    (config / 'themes').symlink_to('/source/themes')
    (config / 'config.json').write_text(json.dumps({
        'schemaVersion': 1, 'theme': args.theme, 'motionProfile': args.motion,
        'idle': False,
        'mode': 'bar', 'leftWidgets': ['clock'], 'centerWidgets': [],
        'rightWidgets': ['ai'] if args.startup_ai_widget else [], 'collapsedWidgets': ['clock'],
    }))
    Path('/run/test').mkdir(mode=0o700)
    os.environ.update(HOME='/home/user', XDG_CONFIG_HOME='/home/user/.config',
                      XDG_CACHE_HOME='/home/user/.cache', XDG_STATE_HOME='/home/user/.local/state',
                      XDG_DATA_HOME='/home/user/.local/share', XDG_RUNTIME_DIR='/run/test',
                      WLR_BACKENDS='headless', WLR_HEADLESS_OUTPUTS='1', WLR_LIBINPUT_NO_DEVICES='1',
                      WLR_RENDER_DRM_DEVICE=args.render_node, QT_QPA_PLATFORM='wayland',
                      QT_QUICK_BACKEND='software', QT_QPA_PLATFORMTHEME='',
                      NBSHELL_DISABLE_HOT_RELOAD='1')
    Path('/work/umbriel.toml').write_text('[general]\nxwayland = false\nshow_cheatsheet = false\nautostart = []\n'
                                        f'[output.HEADLESS-1]\nmode = "{args.width}x{args.height}@60"\nscale = 1.0\n')
    shutil.copytree('/source/shell', '/work/shell')
    if args.startup_profile:
        # Process labels only: never log command arguments or user data.
        for service in Path('/work/shell/Services').glob('*.qml'):
            text = service.read_text()
            if 'pragma Singleton' not in text or 'Singleton {' not in text:
                continue
            text = text.replace('Singleton {', 'Singleton {\n    QtObject { Component.onCompleted: console.info("STARTUP_SERVICE ' + service.stem + '") }', 1)
            if 'onStarted:' not in text:
                number = [0]
                def trace(match):
                    number[0] += 1
                    return match.group(0) + '\n        onStarted: console.info("STARTUP_PROCESS ' + service.stem + '.' + str(number[0]) + '")\n'
                text = re.sub(r'\bProcess\s*\{', trace, text)
            service.write_text(text)
    root = Path('/work/shell/recovery.qml'  if args.recovery else '/work/shell/shell.qml')
    source = root.read_text(); end = source.rfind('}')
    # Diagnostic IPC lives only in the disposable copy, never production.
    source = source[:end] + '''
    IpcHandler {
        target: "lifecycleProbe"
        function showConfigError(): string {
            Config.readError = "Configuration could not be loaded. The file contains invalid JSON.";
            Config.configValid = false;
            Config.writeError = "Changes were not saved. An edited setting changed elsewhere; review the current value and retry your change.";
            return "shown";
        }
        function closePanels(): string {
            Runtime.settingsOpen = false;
            Runtime.modulesOpen = false;
            Runtime.agentCenterOpen = false;
            Runtime.dashboardOpen = false;
            Runtime.pluginDeveloperOpen = false;
            Runtime.closeMenu();
            return "closed";
        }
    }
''' + source[end:]
    if args.recovery:
        # Recovery runs without loading the main shell or any plugin services.
        source = root.read_text(); end = source.rfind('}')
        source = source[:end] + '''
    IpcHandler {
        target: "recoveryProbe"
        function ready(): bool { return !worker.running; }
        function preview(): string { root.run("preview", "/work/candidate.json"); return "started"; }
        function tokenReady(): bool { return !worker.running && root.token !== ""; }
        function apply(): string { root.run("apply", root.token); return "started"; }
        function restored(): bool { return !worker.running && root.token === "" && root.message.indexOf("restored") >= 0; }
        function retryStartup(): string { root.run("retry", ""); return "started"; }
        function focusVisible(): bool {
            const control = restore.activeFocus ? restore : retry;
            const y = control.mapToItem(viewport, 0, 0).y;
            return control.activeFocus && y >= 0 && y + control.height <= viewport.height;
        }
    }
''' + source[end:]
        Path('/work/candidate.json').write_bytes((config / 'config.json').read_bytes())
        if args.theme == 'tokyo-night':
            (config / 'config.json').write_text('{invalid startup config')
        else:
            state = Path('/home/user/.local/state/nbshell')
            state.mkdir(parents=True)
            (state / 'config-migrations.json').write_text('{invalid migration history')
    root.write_text(source)
    settings = Path('/work/shell/Settings/SettingsMenu.qml')
    source = settings.read_text(); end = source.rfind('}')
    source = 'import Quickshell.Io\n' + source[:end] + '''
    IpcHandler {
        target: root.embedded ? "lifecycleEmbeddedSettings" : "lifecycleSettings"
        enabled: root.visible
        function cursorThemesReady(): bool { return Cursor.themesLoaded; }
        function showCursorChoices(): string {
            root.group = root.groups.findIndex(group => group.head === "APPEARANCE");
            root.selected = 1;
            root.pane = 1;
            return "shown";
        }
        function focusRecovery(): string {
            root.pane = 1;
            root.switchPane();
            return "focused";
        }
        function recoveryFocused(): bool { return recoveryButton.activeFocus; }
        function headerVisible(): bool {
            return content.mapToItem(viewport, 0, 0).y >= 0;
        }
    }
''' + source[end:]
    settings.write_text(source)
    if args.startup_profile:
        menu = Path('/work/shell/Menu/Menu.qml')
        text = menu.read_text(); end = text.rfind('}')
        menu.write_text('import Quickshell.Io\n' + text[:end] + '''
    IpcHandler {
        target: "startupMenu"
        function settings(): string { root.openSettings(); return "open"; }
    }
''' + text[end:])
    panel_profile = None
    if args.panel_profile:
        panel_profile = runpy.run_path('/source/tests/panel-profile.py')
        panel_profile['instrument'](Path('/work/shell'), args.panel_async)
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
        return run(['/test-bin/qs', '-p', str(root) if args.recovery else '/work/shell', 'ipc', 'call', *argv]).stdout.strip()

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
        if args.recovery:
            shell = launch(['/test-bin/qs', '-p', str(root), '--no-color'], 'shell.log')
            wait(lambda: run(['/test-bin/qs', '-p', str(root), 'ipc', 'call', 'recoveryProbe', 'ready'], False).stdout.strip() == 'true', 'recovery IPC')
            time.sleep(1)
            run(['grim', '/work/recovery.png'])
            ipc('recoveryProbe', 'preview')
            wait(lambda: ipc('recoveryProbe', 'tokenReady') == 'true', 'candidate preview')
            time.sleep(0.5)
            require(ipc('recoveryProbe', 'focusVisible') == 'true', 'Restore focus is clipped')
            run(['grim', '/work/preview.png'])
            ipc('recoveryProbe', 'apply')
            wait(lambda: ipc('recoveryProbe', 'restored') == 'true', 'candidate restoration')
            time.sleep(0.5)
            require(ipc('recoveryProbe', 'focusVisible') == 'true', 'Retry focus is clipped')
            run(['grim', '/work/restored.png'])
            require(json.loads((config / 'config.json').read_text())['theme'] == args.theme, 'Candidate not restored')
            log = Path('/work/shell.log').read_text()
            require(not any(word in log for word in ('ReferenceError', 'TypeError', 'Binding loop')), 'Recovery QML runtime error')
            # Exercise the production Retry startup action and CLI fallback in
            # this private session, with no user systemd manager available.
            runtime = Path('/home/user/.config/quickshell')
            runtime.mkdir(parents=True)
            (runtime / 'nbshell').symlink_to('/work/shell')
            # The running recovery inherits its original PATH, so use a bridge
            # at a path already included when launching it.
            Path('/test-bin/nbshell').symlink_to('/source/bin/nbshell')
            ipc('recoveryProbe', 'retryStartup')
            wait(lambda: run(['/test-bin/qs', '-c', 'nbshell', 'ipc', 'call', 'config', 'status'], False).returncode == 0, 'recovered main shell IPC')
            status = json.loads(run(['/test-bin/qs', '-c', 'nbshell', 'ipc', 'call', 'config', 'status']).stdout)
            require(status['valid'], 'Recovered main shell rejected config')
            run(['/test-bin/qs', '-c', 'nbshell', 'kill'])
            Path('/work/results.json').write_text(json.dumps({'recovery': True, 'previewApplied': True, 'mainShellRestarted': True, 'focusVisible': True, 'theme': args.theme, 'motion': args.motion}))
            return
        shell = launch(['/test-bin/qs', '-p', '/work/shell', '--no-color'], 'shell.log')
        wait(lambda: run(['/test-bin/qs', '-p', '/work/shell', 'ipc', 'call', 'state', 'dump'], False).returncode == 0, 'shell IPC')
        time.sleep(2)
        if args.panel_profile:
            time.sleep(4)
            panel_profile['measure'](ipc, wait, mapped, args.cycles, args.panel_async)
            log = Path('/work/shell.log').read_text()
            require(not any(word in log for word in ('ReferenceError', 'TypeError', 'Binding loop')), 'Panel profile QML error')
            return
        if args.startup_profile:
            def snapshot():
                log = Path('/work/shell.log').read_text()
                return {'services': sorted(set(re.findall(r'STARTUP_SERVICE (\w+)', log))),
                        'processStarts': dict(Counter(re.findall(r'STARTUP_PROCESS ([\w.]+)', log))),
                        'memory': memory()}
            time.sleep(4)
            before = snapshot()
            require(before['processStarts'].get('Cursor.1', 0) == 0, 'Cursor enumeration ran before demand')
            for process in ['AiUsage.1', 'AiUsage.2', 'AiUsage.3']:
                require((before['processStarts'].get(process, 0) > 0) == args.startup_ai_widget, 'AI startup demand mismatch: ' + process)
            settings_target = 'lifecycleEmbeddedSettings' if args.startup_embedded_settings else 'lifecycleSettings'
            if args.startup_embedded_settings:
                ipc('menu', 'open')
                time.sleep(0.3)
                require(snapshot()['processStarts'].get('Cursor.1', 0) == 0, 'Main menu enumerated hidden settings choices')
                ipc('startupMenu', 'settings')
            else:
                ipc('settings', 'open')
                wait(lambda: len(mapped('settings')) == 1, 'settings map')
            wait(lambda: ipc(settings_target, 'cursorThemesReady') == 'true', 'cursor choices')
            ipc(settings_target, 'showCursorChoices')
            time.sleep(0.3)
            run(['grim', '/work/settings.png'])
            ipc('lifecycleProbe', 'closePanels')
            wait(lambda: not mapped('settings'), 'settings unmap')
            ipc('settings', 'open')
            wait(lambda: len(mapped('settings')) == 1, 'settings reopen')
            time.sleep(0.3)
            settings = snapshot()
            require(settings['processStarts'].get('Cursor.1', 0) == 1, 'Cursor enumeration was repeated or not started')
            ipc('lifecycleProbe', 'closePanels')
            first_status = ipc('ai', 'status')
            require(first_status != 'helper script not found', 'First AI access falsely reported a missing helper')
            ipc('ai', 'refresh')
            time.sleep(2)
            after = snapshot()
            require(all(after['processStarts'].get(process, 0) > 0 for process in ['AiUsage.1', 'AiUsage.2', 'AiUsage.3']), 'AI first request did not start its helpers')
            result = {'measurement': 'Observed QML Process starts in a private six-second startup window; excludes detached commands and child processes; no provider accounts/network.',
                      'startup': before, 'afterSettings': settings, 'afterUsageRequest': after,
                      'aiWidget': args.startup_ai_widget, 'embeddedSettings': args.startup_embedded_settings, 'firstAiStatus': first_status}
            Path('/work/startup-profile.json').write_text(json.dumps(result, indent=2))
            log = Path('/work/shell.log').read_text()
            require(not any(word in log for word in ('ReferenceError', 'TypeError', 'Binding loop')), 'Startup profiling QML error')
            print(json.dumps(result, indent=2))
            return
        if args.settings_error:
            ipc('lifecycleProbe', 'showConfigError')
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
                        if args.settings_error:
                            ipc('lifecycleSettings', 'focusRecovery')
                            wait(lambda: ipc('lifecycleSettings', 'recoveryFocused') == 'true', 'Recovery keyboard focus')
                            run(['grim', '/work/settings-recovery-focus.png'])
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
    parser.add_argument('--panel-profile', action='store_true', help='Measure Qt first output, visible readback and event-loop gaps')
    parser.add_argument('--panel-async', action='store_true', help='Experiment with async MotionLoader only in the private profile copy')
    parser.add_argument('--startup-embedded-settings', action='store_true', help='Exercise first cursor demand through the main menu')
    parser.add_argument('--startup-ai-widget', action='store_true', help='Include the AI widget in the isolated startup fixture')
    parser.add_argument('--startup-profile', action='store_true', help='Measure private service/process startup and subsequent demand')
    parser.add_argument('--recovery', action='store_true', help='Exercise recovery preview and restore in a private Wayland session')
    parser.add_argument('--settings-error', action='store_true', help='Show a persistence error in the isolated settings fixture')
    parser.add_argument('--motion', choices=['standard', 'reduced'], default='standard')
    parser.add_argument('--width', type=int, default=800)
    parser.add_argument('--height', type=int, default=600)
    parser.add_argument('--inside', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    require(1 <= args.cycles <= 1000 and 0 <= args.settle_seconds <= 3600, 'Invalid duration/cycle count')
    require(not args.panel_async or args.panel_profile, '--panel-async requires --panel-profile')
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
