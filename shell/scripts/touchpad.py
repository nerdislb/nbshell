#!/usr/bin/env python3
"""Native Umbriel touchpad settings. No device access, privileges or Hyprland.

Only Apply writes. A journal protects the include insertion and managed settings;
recovery refuses to overwrite edits made by a different configuration tool.
"""
from __future__ import annotations
import argparse
import copy
import ctypes
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import tempfile
import time
import tomllib
from contextlib import contextmanager

CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config'))
MAIN = CONFIG / 'umbriel/config.toml'
OWNED = CONFIG / 'umbriel/nbshell-touchpad.toml'
STORE = CONFIG / 'nbshell/touchpad'
JOURNAL = STORE / 'pending.json'
MARKER = '# nbshell-touchpad-v1 '
DEFAULT_CURVE = dict(precision=0.1875, start=0.8, end=2.8, fast=1.0)
INPUT_KEYS = {'tap', 'natural_scroll', 'disable_while_typing', 'click_method',
              'sensitivity', 'scroll_factor', 'accel_profile'}


def check_parents(path):
    for parent in [path.parent, *path.parent.parents]:
        if parent.is_symlink():
            raise ValueError(f'Symlink in configuration path: {parent}')


def read(path):
    check_parents(path)
    if not path.exists() and not path.is_symlink():
        return None
    info = path.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_nlink != 1:
        raise ValueError(f'Not a regular, user-owned file: {path}')
    if info.st_mode & 0o022 or info.st_size > 1024 * 1024:
        raise ValueError(f'Unsafe permissions or oversized file: {path}')
    return path.read_text()


