#!/usr/bin/env python3
"""Static contracts for the Umbriel-only nbshell integration."""

from pathlib import Path
import json
import os
import subprocess
import tomllib

ROOT = Path(__file__).resolve().parents[1]

for relative in (
    "umbriel/nbshell.toml",
    "umbriel/nbshell-colors.toml",
    "umbriel/nbshell-nested.toml",
    "umbriel/nbshell-cursor.toml",
    "umbriel/nbshell-overview.toml",
    "umbriel/nbshell-motion.toml",
):
    with (ROOT / relative).open("rb") as handle:
        tomllib.load(handle)

integration = tomllib.loads((ROOT / "umbriel/nbshell.toml").read_text())
colors = tomllib.loads((ROOT / "umbriel/nbshell-colors.toml").read_text())
overview = tomllib.loads((ROOT / "umbriel/nbshell-overview.toml").read_text())
assert colors["colors"]["border"]["focused"] == "#7AA2F7FF"
assert colors["colors"]["insert_hint"] == "#7AA2F780"
assert colors["colors"]["backdrop"] == "#1A1B26FF"
assert "border_focused" not in colors["appearance"]
assert overview["colors"]["overview"]["background_tint"] == "#1A1B2680"
assert "overview" not in overview
assert integration["keybinds"]["Mod+BackSpace"] == "workspace-set-layout:toggle"
assert integration["keybinds"]["Mod+F"] == "window-toggle-maximize"
assert integration["keybinds"]["Mod+Shift+F"] == "window-toggle-fullscreen"
assert integration["keybinds"]["Mod+Shift+V"] == "window-toggle-floating"
assert integration["keybinds"]["Mod+Tab"] == "overview-toggle"
assert "Mod+Alt+Shift+P" not in integration["keybinds"]
assert integration["include"]["files"] == [
    "nbshell-outputs.toml", "nbshell-cursor.toml", "nbshell-overview.toml",
    "nbshell-motion.toml",
]

keys_env = os.environ.copy()
keys_env["NBSHELL_UMBRIEL_CONFIG"] = str(ROOT / "umbriel/nbshell.toml")
key_data = json.loads(subprocess.check_output(
    ["python3", str(ROOT / "shell/scripts/keys.py")], text=True, env=keys_env
))
assert key_data["backend"] == "umbriel"
assert len(key_data["binds"]) == len(integration["keybinds"])
assert any(row["roh"] == "Mod+Tab" and row["text"] == "overview" for row in key_data["binds"])

service = (ROOT / "shell/Services/Compositor.qml").read_text()
for contract in (
    'readonly property string backend: "umbriel"',
    '"workspaces", "windows", "keyboard_layout"',
    "function normalizeWorkspaces",
    "function focusWorkspace",
    "function focusWindow",
    "function logout",
):
    assert contract in service, contract
for forbidden in ("NIRI_SOCKET", "handleNiri", "isNiri", "Compositor.action"):
    assert forbidden not in service

assert not (ROOT / "niri").exists()
assert not (ROOT / "shell/Services/Niri.qml").exists()
assert not (ROOT / "shell/scripts/grid-layout.py").exists()
assert not (ROOT / "native/umbriel-workspaces.c").exists()

for path in (ROOT / "shell").rglob("*.qml"):
    text = path.read_text()
    assert "Niri." not in text, f"retired compositor singleton reference: {path}"

cursor_script = (ROOT / "shell/scripts/cursors.sh").read_text()
assert "nbshell-cursor.toml" in cursor_script
assert "umbriel msg config-reload" in cursor_script
assert "config.kdl" not in cursor_script

display_tool = (ROOT / "shell/scripts/displays.py").read_text()
assert '"wlr-randr", "--json"' in display_tool
assert "render_toml" in display_tool
assert "render_kdl" not in display_tool
assert "def set_umbriel_mode" in display_tool

capture_service = (ROOT / "shell/Services/CaptureService.qml").read_text()
assert "Compositor.isNiri" not in capture_service
assert "Compositor.action" not in capture_service
assert 'Runtime.captureWindowSelect = true' in (ROOT / "shell/Ipc/DesktopIpc.qml").read_text()
assert 'Quickshell.execDetached(["umbriel", "msg", "dpms-off"])' in (ROOT / "shell/Services/Idle.qml").read_text()

setup = (ROOT / "setup.sh").read_text()
assert "--niri-only" not in setup
assert '"$SRC/setup-umbriel.sh" --skip-shell-install' in setup
assert "greetd-regreet" not in setup

installer = (ROOT / "install.sh").read_text()
assert "nbshell-takeover.kdl" not in installer.split("# Remove only nbshell-owned artifacts", 1)[0]

cli = (ROOT / "bin/nbshell").read_text()
assert "nbshell grid" not in cli
assert "workspace-set-layout:${1:-toggle}" in cli
assert "/usr/bin/niri" not in cli

resume_unit = (ROOT / "systemd/nbshell-umbriel-resume-guard.service").read_text()
assert "ConditionEnvironment=UMBRIEL_SOCKET" in resume_unit
assert "umbriel_resume_guard.py" in resume_unit
assert "ProtectSystem=strict" in resume_unit

sleep_lock_unit = (ROOT / "systemd/nbshell-sleep-lock.service").read_text()
assert "sleep_lock_inhibitor.py" in sleep_lock_unit
assert "WantedBy=graphical-session.target" in sleep_lock_unit
assert "Restart=on-failure" in sleep_lock_unit
assert "Requisite=graphical-session.target" in sleep_lock_unit
assert "ConditionEnvironment=" not in sleep_lock_unit

lock_unit = (ROOT / "systemd/nbshell-lock.service").read_text()
assert "ExecStartPre=/usr/bin/rm -f %t/nbshell-lock-ready" in lock_unit

print("Umbriel-only contracts: OK")
