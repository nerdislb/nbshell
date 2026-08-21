#!/usr/bin/env python3
"""Workspace-local 2x2 grid mode on top of niri's scrolling layout."""

from __future__ import annotations

import fcntl
import json
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import time


STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "nbshell"
STATE_FILE = STATE_DIR / "grid-layout.json"
LOCK_FILE = STATE_DIR / "grid-layout.lock"
PID_FILE = STATE_DIR / "grid-layout.pid"
SESSION = os.environ.get("NIRI_SOCKET", "")


def niri_json(command: str) -> list[dict]:
    result = subprocess.run(
        ["niri", "msg", "-j", command], check=True, text=True, capture_output=True
    )
    value = json.loads(result.stdout)
    return value if isinstance(value, list) else []


def action(name: str, *args: str) -> None:
    subprocess.run(
        ["niri", "msg", "action", name, *args],
        check=True,
        stdout=subprocess.DEVNULL,
    )


def load_state() -> set[int]:
    try:
        data = json.loads(STATE_FILE.read_text(encoding="utf-8"))
        if data.get("session") != SESSION:
            return set()
        return {int(value) for value in data.get("workspaces", [])}
    except (OSError, ValueError, TypeError):
        return set()


def save_state(workspaces: set[int]) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    temporary = STATE_FILE.with_suffix(".tmp")
    temporary.write_text(
        json.dumps({"session": SESSION, "workspaces": sorted(workspaces)}, indent=2) + "\n",
        encoding="utf-8",
    )
    temporary.replace(STATE_FILE)


def focused_workspace() -> int:
    for workspace in niri_json("workspaces"):
        if workspace.get("is_focused"):
            return int(workspace["id"])
    raise RuntimeError("No focused niri workspace")


def tiled_windows(workspace_id: int) -> list[dict]:
    result = []
    for window in niri_json("windows"):
        layout = window.get("layout") or {}
        position = layout.get("pos_in_scrolling_layout")
        if (
            int(window.get("workspace_id", -1)) == workspace_id
            and not window.get("is_floating")
            and isinstance(position, list)
            and len(position) == 2
        ):
            result.append(window)
    return sorted(result, key=lambda item: tuple(item["layout"]["pos_in_scrolling_layout"]))


def columns(workspace_id: int) -> list[list[dict]]:
    grouped: dict[int, list[dict]] = {}
    for window in tiled_windows(workspace_id):
        column = int(window["layout"]["pos_in_scrolling_layout"][0])
        grouped.setdefault(column, []).append(window)
    return [grouped[key] for key in sorted(grouped)]


def separate_all(workspace_id: int) -> None:
    # Expelling stacked tiles to the right preserves their top-to-bottom order
    # as left-to-right columns when grid mode is disabled again.
    # Re-query after every change because column and tile indices shift.
    limit = max(4, len(tiled_windows(workspace_id)) * 3)
    for _ in range(limit):
        stacked = [
            window
            for window in tiled_windows(workspace_id)
            if int(window["layout"]["pos_in_scrolling_layout"][1]) > 1
        ]
        if not stacked:
            return
        action("consume-or-expel-window-right", "--id", str(stacked[-1]["id"]))
        time.sleep(0.04)
    raise RuntimeError("Could not separate every stacked window")


