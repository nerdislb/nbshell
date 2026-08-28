#!/usr/bin/env python3
"""Static contract checks for Niri/Umbriel dual-backend support."""

from pathlib import Path
import tomllib
import json
import os
import subprocess


ROOT = Path(__file__).resolve().parents[1]

for relative in (
    "umbriel/nbshell.toml",
    "umbriel/nbshell-colors.toml",
    "umbriel/nbshell-nested.toml",
    "umbriel/nbshell-cursor.toml",
    "umbriel/nbshell-overview.toml",
):
    with (ROOT / relative).open("rb") as handle:
        tomllib.load(handle)

integration = tomllib.loads((ROOT / "umbriel/nbshell.toml").read_text())
motion = tomllib.loads((ROOT / "umbriel/nbshell-motion.toml").read_text())
assert integration["keybinds"]["Mod+Space"].endswith("nbshell menu")
assert integration["keybinds"]["Mod+BackSpace"] == "workspace-set-layout:toggle"
assert integration["keybinds"]["Mod+Return"] == "spawn:ghostty"
assert integration["keybinds"]["Mod+Shift+M"].endswith("nbshell whatsapp open")
assert integration["keybinds"]["Mod+F"] == "window-toggle-maximize"
assert integration["keybinds"]["Mod+Shift+F"] == "window-toggle-fullscreen"
assert integration["keybinds"]["Mod+Shift+V"] == "window-toggle-floating"
assert integration["keybinds"]["Mod+Tab"] == "overview-toggle"
assert integration["keybinds"]["Mod+O"].endswith("nbshell toggle")
assert integration["keybinds"]["Mod+Shift+P"].endswith("nbshell power display-off")
assert integration["keybinds"]["Ctrl+Shift+Space"] == "spawn:1password --quick-access"
for media_key in (
    "XF86AudioRaiseVolume", "XF86AudioLowerVolume", "XF86AudioMute", "XF86AudioMicMute"
):
    assert integration["keybinds"][media_key].startswith("spawn:$HOME/.local/bin/nbshell audio ")
assert integration["include"]["files"] == [
    "nbshell-outputs.toml", "nbshell-cursor.toml", "nbshell-overview.toml",
    "nbshell-motion.toml"
]
assert integration["input"]["keyboard"]["layout"] == "de"
assert integration["input"]["keyboard"]["numlock_toggle"] is True
assert integration["input"]["focus"] == {"follows_mouse": True, "follows_mouse_max_scroll": 0.5}
assert motion["animation"]["duration_ms"] == 240
assert motion["animation"]["windows_in"]["duration_ms"] == 300
assert integration["hot_corners"]["top_left"]["action"] == "overview-open"
assert integration["window_rule"] and integration["layer_rule"]
clear_layer_namespaces = {"^nbshell:menu$", "^nbshell:settings$"}
clear_layer_rules = [rule for rule in integration["layer_rule"]
                     if rule.get("match", {}).get("namespace") in clear_layer_namespaces]
assert {rule["match"]["namespace"] for rule in clear_layer_rules} == clear_layer_namespaces
assert all(rule.get("blur") is False for rule in clear_layer_rules)

keys_env = os.environ.copy()
keys_env["NBSHELL_COMPOSITOR"] = "umbriel"
keys_env["NBSHELL_UMBRIEL_CONFIG"] = str(ROOT / "umbriel/nbshell.toml")
key_data = json.loads(subprocess.check_output(
    ["python3", str(ROOT / "shell/scripts/keys.py")], text=True, env=keys_env
))
assert key_data["backend"] == "umbriel"
assert len(key_data["binds"]) == len(integration["keybinds"])
assert any(row["roh"] == "Mod+Tab" and row["text"] == "overview" for row in key_data["binds"])
assert any(row["roh"] == "Ctrl+Alt+Shift+L"
           and row["aktion"].startswith("spawn:systemctl --user restart nbshell-lock.service")
           for row in key_data["binds"])

cursor_script = (ROOT / "shell/scripts/cursors.sh").read_text()
assert "nbshell-cursor.toml" in cursor_script
assert "umbriel msg config-reload" in cursor_script

theme_export = (ROOT / "shell/Services/ThemeExport.qml").read_text()
assert "nbshell-overview.toml" in theme_export
assert 'background_tint = \\"' in theme_export
assert "onWallpaperBlurChanged" in theme_export

