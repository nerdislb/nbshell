#!/usr/bin/env python3
"""Store-specific recipes on a shared, private-display Faugus/UMU installer."""
import argparse
from contextlib import ExitStack
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import secrets
import subprocess
import sys
import tarfile
import tempfile
import time
import urllib.request

from gaming_display import PrivateDisplay
from battlenet import write_atomic, prefix_running

RECIPES = {
    'battlenet': dict(title='Battle.net', url='https://downloader.battle.net/download/getInstaller?os=win&installer=Battle.net-Setup.exe',
        file='Battle.net-Setup.exe', exe='Program Files (x86)/Battle.net/Battle.net.exe',
        args=['--installpath=C:\\Program Files (x86)\\Battle.net', '--lang=enUS'], launch=['--disable-gpu'], close=['Battle.net Login']),
    'gog': dict(title='GOG Galaxy', url='https://github.com/Faugus/components/releases/download/v1.0.1/gog.tar.gz',
        file='gog.tar.gz', sha256='f024ec31dc90001496986296c63cefc939bca21f6a8e36f17ef9a7edf6923333',
        exe='Program Files/GOG Galaxy/GalaxyClient.exe', args=['/VERYSILENT', '/NORESTART', '/SUPPRESSMSGBOXES'], launch=['--in-process-gpu', '/deelevated'], close=['GOG GALAXY']),
    'epic': dict(title='Epic Games', url='https://launcher-public-service-prod06.ol.epicgames.com/launcher/api/installer/download/EpicGamesLauncherInstaller.msi',
        file='EpicGamesLauncherInstaller.msi', exe='Program Files/Epic Games/Launcher/Portal/Binaries/Win64/EpicGamesLauncher.exe',
        args=[], launch=[], close=['Epic Games Launcher']),
}


def locations(store):
    home = Path.home()
    data = Path(os.getenv('XDG_DATA_HOME', home / '.local/share'))
    state = Path(os.getenv('XDG_STATE_HOME', home / '.local/state')) / 'nbshell/gaming' / store
    config = Path(os.getenv('XDG_CONFIG_HOME', home / '.config')) / 'nbshell/gaming' / (store + '.json')
    saved = json.loads(config.read_text()) if config.exists() else {}
    prefix = Path(os.getenv('NBSHELL_GAMING_PREFIX', saved.get('prefix', str(home / 'Faugus' / (store + '-nbshell'))))).expanduser().absolute()
    proton = Path(os.getenv('NBSHELL_GAMING_PROTON', saved.get('proton', str(data / 'Steam/compatibilitytools.d/Proton-CachyOS Latest')))).expanduser().resolve()
    return dict(data=data, state=state, config=config, prefix=prefix, proton=proton,
                umu=Path(os.getenv('NBSHELL_GAMING_UMU', str(data / 'faugus-launcher/umu-run'))), exe=prefix / 'drive_c' / RECIPES[store]['exe'])


def emit(phase, message, **extra):
    print(json.dumps(dict(phase=phase, message=message, **extra)), flush=True)


def stopped(paths):
    if (paths['state'] / 'cancel').exists():
        raise RuntimeError('Cancelled. Existing games are unchanged; installation files are kept for retry.')


def stop_process(proc):
    if proc.poll() is None:
        os.killpg(proc.pid, signal.SIGTERM)
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()


def environment(paths, display=None):
    env = os.environ.copy()
    env.update(WINEPREFIX=str(paths['prefix']), PROTONPATH=str(paths['proton']),
               GAMEID='umu-default', PROTON_ENABLE_WAYLAND='0', WINE_SIMULATE_WRITECOPY='1')
    if display:
        env.pop('WAYLAND_DISPLAY', None)
        env.update(display.env)
    return env


