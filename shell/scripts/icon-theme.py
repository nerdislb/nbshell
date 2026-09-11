#!/usr/bin/env python3
"""Select the desktop icon theme for Quickshell without loading a Qt style plugin."""
import configparser
import os
from pathlib import Path


def select_theme(config_home, data_home, data_dirs):
    roots = [Path(data_home) / 'icons', Path.home() / '.icons']
    roots += [Path(path) / 'icons' for path in data_dirs.split(os.pathsep) if path]

    def installed(name):
        return name and '/' not in name and '\\' not in name and not any(ord(c) < 32 for c in name) and any(
            (root / name / 'index.theme').is_file() for root in roots)

    for filename, section, key in [('qt6ct/qt6ct.conf', 'Appearance', 'icon_theme'),
                                   ('kdeglobals', 'Icons', 'Theme'),
                                   ('gtk-3.0/settings.ini', 'Settings', 'gtk-icon-theme-name')]:
        parser = configparser.ConfigParser(interpolation=None, strict=False)
        try:
            parser.read(Path(config_home) / filename, encoding='utf-8')
            name = parser.get(section, key, fallback='').strip()
        except (OSError, UnicodeError, configparser.Error):
            continue
        if installed(name):
            return name
    for name in ['Papirus-Dark', 'Papirus', 'Adwaita', 'hicolor']:
        if installed(name):
            return name
    return ''


if __name__ == '__main__':
    print(select_theme(os.environ.get('XDG_CONFIG_HOME', str(Path.home() / '.config')),
                       os.environ.get('XDG_DATA_HOME', str(Path.home() / '.local/share')),
                       os.environ.get('XDG_DATA_DIRS', '/usr/local/share:/usr/share')))
