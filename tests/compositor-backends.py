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
assert integration["keybinds"]["Mod+Space"].endswith("nbshell menu")
assert integration["keybinds"]["Mod+BackSpace"] == "workspace-set-layout:toggle"
assert integration["keybinds"]["Mod+Return"] == "spawn:ghostty"
assert integration["keybinds"]["Mod+Shift+M"] == "spawn:prettyzap --show"
assert integration["keybinds"]["Mod+F"] == "window-toggle-maximize"
assert integration["keybinds"]["Mod+Shift+F"] == "window-toggle-fullscreen"
assert integration["keybinds"]["Mod+Shift+V"] == "window-toggle-floating"
assert integration["keybinds"]["Mod+Tab"] == "overview-toggle"
assert integration["keybinds"]["Mod+O"].endswith("nbshell toggle")
assert integration["keybinds"]["Mod+Shift+P"].endswith("nbshell power display-off")
for media_key in (
    "XF86AudioRaiseVolume", "XF86AudioLowerVolume", "XF86AudioMute", "XF86AudioMicMute"
):
    assert integration["keybinds"][media_key].startswith("spawn:$HOME/.local/bin/nbshell audio ")
assert integration["include"]["files"] == [
    "nbshell-outputs.toml", "nbshell-cursor.toml", "nbshell-overview.toml"
]
assert integration["input"]["keyboard"]["layout"] == "de"
assert integration["input"]["focus"] == {"follows_mouse": True, "follows_mouse_max_scroll": 0.5}
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

for path in (ROOT / "shell").rglob("*.qml"):
    if path.name == "Niri.qml":
        continue
    text = path.read_text()
    assert "Niri." not in text, f"direct Niri dependency outside compatibility service: {path}"

display_tool = (ROOT / "shell/scripts/displays.py").read_text()
assert '"wlr-randr", "--json"' in display_tool
assert "render_toml" in display_tool
assert "umbriel windows --json" in (ROOT / "shell/scripts/capture.sh").read_text()
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

print("Compositor backend contracts: OK")
