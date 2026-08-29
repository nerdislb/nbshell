#!/usr/bin/env python3
"""Signal exactly the process incarnation selected by the process panel."""

from __future__ import annotations

import argparse
import os
import signal
import subprocess
import sys


def normalize_start(value: str) -> str:
    return " ".join(value.split())


def current_start(pid: int) -> str:
    result = subprocess.run(
        ["ps", "-p", str(pid), "-o", "lstart="],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return ""
    return normalize_start(result.stdout)


def signal_process(pid: int, expected_start: str, signal_number: int) -> int:
    if pid < 2 or signal_number not in (signal.SIGTERM, signal.SIGKILL):
        return 2

    try:
        pidfd = os.pidfd_open(pid)
    except (AttributeError, OSError):
        return 3

    try:
        if current_start(pid) != normalize_start(expected_start):
            return 4
        signal.pidfd_send_signal(pidfd, signal_number)
    except (AttributeError, ProcessLookupError, PermissionError, OSError):
        return 5
    finally:
        os.close(pidfd)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("pid", type=int)
    parser.add_argument("expected_start")
    parser.add_argument("signal", type=int, choices=(9, 15))
    args = parser.parse_args()
    return signal_process(args.pid, args.expected_start, args.signal)


if __name__ == "__main__":
    sys.exit(main())
