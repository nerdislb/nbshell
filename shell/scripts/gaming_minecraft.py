#!/usr/bin/env python3
"""Native Prism setup with the shared gaming progress protocol; no auto-launch."""
import argparse
from contextlib import ExitStack
import fcntl
import json
import os
from pathlib import Path
import secrets
import shutil
import signal
import subprocess
import sys

from battlenet import write_atomic

ICON = Path('/usr/share/icons/Papirus/64x64/apps/minecraft.svg')
PACKAGES = ('prismlauncher', 'jre21-openjdk', 'papirus-icon-theme')


def emit(phase, message, **extra):
    print(json.dumps(dict(phase=phase, message=message, **extra)), flush=True)


def locations():
    home = Path.home()
    return (Path(os.getenv('XDG_DATA_HOME', home / '.local/share')),
            Path(os.getenv('XDG_STATE_HOME', home / '.local/state')) / 'nbshell/gaming/minecraft')


def installed(package):
    return subprocess.run(['pacman', '-Qq', package], capture_output=True, timeout=15).returncode == 0


def register(data):
    if not shutil.which('prismlauncher'):
        raise RuntimeError('Install Prism Launcher first.')
    if not ICON.is_file():
        raise RuntimeError('Minecraft icon is missing. Retry Minecraft setup to install papirus-icon-theme.')
    # Keep the app identity independent of the selected instance and icon theme.
    write_atomic(data / 'icons/hicolor/scalable/apps/nbshell-minecraft.svg', ICON.read_bytes())
    write_atomic(data / 'applications/nbshell-minecraft.desktop', b'''[Desktop Entry]
Type=Application
Name=Minecraft
Comment=Play Minecraft with Prism Launcher
Exec=nbshell gaming launch minecraft
Icon=nbshell-minecraft
Terminal=false
Categories=Game;
Keywords=minecraft;game;prism;
StartupNotify=true
''')
    if shutil.which('update-desktop-database'):
        subprocess.run(['update-desktop-database', str(data / 'applications')],
                       capture_output=True, timeout=15, check=True)


def check_cancel(state):
    if (state / 'cancel').exists():
        raise RuntimeError('Cancelled. Installed packages and existing Minecraft data were kept.')


def install(data, state):
    emit('checking', 'Checking Minecraft prerequisites…')
    if not shutil.which('pacman'):
        raise RuntimeError('Minecraft setup requires an Arch-compatible package manager.')
    missing = [p for p in PACKAGES if not installed(p)]
    check_cancel(state)
    if missing:
        if not shutil.which('pkexec'):
            raise RuntimeError('System authentication is unavailable. Install polkit first.')
        for package in missing:
            if subprocess.run(['pacman', '-Si', package], capture_output=True, timeout=15).returncode:
                raise RuntimeError(f'{package} is not in the configured repositories. Install it first, then retry.')
        check_cancel(state)
        emit('dependencies', 'Installing Minecraft prerequisites…',
             detail='System authentication may appear. Cancellation waits for package setup to finish.')
        # Package transactions must complete even when Cancel/Escape is requested.
        handlers = {sig: signal.signal(sig, signal.SIG_IGN) for sig in (signal.SIGTERM, signal.SIGINT)}
        try:
            with (state / 'dependencies.log').open('w') as log:
                result = subprocess.run(['pkexec', 'pacman', '-S', '--needed', '--noconfirm', *missing],
                                        stdout=log, stderr=log)
        finally:
            for sig, handler in handlers.items():
                signal.signal(sig, handler)
        if result.returncode:
            raise RuntimeError('Package setup failed or authentication was cancelled. See dependencies.log.')
    check_cancel(state)
    if not all(installed(p) for p in PACKAGES):
        raise RuntimeError('Package verification failed. Retry Minecraft setup.')
    emit('registering', 'Adding Minecraft to Apps…')
    register(data)
    emit('done', 'Minecraft is ready in Apps.',
         detail='Open Minecraft when ready. First-time sign-in and game-version setup happen in Prism Launcher.')


def main():
    os.umask(0o077)
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=('install', 'desktop', 'launch', 'cancel'))
    parser.add_argument('store', nargs='?', choices=('minecraft',), default='minecraft')
    parser.add_argument('--job', default='')
    args = parser.parse_args()
    data, state = locations()
    state.mkdir(parents=True, exist_ok=True)
    active = state / 'active-job.json'
    if args.action == 'cancel':
        job = json.loads(active.read_text()) if active.exists() else {}
        if not args.job or job.get('token') != args.job:
            raise RuntimeError('This setup is no longer active.')
        write_atomic(state / 'cancel', b'cancel\n')
        return
    if args.action == 'launch':
        if not shutil.which('prismlauncher'):
            raise RuntimeError('Install Prism Launcher first.')
        subprocess.Popen(['nbshell', 'gaming', 'launch', 'minecraft'], start_new_session=True,
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        emit('launched', 'Minecraft launch requested.')
        return
    with ExitStack() as stack:
        # Share the Windows-store setup lock, without starting Wine/Faugus.
        for path in (state.parent / 'setup.lock', state / 'operation.lock'):
            lock = stack.enter_context(path.open('a'))
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise RuntimeError('Another gaming setup is running. Wait for it to finish.')
        if args.action == 'desktop':
            register(data)
            return
        (state / 'cancel').unlink(missing_ok=True)
        token = secrets.token_hex(16)
        write_atomic(active, json.dumps({'pid': os.getpid(), 'token': token}).encode())
        stack.callback(lambda: active.unlink(missing_ok=True))
        emit('started', 'Preparing Minecraft…', job=token)
        install(data, state)


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, ValueError, subprocess.SubprocessError) as error:
        emit('error', str(error))
        sys.exit(1)
