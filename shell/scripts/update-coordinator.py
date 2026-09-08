#!/usr/bin/env python3
"""Serialize nbshell update workflows and retain per-step recovery information."""
from __future__ import annotations

import argparse
import contextlib
import ctypes
import fcntl
import json
import os
from pathlib import Path
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import time

SCRIPTS = Path(__file__).resolve().parent
MODES = {'shell': ['shell'], 'compositor': ['compositor'],
         'desktop': ['shell', 'compositor'], 'system': ['packages', 'flatpak']}
GIB = 1024 ** 3


def state_dir():
    return Path(os.environ.get('XDG_STATE_HOME', str(Path.home() / '.local/state'))) / 'nbshell'


def lock_path():
    # A persistent inode also coordinates terminals with different runtime dirs.
    return state_dir() / 'update.lock'


def open_lock():
    state_dir().mkdir(parents=True, exist_ok=True)
    fd = os.open(lock_path(), os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1:
        os.close(fd)
        raise RuntimeError('Unsafe update lock file')
    return fd


def inherited_guard():
    """Internal worker entry requires the actual inherited, already locked inode."""
    try:
        fd = int(os.environ['NBSHELL_UPDATE_LOCK_FD'])
        held, expected = os.fstat(fd), lock_path().stat()
        if (held.st_dev, held.st_ino) != (expected.st_dev, expected.st_ino):
            return False
        probe = open_lock()
        try:
            try:
                fcntl.flock(probe, fcntl.LOCK_EX | fcntl.LOCK_NB)
                return False
            except BlockingIOError:
                return True
        finally:
            os.close(probe)
    except (KeyError, ValueError, OSError):
        return False


@contextlib.contextmanager
def inhibit_sleep():
    """Use logind's established Inhibit API; retaining its fd holds the lock."""
    lib = ctypes.CDLL('libsystemd.so.0')
    ptr = ctypes.c_void_p
    lib.sd_bus_open_system.argtypes = [ctypes.POINTER(ptr)]
    lib.sd_bus_call_method.argtypes = [ptr, ctypes.c_char_p, ctypes.c_char_p,
                                      ctypes.c_char_p, ctypes.c_char_p, ptr,
                                      ctypes.POINTER(ptr), ctypes.c_char_p]
    lib.sd_bus_message_read_basic.argtypes = [ptr, ctypes.c_char, ptr]
    lib.sd_bus_message_unref.argtypes = [ptr]
    lib.sd_bus_unref.argtypes = [ptr]
    bus, reply = ptr(), ptr()
    fd = None
    def check(result):
        if result < 0:
            raise OSError(-result, 'Cannot inhibit sleep: ' + os.strerror(-result))
    try:
        check(lib.sd_bus_open_system(ctypes.byref(bus)))
        check(lib.sd_bus_call_method(bus, b'org.freedesktop.login1',
              b'/org/freedesktop/login1', b'org.freedesktop.login1.Manager', b'Inhibit',
              None, ctypes.byref(reply), b'ssss', b'sleep', b'nbshell updates',
              b'Installing desktop or system updates', b'block'))
        received = ctypes.c_int(-1)
        check(lib.sd_bus_message_read_basic(reply, b'h', ctypes.byref(received)))
        fd = os.dup(received.value)
        yield fd
    finally:
        if fd is not None:
            os.close(fd)
        lib.sd_bus_message_unref(reply)
        lib.sd_bus_unref(bus)


def drain_children():
    """Wait for adopted installers as well as the direct worker (including sudo)."""
    failed = False
    while True:
        try:
            _pid, result = os.waitpid(-1, 0)
            failed = failed or os.waitstatus_to_exitcode(result) != 0
        except ChildProcessError:
            return failed


@contextlib.contextmanager
def supervise_descendants():
    # Linux reparents orphaned grandchildren here, including privileged workers
    # whose sudo launcher closes inherited fds. Never release protection while
    # an adopted installer is still writing after its immediate parent died.
    libc = ctypes.CDLL(None, use_errno=True)
    libc.prctl.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_ulong,
                          ctypes.c_ulong, ctypes.c_ulong]
    previous = ctypes.c_int()
    for option, value in ((37, ctypes.byref(previous)), (36, ctypes.c_void_p(1))):
        if libc.prctl(option, value, 0, 0, 0) != 0:
            raise OSError(ctypes.get_errno(), 'Cannot supervise update descendants')
    try:
        yield
    finally:
        drain_children()
        libc.prctl(36, ctypes.c_void_p(previous.value), 0, 0, 0)


