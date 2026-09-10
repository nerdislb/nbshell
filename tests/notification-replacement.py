#!/usr/bin/env python3
"""Exercise the real Notify service and replaces_id on a private session bus."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
if '--private-bus' not in sys.argv:
    sys.exit(subprocess.call(['dbus-run-session', '--', sys.executable, __file__, '--private-bus']))

with tempfile.TemporaryDirectory(prefix='nbshell-notify-test-') as directory:
    base = Path(directory)
    shell = base / 'shell'
    common = shell / 'Common'
    services = shell / 'Services'
    common.mkdir(parents=True)
    services.mkdir()
    (common / 'qmldir').write_text('module qs.Common\nsingleton Config 1.0 Config.qml\n')
    (common / 'Config.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
 property var data: ({notifyTimeout: 1500})
 function value(key, fallback) { return data[key] === undefined ? fallback : data[key]; }
 function set(key, value) { data = Object.assign({}, data, {[key]: value}); }
}
''')
    (services / 'qmldir').write_text('module qs.Services\nsingleton Notify 1.0 Notify.qml\n')
    shutil.copy2(ROOT / 'shell/Services/Notify.qml', services / 'Notify.qml')
    (shell / 'shell.qml').write_text('''import Quickshell
import Quickshell.Io
import qs.Services
ShellRoot {
 IpcHandler {
  target: "regression"
  function reset(): void { Notify.clear(); }
  function status(): string {
   return JSON.stringify({history: Notify.history.map(e => ({key:e.key, summary:e.summary, body:e.body, urgency:e.urgency})),
    popups: Notify.popups.map(e => ({key:e.key, summary:e.summary, body:e.body, urgency:e.urgency})), remaining: Notify.popupRemaining});
  }
 }
}
''')
    env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
               XDG_STATE_HOME=str(base / 'state'), XDG_RUNTIME_DIR=str(base / 'runtime'))
    Path(env['XDG_RUNTIME_DIR']).mkdir(mode=0o700)
    (base / 'state/nbshell').mkdir(parents=True)
    (base / 'state/nbshell/notifications.json').write_text(json.dumps([
        {'key': 'load-marker', 'id': 0, 'appName': 'Fixture', 'summary': 'Loaded',
         'body': '', 'time': int(time.time() * 1000), 'pending': False}]))
    (base / 'state/nbshell/notifications-seen').write_text('0')
    def command(args):
        return subprocess.check_output(args, env=env, text=True, stderr=subprocess.STDOUT, timeout=10).strip()
    def state():
        return json.loads(command(['qs', 'ipc', '-p', str(shell), 'call', 'regression', 'status']))
    def wait_for(predicate):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            try:
                result = state()
                if predicate(result):
                    return result
            except (subprocess.CalledProcessError, json.JSONDecodeError):
                pass
            time.sleep(.05)
        raise AssertionError('Notification state did not converge')
    def send(title, body, old=None, urgency='normal'):
        args = ['notify-send', '-a', 'ReplacementRegression', '-p', '-t', '1', '-u', urgency]
        if old is not None:
            args += ['-r', str(old)]
        return command(args + [title, body])
    with (base / 'quickshell.log').open('w+') as log:
        process = subprocess.Popen(['qs', '-n', '-p', str(shell)], env=env, stdout=log, stderr=log)
        try:
            wait_for(lambda s: any(e['key'] == 'load-marker' for e in s['history']))
            command(['qs', 'ipc', '-p', str(shell), 'call', 'regression', 'reset'])
            original = send('Before', 'Old body')
            initial = wait_for(lambda s: len(s['popups']) == 1)
            key = initial['popups'][0]['key']
            time.sleep(.8)
            remaining_before = state()['remaining'][key]
            assert send('After', 'New body', original) == original
            updated = wait_for(lambda s: s['popups'] and s['popups'][0]['summary'] == 'After')
            assert len(updated['history']) == len(updated['popups']) == 1
            assert updated['history'][0]['body'] == 'New body'
            assert updated['popups'][0]['key'] == key
            assert updated['remaining'][key] > remaining_before, updated
            def persisted_after_update():
                try:
                    rows = json.loads((base / 'state/nbshell/notifications.json').read_text())
                    return rows if rows and rows[0]['summary'] == 'After' else None
                except (OSError, json.JSONDecodeError):
                    return None
            wait_for(lambda s: persisted_after_update() is not None)
            persisted = persisted_after_update()
            assert len(persisted) == 1 and persisted[0]['summary'] == 'After'
            send('Urgent update', 'Critical', original, 'critical')
            wait_for(lambda s: s['popups'] and s['popups'][0]['urgency'] == 2)
            time.sleep(1.7)
            assert len(state()['popups']) == 1, 'Critical replacement expired'
            send('Final update', 'Normal again', original)
            wait_for(lambda s: s['popups'] and s['popups'][0]['urgency'] == 1)
            wait_for(lambda s: not s['popups'])
            archived = state()['history']
            assert len(archived) == 1 and archived[0]['summary'] == 'Final update'
            renewed = send('After expiry', 'A new notification', original)
            assert renewed != original
            fresh = wait_for(lambda s: len(s['popups']) == 1)
            assert len(fresh['history']) == 2
            assert fresh['popups'][0]['key'] != key
            assert fresh['history'][1]['summary'] == 'Final update'
            print('PASS: replacement identity, text, history, persistence, renewed lifetime and urgency changes')
        except BaseException:
            log.flush(); log.seek(0); print(log.read(), file=sys.stderr)
            raise
        finally:
            process.terminate()
            process.wait(timeout=10)
