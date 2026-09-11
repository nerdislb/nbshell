"""Synthetic imports and writable outputs, independent of source permissions."""
import os
from pathlib import Path
import shutil
import tempfile
from contextlib import contextmanager

ROOT = Path(__file__).resolve().parents[3]

@contextmanager
def sandbox():
    with tempfile.TemporaryDirectory(prefix='calendar-test-') as folder:
        work = Path(folder)
        common = work / 'imports/qs/Common'
        shutil.copytree(ROOT / 'tests/imports/qs/Common', common)
        for path in [common, *common.rglob('*')]:
            path.chmod(0o755 if path.is_dir() else 0o644)
        theme = common / 'Theme.qml'
        theme.write_text(theme.read_text().replace('QtObject {', 'QtObject {\n    readonly property color fgBright: fg'))
        widgets = work / 'imports/qs/Widgets'
        widgets.mkdir()
        names = ['ActionButton', 'ControlButton', 'InteractiveSurface', 'Line', 'TextField', 'Segments', 'PanelSurface', 'PanelHead', 'PanelRow', 'SectionHeader', 'Glyph']
        for name in names:
            shutil.copy(ROOT / 'shell/Widgets' / (name + '.qml'), widgets)
        (widgets / 'qmldir').write_text('module qs.Widgets\n' + ''.join(f'{n} 1.0 {n}.qml\n' for n in names))
        (work / 'runtime').mkdir(mode=0o700)
        env = dict(os.environ, XDG_RUNTIME_DIR=str(work/'runtime'), XDG_CONFIG_HOME=str(work/'config'),
                   XDG_STATE_HOME=str(work/'state'), XDG_CACHE_HOME=str(work/'cache'),
                   NBSHELL_CALENDAR_STATE=str(work/'accounts'), QT_QPA_PLATFORM='offscreen',
                   QT_QUICK_BACKEND='software', QT_QPA_PLATFORMTHEME='',
                   DBUS_SESSION_BUS_ADDRESS='unix:path='+str(work/'no-bus'),
                   PYTHONDONTWRITEBYTECODE='1', QML_DISABLE_DISK_CACHE='1')
        for key in ('DISPLAY', 'WAYLAND_DISPLAY'):
            env.pop(key, None)
        yield work, env
