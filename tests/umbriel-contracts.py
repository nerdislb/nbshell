#!/usr/bin/env python3
"""Static contracts for the Umbriel-only nbshell integration."""

from pathlib import Path
import json
import os
import re
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
contract = json.loads((ROOT / "shell/Catalog/umbriel-capabilities.json").read_text())
assert contract["schemaVersion"] == 1
assert contract["contractVersion"] == 1
assert contract["backend"] == "umbriel"
assert contract["transport"] == {
    "type": "unix-stream",
    "framing": "newline-delimited-json",
    "successField": "ok",
    "errorField": "err",
    "maxRequestBytes": 65536,
}
reference_revision = contract["referenceRevision"]
assert re.fullmatch(r"[0-9a-f]{40}", reference_revision)
setup = (ROOT / "setup-umbriel.sh").read_text()
assert f'UMBRIEL_REVISION="{reference_revision}"' in setup
manifest = tomllib.loads((ROOT / "iso/packages/MANIFEST.toml").read_text())
manifest_umbriel = next(row for row in manifest["custom"] if row["name"] == "umbriel")
assert manifest_umbriel["revision"] == reference_revision
pkgbuild = (ROOT / "iso/packages/pkgbuilds/umbriel/PKGBUILD").read_text()
assert re.search(rf"^_commit={reference_revision}$", pkgbuild, re.MULTILINE)
external_sources = json.loads((ROOT / "shell/Catalog/external-sources.json").read_text())
external_umbriel = next(row for row in external_sources["sources"] if row["name"] == "Umbriel")
assert reference_revision.startswith(external_umbriel["reviewedCommit"])
capabilities = {row["id"]: row for row in contract["capabilities"]}
assert len(capabilities) == len(contract["capabilities"])
assert not any(row["wireName"] == "spawn" for row in contract["capabilities"])
for required in (
    "query.windows", "query.workspaces", "event.windows", "event.workspaces",
    "workspace.focus", "workspace.layout.set", "window.focus", "window.close",
    "window.move-to-workspace", "window.floating.toggle", "session.quit",
    "config.reload", "output.dpms.off",
):
    assert capabilities[required]["required"] is True
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
for expected in (
    'readonly property string backend: "umbriel"',
    "readonly property int contractVersion: 1",
    '"workspaces", "windows", "keyboard_layout"',
    "function normalizeWorkspaces",
    '"workspace-switch:" + String(value)',
    '"window-focus:" + String(id)',
    '"session-quit:skip-confirmation"',
    "function focusWorkspace",
    "function focusWindow",
    "function logout",
    "function scheduleReconnect",
    "id: reconnectTimer",
    "connected: root._connectRequested",
    'focusedOutput = "";',
):
    assert expected in service, expected
for forbidden in ("NIRI_SOCKET", "handleNiri", "isNiri", "Compositor.action", "function _runAction"):
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

system_report = (ROOT / "shell/scripts/system-report.py").read_text()
assert '"wlr-randr", "--json"' in system_report
assert '"umbriel", "outputs", "--json"' not in system_report

capture_service = (ROOT / "shell/Services/CaptureService.qml").read_text()
assert "Compositor.isNiri" not in capture_service
assert "Compositor.action" not in capture_service
assert 'Runtime.captureWindowSelect = true' in (ROOT / "shell/Ipc/DesktopIpc.qml").read_text()
assert "Compositor.turnOutputsOff()" in (ROOT / "shell/Services/Idle.qml").read_text()

setup = (ROOT / "setup.sh").read_text()
assert "--niri-only" not in setup
assert '"$SRC/setup-umbriel.sh" --skip-shell-install' in setup
assert "greetd-regreet" not in setup
umbriel_setup = (ROOT / "setup-umbriel.sh").read_text()
assert contract["referenceRevision"] in umbriel_setup
assert 'tests/umbriel-capability-contract.py"' in umbriel_setup
assert '--binary "$SOURCE_ROOT/umbriel/build-nbshell/umbriel"' in umbriel_setup
assert '--source "$SOURCE_ROOT/umbriel"' in umbriel_setup

installer = (ROOT / "install.sh").read_text()
installer_before_niri_retirement = installer.split("# Remove only nbshell-owned artifacts", 1)[0]
pre_retirement_niri_mentions = [
    line
    for line in installer_before_niri_retirement.splitlines()
    if "nbshell-takeover.kdl" in line
]
assert pre_retirement_niri_mentions
assert all(
    line.strip().startswith("transaction_backup_path")
    for line in pre_retirement_niri_mentions
)

cli = (ROOT / "bin/nbshell").read_text()
assert "nbshell grid" not in cli
assert 'action workspace.layout.set "${1:-toggle}"' in cli
assert "compositor capabilities [--json]" in cli
assert "compositor action <name> [value] [--json]" in cli
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
