#!/usr/bin/env python3
"""Control Zen's native Picture-in-Picture window through Umbriel."""

import json
import os
import subprocess
import sys
from pathlib import Path

STATE = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "nbshell/zen-pip.json"
SIZES = (0.25, 0.38, 0.55)
SIZE_NAMES = ("small", "medium", "large")


def umbriel(*args):
    return subprocess.run(["umbriel", *args], text=True, capture_output=True, check=True).stdout


def windows():
    return json.loads(umbriel("windows", "--json"))


def action(name):
    subprocess.run(["umbriel", "msg", name], check=True)


def pip_window():
    for win in windows():
        title = (win.get("title") or "").lower()
        app_id = (win.get("app_id") or "").lower()
        if (app_id.startswith("zen") or app_id == "firefox") and any(
            name in title for name in ("picture-in-picture", "bild-im-bild")
        ):
            return win
    return None


def load_state():
    try:
        state = {**{"size": 0}, **json.loads(STATE.read_text())}
        state["size"] = int(state["size"]) % len(SIZES)
        return state
    except (OSError, TypeError, ValueError):
        return {"size": 0}


def save_state(state):
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state) + "\n")


def status():
    win = pip_window()
    state = load_state()
    print(json.dumps({
        "active": win is not None,
        "id": win.get("id") if win else None,
        "floating": bool(win and win.get("floating")),
        "size": state["size"],
        "sizeName": SIZE_NAMES[state["size"]],
    }))


def require_window():
    win = pip_window()
    if not win:
        raise RuntimeError("No Zen PiP is open — press Ctrl+Shift+] in the video")
    return win


def apply(win, state):
    action("window-focus:" + str(win["id"]))
    if not win.get("floating"):
        action("window-toggle-floating")
    action("window-set-width:" + str(SIZES[state["size"]]))


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "status"
    if command == "status":
        status()
        return

    state = load_state()
    win = require_window()
    if command == "size":
        state["size"] = (state["size"] + 1) % len(SIZES)
        save_state(state)
        apply(win, state)
        print(SIZE_NAMES[state["size"]])
    elif command == "apply":
        apply(win, state)
    elif command == "focus":
        action("window-focus:" + str(win["id"]))
    elif command == "close":
        action("window-close:" + str(win["id"]))
    else:
        raise RuntimeError("Expected: status | apply | size | focus | close")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"zen-pip: {exc}", file=sys.stderr)
        raise SystemExit(1)