def save(data):
    destination = state_dir() / 'update-transaction.json'
    fd, name = tempfile.mkstemp(prefix='.update-transaction-', dir=state_dir())
    try:
        with os.fdopen(fd, 'w') as output:
            json.dump(data, output, indent=2)
            output.write('\n')
            output.flush()
            os.fsync(output.fileno())
        os.replace(name, destination)
    finally:
        Path(name).unlink(missing_ok=True)


def load():
    try:
        data = json.loads((state_dir() / 'update-transaction.json').read_text())
        if not isinstance(data, dict):
            raise ValueError('Invalid update transaction')
        return data
    except FileNotFoundError:
        return {'status': 'none', 'steps': []}


def status():
    data = load()
    fd = open_lock()
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            active = False
        except BlockingIOError:
            active = True
        data['active'] = active
        if not active and data.get('status') == 'running':
            data['status'] = 'interrupted'
    finally:
        os.close(fd)
    return data


def existing_parent(path):
    path = Path(path).expanduser().absolute()
    while not path.exists():
        if path == path.parent:
            raise OSError('No existing parent for space check')
        path = path.parent
    return path


def check_space(step):
    # Conservative floors, not a prediction of package/build sizes. Package
    # managers still enforce their own transaction-specific space requirements.
    config = Path(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config')))
    cache = Path(os.environ.get('XDG_CACHE_HOME', str(Path.home() / '.cache')))
    data = Path(os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share')))
    binaries = Path(os.environ.get('XDG_BIN_HOME', str(Path.home() / '.local/bin')))
    paths = [(Path(tempfile.gettempdir()), GIB), (state_dir(), 64 * 1024 ** 2)]
    if step == 'shell':
        paths += [(config / 'quickshell', GIB), (data, GIB), (binaries, GIB)]
    elif step == 'compositor':
        paths += [(Path(tempfile.gettempdir()), 4 * GIB),
                  (Path(os.environ.get('NBSHELL_UMBRIEL_PREFIX', '/usr/local')), GIB),
                  (Path(os.environ.get('NBSHELL_UMBRIEL_SOURCE_DIR', str(Path.home() / 'projects'))), GIB)]
    elif step == 'packages':
        paths += [(Path('/'), 2 * GIB), (Path('/usr'), 2 * GIB),
                  (Path('/var/lib/pacman'), 2 * GIB), (Path('/var/cache/pacman/pkg'), 2 * GIB),
                  (cache, 4 * GIB)]
        paths += [(p, 128 * 1024 ** 2) for p in (Path('/boot'), Path('/efi'), Path('/boot/efi')) if p.exists()]
    elif step == 'flatpak':
        paths += [(Path('/var/lib/flatpak'), 2 * GIB), (data / 'flatpak', 2 * GIB)]
    for path, required in paths:
        if shutil.disk_usage(existing_parent(path)).free < required:
            raise RuntimeError(f'Not enough free space at {path}: at least {required // (1024 ** 2)} MiB required')


def command(step, scripts, channel, yes):
    if step in ('shell', 'compositor'):
        name = 'nbshell-update.py' if step == 'shell' else 'umbriel-update.py'
        result = [sys.executable, str(scripts / name), 'install', '--coordinated']
        if step == 'shell':
            result += ['--channel', channel]
        return result + (['--yes'] if yes else [])
    return ['bash', str(scripts / 'updates.sh'), '_' + step]


def execute(data, lock_fd, inhibit_fd, scripts):
    stopped = []
    old_handlers = {}
    def stop(signum, _frame):
        # Do not release protection underneath an in-flight package transaction.
        stopped.append(signum)
        print('\nStop requested; waiting for the current update step to finish.', flush=True)
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        old_handlers[sig] = signal.signal(sig, stop)
    try:
        with supervise_descendants():
            for row in data['steps']:
                if row['status'] == 'completed':
                    continue
                if stopped:
                    break
                if row['name'] == 'flatpak' and not shutil.which('flatpak'):
                    row.update(status='completed', detail='Flatpak is not installed; nothing to update', exitCode=0)
                    save(data)
                    continue
                row.update(status='running', detail='')
                save(data)
                print(f"\n:: Updating {row['name']}", flush=True)
                try:
                    check_space(row['name'])
                    env = dict(os.environ, NBSHELL_UPDATE_LOCK_FD=str(lock_fd))
                    result = subprocess.run(command(row['name'], scripts, data['channel'], data['yes'] or (row['name'] == 'compositor' and data.get('compositorYes', False))),
                                            env=env, pass_fds=(lock_fd, inhibit_fd))
                    orphan_failed = drain_children()
                    code = result.returncode or (1 if orphan_failed else 0)
                    row.update(exitCode=code, status='completed' if code == 0 else 'cancelled' if code == 125 else 'failed')
                    if code:
                        row['detail'] = f'Updater exited with code {code}; inspect the terminal output before retrying'
                except (OSError, RuntimeError) as exc:
                    row.update(status='failed', exitCode=1, detail=str(exc))
                    print(str(exc), file=sys.stderr)
                    drain_children()
                save(data)
                # A failed desktop dependency must not be followed by another
                # desktop install. Packages and Flatpak are independent.
                if row['status'] != 'completed' and data['mode'] != 'system':
                    break
            data['status'] = ('completed' if all(r['status'] == 'completed' for r in data['steps'])
                              else 'interrupted' if stopped else 'partial' if any(r['status'] == 'completed' for r in data['steps'])
                              else 'failed')
            data['finishedAt'] = int(time.time())
            save(data)
            for row in data['steps']:
                print(f"{row['name']}: {row['status']}" + (f" — {row['detail']}" if row.get('detail') else ''))
            if data['status'] != 'completed':
                print('Completed steps were retained. Review the output, then run: nbshell update retry')
                print('An unsuccessful step may have made changes; retry rechecks it and is not a rollback.')
                return 1
            return 0
    finally:
        for sig, handler in old_handlers.items():
            signal.signal(sig, handler)


def run(mode, channel='beta', yes=False, compositor_yes=False):
    fd = open_lock()
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print('Another nbshell update is running. Finish it before starting another.', file=sys.stderr)
            return 75
        if mode == 'retry':
            previous = load()
            mode = previous.get('mode')
            channel = previous.get('channel')
            if mode not in MODES or channel not in ('stable', 'beta'):
                raise ValueError('No valid previous update to retry')
            rows = previous.get('steps')
            if (not isinstance(rows, list) or len(rows) != len(MODES[mode])
                    or any(not isinstance(r, dict) for r in rows)
                    or [r.get('name') for r in rows] != MODES[mode]):
                raise ValueError('Invalid previous update steps; start a new workflow')
            completed = {r['name'] for r in rows if r.get('status') == 'completed'}
            yes = yes or previous.get('yes') is True
            compositor_yes = compositor_yes or previous.get('compositorYes') is True
        else:
            completed = set()
        data = dict(mode=mode, channel=channel, yes=yes, compositorYes=compositor_yes, status='running', startedAt=int(time.time()),
                    steps=[dict(name=s, status='completed' if s in completed else 'pending') for s in MODES[mode]])
        if all(r['status'] == 'completed' for r in data['steps']):
            print('The previous update completed; nothing to retry.')
            return 0
        # Do not overwrite the last recoverable transaction if preflight fails.
        with inhibit_sleep() as inhibitor:
            for row in data['steps']:
                if row['status'] != 'completed' and (row['name'] != 'flatpak' or shutil.which('flatpak')):
                    check_space(row['name'])
            # Keep one reviewed helper version across shell runtime replacement.
            with tempfile.TemporaryDirectory(prefix='nbshell-update-workflow-') as temporary:
                snapshot = Path(temporary) / 'scripts'
                shutil.copytree(SCRIPTS, snapshot, ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
                catalog = SCRIPTS.parent / 'Catalog'
                if catalog.is_dir():
                    shutil.copytree(catalog, snapshot.parent / 'Catalog')
                for version in (SCRIPTS.parent / 'VERSION', SCRIPTS.parent.parent / 'VERSION'):
                    if version.is_file():
                        shutil.copy2(version, snapshot.parent / 'VERSION')
                        break
                save(data)
                return execute(data, fd, inhibitor, snapshot)
    finally:
        os.close(fd)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=(*MODES, 'retry', 'status', '_guard'))
    parser.add_argument('--channel', choices=('beta', 'stable'), default='beta')
    parser.add_argument('--yes', action='store_true')
    parser.add_argument('--yes-compositor', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    try:
        if args.mode == '_guard':
            return 0 if inherited_guard() else 1
        if args.mode == 'status':
            print(json.dumps(status()))
            return 0
        return run(args.mode, args.channel, args.yes, args.yes_compositor)
    except (OSError, RuntimeError, ValueError) as exc:
        print(f'Update failed: {exc}', file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
