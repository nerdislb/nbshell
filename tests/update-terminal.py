#!/usr/bin/env python3
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="update ' quoted ") as temporary:
    root = Path(temporary)
    runner = root / 'update-terminal.sh'
    shutil.copy(ROOT / 'shell/scripts/update-terminal.sh', runner)
    log = root / 'argv.json'
    (root / 'update-coordinator.py').write_text('import json, os, sys\nfrom pathlib import Path\nPath(os.environ["TEST_LOG"]).write_text(json.dumps(sys.argv[1:]))\nraise SystemExit(7)\n')
    env = dict(os.environ, TEST_LOG=str(log))
    result = subprocess.run(['bash', str(runner), 'shell', 'stable'], env=env, stdin=subprocess.DEVNULL, capture_output=True)
    assert result.returncode == 7
    assert json.loads(log.read_text()) == ['shell', '--channel', 'stable']
    log.unlink()
    result = subprocess.run(['bash', str(runner), 'shell', 'beta;touch INJECTED'], env=env, stdin=subprocess.DEVNULL, capture_output=True)
    assert result.returncode == 2 and not log.exists()
print('Update terminal argument boundaries and exit status: OK')
