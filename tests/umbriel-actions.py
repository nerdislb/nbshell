#!/usr/bin/env python3
"""Real action/state and QML reconnect checks, only inside wayland-lifecycle's sandbox."""
import json
import os
from pathlib import Path
import select
import socket
import threading


def exercise(run, launch, wait, compositor):
    assert os.environ.get('NBSHELL_LIFECYCLE_TEST') == '1'
    assert os.environ['UMBRIEL_SOCKET'] == '/run/test/umbriel-wayland-0.sock'
    checked = []
    def query(name):
        return json.loads(run(['/test-bin/umbriel', name, '--json']).stdout)
    def action(name, value=None):
        args = ['python3', '/source/shell/scripts/umbriel-contract.py', 'action', name]
        if value is not None:
            args.append(str(value))
        result = json.loads(run(args + ['--binary', '/test-bin/umbriel', '--json']).stdout)
        assert result['ok'] and not result['fallbackUsed'], result
    def window():
        return next(w for w in query('windows') if w['title'] == 'Contract fixture')

    wait(lambda: len(query('windows')) == 2, 'two fixture windows')
    peer = next(w['id'] for w in query('windows') if w['title'] == 'Contract peer')
    run(['/test-bin/umbriel', 'msg', 'window-focus:' + peer])
    wait(lambda: not window()['focused'], 'peer focused before focus test')
    wid = window()['id']
    original_workspace = window()['workspace']
    action('window.focus', wid)
    wait(lambda: window()['focused'], 'window focus')
    checked.append('window.focus')
    action('window.floating.toggle')
    wait(lambda: window()['floating'], 'float window')
    action('window.floating.toggle')
    wait(lambda: not window()['floating'], 'tile window')
    checked.append('window.floating.toggle')
    for layout in ('dwindle', 'master', 'scrolling'):
        action('workspace.layout.set', layout)
        wait(lambda: any(w['focused'] and w['layout'] == layout for w in query('workspaces')), 'layout ' + layout)
    checked.append('workspace.layout.set')
    action('window.move-to-workspace', '2')
    wait(lambda: window()['workspace'] != original_workspace, 'move workspace')
    destination = window()['workspace']
    action('workspace.focus', '2')
    wait(lambda: any(w['id'] == destination and w['focused'] for w in query('workspaces')), 'focus workspace')
    checked.extend(['window.move-to-workspace', 'workspace.focus'])
    action('workspace.focus', '1')
    wait(lambda: any(w['focused'] and w['id'] == original_workspace for w in query('workspaces')), 'leave destination before warp')
    action('window.focus-warp', wid)
    wait(lambda: window()['focused'] and any(w['id'] == destination and w['focused'] for w in query('workspaces')), 'focus warp switches output workspace')
    checked.append('window.focus-warp')
    action('window.width.set', '0.5')
    wait(lambda: window()['w'] < 500, 'half width')
    narrow = window()['w']
    action('window.width.set', '0.9')
    wait(lambda: window()['w'] > narrow + 100, 'wider window')
    checked.append('window.width.set geometry')
    for name in ('output.dpms.off', 'output.dpms.on'):
        action(name)
        checked.append(name + ' (headless acknowledgement)')
    action('config.reload')
    wait(lambda: len(query('workspaces')) > 0, 'reload retains IPC')
    checked.append('config.reload (acknowledgement and continued IPC)')

    # Observe the unchanged production QML service through a private forwarding
    # socket. Dropping this transport leaves the compositor/Wayland session alive.
    upstream = os.environ['UMBRIEL_SOCKET']
    relay_path = '/run/test/contract-relay.sock'
    stop = threading.Event()
    errors = []
    def relay():
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as listener:
                listener.bind(relay_path); listener.listen(); listener.settimeout(.05)
                while not stop.is_set():
                    try:
                        client, _ = listener.accept()
                    except socket.timeout:
                        continue
                    with client, socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as server:
                        client.settimeout(1); server.settimeout(1)
                        server.connect(upstream)
                        while not stop.is_set():
                            readable, _, _ = select.select([client, server], [], [], .05)
                            ended = False
                            for source in readable:
                                data = source.recv(65536)
                                if not data:
                                    ended = True; break
                                (server if source is client else client).sendall(data)
                            if ended:
                                break
        except Exception as error:
            errors.append(repr(error))
        finally:
            Path(relay_path).unlink(missing_ok=True)
    def start_relay():
        stop.clear()
        thread = threading.Thread(target=relay, daemon=True); thread.start()
        wait(lambda: Path(relay_path).exists(), 'relay socket')
        return thread
    observer = Path('/work/contract-observer')
    (observer / 'Services').mkdir(parents=True)
    (observer / 'Common').mkdir()
    (observer / 'Services/Compositor.qml').write_bytes(Path('/source/shell/Services/Compositor.qml').read_bytes())
    (observer / 'Services/qmldir').write_text('singleton Compositor 1.0 Compositor.qml\n')
    (observer / 'Common/qmldir').write_text('singleton Runtime 1.0 Runtime.qml\n')
    (observer / 'Common/Runtime.qml').write_text('pragma Singleton\nimport Quickshell\nSingleton { property int popoutCount: 0; property bool barHover: false; property bool popoutHover: false; function closeAll() {} }\n')
    (observer / 'shell.qml').write_text('''import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Services
ShellRoot {
    PanelWindow {
        id: focusPanel
        visible: false
        anchors.top: true
        implicitWidth: 100
        implicitHeight: 40
        exclusiveZone: 0
        WlrLayershell.namespace: "contract-focus-layer"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    }
    IpcHandler { target: "observer"
        function panel(show: bool): void { focusPanel.visible = show; }
        function state(): string { return JSON.stringify({available: Compositor.available, windows: Compositor.windows.length, workspaces: Compositor.workspaces.length, focus: Compositor.focusedWindowId, output: Compositor.focusedOutput, keyboard: Compositor.keyboardLayout}); }
    }
}
''')
    def state():
        result = run(['/test-bin/qs', '-p', str(observer), 'ipc', 'call', 'observer', 'state'], False)
        return json.loads(result.stdout) if result.returncode == 0 else {}
    thread = start_relay()
    try:
        launch(['env', 'UMBRIEL_SOCKET=' + relay_path, '/test-bin/qs', '-p', str(observer), '--no-color'], 'contract-observer.log')
        wait(lambda: state().get('windows', 0) > 0 and state().get('workspaces', 0) > 0, 'observer snapshots')
        for cycle in range(3):
            stop.set(); thread.join(2)
            assert not thread.is_alive() and not errors, errors
            wait(lambda: state() == {'available': False, 'windows': 0, 'workspaces': 0, 'focus': '', 'output': '', 'keyboard': ''}, 'clear disconnected QML state')
            thread = start_relay()
            wait(lambda: state().get('available') and state().get('windows', 0) == 2 and state().get('workspaces', 0) > 0 and state().get('output') and state().get('focus') == wid, 'restore QML snapshots')
        checked.append('QML disconnect clears state and reconnect restores snapshots (3 cycles)')
        run(['/test-bin/umbriel', 'msg', 'window-move-to-scratchpad'])
        run(['/test-bin/umbriel', 'msg', 'scratchpad-toggle'])
        wait(lambda: window()['active'] and not window()['focused'], 'scratchpad seat activation')
        wait(lambda: state().get('focus') == wid, 'QML scratchpad focus follows activation')
        run(['/test-bin/qs', '-p', str(observer), 'ipc', 'call', 'observer', 'panel', 'true'])
        wait(lambda: not any(w['active'] for w in query('windows')), 'layer takes keyboard focus')
        import time
        time.sleep(0.8)
        assert state().get('focus') == wid, 'layer focus must retain scratchpad title'
        run(['/test-bin/qs', '-p', str(observer), 'ipc', 'call', 'observer', 'panel', 'false'])
        # Closing an exclusive layer may focus the workspace beneath it.
        # Explicitly select the scratchpad again before testing restoration.
        run(['/test-bin/umbriel', 'msg', 'window-focus:' + wid])
        wait(lambda: window()['active'] and state().get('focus') == wid, 'scratchpad explicitly refocused')
        checked.append('keyboard layer retains scratchpad focus identity')
        run(['/test-bin/umbriel', 'msg', 'window-restore-from-scratchpad'])
        wait(lambda: window()['focused'] and state().get('focus') == wid, 'restore scratchpad focus')
        checked.append('scratchpad activation and restored QML focus')
        action('window.close', wid)
        wait(lambda: not any(w['id'] == wid for w in query('windows')), 'close window')
        wait(lambda: state().get('windows') == 1 and state().get('focus') != wid, 'live close event')
        checked.append('window.close and subsequent QML event')
    finally:
        stop.set(); thread.join(2)
    assert not errors, errors
    action('session.quit', 'skip-confirmation')
    assert compositor.wait(timeout=5) == 0, 'Private compositor did not quit cleanly'
    checked.append('session.quit exits private compositor cleanly')
    result = {'checked': checked, 'notVerified': ['output.dpms.off/on physical output', 'full stack release acceptance']}
    Path('/work/action-contract.json').write_text(json.dumps(result, indent=2))
    print(json.dumps(result))