def atomic(path, content):
    # Private state and config paths must not redirect writes through symlinks.
    for parent in [path.parent, *path.parent.parents]:
        if parent == Path.home().resolve().parent:
            break
        if parent.is_symlink():
            raise ValueError(f'Symlink in configuration path: {parent}')
    read(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    if content is None:
        path.unlink(missing_ok=True)
        return
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o600
    fd, name = tempfile.mkstemp(prefix='.' + path.name, dir=path.parent)
    try:
        with os.fdopen(fd, 'w') as out:
            os.fchmod(out.fileno(), mode)
            out.write(content)
            out.flush()
            os.fsync(out.fileno())
        os.replace(name, path)
        directory = os.open(path.parent, os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(name):
            os.unlink(name)


@contextmanager
def locked():
    check_parents(STORE / "lock")
    STORE.mkdir(parents=True, exist_ok=True)
    lock = STORE / 'lock'
    read(lock)
    fd = os.open(lock, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        deadline = time.monotonic() + 2
        while True:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except BlockingIOError:
                if time.monotonic() > deadline:
                    raise ValueError('Touchpad settings are busy; retry shortly.')
                time.sleep(.05)
        yield
    finally:
        os.close(fd)


def run(*args):
    result = subprocess.run(args, capture_output=True, text=True, timeout=8)
    if result.returncode:
        raise ValueError((result.stderr or result.stdout or 'Command failed').strip()[-3000:])
    return result.stdout + result.stderr


def reload():
    output = run('umbriel', 'msg', 'config-reload')
    if 'error' in output.lower() or 'failed' in output.lower():
        raise ValueError(output.strip())


def merge(base, overlay):
    for key, value in overlay.items():
        if isinstance(value, dict) and isinstance(base.get(key), dict):
            merge(base[key], value)
        elif isinstance(value, list) and value and all(isinstance(v, dict) for v in value) and isinstance(base.get(key), list):
            base[key] += copy.deepcopy(value)
        else:
            base[key] = copy.deepcopy(value)
    return base


def effective(path= None, seen=None):
    path = MAIN if path is None else path
    seen = set() if seen is None else seen
    real = path.resolve()
    if real in seen:
        raise ValueError('Repeated or cyclic Umbriel include; inspect the config first.')
    seen.add(real)
    raw = read(path)
    if raw is None:
        raise ValueError(f'Missing config: {path}')
    data = tomllib.loads(raw)
    base = {}
    includes = data.pop('include', {})
    for kind, items in [('files', includes.get('files', [])), ('optional', includes.get('optional', {}).get('files', []))]:
        for item in items:
            child = Path(os.path.expandvars(os.path.expanduser(item)))
            if not child.is_absolute():
                child = path.parent / child
            if not child.exists() and kind == 'optional':
                continue
            merge(base, effective(child, seen))
    return merge(base, data)


def include_text(raw):
    data = tomllib.loads(raw)
    inc = data.get('include', {})
    target = OWNED.name
    if target in inc.get('files', []) or target in inc.get('optional', {}).get('files', []):
        return raw
    section = re.search(r'(?m)^\[include\][ \t]*(?:#[^\n]*)?\n', raw)
    if section:
        tail = raw[section.end():]
        end = re.search(r'(?m)^\s*\[', tail)
        limit = section.end() + (end.start() if end else len(tail))
        body = raw[section.end():limit]
        if 'files' in inc:
            match = re.search(r'(?ms)^files\s*=\s*\[(.*?)\]', body)
            if not match:
                raise ValueError('Unsupported include syntax; add nbshell-touchpad.toml to include.files.')
            replacement = 'files = ' + json.dumps(inc['files'] + [target])
            body = body[:match.start()] + replacement + body[match.end():]
        else:
            body = 'files = ["' + target + '"]\n' + body
        changed = raw[:section.end()] + body + raw[limit:]
    elif inc:
        raise ValueError('Unsupported include syntax; use an [include] table first.')
    else:
        changed = raw + '\n[include]\nfiles = ["' + target + '"]\n'
    expected = copy.deepcopy(data)
    expected.setdefault('include', {}).setdefault('files', []).append(target)
    if tomllib.loads(changed) != expected:
        raise ValueError('Include edit would change unrelated configuration.')
    return changed


def curve_points(curve):
    if set(curve) != {'precision', 'start', 'end', 'fast'}:
        raise ValueError('Invalid curve fields.')
    p, start, end, fast = (number(curve[k], 0, 10) for k in ('precision', 'start', 'end', 'fast'))
    if not .01 <= p <= fast <= 10 or not 0 <= start < end <= 4 or end - start < .199999:
        raise ValueError('Curve needs 0.01 ≤ precision ≤ fast ≤ 10 and a transition of at least 5%.')
    points = []
    for i in range(43):
        speed = i * .1
        t = max(0, min(1, (speed - start) / (end - start)))
        points.append(round(speed * (p + (fast-p) * t*t*(3-2*t)), 6))
    return points


def number(value, low, high):
    if isinstance(value, bool) or not isinstance(value, (float, int)) or not math.isfinite(value) or not low <= value <= high:
        raise ValueError(f'Expected a number in {low}…{high}.')
    return value


def native_validate(points, step=.1):
    lib = ctypes.CDLL('libinput.so.10')
    lib.libinput_config_accel_create.argtypes = [ctypes.c_int]
    lib.libinput_config_accel_create.restype = ctypes.c_void_p
    lib.libinput_config_accel_set_points.argtypes = [ctypes.c_void_p, ctypes.c_int, ctypes.c_double, ctypes.c_size_t, ctypes.POINTER(ctypes.c_double)]
    lib.libinput_config_accel_set_points.restype = ctypes.c_int
    lib.libinput_config_accel_destroy.argtypes = [ctypes.c_void_p]
    obj = lib.libinput_config_accel_create(4)
    if not obj:
        raise ValueError('libinput custom acceleration is unavailable.')
    try:
        values = (ctypes.c_double * len(points))(*points)
        if lib.libinput_config_accel_set_points(obj, 1, step, len(points), values) != 0:
            raise ValueError('libinput rejected the custom curve.')
    finally:
        lib.libinput_config_accel_destroy(obj)


def validate(settings):
    settings = copy.deepcopy(settings)
    allowed = INPUT_KEYS | {'profile', 'curve'}
    if not isinstance(settings, dict) or set(settings) - allowed:
        raise ValueError('Unknown touchpad settings.')
    for key in ('tap', 'natural_scroll', 'disable_while_typing'):
        if key in settings and type(settings[key]) is not bool:
            raise ValueError(f'{key} must be a boolean.')
    if 'sensitivity' in settings: number(settings['sensitivity'], -1, 1)
    if 'scroll_factor' in settings: number(settings['scroll_factor'], .1, 10)
    if 'click_method' in settings and settings['click_method'] not in ('button_areas', 'clickfinger'):
        raise ValueError('Unknown click method.')
    profile = settings.get('profile', 'system')
    if profile not in ('system', 'adaptive', 'flat', 'mac', 'custom', 'external'):
        raise ValueError('Unknown pointer profile.')
    if profile in ('mac', 'custom'):
        points = curve_points(settings.get('curve', {}))
        native_validate(points)
        settings['accel_profile'] = 'custom 0.1 ' + ' '.join(format(v, '.6f') for v in points)
    elif profile in ('adaptive', 'flat'):
        settings['accel_profile'] = profile
    elif profile == 'system':
        settings.pop('accel_profile', None)
    elif not isinstance(settings.get('accel_profile'), str):
        raise ValueError('Missing inherited acceleration profile.')
    return settings


def metadata(raw):
    if not raw:
        return {'active': False, 'settings': {}, 'previous': None}
    first = raw.splitlines()[0]
    if not first.startswith(MARKER):
        raise ValueError('The touchpad file is not owned by this tool; refusing to overwrite it.')
    result = json.loads(first[len(MARKER):])
    if set(result) != {'active', 'settings', 'previous'}:
        raise ValueError('Unsupported touchpad state.')
    if render(result) != raw:
        raise ValueError('The managed touchpad file changed externally. Preserve it before continuing.')
    return result


def render(meta):
    lines = [MARKER + json.dumps(meta, separators=(',', ':')), '# Managed by nbshell touchpad. Use Restore previous to undo.']
    if meta['active']:
        lines.append('[input.touchpad]')
        for key in sorted(INPUT_KEYS & meta['settings'].keys()):
            lines.append(key + ' = ' + json.dumps(meta['settings'][key]))
    return '\n'.join(lines) + '\n'


def devices():
    rows = []
    for entry in sorted(Path('/sys/class/input').glob('event*')):
        props = run('udevadm', 'info', '--query=property', '--path=' + str(entry))
        if 'ID_INPUT_TOUCHPAD=1' in props.splitlines():
            rows.append({'name': (entry / 'device/name').read_text().strip(), 'event': entry.name})
    return rows


def revision():
    return hashlib.sha256(((read(MAIN) or '') + '\0' + (read(OWNED) or '') + '\0' + json.dumps(effective(), sort_keys=True)).encode()).hexdigest()


def status():
    data = effective().get('input', {})
    meta = metadata(read(OWNED))
    settings = {k: v for k, v in data.get('touchpad', {}).items() if k in INPUT_KEYS}
    profile = settings.get('accel_profile', 'system')
    if profile.startswith('custom '): profile = 'external'
    settings['profile'] = meta['settings'].get('profile', profile) if meta['active'] else profile
    settings['curve'] = meta['settings'].get('curve', DEFAULT_CURVE) if meta['active'] else DEFAULT_CURVE
    warnings = []
    if data.get('device'):
        warnings.append('Per-device rules exist and may override these global touchpad settings.')
    if tomllib.loads(read(MAIN) or '').get('input', {}).get('touchpad'):
        warnings.append('The main config has touchpad overrides; conflicting edits are rejected.')
    return dict(settings=settings, devices=devices(), revision=revision(), canRestore=meta['previous'] is not None,
                warnings=warnings, scope='All touchpads; per-device rules take precedence.')


def recover():
    raw = read(JOURNAL)
    if raw is None:
        return
    transaction = json.loads(raw)
    for key, path in [('main', MAIN), ('owned', OWNED)]:
        if read(path) not in (transaction['before'][key], transaction['after'][key]):
            raise ValueError(f'Recovery paused: {path.name} changed externally. Preserve pending.json and resolve the conflict.')
    # Restore the include first so deleting a newly created owned file is safe.
    for key, path in [('main', MAIN), ('owned', OWNED)]:
        atomic(path, transaction['before'][key])
    reload()
    atomic(JOURNAL, None)


def apply(payload, restore=False):
    if payload.get('revision') != revision():
        raise ValueError('Configuration changed. Refresh before applying your draft.')
    previous = metadata(read(OWNED))
    if restore:
        if previous['previous'] is None:
            raise ValueError('There is no previous configuration to restore.')
        meta = copy.deepcopy(previous['previous'])
    else:
        settings = validate(payload['settings'])
        # Unsupported private/custom raw profiles must remain byte-for-byte inherited.
        if settings.get('profile') == 'external' and settings.get('accel_profile') != status()['settings'].get('accel_profile'):
            raise ValueError('Choose Custom to edit a curve.')
        meta = {'active': True, 'settings': settings}
    meta['previous'] = {k: previous[k] for k in ('active', 'settings')}
    before = {'main': read(MAIN), 'owned': read(OWNED)}
    after = {'main': include_text(before['main']), 'owned': render(meta)}
    # Validate a candidate BEFORE touching watched files. Umbriel auto-reloads
    # config changes, so validation after replacing the live file is too late.
    candidates = []
    try:
        for prefix, content in [('touchpad', after['owned']), ('root', None)]:
            fd, name = tempfile.mkstemp(prefix='.nbshell-' + prefix + '-', suffix='.toml', dir=MAIN.parent)
            os.close(fd)
            candidate = Path(name)
            candidates.append(candidate)
            if content is not None: atomic(candidate, content)
        candidate_owned, candidate_root = candidates
        candidate_text = after['main'].replace('"' + OWNED.name + '"', '"' + candidate_owned.name + '"')
        atomic(candidate_root, candidate_text)
        actual = effective(candidate_root).get('input', {}).get('touchpad', {})
        if meta['active']:
            for key in INPUT_KEYS & meta['settings'].keys():
                if actual.get(key) != meta['settings'][key]:
                    raise ValueError(f'{key} is overridden by another config file. No changes applied.')
        validation = run('umbriel', 'validate', '-c', str(candidate_root))
        if re.search(r'\b(warn|warning|error|invalid)\b', validation, re.I):
            raise ValueError('Umbriel configuration has warnings; resolve them before applying. ' + validation[-1500:])
    finally:
        for candidate in candidates: candidate.unlink(missing_ok=True)
    if payload.get('revision') != revision():
        raise ValueError('Configuration changed during validation. Refresh and retry.')
    atomic(JOURNAL, json.dumps({'before': before, 'after': after}))
    try:
        atomic(OWNED, after['owned'])
        if before['main'] != after['main']: atomic(MAIN, after['main'])
        reload()
    except Exception:
        recover()
        raise
    atomic(JOURNAL, None)
    return status()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['status', 'apply', 'restore'], default='status', nargs='?')
    args = parser.parse_args()
    try:
        with locked():
            recover()
            if args.action == 'status':
                result = status()
            else:
                raw = sys.stdin.read(65537)
                if len(raw) > 65536: raise ValueError('Request too large.')
                result = apply(json.loads(raw), args.action == 'restore')
        print(json.dumps(result))
    except Exception as error:
        print(json.dumps({'error': str(error)}))
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
