#!/usr/bin/env python3
"""Static contract checks for Niri/Umbriel dual-backend support."""

from pathlib import Path
import tomllib


ROOT = Path(__file__).resolve().parents[1]

for relative in (
    "umbriel/nbshell.toml",
    "umbriel/nbshell-colors.toml",
    "umbriel/nbshell-nested.toml",
):
    with (ROOT / relative).open("rb") as handle:
        tomllib.load(handle)

integration = tomllib.loads((ROOT / "umbriel/nbshell.toml").read_text())
assert integration["keybinds"]["Mod+Space"].endswith("nbshell menu")
assert integration["keybinds"]["Mod+BackSpace"] == "workspace-set-layout:toggle"
assert integration["keybinds"]["Mod+Return"] == "spawn:ghostty"
assert integration["include"]["files"] == ["nbshell-outputs.toml"]
assert integration["input"]["keyboard"]["layout"] == "de"
assert integration["input"]["focus"] == {"follows_mouse": True, "follows_mouse_max_scroll": 0.5}
assert integration["hot_corners"]["top_left"]["action"] == "overview-open"
assert integration["window_rule"] and integration["layer_rule"]
clear_layer_namespaces = {"^nbshell:menu$", "^nbshell:settings$"}
clear_layer_rules = [rule for rule in integration["layer_rule"]
                     if rule.get("match", {}).get("namespace") in clear_layer_namespaces]
assert {rule["match"]["namespace"] for rule in clear_layer_rules} == clear_layer_namespaces
assert all(rule.get("blur") is False for rule in clear_layer_rules)

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

print("Compositor backend contracts: OK")
