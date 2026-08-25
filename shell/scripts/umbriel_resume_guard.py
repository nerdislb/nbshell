#!/usr/bin/env python3
"""Repair Umbriel windows orphaned by an output disappearing across suspend."""

from __future__ import annotations

import os
from pathlib import Path
import json
import select
import socket
import sys
import time


SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import lockscreen  # noqa: E402


SOCKET_WAIT_SECONDS = 1.0
RESUME_GAP_SECONDS = 4.0


def update_snapshot(
    rows: list[dict], known: dict[str, str], focused_id: str
) -> tuple[dict[str, str], str]:
    """Remember only valid assignments, retaining them while an output is absent."""
    next_known = dict(known)
    next_focused = focused_id
    for row in rows:
        window_id = str(row.get("id") or "")
        workspace = str(row.get("workspace") or "")
        if window_id and workspace:
            next_known[window_id] = workspace
        if window_id and row.get("focused"):
            next_focused = window_id
    return next_known, next_focused


def boottime() -> float:
    """Return a monotonic clock which includes time spent suspended."""
    return time.clock_gettime(time.CLOCK_BOOTTIME)


def main() -> int:
    binary = lockscreen.umbriel_binary()
    socket_path = os.environ.get("UMBRIEL_SOCKET", "")
    if not binary or not socket_path:
        return 0

    known: dict[str, str] = {}
    focused_id = ""
    previous = boottime()
    while True:
        try:
            with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as ipc:
                ipc.connect(socket_path)
                ipc.sendall(b'{"cmd":"subscribe","events":["windows"]}\n')
                buffer = b""
                connected = True
                while connected:
                    readable, _, _ = select.select(
                        [ipc], [], [], SOCKET_WAIT_SECONDS
                    )
                    if readable:
                        chunk = ipc.recv(262144)
                        if not chunk:
                            connected = False
                        else:
                            buffer += chunk
                            while b"\n" in buffer:
                                line, buffer = buffer.split(b"\n", 1)
                                try:
                                    event = json.loads(line)
                                except (UnicodeDecodeError, ValueError):
                                    continue
                                if event.get("event") == "windows" and isinstance(
                                    event.get("data"), list
                                ):
                                    known, focused_id = update_snapshot(
                                        event["data"], known, focused_id
                                    )

                    current = boottime()
                    gap = current - previous
                    if gap >= RESUME_GAP_SECONDS and known:
                        repaired = lockscreen.repair_umbriel_resume(
                            binary, known, focused_id
                        )
                        print(
                            f"nbshell: detected a {gap:.1f}s resume gap; "
                            f"repaired {repaired} Umbriel window(s)",
                            flush=True,
                        )
                    previous = current
        except OSError as error:
            print(f"nbshell: Umbriel IPC reconnect: {error}", flush=True)
            time.sleep(SOCKET_WAIT_SECONDS)
            previous = boottime()


if __name__ == "__main__":
    raise SystemExit(main())
