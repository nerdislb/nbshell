#!/usr/bin/env python3
"""Local theme drafts and explicit, non-overwriting Theme Maker publication."""
from __future__ import annotations

import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import tomllib

COLORS = ('background foreground accent muted selection dark_foreground bright_foreground '
          'dark_background darker_background lighter_background red green yellow blue magenta cyan orange '
          'bright_red bright_green bright_yellow bright_blue bright_magenta bright_cyan inactive_border_color outer_border_color').split()
IMAGES = {'.png', '.jpg', '.jpeg', '.webp', '.bmp'}
MOTION = {'.gif', '.mp4', '.webm', '.mkv', '.mov'}
MAX_MEDIA = 2 * 1024**3


def paths():
    config = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config')) / 'nbshell'
    state = Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state')) / 'nbshell/theme-maker'
    return config, state


def read_json(path, default):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return default


def atomic_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode='w', encoding='utf-8', dir=path.parent, delete=False) as handle:
            temporary = Path(handle.name)
            json.dump(value, handle, indent=2, ensure_ascii=False, allow_nan=False)
            handle.write('\n')
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
        temporary = None
    finally:
        if temporary:
            temporary.unlink(missing_ok=True)


def validate(raw):
    if not isinstance(raw, dict) or not isinstance(raw.get('palette'), dict):
        raise ValueError('The draft has no color palette.')
    palette = {}
    for key in COLORS:
        value = raw['palette'].get(key)
        if value is not None:
            if not isinstance(value, str) or not re.fullmatch(r'#[0-9a-fA-F]{6}', value):
                raise ValueError(f'Invalid color for {key}. Use #RRGGBB.')
            palette[key] = value.lower()
    if not all(key in palette for key in ('background', 'foreground', 'accent')):
        raise ValueError('Background, foreground and accent are required.')
    mode = raw['palette'].get('mode', 'dark')
    if mode not in ('light', 'dark'):
        raise ValueError('Choose light or dark mode.')
    palette['mode'] = mode
    if 'border_width' in raw['palette']:
        border = raw['palette']['border_width']
        if type(border) is not int or not 1 <= border <= 8:
            raise ValueError('Window border width must be between 1 and 8.')
        palette['border_width'] = border
    name = str(raw.get('name') or '').strip()
    if not name or len(name) > 80 or any(ord(c) < 32 for c in name):
        raise ValueError('Use a theme name between 1 and 80 characters.')
    background = raw.get('background', {})
    if not isinstance(background, dict):
        raise ValueError('Invalid background settings.')
    result = {'enabled': background.get('enabled') is True}
    for key in ('image', 'motion'):
        path = str(background.get(key) or '')
        if path and (not Path(path).is_absolute() or '\x00' in path or len(path) > 4096):
            raise ValueError('Choose a local background file.')
        result[key] = path
    for key, default in (('dim', 0.25), ('panelOpacity', 0.94)):
        value = float(background.get(key, default))
        if not 0 <= value <= 1:
            raise ValueError('Background values must be between zero and one.')
        result[key] = value
    result['paused'] = background.get('paused') is True
    return {'name': name, 'palette': palette, 'background': result,
            'linked': raw.get('linked', True) is True}


def theme_names():
    config, _ = paths()
    directory = config / 'themes'
    return sorted(p.name for p in directory.iterdir() if not p.name.startswith(".") and p.is_dir() and (p / 'colors.toml').is_file()) if directory.is_dir() else []


def load_theme(name):
    config, _ = paths()
    if name not in theme_names():
        raise ValueError('The selected theme is no longer available.')
    directory = config / 'themes' / name
    with (directory / 'colors.toml').open('rb') as handle:
        palette = tomllib.load(handle)
    meta = read_json(directory / 'theme-maker.json', {})
    if not isinstance(meta, dict):
        meta = {}
    assets = meta.get('assets', {})
    if not isinstance(assets, dict):
        assets = {}
    images = sorted(p for p in (directory / 'backgrounds').glob('*') if p.suffix.lower() in IMAGES)
    def asset(key):
        value = str(assets.get(key) or '')
        # Export metadata is portable and cannot redirect outside the package.
        if not value or Path(value).is_absolute() or '..' in Path(value).parts:
            return ''
        p = directory / value
        return str(p) if p.is_file() and p.resolve().is_relative_to(directory.resolve()) else ''
    settings = meta.get('background', {})
    if not isinstance(settings, dict):
        settings = {}
    desktop = read_json(config / 'config.json', {})
    if not isinstance(desktop, dict):
        raise ValueError('The shell configuration must be a JSON object.')
    current_image = ''
    if desktop.get('theme') == name:
        current_image = str(desktop.get('wallpaperOverride') or (desktop.get('wallpaperByTheme') or {}).get(name) or '')
    data_root = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share')) / 'nbshell/wallpapers' / name
    if not images and data_root.is_dir():
        images = sorted(p for p in data_root.iterdir() if p.suffix.lower() in IMAGES and p.is_file())
    background = {'enabled': False, 'image': asset('image') or current_image or (str(images[0]) if images else ''),
                  'motion': asset('motion'), 'dim': settings.get('dim', 0.25),
                  'panelOpacity': settings.get('panelOpacity', 0.94), 'paused': False}
    return {'name': name + '-custom', 'palette': palette, 'background': background, 'linked': True}