service = (ROOT / "shell/Services/Compositor.qml").read_text()
for contract in (
    'readonly property string backend',
    '"cmd": "subscribe"',
    '"windows", "keyboard_layout"',
    'function focusWorkspace',
    'function focusWindow',
    'function logout',
    'umbriel-workspaces',
    'fullWorkspaceModel',
):
    assert contract in service, contract
assert 'property string focusedOutput: ""' in service
assert '"is_focused": data.focused ? w.id === data.id : w.is_focused' in service
assert "focusedOutput = output" in service

cell = (ROOT / "shell/Widgets/Cell.qml").read_text()
workspace_widget = (ROOT / "shell/Bar/Widgets/Workspaces.qml").read_text()
widget_host = (ROOT / "shell/Bar/WidgetHost.qml").read_text()
assert 'property string popupOutput: ""' in cell
assert 'property string output: ""' not in cell
assert 'property string output: ""' in workspace_widget
assert 'property: "popupOutput"' in widget_host

for path in (ROOT / "shell").rglob("*.qml"):
    if path.name == "Niri.qml":
        continue
    text = path.read_text()
    assert "Niri." not in text, f"direct Niri dependency outside compatibility service: {path}"

display_tool = (ROOT / "shell/scripts/displays.py").read_text()
assert '"wlr-randr", "--json"' in display_tool
assert "render_toml" in display_tool
assert "def set_umbriel_mode" in display_tool
assert "Umbriel rejected mode" in display_tool
display_panel = (ROOT / "shell/Settings/DisplayPanel.qml").read_text()
apply_mode = 'Displays.setValue(root.display.name, "mode", modelData.label);'
close_modes = "root.resolutionOpen = false;"
assert display_panel.index(apply_mode) < display_panel.index(close_modes, display_panel.index(apply_mode)), (
    "mode selection must be submitted before closing and destroying its delegate"
)
assert "umbriel windows --json" in (ROOT / "shell/scripts/capture.sh").read_text()
capture_service = (ROOT / "shell/Services/CaptureService.qml").read_text()
capture_menu = (ROOT / "shell/Capture/CaptureMenu.qml").read_text()
capture_ipc = (ROOT / "shell/Ipc/DesktopIpc.qml").read_text()
assert 'function schedule(action)' in capture_service
assert 'id: actionDelay' in capture_service
assert 'CaptureService.schedule(id)' in capture_menu
assert 'id: delay' not in capture_menu
assert 'Runtime.captureWindowSelect = true' in capture_ipc
assert 'Quickshell.execDetached(["umbriel", "msg", "dpms-off"])' in (ROOT / "shell/Services/Idle.qml").read_text()
assert (ROOT / "native/umbriel-workspaces.c").is_file()
assert (ROOT / "setup-umbriel.sh").stat().st_mode & 0o111
setup = (ROOT / "setup-umbriel.sh").read_text()
assert '"Exec=$PREFIX/bin/start-umbriel"' in setup
assert "ConditionEnvironment=!XDG_CURRENT_DESKTOP=umbriel" in setup
main_setup = (ROOT / "setup.sh").read_text()
assert "WITH_UMBRIEL=1" in main_setup
assert "--niri-only) WITH_UMBRIEL=0" in main_setup
assert '"$SRC/setup-umbriel.sh" --skip-shell-install' in main_setup
cli = (ROOT / "bin/nbshell").read_text()
assert 'local_runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"' in cli
assert 'local_umbriel_socket="${UMBRIEL_SOCKET:-$local_runtime/umbriel-$local_wayland.sock}"' in cli
assert 'local_umbriel_bin="$HOME/.local/bin/umbriel"' in cli
assert '"$local_umbriel_bin" msg dpms-off 2>/dev/null' in cli
assert "/usr/bin/niri msg action power-off-monitors" in cli

niri_takeover = (ROOT / "niri/nbshell-takeover.kdl").read_text()
assert 'Ctrl+Shift+Space hotkey-overlay-title="1Password: Quick Access"' in niri_takeover

menu = (ROOT / "shell/Menu/Menu.qml").read_text()
commands = (ROOT / "shell/Services/Commands.qml").read_text()
for action in ("--show", "--quick-access", "--lock"):
    assert action in menu
    assert action in commands

resume_unit = (ROOT / "systemd/nbshell-umbriel-resume-guard.service").read_text()
assert "ConditionEnvironment=UMBRIEL_SOCKET" in resume_unit
assert "umbriel_resume_guard.py" in resume_unit
assert "ProtectSystem=strict" in resume_unit

print("Compositor backend contracts: OK")
