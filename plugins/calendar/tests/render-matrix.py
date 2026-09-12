#!/usr/bin/env python3
"""Render synthetic scenes to an explicit output directory; clean up fixtures."""
import os
from pathlib import Path
import subprocess
import sys
from harness import ROOT as root, sandbox
if len(sys.argv) != 2:
    raise SystemExit('Usage: render-matrix.py OUTPUT_DIRECTORY')
output = Path(sys.argv[1]).resolve()
output.mkdir(parents=True, exist_ok=True)
with sandbox() as (work, env):
    env.update(CALENDAR_TEST_WORK=str(work), CALENDAR_TEST_OUTPUT=str(output))
    theme = work / 'imports/qs/Common/Theme.qml'
    dark = theme.read_text()
    import re
    palette = {'#101010':'#fafafa','#f0f0f0':'#202020','#a0a0a0':'#606060','#202020':'#eeeeee','#303030':'#dedede','#60a0ff':'#1856a0','#80b8ff':'#1856a0','#ff6060':'#ae2020'}
    light = re.sub('|'.join(palette), lambda match: palette[match[0]], dark)
    try:
        for mode,page,width,height,name,source in [
            ('Month','calendar',1100,760,'month-dark',dark),
            ('Month','calendar',940,1000,'month-tall-light',light),
            ('Month','calendar',700,480,'month-small-light',light),
            ('Week','calendar',620,720,'week-light',light),
            ('Agenda','accounts',360,760,'accounts-narrow-light',light),
            ('Agenda','editor',620,760,'editor-dark',dark),
            ('Agenda','error',360,640,'error-narrow-dark',dark),
            ('Agenda','empty',620,640,'empty-light',light),
            ('Agenda','loading',620,640,'loading-dark',dark),
            ('Agenda','invalid',360,640,'invalid-narrow-light',light),
            ('Agenda','disconnect',360,640,'disconnect-narrow-dark',dark),
            ('Agenda','allday',620,640,'allday-light',light)]:
            theme.write_text(source)
            subprocess.run([sys.executable,str(root/'plugins/calendar/tests/render.py'),mode,page,str(width),str(height),name],env=env,check=True,timeout=15)
    finally:
        theme.write_text(dark)