def initialize():
    config, state = paths()
    settings = read_json(config / 'config.json', {})
    if not isinstance(settings, dict):
        raise ValueError('The shell configuration must be a JSON object.')
    names = theme_names()
    selected = settings.get('theme', '')
    if selected not in names:
        selected = names[0] if names else ''
    if not selected:
        raise ValueError('No installed themes were found.')
    draft = None
    try:
        draft = validate(read_json(state / 'draft.json', {}))
    except (ValueError, TypeError):
        pass
    return {'themes': names, 'selected': selected, 'state': load_theme(selected), 'draft': draft}


def copy_media(source, destination, extensions):
    if source.suffix.lower() not in extensions:
        raise ValueError('Unsupported background format.')
    # Pin the selected regular inode without blocking on a FIFO or device.
    fd = os.open(source, os.O_RDONLY | os.O_NONBLOCK)
    with os.fdopen(fd, 'rb') as incoming:
        info = os.fstat(incoming.fileno())
        if not stat.S_ISREG(info.st_mode) or info.st_size > MAX_MEDIA:
            raise ValueError('Choose a regular background file smaller than 2 GiB.')
        remaining = MAX_MEDIA
        with destination.open('xb') as output:
            while chunk := incoming.read(min(1024 * 1024, remaining + 1)):
                remaining -= len(chunk)
                if remaining < 0:
                    raise ValueError('The background grew beyond the 2 GiB limit.')
                output.write(chunk)
            output.flush()
            os.fsync(output.fileno())


def ffmpeg(arguments):
    try:
        result = subprocess.run(['ffmpeg', '-nostdin', '-hide_banner', '-loglevel', 'error', '-protocol_whitelist', 'file,pipe', *arguments],
                                capture_output=True, text=True, timeout=180)
    except FileNotFoundError:
        raise ValueError('Install ffmpeg to package animated backgrounds.') from None
    if result.returncode:
        raise ValueError('The background could not be decoded. Choose another media file.')


def publish(raw, parent=None):
    draft = validate(raw)
    config, _ = paths()
    parent = Path(parent) if parent else config / 'themes'
    if not parent.is_absolute():
        raise ValueError('Choose an absolute export folder.')
    parent.mkdir(parents=True, exist_ok=True)
    slug = re.sub(r'[^a-z0-9]+', '-', draft['name'].lower()).strip('-')[:60] or 'custom-theme'
    stage = Path(tempfile.mkdtemp(prefix='.theme-maker-', dir=parent))
    destination = None
    try:
        lines = ['# Created with nbshell Theme Maker']
        lines += [key + ' = ' + json.dumps(value) for key, value in draft['palette'].items()]
        (stage / 'colors.toml').write_text('\n'.join(lines) + '\n')
        assets = {}
        bg = draft['background']
        if bg['enabled'] and (bg['image'] or bg['motion']):
            media_dir = stage / 'backgrounds'
            media_dir.mkdir()
            if bg['image']:
                image = Path(bg['image'])
                name = 'wallpaper' + image.suffix.lower()
                copy_media(image, media_dir / name, IMAGES)
                assets['image'] = 'backgrounds/' + name
            if bg['motion']:
                motion = Path(bg['motion'])
                name = 'loop' + motion.suffix.lower()
                copy_media(motion, media_dir / name, MOTION)
                if motion.suffix.lower() == '.gif':
                    ffmpeg(['-i', str(media_dir / name), '-an', '-vf', 'pad=ceil(iw/2)*2:ceil(ih/2)*2',
                            '-c:v', 'libx264', '-pix_fmt', 'yuv420p', str(media_dir / 'loop.mp4')])
                    assets['gif'] = 'backgrounds/' + name
                    name = 'loop.mp4'
                assets['motion'] = 'backgrounds/' + name
                if 'image' not in assets:
                    ffmpeg(['-i', str(media_dir / name), '-frames:v', '1', str(media_dir / 'wallpaper.png')])
                    assets['image'] = 'backgrounds/wallpaper.png'
        meta = {'version': 1, 'name': draft['name'], 'assets': assets,
                'background': {key: bg[key] for key in ('dim', 'panelOpacity')}}
        atomic_json(stage / 'theme-maker.json', meta)
        # Reserve a unique name with mkdir. Never replace an existing theme.
        for index in range(1, 10000):
            candidate = parent / (slug if index == 1 else f'{slug}-{index}')
            try:
                candidate.mkdir()
                destination = candidate
                break
            except FileExistsError:
                continue
        if destination is None:
            raise ValueError('No free theme name is available.')
        # Only our empty reserved directory is replaced; colors.toml appears last
        # through the directory rename, so the theme index never sees half a theme.
        os.replace(stage, destination)
        return {'name': destination.name, 'path': str(destination), 'assets': assets}
    finally:
        if stage.exists():
            shutil.rmtree(stage)
            if destination and destination.is_dir() and not any(destination.iterdir()):
                destination.rmdir()


