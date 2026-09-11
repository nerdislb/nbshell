#!/usr/bin/env python3
"""Manage native Polkit authentication and the established fallback agent."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import time

UNIT = 'nbshell-polkit-trial.service'
NATIVE = 'nbshell-polkit.service'
FALLBACK = 'hyprpolkitagent.service'
OTHER_AGENTS = ('polkit-gnome-authentication-agent-1.service', 'lxqt-policykit-agent.service', 'mate-polkit.service')
HOME = Path.home()
SHELL = Path(__file__).resolve().parent.parent
RUNTIME = HOME / '.local/lib/nbshell/polkit-runtime'
BINARY = RUNTIME / 'quickshell'

def run(args, **kwargs):
    return subprocess.run(args, text=True, **kwargs)

def active(unit):
    return run(['systemctl', '--user', 'is-active', '--quiet', unit]).returncode == 0

def verify_runtime():
    record = json.loads((RUNTIME / 'build.json').read_text())
    if record.get('queueRegressionPassed') is not True or hashlib.sha256(BINARY.read_bytes()).hexdigest() != record.get('sha256'):
        raise RuntimeError('The tested, queue-corrected Polkit runtime is unavailable.')

def registration():
    result = run(['/usr/bin/qs', 'ipc', '-p', str(SHELL / 'polkit.qml'), 'call', 'polkit', 'status'], capture_output=True, timeout=3)
    return json.loads(result.stdout) if result.returncode == 0 else {}

def wait_registered():
    deadline = time.monotonic() + 10
    while time.monotonic() < deadline:
        try:
            if registration().get('registered') is True:
                return
        except (ValueError, subprocess.TimeoutExpired):
            pass
        time.sleep(0.2)
    raise RuntimeError('Native Polkit registration failed.')

def serve():
    # Deliberately outside the CLI lock: restore must remain callable while
    # the agent is running. systemd owns process-group termination on stop.
    verify_runtime()
    result = run([str(BINARY), '-p', str(SHELL / 'polkit.qml')])
    raise RuntimeError('Native agent exited unexpectedly (status ' + str(result.returncode) + ').')

def fallback():
    # A separate failure unit survives an agent-cgroup kill. Do not resurrect
    # an authentication window while the graphical session is stopping.
    if active('graphical-session.target'):
        run(['systemctl', '--user', 'start', FALLBACK], check=True)

def restore():
    run(['systemctl', '--user', 'stop', UNIT], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    run(['systemctl', '--user', 'disable', '--now', NATIVE], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    run(['systemctl', '--user', 'enable', '--now', FALLBACK], check=True)
    if not active(FALLBACK):
        raise RuntimeError('The previous Polkit agent did not restart.')
    if run(['systemctl', '--user', 'is-enabled', '--quiet', NATIVE]).returncode == 0:
        raise RuntimeError('Previous agent is running, but native login could not be disabled.')
    print('Previous Polkit agent restored and enabled for login.')

def status():
    if active(NATIVE) or active(UNIT):
        state = registration()
        print(('Native agent: ' if active(NATIVE) else 'Native trial: ') + json.dumps(state))
    else:
        print('Native agent: inactive')
    enabled = run(['systemctl', '--user', 'is-enabled', '--quiet', NATIVE]).returncode == 0
    print('Native at login: ' + ('enabled' if enabled else 'disabled'))
    print('Previous agent: ' + ('running' if active(FALLBACK) else 'inactive'))

def keep():
    verify_runtime()
    if any(active(unit) for unit in OTHER_AGENTS):
        raise RuntimeError('Another Polkit agent is active; native agent not started.')
    if active(NATIVE):
        wait_registered()
        run(['systemctl', '--user', 'enable', NATIVE], check=True)
        run(['systemctl', '--user', 'disable', FALLBACK], check=True)
        status()
        return
    if active(UNIT) and registration().get('active'):
        raise RuntimeError('Finish or cancel the current authentication request first.')
    try:
        run(['systemctl', '--user', 'stop', UNIT], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        run(['systemctl', '--user', 'disable', FALLBACK], check=True)
        run(['systemctl', '--user', 'reset-failed', NATIVE], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        run(['systemctl', '--user', 'enable', '--now', NATIVE], check=True)
        wait_registered()
        print('Native Polkit enabled at login, with no time limit.')
    except BaseException:
        restore()
        raise

def trial():
    if active(NATIVE) or active(UNIT):
        status(); return
    if not active(FALLBACK):
        raise RuntimeError('Start the existing hyprpolkitagent before the trial.')
    if any(active(unit) for unit in OTHER_AGENTS):
        raise RuntimeError('Another Polkit agent is active; trial not started.')
    verify_runtime()
    try:
        run(['systemd-run', '--user', '--collect', '--unit=' + UNIT,
             '--property=Type=exec', '--property=RuntimeMaxSec=15min',
             '--property=PartOf=graphical-session.target',
             '--property=LimitCORE=0',
             '--property=ExecStartPre=/usr/bin/systemctl --user stop ' + FALLBACK,
             '--property=ExecStopPost=/usr/bin/systemctl --user start ' + FALLBACK,
             '--setenv=QT_LOGGING_RULES=quickshell.service.polkit*.debug=false;quickshell.polkit*.debug=false',
             str(BINARY), '-p', str(SHELL / 'polkit.qml')], check=True)
        wait_registered()
        print('Native Polkit trial ready for 15 minutes. Restore early: nbshell polkit restore')
    except BaseException:
        restore()
        raise

def main():
    action = sys.argv[1] if len(sys.argv) > 1 else 'status'
    if action in ('serve', 'fallback'):
        {'serve': serve, 'fallback': fallback}[action]()
        return
    if action not in ('trial', 'keep', 'restore', 'status'):
        raise RuntimeError('Usage: nbshell polkit trial|keep|restore|status')
    runtime_dir = Path(os.environ.get('XDG_RUNTIME_DIR', '/run/user/' + str(os.getuid())))
    with (runtime_dir / 'nbshell-polkit-trial.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        {'trial': trial, 'keep': keep, 'restore': restore, 'status': status}[action]()

if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        print('Polkit agent: ' + str(error), file=sys.stderr)
        sys.exit(1)
