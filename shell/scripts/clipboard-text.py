#!/usr/bin/env python3
"""Bound clipboard input and persisted history before it reaches the UI."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ENTRY_LIMIT = 64 * 1024
HISTORY_LIMIT = 1024 * 1024
COUNT_LIMIT = 100


def bounded_read(stream, limit):
    value = stream.read(limit + 1)
    if len(value) > limit:
        while stream.read(65536):
            pass
        return None
    return value


def history(raw):
    try:
        rows = json.loads(raw or b"[]")
        if not isinstance(rows, list):
            return []
        result = []
        size = 2
        for row in rows[:COUNT_LIMIT]:
            if not isinstance(row, str) or len(row.encode('utf-8')) > ENTRY_LIMIT:
                continue
            cost = len(json.dumps(row, ensure_ascii=False).encode('utf-8')) + 2
            if size + cost > HISTORY_LIMIT:
                break
            size += cost
            result.append(row)
        return result
    except (ValueError, UnicodeError):
        return []


def main():
    action = sys.argv[1]
    if action == 'capture':
        raw = bounded_read(sys.stdin.buffer, ENTRY_LIMIT)
        if raw is None:
            return
        if sys.argv[2] == 'true':
            if os.environ.get('CLIPBOARD_STATE') in ('sensitive', 'nil', 'clear'):
                return
            try:
                types = subprocess.run(['wl-paste', '--list-types'], capture_output=True, timeout=2)
                if types.returncode or b'passwordmanagerhint' in types.stdout.lower():
                    return
            except (OSError, subprocess.TimeoutExpired):
                return
        print(json.dumps(raw.decode('utf-8', errors='replace'), ensure_ascii=False))
        return
    path = Path(sys.argv[2])
    if action == 'load':
        try:
            with path.open('rb') as stream:
                # Do not drain files: an oversized history is rejected immediately.
                raw = stream.read(HISTORY_LIMIT + 1)
            rows = history(raw) if len(raw) <= HISTORY_LIMIT else []
        except OSError:
            rows = []
        print(json.dumps(rows, ensure_ascii=False))
    elif action == 'save':
        raw = bounded_read(sys.stdin.buffer, HISTORY_LIMIT)
        if raw is None:
            return
        path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile('w', encoding='utf-8', dir=path.parent, delete=False) as stream:
            temporary = Path(stream.name)
            json.dump(history(raw), stream, ensure_ascii=False)
        try:
            os.replace(temporary, path)
        finally:
            temporary.unlink(missing_ok=True)
    else:
        raise SystemExit('Unknown clipboard action')


if __name__ == '__main__':
    main()