def preview(raw):
    draft = validate(raw)
    bg = draft['background']
    wallpaper = None
    if bg['enabled'] and (bg['image'] or bg['motion']):
        image, motion = bg['image'], bg['motion']
        for path in (image, motion):
            if path and not Path(path).is_file():
                raise ValueError('The selected background file is no longer available.')
        if motion.lower().endswith('.gif'):
            # Media conversion only; Apply never writes a theme package.
            cache = paths()[1] / 'preview-media'
            cache.mkdir(parents=True, exist_ok=True)
            import hashlib
            source = Path(motion)
            identity = f'{source.resolve()}:{source.stat().st_mtime_ns}:{source.stat().st_size}'
            target = cache / (hashlib.sha256(identity.encode()).hexdigest() + '.mp4')
            if not target.exists():
                temporary = Path(tempfile.mkdtemp(dir=cache))
                try:
                    ffmpeg(['-i', motion, '-an', '-vf', 'pad=ceil(iw/2)*2:ceil(ih/2)*2',
                            '-c:v', 'libx264', '-pix_fmt', 'yuv420p', str(temporary / 'loop.mp4')])
                    os.replace(temporary / 'loop.mp4', target)
                finally:
                    shutil.rmtree(temporary)
            motion = str(target)
        wallpaper = {'daytimeEnabled': False, 'image': image,
                     'videoEnabled': bool(motion), 'video': motion}
    preview_ipc('preview', json.dumps({'palette': draft['palette'], 'wallpaper': wallpaper}))
    return {'message': 'Preview applied · not saved. Save theme to keep it in your library.'}


def preview_ipc(action, payload=None):
    command = ['nbshell', 'themes', action]
    if payload is not None:
        command.append(payload)
    result = subprocess.run(command, capture_output=True, text=True, timeout=10)
    expected = 'preview applied' if action == 'preview' else 'preview reset'
    if result.returncode or result.stdout.strip() != expected:
        raise ValueError('Desktop preview failed. Make sure the updated nbshell is running.')


def main():
    try:
        raw = sys.stdin.buffer.readline(2 * 1024 * 1024 + 1)
        if len(raw) > 2 * 1024 * 1024:
            raise ValueError('Theme request is too large.')
        request = json.loads(raw or '{}')
        if not isinstance(request, dict):
            raise ValueError('Expected a Theme Maker request object.')
        action = request.get('action', 'init')
        if action == 'init':
            result = initialize()
        elif action == 'load':
            result = {'state': load_theme(str(request.get('name') or ''))}
        elif action == 'draft':
            atomic_json(paths()[1] / 'draft.json', validate(request['state']))
            result = {'message': 'Draft saved'}
        elif action == 'apply':
            result = preview(request['state'])
        elif action == 'reset-preview':
            preview_ipc('reset-preview')
            result = {'message': 'Desktop preview reset · saved theme restored'}
        elif action in ('save', 'export'):
            result = publish(request['state'], request.get('folder') if action == 'export' else None)
            result['message'] = 'Saved ' + result['name']
            if action != 'export' and shutil.which('nbshell'):
                try:
                    subprocess.run(['nbshell', 'themes', 'reload'], capture_output=True, timeout=10)
                except (OSError, subprocess.TimeoutExpired):
                    result['message'] += ' (theme list will refresh on restart)'
        else:
            raise ValueError('Unknown Theme Maker action.')
        print(json.dumps({'ok': True, **result}))
        return 0
    except (OSError, ValueError, TypeError, KeyError, subprocess.TimeoutExpired) as error:
        print(json.dumps({'ok': False, 'error': str(error)}))
        return 1


if __name__ == '__main__':
    sys.exit(main())
