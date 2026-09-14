#!/usr/bin/env python3
"""Native Prism setup with the shared gaming progress protocol and native Prism account handoff."""
import argparse
import configparser
import io
import re
import tempfile
import urllib.request
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
PACKAGES = ('prismlauncher', 'papirus-icon-theme')


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


MANIFEST_URL = 'https://piston-meta.mojang.com/mc/game/version_manifest_v2.json'


def latest_release():
    with urllib.request.urlopen(MANIFEST_URL, timeout=30) as response:
        raw = response.read(4 * 1024 * 1024 + 1)
    if len(raw) > 4 * 1024 * 1024:
        raise RuntimeError('Minecraft version manifest is too large.')
    manifest = json.loads(raw)
    if not isinstance(manifest, dict) or not isinstance(manifest.get('latest'), dict) or not isinstance(manifest.get('versions'), list):
        raise RuntimeError('Invalid Minecraft version manifest.')
    version = manifest['latest']['release']
    if not isinstance(version, str) or not re.fullmatch(r'[0-9][0-9A-Za-z._-]{0,79}', version):
        raise RuntimeError('Invalid Minecraft release identifier.')
    if not any(isinstance(v, dict) and v.get('id') == version and v.get('type') == 'release' for v in manifest['versions']):
        raise RuntimeError('No stable Minecraft release was found.')
    return version


def prepare_prism(data, state):
    # Never edit settings while Prism may write them or inspect account tokens.
    if subprocess.run(['pgrep', '-u', str(os.getuid()), '-x', 'prismlauncher'],
                      capture_output=True, timeout=5).returncode == 0:
        raise RuntimeError('Close Prism Launcher before preparing Minecraft, then retry.')
    root = data / 'PrismLauncher'
    cfg_path = root / 'prismlauncher.cfg'
    config = configparser.ConfigParser(interpolation=None, strict=False)
    config.optionxform = str
    previous = cfg_path.read_bytes() if cfg_path.exists() else None
    if previous:
        config.read_string(previous.decode('utf-8'))
    if not config.has_section('General'):
        config.add_section('General')
    settings = config['General']
    instance_dir = Path(settings.get('InstanceDir', 'instances'))
    if not instance_dir.is_absolute():
        instance_dir = root / instance_dir
    existing = sorted(instance_dir.glob('*/instance.cfg'))
    if existing:
        # Existing worlds/modpacks and user choices are never silently upgraded.
        emit('prepared', 'Existing Minecraft instances kept.',
             detail='Your selected Prism instance will open; no worlds or versions were changed.')
        return
    emit('version', 'Finding the latest stable Minecraft Java release…')
    version = latest_release()
    check_cancel(state)
    instance_id = 'nbshell-minecraft'
    target = instance_dir / instance_id
    if target.exists():
        raise RuntimeError('An incomplete Minecraft folder already exists. Move it aside before retrying.')
    instance_dir.mkdir(parents=True, exist_ok=True)
    # Set the documented first-run choices, leaving only Prism's native login page.
    defaults = {'Language': 'en_US', 'ApplicationTheme': 'system', 'IconTheme': 'pe_colored',
                'PastebinURL': '', 'ShowConsole': 'false', 'AutoCloseConsole': 'true'}
    for key, value in defaults.items():
        if not settings.get(key):
            settings[key] = value
    settings['AutomaticJavaSwitch'] = 'true'
    settings['AutomaticJavaDownload'] = 'true'
    settings['UserAskedAboutAutomaticJavaDownload'] = 'true'
    settings['SelectedInstance'] = instance_id
    output = io.StringIO()
    config.write(output, space_around_delimiters=False)
    backup = state / 'prismlauncher.cfg.before-setup'
    if previous is not None and not backup.exists():
        write_atomic(backup, previous)
    # Publish settings before the complete instance. Interrupted setup can retry
    # without mistaking a partially configured instance for existing user data.
    if cfg_path.exists() and cfg_path.read_bytes() != previous:
        raise RuntimeError('Prism settings changed during setup. Close Prism and retry.')
    write_atomic(cfg_path, output.getvalue().encode())
    with tempfile.TemporaryDirectory(prefix='.nbshell-stage-', dir=instance_dir) as staging:
        staged = Path(staging) / instance_id
        staged.mkdir()
        (staged / 'instance.cfg').write_text('[General]\nInstanceType=OneSix\nname=Minecraft\niconKey=default\n', encoding='utf-8')
        (staged / 'mmc-pack.json').write_text(json.dumps({'formatVersion': 1, 'components': [
            {'uid': 'net.minecraft', 'version': version, 'important': True}]}), encoding='utf-8')
        staged.rename(target)
    emit('prepared', f'Minecraft {version} prepared.',
         detail='Sign in with Microsoft next. Prism downloads the matching Java runtime and game files automatically.')


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
    prepare_prism(data, state)
    check_cancel(state)
    emit('registering', 'Adding Minecraft to Apps…')
    register(data)
    emit('done', 'Minecraft is prepared. Opening sign-in…',
         detail='After Microsoft sign-in, Prism downloads the game and starts Minecraft automatically.')


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
    except (RuntimeError, OSError, ValueError, KeyError, TypeError, configparser.Error, subprocess.SubprocessError) as error:
        emit('error', str(error))
        sys.exit(1)