def download(recipe, target, paths):
    part = target.with_suffix(target.suffix + '.part')
    if target.exists() and recipe.get('sha256'):
        with target.open('rb') as stream:
            if hashlib.file_digest(stream, 'sha256').hexdigest() == recipe['sha256']:
                return
    try:
        with urllib.request.urlopen(recipe['url'], timeout=30) as response, part.open('wb') as output:
            size = int(response.headers.get('Content-Length', '0'))
            received, last = 0, 0
            while chunk := response.read(1024 * 1024):
                stopped(paths)
                received += len(chunk)
                if received > 1024 * 1024 * 1024:
                    raise RuntimeError('Installer download exceeds the 1 GiB limit.')
                output.write(chunk)
                if time.monotonic() - last > 0.5:
                    emit('download', 'Downloading installer…', received=received, total=size)
                    last = time.monotonic()
        if recipe.get('sha256'):
            with part.open('rb') as stream:
                if hashlib.file_digest(stream, 'sha256').hexdigest() != recipe['sha256']:
                    raise RuntimeError('Installer checksum mismatch.')
        part.replace(target)
    finally:
        part.unlink(missing_ok=True)


def extract_gog(archive, destination):
    with tarfile.open(archive) as bundle:
        members = bundle.getmembers()
        if len(members) > 1000 or sum(m.size for m in members) > 1024 * 1024 * 1024:
            raise RuntimeError('Unexpected GOG archive size.')
        for m in members:
            if not (m.isfile() or m.isdir()) or Path(m.name).is_absolute() or '..' in Path(m.name).parts:
                raise RuntimeError('Unsafe GOG archive member.')
        bundle.extractall(destination, members=members, filter='data')
    return destination / 'gog/GalaxySetup.exe'


def run_installer(store, paths, installer, display, log):
    recipe = RECIPES[store]
    args = ['msiexec', '/i', str(installer), '/passive', '/norestart'] if store == 'epic' else [str(installer), *recipe['args']]
    proc = subprocess.Popen([str(paths['umu']), *args], env=environment(paths, display), stdout=log, stderr=log, start_new_session=True)
    started, ready_since, closed = time.monotonic(), None, set()
    try:
        while proc.poll() is None:
            stopped(paths)
            if time.monotonic() - started > 900:
                raise RuntimeError('Installation timed out. See the private install log; no existing games were removed.')
            if paths['exe'].is_file():
                ready_since = ready_since or time.monotonic()
                if time.monotonic() - ready_since > 20:
                    for window, title in display.windows():
                        # Only exact client titles on our private display, never desktop-wide class rules.
                        if title in recipe['close'] and window not in closed:
                            emit('finishing', 'Finishing launcher setup…')
                            display.close(window)
                            closed.add(window)
            time.sleep(1)
        if proc.returncode != 0:
            raise RuntimeError(f'Installer exited with code {proc.returncode}. See install.log.')
        if not paths['exe'].is_file():
            raise RuntimeError('Installer ended without a usable launcher executable.')
    finally:
        stop_process(proc)


def run_checked(args, env, log, paths, timeout=120):
    proc = subprocess.Popen(args, env=env, stdout=log, stderr=log, start_new_session=True)
    start = time.monotonic()
    try:
        while proc.poll() is None:
            stopped(paths)
            if time.monotonic() - start > timeout:
                raise RuntimeError('Launcher configuration timed out.')
            time.sleep(0.5)
        if proc.returncode:
            raise RuntimeError('Launcher configuration failed. See install.log.')
    finally:
        stop_process(proc)


def faugus_running():
    for process in Path('/proc').glob('[0-9]*'):
        try:
            if process.stat().st_uid != os.getuid():
                continue
            argv = (process / 'cmdline').read_bytes().split(b'\0')
            # Match executable/module arguments, not unrelated prompts or log paths.
            if any(Path(os.fsdecode(a)).name in ('faugus-launcher', 'faugus.launcher', 'faugus.tray') for a in argv[:4]):
                return True
        except OSError:
            pass
    return False


