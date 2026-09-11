import subprocess
from harness import ROOT, sandbox

with sandbox() as (work, env):
    # Pin a DST-observing zone so date expectations are reproducible.
    env['TZ'] = 'Europe/Vienna'
    subprocess.run(['/usr/lib/qt6/bin/qmltestrunner', '-import', str(work/'imports'),
                    '-input', str(ROOT/'plugins/calendar/tests/tst_calendar.qml'), '-o', '-,txt'],
                   env=env, check=True, timeout=30)
