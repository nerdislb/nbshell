#!/usr/bin/env python3
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'shell/scripts/clipboard-text.py'
spec = importlib.util.spec_from_file_location('clipboard_text', SCRIPT)
clipboard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(clipboard)
stream = io.BytesIO(b'x' * (4 * 1024 * 1024))
assert clipboard.bounded_read(stream, clipboard.ENTRY_LIMIT) is None
assert stream.tell() == 4 * 1024 * 1024  # Producer is drained without retaining its payload.
assert clipboard.history(b'{broken') == []
assert clipboard.history(json.dumps([None, 'ok', 'x' * 65537]).encode()) == ['ok']
with tempfile.TemporaryDirectory() as temporary:
    path = Path(temporary) / 'history.json'
    path.write_bytes(b'[' + b' ' * (2 * clipboard.HISTORY_LIMIT) + b']')
    run = lambda *args, **kw: subprocess.run([sys.executable, str(SCRIPT), *args], capture_output=True, check=True, **kw)
    assert json.loads(run('load', str(path)).stdout) == []
    text = 'line one\nGrüße ✦'
    assert json.loads(run('capture', 'false', input=text.encode()).stdout) == text
    assert run('capture', 'false', input=b'x' * (4 * 1024 * 1024)).stdout == b''
    run('save', str(path), input=json.dumps([text]).encode())
    assert json.loads(run('load', str(path)).stdout) == [text]
    assert path.stat().st_mode & 0o777 == 0o600
print('Bounded clipboard ingestion and history: OK')