def register_faugus(store, paths):
    if faugus_running():
        raise RuntimeError('Close Faugus before registering this launcher, then retry setup.')
    target = paths['data'] / 'faugus-launcher/games.json'
    previous = target.read_bytes() if target.exists() else b'[]'
    games = json.loads(previous)
    if not isinstance(games, list) or not all(isinstance(g, dict) for g in games):
        raise RuntimeError('Unknown Faugus games format; library left unchanged.')
    for game in games:
        if Path(game.get('prefix') or '/').expanduser().resolve() == paths['prefix'].resolve():
            return  # Preserve all user launch options of an existing entry.
        if game.get('gameid') == 'nbshell-' + store or game.get('title', '').casefold() == RECIPES[store]['title'].casefold():
            raise RuntimeError('A different Faugus entry already uses this launcher name. Library left unchanged.')
    games.append(dict(gameid='nbshell-' + store, title=RECIPES[store]['title'], path=str(paths['exe']),
        prefix=str(paths['prefix']), runner=str(paths['proton']), protonfix='umu-default',
        launch_arguments='PROTON_ENABLE_WAYLAND=0 WINE_SIMULATE_WRITECOPY=1',
        game_arguments=' '.join(RECIPES[store]['launch']),
        icon=str(paths['data'] / f'icons/hicolor/256x256/apps/nbshell-{store}.png'),
        playtime=0, hidden=False, no_sleep=False, category=False))
    if target.exists():
        write_atomic(paths['state'] / 'faugus-games.before.json', previous)
    if faugus_running() or (target.read_bytes() if target.exists() else b'[]') != previous:
        raise RuntimeError('Faugus library changed during setup. Close Faugus and retry.')
    write_atomic(target, (json.dumps(games, indent=2) + '\n').encode())


def register(store, paths):
    recipe = RECIPES[store]
    with tempfile.TemporaryDirectory() as folder:
        ico, png = Path(folder) / 'icon.ico', Path(folder) / 'icon.png'
        subprocess.run(['icoextract', str(paths['exe']), str(ico)], check=True, capture_output=True, timeout=30)
        from PIL import Image
        with Image.open(ico) as image:
            image.ico.getimage(max(image.ico.sizes(), key=lambda s: s[0] * s[1])).save(png)
        write_atomic(paths['data'] / f'icons/hicolor/256x256/apps/nbshell-{store}.png', png.read_bytes())
    write_atomic(paths['config'], (json.dumps({key: str(paths[key]) for key in ('prefix', 'proton')}, indent=2) + '\n').encode())
    register_faugus(store, paths)
    desktop = paths['data'] / f'applications/nbshell-{store}.desktop'
    write_atomic(desktop, (f'[Desktop Entry]\nType=Application\nName={recipe["title"]}\nExec=nbshell gaming launch {store}\n'
        f'Icon=nbshell-{store}\nTerminal=false\nStartupNotify=false\nCategories=Game;\n').encode())
    if shutil.which('update-desktop-database'):
        subprocess.run(['update-desktop-database', str(desktop.parent)], check=True, capture_output=True, timeout=30)


def prerequisites(paths):
    packages = []
    if not (os.getenv('NBSHELL_GAMING_XVFB') or shutil.which('Xvfb')):
        packages.append('xorg-server-xvfb')
    if not shutil.which('icoextract'):
        packages.append('icoextract')
    if not shutil.which('faugus-launcher'):
        packages.append('faugus-launcher')
    if packages:
        if not shutil.which('pkexec') or not shutil.which('pacman'):
            raise RuntimeError('Install these prerequisites first: ' + ', '.join(packages))
        for package in packages:
            result = subprocess.run(['pacman', '-Si', package], capture_output=True, timeout=15)
            if result.returncode:
                raise RuntimeError(f'{package} is not available in configured repositories. Install it first, then retry.')
        emit('dependencies', 'Installing gaming prerequisites. System authentication may appear; cancellation resumes after package setup.')
        # Never interrupt pacman mid-transaction. No shell, AUR builds or repository changes.
        handlers = {sig: signal.signal(sig, signal.SIG_IGN) for sig in (signal.SIGTERM, signal.SIGINT)}
        try:
            with (paths['state'] / 'dependencies.log').open('w') as log:
                result = subprocess.run(['pkexec', 'pacman', '-S', '--needed', '--noconfirm', *packages], stdout=log, stderr=log)
        finally:
            for sig, handler in handlers.items():
                signal.signal(sig, handler)
        if result.returncode:
            raise RuntimeError('Prerequisite installation failed or authentication was cancelled. See dependencies.log.')
    stopped(paths)
    with (paths['state'] / 'runtime.log').open('w') as log:
        # Delegate only missing components to Faugus, never update an existing runner.
        if not paths['umu'].exists():
            emit('runtime', 'Preparing Faugus runtime…')
            run_checked([sys.executable, '-c', 'from faugus.components import update_umu; update_umu()'], os.environ.copy(), log, paths, 300)
        if not (paths['proton'] / 'proton').is_file():
            if paths['proton'].exists() or os.getenv('NBSHELL_GAMING_PROTON'):
                raise RuntimeError('Configured Proton runner is incomplete. Repair it in Faugus first.')
            emit('runtime', 'Downloading Proton through Faugus…')
            run_checked([sys.executable, '-m', 'faugus.proton_downloader', '--cachyos'], os.environ.copy(), log, paths, 900)
        for item in (paths['umu'], paths['proton'] / 'proton'):
            if not item.is_file() or not os.access(item, os.X_OK):
                raise RuntimeError('Faugus runtime preparation did not complete. Open Faugus to check the selected runner.')
    return os.getenv('NBSHELL_GAMING_XVFB') or shutil.which('Xvfb')


