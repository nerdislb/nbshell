#!/usr/bin/env python3
"""The real release audit only exempts the exact public TLS fixture."""
from pathlib import Path
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
KEY = Path('plugins/omamail/src/providers/testdata/tls/server-key.pem')
with tempfile.TemporaryDirectory(prefix='nbshell-privacy-test-') as directory:
    root = Path(directory)
    names = subprocess.check_output(['git', 'ls-files', '-z'], cwd=ROOT).decode().split('\0')
    for name in filter(None, names):
        source, destination = ROOT / name, root / name
        if source.is_file():
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(source, destination)
    env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
    env.update(GIT_CONFIG_NOSYSTEM='1', GIT_CONFIG_GLOBAL='/dev/null')
    def git(*args):
        subprocess.run(['git', '-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false',
                        *args], cwd=root, env=env, check=True, capture_output=True)
    git('init', '--quiet', '--template=')
    git('add', '.')
    def audit():
        return subprocess.run(['bash', 'tests/release-audit.sh'], cwd=root, env=env,
                              capture_output=True, text=True, timeout=30)
    result = audit()
    assert result.returncode == 0, result.stdout + result.stderr
    payload = (root / KEY).read_bytes()
    (root / KEY).write_bytes(payload + b'\n')
    result = audit()
    assert result.returncode != 0 and str(KEY) in result.stderr, result.stdout + result.stderr
    (root / KEY).write_bytes(payload)
    extra = root / 'tests/copied-key.pem'
    extra.write_bytes(payload)
    git('add', str(extra.relative_to(root)))
    result = audit()
    assert result.returncode != 0 and 'tests/copied-key.pem' in result.stderr, result.stdout + result.stderr
print('Release privacy: exact fixture accepted; modified and relocated keys rejected')
