#!/usr/bin/env python3
"""Register and launch an existing native Faugus/UMU Battle.net installation."""
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile


def paths():
    home = Path.home()
    config = Path(os.getenv('XDG_CONFIG_HOME', home / '.config')) / 'nbshell/gaming/battlenet.json'
    data = Path(os.getenv('XDG_DATA_HOME', home / '.local/share'))
    state = Path(os.getenv('XDG_STATE_HOME', home / '.local/state')) / 'nbshell/battlenet'
    return home, config, data, state


def settings():
    home, config, data, _ = paths()
    saved = json.loads(config.read_text()) if config.exists() else {}
    default = home / 'Faugus/battlenet-nbshell'
    if not (default / 'drive_c/Program Files (x86)/Battle.net/Battle.net.exe').is_file():
        default = home / 'Faugus/battlenet'
    return {
        'prefix': str(Path(os.getenv('NBSHELL_BATTLENET_PREFIX', saved.get('prefix', str(default)))).expanduser().resolve()),
        'proton': str(Path(os.getenv('NBSHELL_BATTLENET_PROTON', saved.get('proton', str(data / 'Steam/compatibilitytools.d/Proton-CachyOS Latest')))).expanduser().resolve()),
        'umu': str(data / 'faugus-launcher/umu-run'),
    }


def command(cfg, executable, *args):
    env = os.environ.copy()
    env.update(WINEPREFIX=cfg['prefix'], PROTONPATH=cfg['proton'],
               PROTON_ENABLE_WAYLAND='0', WINE_SIMULATE_WRITECOPY='1', GAMEID='umu-default')
    return [cfg['umu'], str(executable), *args], env


def validate(cfg):
    exe = Path(cfg['prefix']) / 'drive_c/Program Files (x86)/Battle.net/Battle.net.exe'
    for path in (exe, Path(cfg['proton']) / 'proton', Path(cfg['umu'])):
        if not path.is_file():
            raise RuntimeError(f'Missing {path}. See docs/battlenet.md for setup.')
    if not os.access(cfg['umu'], os.X_OK):
        raise RuntimeError('Faugus UMU runner is not executable.')
    return exe


def prefix_running(prefix):
    target = Path(prefix).resolve()
    for proc in Path('/proc').glob('[0-9]*'):
        try:
            if proc.stat().st_uid != os.getuid():
                continue
            for item in (proc / 'environ').read_bytes().split(b'\0'):
                if item.startswith(b'WINEPREFIX=') and Path(os.fsdecode(item[11:])).resolve() == target:
                    return True
        except (OSError, ValueError):
            continue
    return False


def write_atomic(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as f:
        tmp = Path(f.name)
        f.write(content)
    try:
        tmp.replace(path)
    finally:
        tmp.unlink(missing_ok=True)


def register(cfg, exe):
    _, config, data, state = paths()
    if prefix_running(cfg['prefix']):
        raise RuntimeError('Close Battle.net and wait for its update agent to exit before registering.')
    if not shutil.which('icoextract'):
        raise RuntimeError('Install icoextract first to extract the original Battle.net logo.')
    from PIL import Image
    # Extract before modifying the prefix; no copyrighted binary is shipped in Git.
    with tempfile.TemporaryDirectory() as folder:
        ico = Path(folder) / 'battle.ico'
        subprocess.run(['icoextract', str(exe), str(ico)], check=True)
        with Image.open(ico) as image:
            logo = image.ico.getimage(max(image.ico.sizes(), key=lambda size: size[0] * size[1]))
            png = Path(folder) / 'battle.png'
            logo.save(png)
        state.mkdir(parents=True, exist_ok=True)
        registry = Path(cfg['prefix']) / 'user.reg'
        if registry.is_file():
            # Keep the first backup; never overwrite it with later user data.
            backup = state / 'user.reg.before-show-systray'
            if not backup.exists():
                write_atomic(backup, registry.read_bytes())
        reg = Path(cfg['prefix']) / 'drive_c/windows/system32/reg.exe'
        cmd, env = command(cfg, reg, 'add', 'HKCU\\Software\\Wine\\Explorer',
                           '/v', 'ShowSystray', '/t', 'REG_DWORD', '/d', '0', '/f')
        with (state / 'register.log').open('w') as log:
            subprocess.run(cmd, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
        icon = data / 'icons/hicolor/256x256/apps/nbshell-battlenet.png'
        write_atomic(icon, png.read_bytes())
    saved = {'prefix': cfg['prefix'], 'proton': cfg['proton']}
    write_atomic(config, (json.dumps(saved, indent=2) + '\n').encode())
    desktop = data / 'applications/nbshell-battlenet.desktop'
    write_atomic(desktop, b'[Desktop Entry]\nType=Application\nName=Battle.net\n'
                 b'Comment=Play your Blizzard games\nExec=nbshell gaming launch battlenet\n'
                 b'Icon=nbshell-battlenet\nTerminal=false\nStartupNotify=false\n'
                 b'Categories=Game;\nKeywords=Blizzard;Battle.net;Warcraft;Diablo;Overwatch;\n')
    if shutil.which('update-desktop-database'):
        subprocess.run(['update-desktop-database', str(desktop.parent)], check=True)
    print('Battle.net registered in Apps with its original logo.')


def main():
    os.umask(0o077)
    action = sys.argv[1] if len(sys.argv) > 1 else 'status'
    if action not in ('status', 'register', 'launch'):
        raise RuntimeError('Usage: battlenet.py status|register|launch')
    cfg = settings()
    exe = validate(cfg)
    if action == 'status':
        print('Battle.net installation and runner found.')
        return 0
    state = paths()[3]
    state.mkdir(parents=True, exist_ok=True)
    with (state / 'launch.lock').open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError('Battle.net is already running or being configured.')
        if action == 'register':
            register(cfg, exe)
            return 0
        log = state / 'launch.log'
        if log.exists():
            log.replace(state / 'launch.previous.log')
        cmd, env = command(cfg, exe, '--disable-gpu')
        with log.open('w') as output:
            return subprocess.call(cmd, env=env, stdout=output, stderr=subprocess.STDOUT)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, OSError, ValueError, ImportError, subprocess.SubprocessError) as exc:
        print(f'Battle.net: {exc}', file=sys.stderr)
        if shutil.which('notify-send'):
            subprocess.run(['notify-send', '--urgency=critical', 'Battle.net', str(exc)], check=False)
        sys.exit(1)