def install(store, paths):
    recipe = RECIPES[store]
    emit('checking', 'Checking Faugus and graphics runtime…')
    if faugus_running():
        raise RuntimeError('Close Faugus before installing a launcher, then retry.')
    if paths['prefix'].is_symlink():
        raise RuntimeError('Refusing a symbolic-link installation prefix.')
    if prefix_running(paths['prefix']):
        raise RuntimeError('Close this launcher and its update agent before setup.')
    marker = paths['prefix'] / '.nbshell-install-owner'
    if paths['prefix'].exists() and not paths['exe'].is_file() and not marker.exists():
        raise RuntimeError('The target folder already exists and is not owned by this installer.')
    if not paths['exe'].is_file():
        parent = paths['prefix'].parent
        while not parent.exists():
            parent = parent.parent
        if shutil.disk_usage(parent).free < 4 * 1024 ** 3 or shutil.disk_usage(paths['state']).free < 1024 ** 3:
            raise RuntimeError('At least 4 GiB free space is required for launcher setup.')
        paths['prefix'].mkdir(parents=True, exist_ok=True)
        write_atomic(marker, (store + '\n').encode())
    xvfb = prerequisites(paths)
    log_path = paths['state'] / 'install.log'
    if log_path.exists():
        log_path.replace(paths['state'] / 'install.previous.log')
    with log_path.open('w') as log, PrivateDisplay(xvfb, log) as display:
        if not paths['exe'].is_file() or marker.exists():
            installer = paths['state'] / recipe['file']
            download(recipe, installer, paths)
            if store == 'gog':
                installer = extract_gog(installer, paths['state'])
            emit('installing', f'Installing {recipe["title"]} in the background…')
            run_installer(store, paths, installer, display, log)
            marker.unlink(missing_ok=True)
        emit('configuring', 'Preparing launcher and original app icon…')
        reg = paths['prefix'] / 'drive_c/windows/system32/reg.exe'
        registry = paths['prefix'] / 'user.reg'
        backup = paths['state'] / 'user.reg.before-show-systray'
        if registry.is_file() and not backup.exists():
            write_atomic(backup, registry.read_bytes())
        run_checked([str(paths['umu']), str(reg), 'add', 'HKCU\\Software\\Wine\\Explorer',
                     '/v', 'ShowSystray', '/t', 'REG_DWORD', '/d', '0', '/f'], environment(paths, display), log, paths)
    stopped(paths)
    register(store, paths)
    marker.unlink(missing_ok=True)
    emit('done', f'{recipe["title"]} is ready in Apps. Open it to sign in.')


def desktop_windows():
    try:
        result = subprocess.run(['umbriel', 'windows', '--json'], capture_output=True, text=True, timeout=3)
        if result.returncode:
            detail = result.stderr.strip()[:400]
            raise RuntimeError('Cannot query Umbriel windows. Repair the compositor command before launching. ' + detail)
        windows = json.loads(result.stdout)
        if not isinstance(windows, list) or not all(isinstance(w, dict) for w in windows):
            raise ValueError('unexpected window response')
        return windows
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        raise RuntimeError('Cannot query Umbriel windows. Check the desktop session and compositor installation.') from error


