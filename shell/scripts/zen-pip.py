#!/usr/bin/env python3
"""Steuert Zens natives Picture-in-Picture-Fenster ueber niri."""

import json
import os
import subprocess
import sys
from pathlib import Path

STATE = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "nbshell/zen-pip.json"
SIZES = (0.25, 0.38, 0.55)
CORNERS = ("unten-rechts", "unten-links", "oben-links", "oben-rechts")
MARGIN = 16


def niri(*args):
    return subprocess.run(["niri", "msg", *args], text=True, capture_output=True, check=True).stdout


def data(kind):
    return json.loads(niri("--json", kind))


def pip_window():
    for win in data("windows"):
        title = (win.get("title") or "").lower()
        app_id = (win.get("app_id") or "").lower()
        pip_titles = ("picture-in-picture", "bild-im-bild")
        if (app_id.startswith("zen") or app_id == "firefox") and any(name in title for name in pip_titles):
            return win
    return None


def load_state():
    try:
        state = {**{"size": 0, "corner": 0}, **json.loads(STATE.read_text())}
        state["size"] = int(state["size"]) % len(SIZES)
        state["corner"] = int(state["corner"]) % len(CORNERS)
        return state
    except Exception:
        return {"size": 0, "corner": 0}


def save_state(state):
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state) + "\n")


def status():
    win = pip_window()
    state = load_state()
    print(json.dumps({
        "active": win is not None,
        "id": win.get("id") if win else None,
        "floating": bool(win and win.get("is_floating")),
        "size": state["size"],
        "sizeName": ("klein", "mittel", "gross")[state["size"]],
        "corner": state["corner"],
        "cornerName": CORNERS[state["corner"]],
    }))


def geometry(win, state):
    workspaces = {w["id"]: w for w in data("workspaces")}
    workspace = workspaces.get(win["workspace_id"])
    outputs = data("outputs")
    output = outputs.get(workspace.get("output")) if workspace else None
    if not output or not output.get("logical"):
        raise RuntimeError("Ausgabe des PiP-Fensters nicht gefunden")
    area = output["logical"]
    width = round(area["width"] * SIZES[state["size"]])
    height = round(width * 9 / 16)
    # move-floating-window erwartet Koordinaten relativ zum aktuellen Output.
    positions = (
        (area["width"] - width - MARGIN, area["height"] - height - MARGIN),
        (MARGIN, area["height"] - height - MARGIN),
        (MARGIN, MARGIN),
        (area["width"] - width - MARGIN, MARGIN),
    )
    wid = str(win["id"])
    niri("action", "move-window-to-floating", "--id", wid)
    niri("action", "set-window-width", "--id", wid, str(width))
    niri("action", "set-window-height", "--id", wid, str(height))
    x, y = positions[state["corner"]]
    niri("action", "move-floating-window", "--id", wid, "-x", str(x), "-y", str(y))


def require_window():
    win = pip_window()
    if not win:
        raise RuntimeError("Kein Zen-PiP offen — im Video Ctrl+Shift+] druecken")
    return win


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "status"
    if command == "status":
        status()
        return
    state = load_state()
    win = require_window()
    if command == "size":
        state["size"] = (state["size"] + 1) % len(SIZES)
    elif command == "corner":
        state["corner"] = (state["corner"] + 1) % len(CORNERS)
    elif command == "apply":
        pass
    elif command == "focus":
        niri("action", "focus-window", "--id", str(win["id"]))
        return
    elif command == "close":
        niri("action", "close-window", "--id", str(win["id"]))
        return
    else:
        raise RuntimeError("Erwartet: status | apply | size | corner | focus | close")
    save_state(state)
    geometry(win, state)
    print(("klein", "mittel", "gross")[state["size"]] + " · " + CORNERS[state["corner"]])


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"zen-pip: {exc}", file=sys.stderr)
        raise SystemExit(1)
