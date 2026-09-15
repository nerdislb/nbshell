#!/usr/bin/env python3
"""Explicit nbshell Windows setup and desktop entry point (no background polling)."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys

HELPER = Path('/usr/local/bin/nbshell-windows-vm')
SOURCE = Path(__file__).with_name('windows-vm.sh')
PACKAGES = ('docker', 'docker-compose', 'freerdp', 'gum', 'openbsd-netcat')
COMPOSE = Path('/var/lib/nbshell/windows/docker-compose.yml')


def run(args, **kw):
    return subprocess.run([str(x) for x in args], check=True, **kw)


def terminal(action, *options):
    # An app scope survives shell restarts and does not restart the VM itself.
    term = shutil.which('ghostty') or shutil.which('foot') or shutil.which('alacritty')
    if not term:
        raise RuntimeError('Open a terminal and run: nbshell windows ' + action)
    run(['systemd-run', '--user', '--scope', '--collect', '--quiet',
         term, '-e', 'nbshell', 'windows', action, *options])


def trusted_helper():
    if not HELPER.is_file() or HELPER.is_symlink():
        return False
    for path in (HELPER, *HELPER.parents):
        st = path.stat()
        if st.st_uid != 0 or st.st_mode & 0o022:
            return False
    return os.access(HELPER, os.X_OK)


def preflight():
    if not Path('/dev/kvm').exists():
        raise RuntimeError('KVM is unavailable. Enable virtualization in the firmware first.')
    # Do not take over an Omarchy VM, storage, or another container at these ports.
    if Path('/var/lib/omarchy/windows/docker-compose.yml').exists() or Path.home().joinpath('.config/windows/docker-compose.yml').exists():
        raise RuntimeError('An Omarchy Windows VM exists. Migrate it explicitly before installing nbshell Windows.')
    if not COMPOSE.exists() and Path.home().joinpath('.windows').exists() and any(Path.home().joinpath('.windows').iterdir()):
        raise RuntimeError('Existing Windows disk data found. It will not be adopted or overwritten automatically.')


def install(options):
    preflight()
    missing = [p for p in PACKAGES if subprocess.run(['pacman', '-Q', p], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode]
    if missing:
        print('Installing optional Windows dependencies: ' + ', '.join(missing), flush=True)
        run(['pkexec', '/usr/bin/pacman', '-S', '--needed', '--noconfirm', *missing])
    # Only this explicit setup operation may replace the root-owned helper.
    if not trusted_helper() or hashlib.sha256(HELPER.read_bytes()).digest() != hashlib.sha256(SOURCE.read_bytes()).digest():
        print('Installing the root-owned Windows helper (system authorization).', flush=True)
        run(['pkexec', '/usr/bin/install', '-o', 'root', '-g', 'root', '-m', '0755', SOURCE, HELPER])
    if not trusted_helper():
        raise RuntimeError('The Windows helper is not safely installed.')
    print('Windows uses a local VM and a shared ~/Windows folder. No boot autostart is enabled.\nWindows activation requires your own license.', flush=True)
    run([HELPER, 'install', *options])


def main():
    os.umask(0o077)
    args = sys.argv[1:] or ['launch']
    action, options = args[0], args[1:]
    allowed = {'install': ([], ['--defaults']), 'launch': ([], ['--keep-alive'], ['-k']),
               'stop': ([],), 'status': ([],), 'remove': ([],), 'shared': ([],), 'console': ([],),
               'credentials': ([],), 'help': ([],), '--help': ([],)}
    if action not in allowed or options not in allowed[action]:
        raise RuntimeError('Usage: nbshell windows install [--defaults] | launch [--keep-alive] | stop | status | shared | console | credentials | remove')
    if action in ('help', '--help'):
        print('nbshell windows install [--defaults] | launch [--keep-alive] | stop | status | shared | console | credentials | remove')
        return
    if action == 'install':
        if not sys.stdin.isatty() and not options:
            terminal('install')
        else:
            install(options)
        return
    if action == 'status' and not COMPOSE.exists():
        print('Windows is not installed. Use Menu → System → Windows → Install / Configure.')
        return
    if not trusted_helper() or not COMPOSE.exists():
        if action == 'launch':
            terminal('install')
            return
        raise RuntimeError('Install Windows from Menu → System → Windows first.')
    if action == 'remove' and not sys.stdin.isatty():
        terminal('remove')
    elif action == 'shared':
        run(['xdg-open', Path.home() / 'Windows'])
    elif action == 'console':
        run(['xdg-open', 'http://127.0.0.1:8006'])
    elif action == 'credentials':
        if not sys.stdout.isatty():
            raise RuntimeError('Windows credentials can only be displayed in your local terminal.')
        path = Path.home() / '.config/nbshell/windows/credentials'
        print(path.read_text(), end='')
    elif action == 'launch':
        # A detached app service keeps RDP/auto-stop alive across nbshell restarts.
        run(['systemd-run', '--user', '--collect', '--quiet', '--unit=nbshell-windows-session',
             '--property=Type=exec', '--property=TimeoutStopSec=150',
             '--setenv=DISPLAY=' + os.getenv('DISPLAY', ''),
             '--setenv=WAYLAND_DISPLAY=' + os.getenv('WAYLAND_DISPLAY', ''),
             '--setenv=PATH=' + os.environ['PATH'], HELPER, action, *options])
    else:
        run([HELPER, action, *options])


if __name__ == '__main__':
    try:
        main()
    except (RuntimeError, OSError, subprocess.CalledProcessError) as exc:
        message = str(exc)
        print('Windows: ' + message, file=sys.stderr)
        if shutil.which('notify-send'):
            subprocess.run(['notify-send', '-u', 'critical', 'Windows', message], check=False)
        sys.exit(1)