def desired_column_sizes(window_count: int) -> list[int]:
    """Return the preferred layout when building a grid from single columns."""
    if window_count < 3:
        return [1] * window_count
    return [2] * (window_count // 2) + ([1] if window_count % 2 else [])


def stable_column_sizes(sizes: list[int], window_count: int) -> bool:
    """Accept mirrored partial pages so closing a window never causes a rebuild.

    Three windows may be [2, 1] or [1, 2]. Both are the same useful grid and
    preserving the existing orientation avoids a distracting expel/reconsume
    animation.
    """
    if sum(sizes) != window_count or any(size < 1 or size > 2 for size in sizes):
        return False
    if window_count < 3:
        return sizes == [1] * window_count
    return len(sizes) == (window_count + 1) // 2


def merge_only(workspace_id: int, windows: list[dict], desired: list[int]) -> bool:
    """Reach the desired layout using only direct merges when possible."""
    current_groups = [[int(window["id"]) for window in column] for column in columns(workspace_id)]
    order = [int(window["id"]) for window in windows]
    desired_groups: list[list[int]] = []
    cursor = 0
    for size in desired:
        desired_groups.append(order[cursor : cursor + size])
        cursor += size

    # A current stack crossing a desired group boundary must be rebuilt. In
    # the normal 2 -> 3 -> 4 progression every group is either already right
    # or consists of two adjacent singleton columns and needs one merge.
    for current in current_groups:
        if not any(set(current).issubset(set(group)) for group in desired_groups):
            return False

    for group in desired_groups:
        if len(group) != 2:
            continue
        containing = [index for index, current in enumerate(current_groups) if any(item in current for item in group)]
        if len(containing) == 1:
            continue
        if (
            len(containing) != 2
            or containing[1] != containing[0] + 1
            or len(current_groups[containing[0]]) != 1
            or len(current_groups[containing[1]]) != 1
        ):
            return False
        action("consume-or-expel-window-left", "--id", str(group[1]))
        time.sleep(0.04)
    return True


def arrange(workspace_id: int) -> None:
    windows = tiled_windows(workspace_id)
    desired = desired_column_sizes(len(windows))
    current = [len(column) for column in columns(workspace_id)]
    if stable_column_sizes(current, len(windows)):
        return

    if merge_only(workspace_id, windows, desired):
        return

    # Manual rearranging or closing a window from the middle can leave stacks
    # crossing the new group boundaries. Rebuild only for that uncommon case.
    order = [int(window["id"]) for window in windows]
    separate_all(workspace_id)
    cursor = 0
    for size in desired:
        if size == 2:
            action("consume-or-expel-window-left", "--id", str(order[cursor + 1]))
            time.sleep(0.04)
        cursor += size


def enable(workspace_id: int) -> None:
    arrange(workspace_id)


def disable(workspace_id: int) -> None:
    separate_all(workspace_id)


def notify(message: str) -> None:
    if subprocess.run(["sh", "-c", "command -v notify-send"], stdout=subprocess.DEVNULL).returncode == 0:
        subprocess.Popen(
            ["notify-send", "nbshell layout", message],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


def watcher_running() -> bool:
    try:
        pid = int(PID_FILE.read_text(encoding="utf-8"))
        command = Path(f"/proc/{pid}/cmdline").read_bytes().replace(b"\0", b" ")
        return b"grid-layout.py watch" in command
    except (OSError, ValueError):
        return False


def start_watcher() -> None:
    if watcher_running():
        return
    subprocess.Popen(
        [sys.executable, str(Path(__file__).resolve()), "watch"],
        start_new_session=True,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )


def stop_watcher() -> None:
    if not watcher_running():
        PID_FILE.unlink(missing_ok=True)
        return
    try:
        os.kill(int(PID_FILE.read_text(encoding="utf-8")), signal.SIGTERM)
    except (OSError, ValueError):
        pass


def restart_watcher() -> None:
    stop_watcher()
    for _ in range(20):
        if not watcher_running():
            break
        time.sleep(0.05)
    PID_FILE.unlink(missing_ok=True)
    if load_state():
        start_watcher()


def locked(callback) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    with LOCK_FILE.open("w", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        callback()


def toggle() -> None:
    workspace_id = focused_workspace()

    def change() -> None:
        enabled = load_state()
        if workspace_id in enabled:
            disable(workspace_id)
            enabled.remove(workspace_id)
            save_state(enabled)
            notify("Grid-scroll mode off · individual 50% columns")
            if not enabled:
                stop_watcher()
        else:
            enable(workspace_id)
            enabled.add(workspace_id)
            save_state(enabled)
            start_watcher()
            notify("Grid-scroll mode on · two windows per column")

    locked(change)


def status() -> None:
    workspace_id = focused_workspace()
    if load_state() and not watcher_running():
        start_watcher()
    print("on" if workspace_id in load_state() else "off")


def watch() -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    PID_FILE.write_text(f"{os.getpid()}\n", encoding="utf-8")
    try:
        process = subprocess.Popen(
            ["niri", "msg", "-j", "event-stream"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            bufsize=0,
        )
        assert process.stdout is not None
        poller = selectors.DefaultSelector()
        poller.register(process.stdout, selectors.EVENT_READ)
        while True:
            # Wait for one compositor event, then drain the burst. Window
            # creation and our own consume actions emit several events; doing
            # layout work for every intermediate state caused visible jumping.
            ready = poller.select()
            if not ready:
                continue
            if not os.read(process.stdout.fileno(), 65536):
                break
            while poller.select(timeout=0.14):
                if not os.read(process.stdout.fileno(), 65536):
                    break

            def reconcile() -> None:
                enabled = load_state()
                if not enabled:
                    process.terminate()
                    return
                existing = {int(item["id"]) for item in niri_json("workspaces")}
                enabled.intersection_update(existing)
                save_state(enabled)
                for workspace_id in enabled:
                    arrange(workspace_id)

            try:
                locked(reconcile)
            except (OSError, RuntimeError, subprocess.CalledProcessError, json.JSONDecodeError):
                time.sleep(0.2)
            if not load_state():
                break
        poller.close()
    finally:
        PID_FILE.unlink(missing_ok=True)


def main() -> int:
    command = sys.argv[1] if len(sys.argv) > 1 else "toggle"
    try:
        if command == "toggle":
            toggle()
        elif command == "on":
            if focused_workspace() not in load_state():
                toggle()
        elif command == "off":
            if focused_workspace() in load_state():
                toggle()
        elif command == "status":
            status()
        elif command == "watch":
            watch()
        elif command == "restart-watcher":
            restart_watcher()
        else:
            print("usage: grid-layout.py toggle|on|off|status|restart-watcher", file=sys.stderr)
            return 2
    except (OSError, RuntimeError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        print(f"nbshell grid: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
