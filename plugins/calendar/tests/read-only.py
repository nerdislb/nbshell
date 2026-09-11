"""Exercise a chmod read-only synthetic source copy with external test outputs."""
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from harness import ROOT

with tempfile.TemporaryDirectory(prefix='calendar-readonly-') as folder:
    work = Path(folder)
    source = work/'source'
    for relative in ('plugins/calendar', 'shell/Widgets', 'tests/imports/qs/Common'):
        shutil.copytree(ROOT/relative, source/relative, ignore=shutil.ignore_patterns('__pycache__', 'screenshots'))
    paths = list(source.rglob('*')) + [source]
    try:
        for path in paths:
            path.chmod(0o555 if path.is_dir() else 0o444)
        try:
            (source/'probe').write_text('must fail')
        except PermissionError:
            print('Read-only source write probe correctly refused.', flush=True)
        else:
            raise AssertionError('Source is still writable; cannot demonstrate read-only safety')
        env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1', TMPDIR=str(work))
        for command in (
            [sys.executable, '-m', 'unittest', 'discover', '-s', str(source/'plugins/calendar/tests'), '-p', 'test_*.py', '-v'],
            ['bash', str(source/'plugins/calendar/tests/run-ui.sh')],
            [sys.executable, str(source/'plugins/calendar/tests/smoke.py')],
            [sys.executable, str(source/'plugins/calendar/tests/render-matrix.py'), str(work/'screenshots')],
        ):
            subprocess.run(command, env=env, check=True)
        print('Read-only source: backend, QML, smoke and render matrix passed.', flush=True)
    finally:
        for path in paths:
            path.chmod(0o755 if path.is_dir() else 0o644)
