#!/usr/bin/env python3
"""Optional, bounded OpenClaw monitor launcher; emits metadata only."""
import json
import os
from pathlib import Path
import shutil
import subprocess


def snapshot():
    empty = dict(installed=False, online=False, working=0, sessions=0, agents=[], error="")
    state = Path(os.environ.get("OPENCLAW_STATE_DIR") or Path.home() / ".openclaw")
    if not (state / "openclaw.json").is_file():
        return empty
    try:
        node = shutil.which("node")
        if not node:
            raise ValueError("Node unavailable")
        result = subprocess.run([node, "--disable-warning=ExperimentalWarning",
                                 str(Path(__file__).with_name("openclaw-monitor.mjs"))],
                                capture_output=True, text=True, timeout=2.5, check=True)
        data = json.loads(result.stdout)
        if not isinstance(data, dict) or not isinstance(data.get("online"), bool):
            raise ValueError("Invalid monitor output")
        return data
    except (OSError, ValueError, subprocess.SubprocessError):
        return dict(empty, installed=True, error="OpenClaw status unavailable")


if __name__ == "__main__":
    print(json.dumps(snapshot()))
