#!/usr/bin/env python3
"""Refuse upgrading an installed legacy Mail worker while it owns an AI job."""
import os
from pathlib import Path
import sys


def active_workers(script, proc=Path('/proc')):
    expected = os.fsencode(Path(script).resolve())
    for entry in proc.iterdir():
        if not entry.name.isdigit():
            continue
        try:
            if entry.stat().st_uid != os.getuid():
                continue
            args = (entry / 'cmdline').read_bytes().split(b'\0')
            if len(args) == 5 and args[1] == expected and args[2] == b'run':
                yield entry.name
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue


if __name__ == '__main__':
    if any(active_workers(sys.argv[1])):
        sys.exit('Mail has a running legacy AI job. Finish or cancel it in Mail, then retry the update. No job was stopped.')
