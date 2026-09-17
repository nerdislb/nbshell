#!/usr/bin/env python3
"""Bounded, read-only Git summaries for explicitly supplied session directories."""
import concurrent.futures
import json
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import threading
import time

MAX_OUTPUT = 1024 * 1024
COMMAND_TIMEOUT = 2
_children = set()
_children_lock = threading.Lock()
_cancelled = threading.Event()


def stop_child(child):
    try:
        os.killpg(child.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def stop_all():
    with _children_lock:
        for child in _children:
            stop_child(child)


def run_git(command, env, *, empty_ok=False):
    """Bound bytes, elapsed time and descendants, not just the Git parent."""
    with _children_lock:
        if _cancelled.is_set():
            raise InterruptedError("Project inspection cancelled")
        child = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                 stdin=subprocess.DEVNULL, env=env, start_new_session=True)
        _children.add(child)
    output = bytearray()
    deadline = time.monotonic() + COMMAND_TIMEOUT
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(child.stdout, selectors.EVENT_READ)
            while selector.get_map():
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise subprocess.TimeoutExpired(command, COMMAND_TIMEOUT)
                for key, _ in selector.select(remaining):
                    chunk = os.read(key.fd, min(65536, MAX_OUTPUT + 1 - len(output)))
                    if not chunk:
                        selector.unregister(key.fileobj)
                    else:
                        output.extend(chunk)
                        if len(output) > MAX_OUTPUT:
                            raise ValueError("Git output limit exceeded")
        code = child.wait(timeout=max(0.001, deadline - time.monotonic()))
        if code != 0 and not (empty_ok and code == 1 and not output):
            raise subprocess.CalledProcessError(code, command)
        return bytes(output)
    finally:
        # Even a successful parent can leave a child holding stdout open.
        with _children_lock:
            stop_child(child)
            _children.discard(child)
        child.stdout.close()
        child.wait()


def inspect(raw):
    result = {"error": "Not a local Git project"}
    try:
        if not isinstance(raw, str) or len(raw) > 4096 or not raw.startswith("/"):
            return result
        directory = Path(raw)
        if not directory.is_dir():
            return result
        env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        env.update(GIT_OPTIONAL_LOCKS="0", GIT_TERMINAL_PROMPT="0",
                   GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull, GIT_ATTR_NOSYSTEM="1")
        command = ["git", "--no-optional-locks", "-c", "core.fsmonitor=false",
                   "-c", "core.hooksPath=/dev/null", "-C", raw]
        # status can run clean/process filters while comparing tracked files.
        # Read effective local/includes config, then override every filter driver.
        keys = run_git(command + ["config", "--null", "--name-only", "--get-regexp",
                                  r"^filter\..*\.(clean|smudge|process|required)$"], env, empty_ok=True)
        for key in set(keys.decode(errors="strict").split("\0")) - {""}:
            command += ["-c", key + ("=false" if key.endswith(".required") else "=")]
        def git(*args):
            return run_git(command + list(args), env)
        top = git("rev-parse", "--show-toplevel").decode(errors="replace").strip()
        # Do not enter submodule worktrees with their own executable config.
        # Recorded submodule commit changes still appear; nested dirt does not.
        data = git("status", "--porcelain=v1", "-z", "--branch", "--untracked-files=normal",
                   "--ignore-submodules=dirty").decode(errors="replace").split("\0")
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
    except ValueError:
        return {"error": "Git status exceeds supported limits"}
    except (OSError, subprocess.CalledProcessError):
        return result


def snapshot(paths):
    paths = list(dict.fromkeys(p for p in paths if isinstance(p, str)))[:12]
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        return dict(zip(paths, pool.map(inspect, paths)))


if __name__ == "__main__":
    def cancelled(signum, frame):
        _cancelled.set()
        stop_all()
        raise SystemExit(128 + signum)
    signal.signal(signal.SIGTERM, cancelled)
    signal.signal(signal.SIGINT, cancelled)
    try:
        paths = json.loads(sys.argv[1])
        if not isinstance(paths, list):
            raise ValueError()
        print(json.dumps(snapshot(paths)))
    except (ValueError, IndexError):
        print("{}")
        sys.exit(1)
    finally:
        stop_all()
