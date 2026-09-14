#!/usr/bin/env python3
"""Bounded, read-only Git summaries for explicitly supplied session directories."""
import concurrent.futures
import json
import os
from pathlib import Path
import subprocess
import sys


def inspect(raw):
    result = {"error": "Not a local Git project"}
    try:
        if not isinstance(raw, str) or len(raw) > 4096 or not raw.startswith("/"):
            return result
        directory = Path(raw)
        if not directory.is_dir():
            return result
        env = {**os.environ, "GIT_OPTIONAL_LOCKS": "0", "GIT_TERMINAL_PROMPT": "0"}
        def git(*args):
            return subprocess.run(["git", "--no-optional-locks", "-c", "core.fsmonitor=false", "-C", raw, *args],
                                  capture_output=True, timeout=2, check=True, env=env).stdout
        top = git("rev-parse", "--show-toplevel").decode(errors="replace").strip()
        data = git("status", "--porcelain=v1", "-z", "--branch", "--untracked-files=normal").decode(errors="replace").split("\0")
        branch = data.pop(0).removeprefix("## ").split("...")[0]
        changed = conflicts = 0
        skip = False
        for record in data:
            if skip:
                skip = False
                continue
            if not record:
                continue
            status = record[:2]
            changed += 1
            conflicts += status in {"DD", "AU", "UD", "UA", "DU", "AA", "UU"}
            skip = "R" in status or "C" in status
        return dict(root=top, branch=branch, changed=changed, conflicts=conflicts)
    except subprocess.TimeoutExpired:
        return {"error": "Git timed out"}
    except (OSError, ValueError, subprocess.CalledProcessError):
        return result


def snapshot(paths):
    paths = list(dict.fromkeys(p for p in paths if isinstance(p, str)))[:12]
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        return dict(zip(paths, pool.map(inspect, paths)))


if __name__ == "__main__":
    try:
        paths = json.loads(sys.argv[1])
        if not isinstance(paths, list):
            raise ValueError()
        print(json.dumps(snapshot(paths)))
    except (ValueError, IndexError):
        print("{}")
        sys.exit(1)