def launch(store, paths):
    if not paths['exe'].is_file():
        raise RuntimeError('Install this launcher first.')
    if prefix_running(paths['prefix']):
        raise RuntimeError('This launcher is already running.')
    before = {window.get('id') for window in desktop_windows()}
    emit('launching', f'Starting {RECIPES[store]["title"]}…')
    log_path = paths['state'] / 'launch.log'
    if log_path.exists():
        log_path.replace(paths['state'] / 'launch.previous.log')
    with log_path.open('w') as log:
        proc = subprocess.Popen([str(paths['umu']), str(paths['exe']), *RECIPES[store]['launch']],
                                env=environment(paths), stdout=log, stderr=log, start_new_session=True)
        start, visible_since, handed_off = time.monotonic(), None, False
        try:
            while proc.poll() is None:
                stopped(paths)
                if not handed_off:
                    visible = any(w.get('id') not in before and w.get('title', '').casefold().startswith(RECIPES[store]['title'].casefold()) for w in desktop_windows())
                    visible_since = (visible_since or time.monotonic()) if visible else None
                    if visible_since and time.monotonic() - visible_since >= 2:
                        emit('launched', 'Launcher opened.')
                        handed_off = True
                    elif time.monotonic() - start > 120:
                        raise RuntimeError('No launcher window appeared within two minutes. See launch.log.')
                time.sleep(1)
            if not handed_off:
                raise RuntimeError('Launcher exited before opening a window. See launch.log.')
            return proc.returncode
        finally:
            stop_process(proc)


def main():
    os.umask(0o077)
    def interrupted(*_):
        raise RuntimeError('Installation interrupted; files were kept for retry.')
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    parser = argparse.ArgumentParser()
    parser.add_argument('action', choices=['install', 'launch', 'status', 'cancel', 'remove'])
    parser.add_argument('store', choices=RECIPES)
    parser.add_argument('--job', default='')
    args = parser.parse_args()
    paths = locations(args.store)
    state = paths['state']
    if args.action == 'status':
        print(json.dumps({'installed': paths['exe'].is_file(), 'prefix': str(paths['prefix'])}))
        return 0 if paths['exe'].is_file() else 1
    state.mkdir(parents=True, exist_ok=True)
    if args.action == 'cancel':
        active = state / 'active-job.json'
        job = json.loads(active.read_text()) if active.exists() else {}
        if not args.job or job.get('token') != args.job:
            raise RuntimeError('This setup is no longer active.')
        write_atomic(state / 'cancel', b'cancel\n')
        return 0
    with ExitStack() as stack:
        if args.action == 'install':
            setup_lock = stack.enter_context((state.parent / 'setup.lock').open('a'))
            try:
                fcntl.flock(setup_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                raise RuntimeError('Another gaming setup is running. Wait for it to finish.')
        lock = stack.enter_context((state / 'operation.lock').open('a'))
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError('This launcher is already running or being installed.')
        (state / 'cancel').unlink(missing_ok=True)
        token = secrets.token_hex(16)
        active = state / 'active-job.json'
        write_atomic(active, json.dumps({'pid': os.getpid(), 'token': token}).encode())
        stack.callback(lambda: active.unlink(missing_ok=True))
        emit('started', 'Preparing launcher…', job=token)
        if args.action == 'install':
            install(args.store, paths)
        elif args.action == 'remove':
            # Remove only our app registration; never delete prefixes, games, or Faugus.
            (paths['data'] / f'applications/nbshell-{args.store}.desktop').unlink(missing_ok=True)
            emit('done', 'Removed from Apps. Installed games and login data were kept.')
        else:
            return launch(args.store, paths)
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, OSError, ValueError, ImportError, subprocess.SubprocessError, tarfile.TarError) as error:
        emit('error', str(error))
        sys.exit(1)
