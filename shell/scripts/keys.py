#!/usr/bin/env python3
"""Render Umbriel key bindings as the nbshell keyboard-help JSON model."""

import json
import os
import sys
import tomllib

CONFIG = os.path.expanduser(
    os.environ.get("NBSHELL_UMBRIEL_CONFIG", "~/.config/umbriel/nbshell.toml")
)

ACTIONS = {
    "window-close": "close window",
    "window-toggle-fullscreen": "fullscreen",
    "window-toggle-maximize": "maximize/restore window",
    "window-toggle-floating": "toggle floating",
    "window-center": "center window",
    "window-cycle-width": "cycle window width",
    "window-focus-left": "focus window left",
    "window-focus-right": "focus window right",
    "window-focus-up": "focus window above",
    "window-focus-down": "focus window below",
    "window-focus-next": "next window",
    "column-move-left": "move column left",
    "column-move-right": "move column right",
    "window-move-up": "move window up",
    "window-move-down": "move window down",
    "window-consume-left": "move window into left column",
    "window-consume-or-expel-right": "merge or split column to the right",
    "workspace-next": "next workspace",
    "workspace-previous": "previous workspace",
    "window-move-to-workspace-next": "move window to next workspace",
    "window-move-to-workspace-previous": "move window to previous workspace",
    "output-focus-left": "focus display left",
    "output-focus-right": "focus display right",
    "output-focus-up": "focus display above",
    "output-focus-down": "focus display below",
    "column-move-to-output-left": "move column to display left",
    "column-move-to-output-right": "move column to display right",
    "column-move-to-output-up": "move column to display above",
    "column-move-to-output-down": "move column to display below",
    "overview-toggle": "overview",
    "overview-open": "open overview",
    "overview-close": "close overview",
    "cheatsheet-toggle": "show Umbriel key bindings",
    "dpms-off": "turn displays off",
    "session-quit": "log out",
}


def readable_key(value):
    replacements = {
        "return": "Enter", "grave": "^", "comma": ",", "period": ".",
        "slash": "/", "minus": "-", "equal": "=", "bracketleft": "[",
        "bracketright": "]", "wheeldown": "Wheel down", "wheelup": "Wheel up",
        "wheelleft": "Wheel left", "wheelright": "Wheel right",
    }
    return "+".join((replacements.get(part.lower()) or part) for part in value.split("+"))


def action_value(value):
    if isinstance(value, dict):
        return str(value.get("action", ""))
    return str(value)


def describe(action):
    if action.startswith("spawn:"):
        command = action[6:].replace("$HOME/.local/bin/", "")
        if " --app=" in command:
            return "Webapp " + command.split(" --app=", 1)[1].replace("https://", "").replace("www.", "").rstrip("/")
        return command
    if action.startswith("workspace-switch:"):
        return "focus workspace " + action.split(":", 1)[1]
    if action.startswith("window-move-to-workspace:"):
        return "move window to workspace " + action.split(":", 1)[1]
    if action.startswith("window-modify-width:"):
        amount = action.split(":", 1)[1]
        return "window narrower " + amount[1:] if amount.startswith("-") else "window wider " + amount
    if action.startswith("workspace-set-layout:"):
        return "toggle scrolling/dwindle layout"
    return ACTIONS.get(action, action)


def group(key, action):
    if "XF86Audio" in key or "XF86MonBrightness" in key or "XF86Kbd" in key:
        return "Audio and display"
    if " capture " in (" " + action + " ") or "Print" in key or "XF86Launch1" in key:
        return "Capture"
    if action.startswith("spawn:"):
        return "Applications"
    if "workspace" in action:
        return "Workspaces"
    if action.startswith(("output-", "column-move-to-output")):
        return "Displays"
    if action.startswith(("window-", "column-")):
        return "Windows"
    if action.startswith(("session-", "dpms-")):
        return "Session"
    return "Other"


def main():
    with open(CONFIG, "rb") as handle:
        data = tomllib.load(handle)
    bindings = []
    for key, raw_action in data.get("keybinds", {}).items():
        action = action_value(raw_action)
        bindings.append({
            "taste": readable_key(key),
            "roh": key,
            "text": describe(action),
            "aktion": action,
            "gruppe": group(key, action),
            "quelle": os.path.basename(CONFIG),
        })
    print(json.dumps({
        "ok": True,
        "backend": "umbriel",
        "binds": bindings,
        "datei": CONFIG,
    }, ensure_ascii=False))


if __name__ == "__main__":
    try:
        main()
    except Exception as error:  # noqa: BLE001 -- surface the exact parser failure
        print(json.dumps({"ok": False, "grund": str(error)}, ensure_ascii=False))
        sys.exit(1)
